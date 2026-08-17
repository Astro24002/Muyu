from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.activity.models import ActivityEvent
from app.task.models import TaskHandlerHistory, TaskStatusHistory, TaskUserPosition
from app.task.repository import TaskRepository
from app.task.service import TaskCreate, TaskNotFoundError, TaskPatch, TaskRuleError, TaskService
from app.user.repository import UserRepository
from app.user.service import seed_fixed_users


def users(session: Session):
    seed_fixed_users(session, "shared-password")
    return UserRepository(session).list_users()


def create_data(user_a, user_b=None, *, title="  准备旅行  ", parent_task_id=None) -> TaskCreate:
    assignee_ids = (user_a.id,) if user_b is None else (user_a.id, user_b.id)
    return TaskCreate(
        title=title,
        description="整理出行清单",
        assignee_ids=assignee_ids,
        current_handler_id=user_a.id,
        parent_task_id=parent_task_id,
        planned_start_at=datetime(2026, 9, 1, 1, tzinfo=timezone.utc),
        due_at=datetime(2026, 9, 3, 1, tzinfo=timezone.utc),
        estimated_minutes=90,
    )


def test_create_task_records_assignments_positions_histories_and_activity(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, user_b = users(session)
        task = TaskService(session).create(user_a.id, create_data(user_a, user_b))

        assert task.title == "准备旅行"
        assert task.status == "TODO"
        assert task.version == 1
        assert task.status_version == 1
        assert {item.user_id for item in task.assignees} == {user_a.id, user_b.id}
        assert session.scalars(select(TaskUserPosition).where(TaskUserPosition.task_id == task.id)).all()
        assert session.scalar(select(TaskStatusHistory).where(TaskStatusHistory.task_id == task.id)).to_status == "TODO"
        assert session.scalar(select(TaskHandlerHistory).where(TaskHandlerHistory.task_id == task.id)).to_user_id == user_a.id
        event = session.scalar(select(ActivityEvent).where(ActivityEvent.target_id == task.id))
        assert event.action == "TASK_CREATED"
        assert event.after_json["title"] == "准备旅行"


def test_task_lifecycle_transfer_and_audit_are_atomic(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, user_b = users(session)
        service = TaskService(session)
        task = service.create(user_a.id, create_data(user_a, user_b))

        service.start(task.id, user_a.id)
        service.transfer(task.id, user_a.id, user_b.id)
        service.complete(task.id, user_b.id)
        service.reopen(task.id, user_a.id)
        result = service.cancel(task.id, user_a.id)

        assert result.status == "CANCELLED"
        assert result.current_handler_id == user_b.id
        assert result.completed_at is None
        assert result.version == 6
        assert result.status_version == 5
        assert session.scalars(
            select(TaskStatusHistory).where(TaskStatusHistory.task_id == task.id)
        ).all().__len__() == 5
        assert [event.action for event in service.list_events(task.id)] == [
            "TASK_CREATED",
            "TASK_STARTED",
            "TASK_HANDLER_CHANGED",
            "TASK_COMPLETED",
            "TASK_REOPENED",
            "TASK_CANCELLED",
        ]


def test_subtasks_are_limited_to_one_level_and_parent_delete_requires_cleanup(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, _ = users(session)
        service = TaskService(session)
        parent = service.create(user_a.id, create_data(user_a, title="父任务"))
        child = service.create(
            user_a.id,
            create_data(user_a, title="子任务", parent_task_id=parent.id),
        )

        with pytest.raises(TaskRuleError, match="one subtask level") as nested:
            service.create(user_a.id, create_data(user_a, title="孙任务", parent_task_id=child.id))
        assert nested.value.code == "SUBTASK_DEPTH_EXCEEDED"

        with pytest.raises(TaskRuleError, match="active subtasks") as blocked_delete:
            service.delete(parent.id, user_a.id)
        assert blocked_delete.value.code == "TASK_HAS_SUBTASKS"

        service.delete(child.id, user_a.id)
        service.delete(parent.id, user_a.id)
        with pytest.raises(TaskNotFoundError):
            service.get(parent.id)


def test_personal_order_changes_list_order_without_changing_status(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, _ = users(session)
        service = TaskService(session)
        first = service.create(user_a.id, create_data(user_a, title="第一个"))
        second = service.create(user_a.id, create_data(user_a, title="第二个"))

        ordered = service.replace_order(user_a.id, [second.id, first.id])

        assert ordered == [second.id, first.id]
        assert [task.id for task in service.list_tasks(user_a.id)] == [second.id, first.id]
        assert service.get(first.id).status == "TODO"


def test_invalid_assignee_and_transition_are_rejected(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, user_b = users(session)
        service = TaskService(session)
        task = service.create(user_a.id, create_data(user_a))

        with pytest.raises(TaskRuleError) as invalid_handler:
            service.transfer(task.id, user_a.id, user_b.id)
        assert invalid_handler.value.code == "HANDLER_NOT_ASSIGNEE"

        service.complete(task.id, user_a.id)
        with pytest.raises(TaskRuleError) as invalid_transition:
            service.complete(task.id, user_a.id)
        assert invalid_transition.value.code == "INVALID_TASK_TRANSITION"


def test_delay_repository_returns_empty_history_and_zero_summary(db_engine) -> None:
    with Session(db_engine) as session:
        repository = TaskRepository(session)
        task_id = uuid4()

        assert repository.list_delays(task_id) == []
        assert repository.delay_count(task_id) == 0
        assert repository.total_delay_minutes(task_id) == 0


def test_delay_three_times_preserves_history_summary_and_activity(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, _ = users(session)
        service = TaskService(session)
        task = service.create(user_a.id, create_data(user_a))
        due_dates = [
            datetime(2026, 9, 4, 1, tzinfo=timezone.utc),
            datetime(2026, 9, 6, 1, tzinfo=timezone.utc),
            datetime(2026, 9, 9, 1, tzinfo=timezone.utc),
        ]

        for index, due_at in enumerate(due_dates, start=1):
            service = TaskService(
                session,
                clock=lambda index=index: datetime(2026, 9, index, 2, tzinfo=timezone.utc),
            )
            service.delay(
                task.id,
                user_a.id,
                new_due_at=due_at,
                reason="NO_TIME",
                note=f"第 {index} 次延期",
            )

        records = service.list_delays(task.id)
        assert [record.original_due_at for record in records] == [
            datetime(2026, 9, 3, 1, tzinfo=timezone.utc),
            datetime(2026, 9, 4, 1, tzinfo=timezone.utc),
            datetime(2026, 9, 6, 1, tzinfo=timezone.utc),
        ]
        assert [record.new_due_at for record in records] == due_dates
        assert [record.delay_duration_minutes for record in records] == [1440, 2880, 4320]
        assert service.delay_summary(task.id) == (3, 8640)
        assert service.get(task.id).due_at == due_dates[-1]
        assert [event.action for event in service.list_events(task.id)] == [
            "TASK_CREATED",
            "TASK_DELAYED",
            "TASK_DELAYED",
            "TASK_DELAYED",
        ]


@pytest.mark.parametrize(
    ("due_at", "reason", "note", "code"),
    [
        (datetime(2026, 9, 4, 1, tzinfo=timezone.utc), "UNKNOWN", None, "INVALID_DELAY_REASON"),
        (datetime(2026, 9, 4, 1, tzinfo=timezone.utc), "OTHER", "  ", "DELAY_NOTE_REQUIRED"),
        (datetime(2026, 9, 3, 1, tzinfo=timezone.utc), "NO_TIME", None, "INVALID_DELAY_TIME"),
        (datetime(2026, 9, 3, 1, 0, 30, tzinfo=timezone.utc), "NO_TIME", None, "INVALID_DELAY_TIME"),
    ],
)
def test_delay_rejects_invalid_reason_note_or_time(db_engine, due_at, reason, note, code) -> None:
    with Session(db_engine) as session:
        user_a, _ = users(session)
        service = TaskService(session)
        task = service.create(user_a.id, create_data(user_a))

        with pytest.raises(TaskRuleError) as error:
            service.delay(
                task.id,
                user_a.id,
                new_due_at=due_at,
                reason=reason,
                note=note,
            )

        assert error.value.code == code


def test_delay_requires_an_existing_due_date(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, _ = users(session)
        service = TaskService(session)
        payload = create_data(user_a)
        payload = TaskCreate(**{**payload.__dict__, "due_at": None})
        task = service.create(user_a.id, payload)

        with pytest.raises(TaskRuleError) as error:
            service.delay(
                task.id,
                user_a.id,
                new_due_at=datetime(2026, 9, 4, 1, tzinfo=timezone.utc),
                reason="NO_TIME",
                note=None,
            )

        assert error.value.code == "DUE_AT_REQUIRED"


def test_existing_due_date_cannot_be_moved_later_through_regular_update(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, _ = users(session)
        service = TaskService(session)
        task = service.create(user_a.id, create_data(user_a))

        with pytest.raises(TaskRuleError) as error:
            service.update(
                task.id,
                user_a.id,
                TaskPatch(due_at=datetime(2026, 9, 4, 1, tzinfo=timezone.utc)),
            )

        assert error.value.code == "USE_DELAY_ACTION"
        assert service.get(task.id).due_at == datetime(2026, 9, 3, 1, tzinfo=timezone.utc)


def test_block_and_unblock_restore_handler_and_write_histories(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, user_b = users(session)
        service = TaskService(session, clock=lambda: datetime(2026, 9, 1, 1, tzinfo=timezone.utc))
        task = service.create(user_a.id, create_data(user_a, user_b))

        service = TaskService(session, clock=lambda: datetime(2026, 9, 1, 2, tzinfo=timezone.utc))
        waiting = service.block(
            task.id,
            user_a.id,
            blocked_reason="等待确认行程",
            resume_handler_id=user_b.id,
            waiting_for_user_id=user_b.id,
        )

        assert waiting.status == "WAITING"
        assert waiting.current_handler_id == user_a.id
        assert waiting.blocked_reason == "等待确认行程"
        assert waiting.blocked_since == datetime(2026, 9, 1, 2, tzinfo=timezone.utc)
        assert waiting.resume_handler_id == user_b.id
        assert waiting.waiting_for_user_id == user_b.id

        service = TaskService(session, clock=lambda: datetime(2026, 9, 1, 3, tzinfo=timezone.utc))
        resumed = service.unblock(task.id, user_a.id)

        assert resumed.status == "IN_PROGRESS"
        assert resumed.current_handler_id == user_b.id
        assert resumed.blocked_reason is None
        assert resumed.blocked_since is None
        assert resumed.resume_handler_id is None
        assert resumed.waiting_for_user_id is None
        assert [history.to_status for history in session.scalars(
            select(TaskStatusHistory).where(TaskStatusHistory.task_id == task.id).order_by(TaskStatusHistory.changed_at)
        )] == ["TODO", "WAITING", "IN_PROGRESS"]
        assert [history.to_user_id for history in session.scalars(
            select(TaskHandlerHistory).where(TaskHandlerHistory.task_id == task.id).order_by(TaskHandlerHistory.changed_at)
        )] == [user_a.id, user_b.id]
        assert [event.action for event in service.list_events(task.id)] == [
            "TASK_CREATED",
            "TASK_BLOCKED",
            "TASK_UNBLOCKED",
        ]


def test_block_validates_reason_resume_handler_waiting_user_and_transition(db_engine) -> None:
    with Session(db_engine) as session:
        user_a, user_b = users(session)
        service = TaskService(session)
        task = service.create(user_a.id, create_data(user_a))

        cases = [
            ({"blocked_reason": "  ", "resume_handler_id": user_a.id}, "INVALID_BLOCK_REASON"),
            ({"blocked_reason": "等待", "resume_handler_id": user_b.id}, "INVALID_RESUME_HANDLER"),
            (
                {
                    "blocked_reason": "等待",
                    "resume_handler_id": user_a.id,
                    "waiting_for_user_id": uuid4(),
                },
                "INVALID_WAITING_USER",
            ),
        ]
        for kwargs, code in cases:
            with pytest.raises(TaskRuleError) as error:
                service.block(task.id, user_a.id, **kwargs)
            assert error.value.code == code

        service.complete(task.id, user_a.id)
        with pytest.raises(TaskRuleError) as invalid_transition:
            service.block(
                task.id,
                user_a.id,
                blocked_reason="等待",
                resume_handler_id=user_a.id,
            )
        assert invalid_transition.value.code == "INVALID_TASK_TRANSITION"


@pytest.mark.parametrize(("action", "expected"), [("complete", "DONE"), ("cancel", "CANCELLED")])
def test_waiting_task_can_finish_and_clears_blocking_fields(db_engine, action, expected) -> None:
    with Session(db_engine) as session:
        user_a, _ = users(session)
        service = TaskService(session)
        task = service.create(user_a.id, create_data(user_a))
        service.block(
            task.id,
            user_a.id,
            blocked_reason="等待外部确认",
            resume_handler_id=user_a.id,
        )

        result = getattr(service, action)(task.id, user_a.id)

        assert result.status == expected
        assert result.blocked_reason is None
        assert result.blocked_since is None
        assert result.resume_handler_id is None
        assert result.waiting_for_user_id is None
