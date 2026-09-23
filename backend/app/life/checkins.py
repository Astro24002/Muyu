from __future__ import annotations

from collections.abc import Callable
from datetime import date, datetime, timedelta
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.enums import ChangeAction, HabitFrequency, HabitStatus
from app.db.models import Habit, HabitCheckin
from app.life.common import (
    LifeError,
    active_member,
    allocate_resource_cursor,
    get_command,
    json_body,
    now_utc,
    parse_date,
    record_activity,
    save_command,
    workspace_today,
)


ALLOWED_FREQUENCIES = {item.value for item in HabitFrequency}


def period_key(day: date, frequency: HabitFrequency | str) -> str:
    value = HabitFrequency(frequency)
    if value == HabitFrequency.DAILY:
        return day.isoformat()
    if value == HabitFrequency.WEEKLY:
        monday = day - timedelta(days=day.weekday())
        return monday.isoformat()
    return f"{day.year:04d}-{day.month:02d}"


class HabitService:
    def __init__(self, session: Session, *, now: Callable[[], datetime] | None = None) -> None:
        self.session = session
        self.now = now
        self.last_cursor: int | None = None

    def create(
        self,
        workspace_id: UUID,
        actor_user_id: UUID,
        request_id: UUID,
        *,
        title: str,
        note: str | None,
        frequency: HabitFrequency,
        start_date: date | None,
    ) -> Habit:
        active_member(self.session, workspace_id, actor_user_id)
        payload = json_body({"title": title, "note": note, "frequency": frequency, "start_date": start_date})
        command = get_command(self.session, workspace_id, actor_user_id, request_id, "/api/v1/habits", payload)
        if command is not None:
            habit = self.session.get(Habit, command.resource_id)
            if habit is None:
                raise LifeError("not_found", "habit not found", 404)
            self.last_cursor = command.cursor
            return habit
        normalized_title = title.strip()
        if not normalized_title:
            raise LifeError("invalid_request", "habit title is required")
        try:
            normalized_frequency = HabitFrequency(frequency)
        except ValueError as error:
            raise LifeError("invalid_request", "frequency must be DAILY, WEEKLY, or MONTHLY") from error
        chosen_start = start_date or workspace_today(self.now)
        habit = Habit(
            id=uuid4(),
            workspace_id=workspace_id,
            owner_id=actor_user_id,
            title=normalized_title,
            note=note.strip() if isinstance(note, str) and note.strip() else None,
            frequency=normalized_frequency,
            start_date=chosen_start,
            status=HabitStatus.ACTIVE,
        )
        self.session.add(habit)
        self.session.flush()
        cursor = allocate_resource_cursor(self.session, workspace_id, "habit", habit.id, ChangeAction.CREATED, request_id)
        record_activity(self.session, workspace_id, actor_user_id, "HABIT_CREATED", {"habit_id": str(habit.id), "after": self.snapshot(habit, self.current_checkin(habit))}, request_id)
        save_command(self.session, workspace_id, actor_user_id, request_id, "habit", habit.id, cursor, "/api/v1/habits", payload)
        self.last_cursor = cursor
        return habit

    def patch(self, workspace_id: UUID, actor_user_id: UUID, habit_id: UUID, request_id: UUID, expected_version: int, changes: dict[str, Any]) -> Habit:
        payload = json_body({"habit_id": habit_id, "expected_version": expected_version, "changes": changes})
        command = get_command(self.session, workspace_id, actor_user_id, request_id, f"/api/v1/habits/{habit_id}", payload)
        if command is not None:
            habit = self.session.get(Habit, command.resource_id)
            if habit is None:
                raise LifeError("not_found", "habit not found", 404)
            self.last_cursor = command.cursor
            return habit
        active_member(self.session, workspace_id, actor_user_id)
        habit = self._lock(workspace_id, habit_id)
        self._require_owner(habit, actor_user_id)
        if habit.deleted_at is not None or habit.status == HabitStatus.DELETED:
            raise LifeError("lifecycle_conflict", "habit is deleted", 409)
        if habit.version != expected_version:
            raise LifeError("version_conflict", "habit has changed", 409)
        unknown = set(changes) - {"title", "note", "frequency", "start_date"}
        if unknown:
            raise LifeError("invalid_request", f"unknown habit fields: {sorted(unknown)}")
        before = self.snapshot(habit, self.current_checkin(habit))
        if "title" in changes:
            value = changes["title"]
            if not isinstance(value, str) or not value.strip() or len(value.strip()) > 120:
                raise LifeError("invalid_request", "habit title is required")
            habit.title = value.strip()
        if "note" in changes:
            value = changes["note"]
            if value is not None and (not isinstance(value, str) or len(value) > 5000):
                raise LifeError("invalid_request", "note is too long")
            habit.note = value.strip() if isinstance(value, str) and value.strip() else None
        if "frequency" in changes:
            try:
                habit.frequency = HabitFrequency(str(changes["frequency"]))
            except ValueError as error:
                raise LifeError("invalid_request", "frequency must be DAILY, WEEKLY, or MONTHLY") from error
        if "start_date" in changes:
            habit.start_date = parse_date(changes["start_date"], "start_date")
        habit.version += 1
        self.session.flush()
        cursor = allocate_resource_cursor(self.session, workspace_id, "habit", habit.id, ChangeAction.UPDATED, request_id)
        record_activity(self.session, workspace_id, actor_user_id, "HABIT_UPDATED", {"habit_id": str(habit.id), "before": before, "after": self.snapshot(habit, self.current_checkin(habit))}, request_id)
        save_command(self.session, workspace_id, actor_user_id, request_id, "habit", habit.id, cursor, f"/api/v1/habits/{habit_id}", payload)
        self.last_cursor = cursor
        return habit

    def set_status(self, workspace_id: UUID, actor_user_id: UUID, habit_id: UUID, request_id: UUID, expected_version: int, status: HabitStatus) -> Habit:
        payload = {"habit_id": str(habit_id), "expected_version": expected_version, "status": status.value}
        command = get_command(self.session, workspace_id, actor_user_id, request_id, f"/api/v1/habits/{habit_id}/{status.value.lower()}", payload)
        if command is not None:
            habit = self.session.get(Habit, command.resource_id)
            if habit is None:
                raise LifeError("not_found", "habit not found", 404)
            self.last_cursor = command.cursor
            return habit
        active_member(self.session, workspace_id, actor_user_id)
        habit = self._lock(workspace_id, habit_id)
        self._require_owner(habit, actor_user_id)
        if habit.deleted_at is not None or habit.status == HabitStatus.DELETED:
            raise LifeError("lifecycle_conflict", "habit is deleted", 409)
        if habit.version != expected_version:
            raise LifeError("version_conflict", "habit has changed", 409)
        if status not in {HabitStatus.ACTIVE, HabitStatus.PAUSED}:
            raise LifeError("invalid_request", "habit status must be ACTIVE or PAUSED")
        if habit.status == status:
            self.last_cursor = None
            return habit
        before = self.snapshot(habit, self.current_checkin(habit))
        habit.status = status
        habit.version += 1
        self.session.flush()
        cursor = allocate_resource_cursor(self.session, workspace_id, "habit", habit.id, ChangeAction.UPDATED, request_id)
        record_activity(self.session, workspace_id, actor_user_id, "HABIT_STATUS_CHANGED", {"habit_id": str(habit.id), "before": before, "after": self.snapshot(habit, self.current_checkin(habit))}, request_id)
        save_command(self.session, workspace_id, actor_user_id, request_id, "habit", habit.id, cursor, f"/api/v1/habits/{habit_id}/{status.value.lower()}", payload)
        self.last_cursor = cursor
        return habit

    def checkin(self, workspace_id: UUID, actor_user_id: UUID, habit_id: UUID, request_id: UUID, expected_version: int) -> tuple[Habit, HabitCheckin]:
        payload = {"habit_id": str(habit_id), "expected_version": expected_version}
        command = get_command(self.session, workspace_id, actor_user_id, request_id, f"/api/v1/habits/{habit_id}/checkin", payload)
        if command is not None:
            checkin = self.session.get(HabitCheckin, command.resource_id)
            habit = self.session.get(Habit, habit_id)
            if habit is None or checkin is None:
                raise LifeError("not_found", "check-in not found", 404)
            self.last_cursor = command.cursor
            return habit, checkin
        active_member(self.session, workspace_id, actor_user_id)
        habit = self._lock(workspace_id, habit_id)
        self._require_owner(habit, actor_user_id)
        self._require_live(habit)
        if habit.version != expected_version:
            raise LifeError("version_conflict", "habit has changed", 409)
        today = workspace_today(self.now)
        if today < habit.start_date:
            raise LifeError("habit_not_started", "habit has not started", 422)
        key = period_key(today, habit.frequency)
        existing = self.session.scalar(
            select(HabitCheckin).where(
                HabitCheckin.habit_id == habit.id,
                HabitCheckin.frequency_snapshot == habit.frequency,
                HabitCheckin.period_key == key,
                HabitCheckin.revoked_at.is_(None),
            )
        )
        if existing is not None:
            # Repeated taps are deliberately idempotent even with a new command.
            self.last_cursor = None
            return habit, existing
        checkin = HabitCheckin(
            id=uuid4(),
            workspace_id=workspace_id,
            habit_id=habit.id,
            actor_id=actor_user_id,
            frequency_snapshot=habit.frequency,
            period_key=key,
            day=today,
            occurred_at=now_utc(self.now),
            request_id=request_id,
        )
        self.session.add(checkin)
        self.session.flush()
        cursor = allocate_resource_cursor(self.session, workspace_id, "habit_checkin", checkin.id, ChangeAction.CREATED, request_id)
        record_activity(self.session, workspace_id, actor_user_id, "HABIT_CHECKED_IN", {"habit_id": str(habit.id), "checkin_id": str(checkin.id), "period_key": key}, request_id)
        save_command(self.session, workspace_id, actor_user_id, request_id, "habit_checkin", checkin.id, cursor, f"/api/v1/habits/{habit_id}/checkin", payload)
        self.last_cursor = cursor
        return habit, checkin

    def undo(self, workspace_id: UUID, actor_user_id: UUID, habit_id: UUID, request_id: UUID, expected_version: int) -> Habit:
        payload = {"habit_id": str(habit_id), "expected_version": expected_version}
        command = get_command(self.session, workspace_id, actor_user_id, request_id, f"/api/v1/habits/{habit_id}/undo", payload)
        if command is not None:
            habit = self.session.get(Habit, command.resource_id)
            if habit is None:
                raise LifeError("not_found", "habit not found", 404)
            self.last_cursor = command.cursor
            return habit
        active_member(self.session, workspace_id, actor_user_id)
        habit = self._lock(workspace_id, habit_id)
        self._require_owner(habit, actor_user_id)
        self._require_live(habit)
        if habit.version != expected_version:
            raise LifeError("version_conflict", "habit has changed", 409)
        today = workspace_today(self.now)
        key = period_key(today, habit.frequency)
        checkin = self.session.scalar(
            select(HabitCheckin).where(
                HabitCheckin.habit_id == habit.id,
                HabitCheckin.frequency_snapshot == habit.frequency,
                HabitCheckin.period_key == key,
                HabitCheckin.revoked_at.is_(None),
            ).with_for_update()
        )
        if checkin is None:
            raise LifeError("not_found", "no check-in exists for the current period", 404)
        checkin.revoked_at = now_utc(self.now)
        self.session.flush()
        cursor = allocate_resource_cursor(self.session, workspace_id, "habit_checkin", checkin.id, ChangeAction.UPDATED, request_id)
        record_activity(self.session, workspace_id, actor_user_id, "HABIT_CHECKIN_REVOKED", {"habit_id": str(habit.id), "checkin_id": str(checkin.id), "period_key": key}, request_id)
        save_command(self.session, workspace_id, actor_user_id, request_id, "habit", habit.id, cursor, f"/api/v1/habits/{habit_id}/undo", payload)
        self.last_cursor = cursor
        return habit

    def delete(self, workspace_id: UUID, actor_user_id: UUID, habit_id: UUID, request_id: UUID, expected_version: int, confirm: bool) -> Habit:
        payload = {"habit_id": str(habit_id), "expected_version": expected_version, "confirm": confirm}
        command = get_command(self.session, workspace_id, actor_user_id, request_id, f"/api/v1/habits/{habit_id}/delete", payload)
        if command is not None:
            habit = self.session.get(Habit, command.resource_id)
            if habit is None:
                raise LifeError("not_found", "habit not found", 404)
            self.last_cursor = command.cursor
            return habit
        if not confirm:
            raise LifeError("confirmation_required", "confirm habit deletion before continuing")
        active_member(self.session, workspace_id, actor_user_id)
        habit = self._lock(workspace_id, habit_id)
        self._require_owner(habit, actor_user_id)
        if habit.status == HabitStatus.DELETED or habit.deleted_at is not None:
            raise LifeError("lifecycle_conflict", "habit is already deleted", 409)
        if habit.version != expected_version:
            raise LifeError("version_conflict", "habit has changed", 409)
        before = self.snapshot(habit, self.current_checkin(habit))
        deleted_at = now_utc(self.now)
        habit.status = HabitStatus.DELETED
        habit.deleted_at = deleted_at
        habit.version += 1
        active_checkins = self.session.scalars(
            select(HabitCheckin).where(HabitCheckin.habit_id == habit.id, HabitCheckin.revoked_at.is_(None)).with_for_update()
        ).all()
        for checkin in active_checkins:
            checkin.revoked_at = deleted_at
        self.session.flush()
        cursor = allocate_resource_cursor(self.session, workspace_id, "habit", habit.id, ChangeAction.DELETED, request_id)
        record_activity(self.session, workspace_id, actor_user_id, "HABIT_DELETED", {"habit_id": str(habit.id), "before": before, "checkins_hidden": len(active_checkins)}, request_id)
        save_command(self.session, workspace_id, actor_user_id, request_id, "habit", habit.id, cursor, f"/api/v1/habits/{habit_id}/delete", payload)
        self.last_cursor = cursor
        return habit

    def list(self, workspace_id: UUID, viewer_id: UUID, owner: str = "mine") -> list[dict[str, object]]:
        active_member(self.session, workspace_id, viewer_id)
        statement = select(Habit).where(Habit.workspace_id == workspace_id, Habit.deleted_at.is_(None))
        if owner == "mine":
            statement = statement.where(Habit.owner_id == viewer_id)
        elif owner == "other":
            statement = statement.where(Habit.owner_id != viewer_id)
        elif owner != "all":
            raise LifeError("invalid_request", "owner must be mine, other, or all")
        habits = self.session.scalars(statement.order_by(Habit.created_at.asc(), Habit.id.asc())).all()
        return [self.snapshot(habit, self.current_checkin(habit), include_history=True) for habit in habits]

    def _lock(self, workspace_id: UUID, habit_id: UUID) -> Habit:
        habit = self.session.scalar(select(Habit).where(Habit.workspace_id == workspace_id, Habit.id == habit_id).with_for_update())
        if habit is None:
            raise LifeError("not_found", "habit not found", 404)
        return habit

    @staticmethod
    def _require_owner(habit: Habit, actor_user_id: UUID) -> None:
        if habit.owner_id != actor_user_id:
            raise LifeError("permission_denied", "only the habit owner can change it", 403)

    @staticmethod
    def _require_live(habit: Habit) -> None:
        if habit.deleted_at is not None or habit.status == HabitStatus.DELETED:
            raise LifeError("lifecycle_conflict", "habit is deleted", 409)
        if habit.status == HabitStatus.PAUSED:
            raise LifeError("habit_paused", "paused habit cannot be checked in", 409)

    def current_checkin(self, habit: Habit) -> HabitCheckin | None:
        today = workspace_today(self.now)
        key = period_key(today, habit.frequency)
        return self.session.scalar(
            select(HabitCheckin).where(
                HabitCheckin.habit_id == habit.id,
                HabitCheckin.frequency_snapshot == habit.frequency,
                HabitCheckin.period_key == key,
                HabitCheckin.revoked_at.is_(None),
            )
        )

    def snapshot(self, habit: Habit, current: HabitCheckin | None = None, *, include_history: bool = False) -> dict[str, object]:
        today = workspace_today(self.now)
        current_key = period_key(today, habit.frequency)
        result: dict[str, object] = {
            "id": str(habit.id),
            "workspace_id": str(habit.workspace_id),
            "owner_id": str(habit.owner_id),
            "title": habit.title,
            "note": habit.note,
            "frequency": habit.frequency.value if hasattr(habit.frequency, "value") else str(habit.frequency),
            "start_date": habit.start_date.isoformat(),
            "status": habit.status.value if hasattr(habit.status, "value") else str(habit.status),
            "version": habit.version,
            "current_period_key": current_key,
            "checked_in": current is not None,
            "current_checkin": self.checkin_snapshot(current) if current is not None else None,
            "deleted_at": habit.deleted_at.isoformat() if habit.deleted_at else None,
            "created_at": habit.created_at.isoformat() if habit.created_at else None,
            "updated_at": habit.updated_at.isoformat() if habit.updated_at else None,
        }
        if include_history:
            history = self.session.scalars(
                select(HabitCheckin).where(HabitCheckin.habit_id == habit.id).order_by(HabitCheckin.occurred_at.desc(), HabitCheckin.id.desc()).limit(100)
            ).all()
            result["checkins"] = [self.checkin_snapshot(item) for item in history]
            recent_days = [today - timedelta(days=offset) for offset in range(6, -1, -1)]
            recent_checkins = self.session.scalars(
                select(HabitCheckin).where(
                    HabitCheckin.habit_id == habit.id,
                    HabitCheckin.day >= recent_days[0],
                    HabitCheckin.day <= today,
                    HabitCheckin.revoked_at.is_(None),
                )
            ).all()
            result["recent_days"] = [day.isoformat() for day in recent_days]
            result["recent_checkin_days"] = sorted({item.day.isoformat() for item in recent_checkins})
        return result

    @staticmethod
    def checkin_snapshot(checkin: HabitCheckin) -> dict[str, object]:
        return {
            "id": str(checkin.id),
            "habit_id": str(checkin.habit_id),
            "workspace_id": str(checkin.workspace_id),
            "actor_id": str(checkin.actor_id),
            "frequency_snapshot": checkin.frequency_snapshot.value if hasattr(checkin.frequency_snapshot, "value") else str(checkin.frequency_snapshot),
            "period_key": checkin.period_key,
            "day": checkin.day.isoformat(),
            "occurred_at": checkin.occurred_at.isoformat(),
            "revoked_at": checkin.revoked_at.isoformat() if checkin.revoked_at else None,
        }
