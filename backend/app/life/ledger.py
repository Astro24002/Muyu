from __future__ import annotations

from collections.abc import Callable
from datetime import date, datetime
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth.profile import public_display_name
from app.db.enums import ChangeAction, LedgerEntryType
from app.db.models import LedgerEntry, User
from app.life.common import (
    LifeError,
    active_member,
    allocate_resource_cursor,
    format_money_minor,
    get_command,
    json_body,
    now_utc,
    parse_date,
    parse_money_minor,
    record_activity,
    save_command,
)


ALLOWED_FIELDS = {"type", "amount", "amount_minor", "title", "category", "payer_or_payee_id", "date", "note"}


class LedgerService:
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
        entry_type: LedgerEntryType,
        amount: object | None,
        amount_minor: object | None,
        title: str,
        category: str,
        payer_or_payee_id: UUID,
        entry_date: date,
        note: str | None,
    ) -> LedgerEntry:
        active_member(self.session, workspace_id, actor_user_id)
        payload = json_body(
            {
                "type": entry_type,
                "amount": amount,
                "amount_minor": amount_minor,
                "title": title,
                "category": category,
                "payer_or_payee_id": payer_or_payee_id,
                "date": entry_date,
                "note": note,
            }
        )
        command = get_command(self.session, workspace_id, actor_user_id, request_id, "/api/v1/ledger", payload)
        if command is not None:
            entry = self.session.get(LedgerEntry, command.resource_id)
            if entry is None:
                raise LifeError("not_found", "ledger entry not found", 404)
            self.last_cursor = command.cursor
            return entry
        normalized_title = title.strip()
        normalized_category = category.strip()
        if not normalized_title or not normalized_category:
            raise LifeError("invalid_request", "title and category are required")
        payer = active_member(self.session, workspace_id, payer_or_payee_id)
        minor = parse_money_minor(amount, amount_minor)
        if entry_date is None:
            raise LifeError("invalid_request", "date is required")
        entry = LedgerEntry(
            id=uuid4(),
            workspace_id=workspace_id,
            entry_type=LedgerEntryType(entry_type),
            amount_minor=minor,
            currency="CNY",
            title=normalized_title,
            category=normalized_category,
            payer_or_payee_id=payer.id,
            entry_date=entry_date,
            note=note.strip() if isinstance(note, str) and note.strip() else None,
            created_by=actor_user_id,
            updated_by=actor_user_id,
        )
        self.session.add(entry)
        self.session.flush()
        cursor = allocate_resource_cursor(self.session, workspace_id, "ledger_entry", entry.id, ChangeAction.CREATED, request_id)
        record_activity(
            self.session,
            workspace_id,
            actor_user_id,
            "LEDGER_CREATED",
            {"ledger_entry_id": str(entry.id), "after": self.snapshot(entry)},
            request_id,
        )
        save_command(self.session, workspace_id, actor_user_id, request_id, "ledger_entry", entry.id, cursor, "/api/v1/ledger", payload)
        self.last_cursor = cursor
        return entry

    def patch(
        self,
        workspace_id: UUID,
        actor_user_id: UUID,
        entry_id: UUID,
        request_id: UUID,
        expected_version: int,
        changes: dict[str, Any],
    ) -> LedgerEntry:
        active_member(self.session, workspace_id, actor_user_id)
        payload = json_body({"entry_id": entry_id, "expected_version": expected_version, "changes": changes})
        command = get_command(self.session, workspace_id, actor_user_id, request_id, f"/api/v1/ledger/{entry_id}", payload)
        if command is not None:
            entry = self.session.get(LedgerEntry, command.resource_id)
            if entry is None:
                raise LifeError("not_found", "ledger entry not found", 404)
            self.last_cursor = command.cursor
            return entry
        entry = self.session.scalar(
            select(LedgerEntry).where(LedgerEntry.id == entry_id, LedgerEntry.workspace_id == workspace_id).with_for_update()
        )
        if entry is None:
            raise LifeError("not_found", "ledger entry not found", 404)
        if entry.deleted_at is not None:
            raise LifeError("lifecycle_conflict", "deleted ledger entry cannot be edited", 409)
        if entry.version != expected_version:
            raise LifeError("version_conflict", "ledger entry has changed", 409)
        unknown = set(changes) - ALLOWED_FIELDS
        if unknown:
            raise LifeError("invalid_request", f"unknown ledger fields: {sorted(unknown)}")
        before = self.snapshot(entry)
        if "type" in changes:
            try:
                entry.entry_type = LedgerEntryType(str(changes["type"]))
            except ValueError as error:
                raise LifeError("invalid_request", "type must be EXPENSE or INCOME") from error
        if "amount" in changes or "amount_minor" in changes:
            entry.amount_minor = parse_money_minor(changes.get("amount"), changes.get("amount_minor"))
        if "title" in changes:
            value = changes["title"]
            if not isinstance(value, str) or not value.strip() or len(value.strip()) > 200:
                raise LifeError("invalid_request", "title is required")
            entry.title = value.strip()
        if "category" in changes:
            value = changes["category"]
            if not isinstance(value, str) or not value.strip() or len(value.strip()) > 80:
                raise LifeError("invalid_request", "category is required")
            entry.category = value.strip()
        if "payer_or_payee_id" in changes:
            try:
                payer_id = UUID(str(changes["payer_or_payee_id"]))
            except (TypeError, ValueError) as error:
                raise LifeError("invalid_request", "invalid payer_or_payee_id") from error
            active_member(self.session, workspace_id, payer_id)
            entry.payer_or_payee_id = payer_id
        if "date" in changes:
            entry.entry_date = parse_date(changes["date"], "date")
        if "note" in changes:
            note = changes["note"]
            if note is not None and (not isinstance(note, str) or len(note) > 5000):
                raise LifeError("invalid_request", "note is too long")
            entry.note = note.strip() if isinstance(note, str) and note.strip() else None
        if not entry.title or not entry.category:
            raise LifeError("invalid_request", "title and category are required")
        entry.updated_by = actor_user_id
        entry.version += 1
        self.session.flush()
        cursor = allocate_resource_cursor(self.session, workspace_id, "ledger_entry", entry.id, ChangeAction.UPDATED, request_id)
        record_activity(
            self.session,
            workspace_id,
            actor_user_id,
            "LEDGER_UPDATED",
            {"ledger_entry_id": str(entry.id), "before": before, "after": self.snapshot(entry)},
            request_id,
        )
        save_command(self.session, workspace_id, actor_user_id, request_id, "ledger_entry", entry.id, cursor, f"/api/v1/ledger/{entry_id}", payload)
        self.last_cursor = cursor
        return entry

    def delete(
        self,
        workspace_id: UUID,
        actor_user_id: UUID,
        entry_id: UUID,
        request_id: UUID,
        expected_version: int,
        confirm: bool,
    ) -> LedgerEntry:
        active_member(self.session, workspace_id, actor_user_id)
        payload = json_body({"entry_id": entry_id, "expected_version": expected_version, "confirm": confirm})
        command = get_command(self.session, workspace_id, actor_user_id, request_id, f"/api/v1/ledger/{entry_id}/delete", payload)
        if command is not None:
            entry = self.session.get(LedgerEntry, command.resource_id)
            if entry is None:
                raise LifeError("not_found", "ledger entry not found", 404)
            self.last_cursor = command.cursor
            return entry
        if not confirm:
            raise LifeError("confirmation_required", "confirm ledger deletion before continuing")
        entry = self.session.scalar(
            select(LedgerEntry).where(LedgerEntry.id == entry_id, LedgerEntry.workspace_id == workspace_id).with_for_update()
        )
        if entry is None:
            raise LifeError("not_found", "ledger entry not found", 404)
        if entry.deleted_at is not None:
            raise LifeError("lifecycle_conflict", "ledger entry is already deleted", 409)
        if entry.version != expected_version:
            raise LifeError("version_conflict", "ledger entry has changed", 409)
        before = self.snapshot(entry)
        entry.deleted_at = now_utc(self.now)
        entry.deleted_by = actor_user_id
        entry.updated_by = actor_user_id
        entry.version += 1
        self.session.flush()
        cursor = allocate_resource_cursor(self.session, workspace_id, "ledger_entry", entry.id, ChangeAction.DELETED, request_id)
        record_activity(
            self.session,
            workspace_id,
            actor_user_id,
            "LEDGER_DELETED",
            {"ledger_entry_id": str(entry.id), "before": before},
            request_id,
        )
        save_command(self.session, workspace_id, actor_user_id, request_id, "ledger_entry", entry.id, cursor, f"/api/v1/ledger/{entry_id}/delete", payload)
        self.last_cursor = cursor
        return entry

    def list(self, workspace_id: UUID, *, month: str | None = None, entry_type: LedgerEntryType | None = None, category: str | None = None) -> list[LedgerEntry]:
        statement = select(LedgerEntry).where(LedgerEntry.workspace_id == workspace_id, LedgerEntry.deleted_at.is_(None))
        if month is not None:
            start, end = month_bounds(month)
            statement = statement.where(LedgerEntry.entry_date >= start, LedgerEntry.entry_date < end)
        if entry_type is not None:
            statement = statement.where(LedgerEntry.entry_type == entry_type)
        if category:
            statement = statement.where(LedgerEntry.category == category)
        return list(self.session.scalars(statement.order_by(LedgerEntry.entry_date.desc(), LedgerEntry.created_at.desc(), LedgerEntry.id.desc())).all())

    def summary(self, workspace_id: UUID, month: str) -> dict[str, object]:
        start, end = month_bounds(month)
        rows = list(
            self.session.scalars(
                select(LedgerEntry).where(
                    LedgerEntry.workspace_id == workspace_id,
                    LedgerEntry.deleted_at.is_(None),
                    LedgerEntry.entry_date >= start,
                    LedgerEntry.entry_date < end,
                )
            ).all()
        )
        expenses = sum(row.amount_minor for row in rows if row.entry_type == LedgerEntryType.EXPENSE)
        income = sum(row.amount_minor for row in rows if row.entry_type == LedgerEntryType.INCOME)
        category_totals: dict[str, int] = {}
        payer_totals: dict[UUID, int] = {}
        for row in rows:
            if row.entry_type != LedgerEntryType.EXPENSE:
                continue
            category_totals[row.category] = category_totals.get(row.category, 0) + row.amount_minor
            payer_totals[row.payer_or_payee_id] = payer_totals.get(row.payer_or_payee_id, 0) + row.amount_minor
        category_total = sum(category_totals.values())
        users = {
            user.id: user
            for user in self.session.scalars(select(User).where(User.id.in_(payer_totals.keys()))).all()
        }
        return {
            "month": month,
            "currency": "CNY",
            "expense_minor": expenses,
            "income_minor": income,
            "balance_minor": income - expenses,
            "expense": format_money_minor(expenses),
            "income": format_money_minor(income),
            "balance": format_money_minor(income - expenses),
            "categories": [
                {"category": name, "amount_minor": value, "ratio": (value / category_total if category_total else 0)}
                for name, value in sorted(category_totals.items())
            ],
            "payer_totals": [
                {"user_id": str(user_id), "display_name": public_display_name(users[user_id]) if user_id in users else str(user_id), "amount_minor": value}
                for user_id, value in sorted(payer_totals.items(), key=lambda item: str(item[0]))
            ],
        }

    @staticmethod
    def snapshot(entry: LedgerEntry) -> dict[str, object]:
        return {
            "id": str(entry.id),
            "workspace_id": str(entry.workspace_id),
            "type": entry.entry_type.value if hasattr(entry.entry_type, "value") else str(entry.entry_type),
            "amount_minor": entry.amount_minor,
            "amount": format_money_minor(entry.amount_minor),
            "currency": entry.currency,
            "title": entry.title,
            "category": entry.category,
            "payer_or_payee_id": str(entry.payer_or_payee_id),
            "date": entry.entry_date.isoformat(),
            "note": entry.note,
            "created_by": str(entry.created_by),
            "updated_by": str(entry.updated_by),
            "version": entry.version,
            "deleted_at": entry.deleted_at.isoformat() if entry.deleted_at else None,
            "deleted_by": str(entry.deleted_by) if entry.deleted_by else None,
            "created_at": entry.created_at.isoformat() if entry.created_at else None,
            "updated_at": entry.updated_at.isoformat() if entry.updated_at else None,
        }


def month_bounds(month: str) -> tuple[date, date]:
    try:
        year, month_number = (int(value) for value in month.split("-", 1))
        start = date(year, month_number, 1)
    except (AttributeError, TypeError, ValueError) as error:
        raise LifeError("invalid_request", "month must use YYYY-MM format") from error
    end = date(start.year + (1 if start.month == 12 else 0), 1 if start.month == 12 else start.month + 1, 1)
    return start, end
