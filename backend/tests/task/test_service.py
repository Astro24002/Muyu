from datetime import datetime, timezone
from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.activity.models import ActivityEvent
from app.task.models import TaskHandlerHistory, TaskStatusHistory, TaskUserPosition
from app.task.repository import TaskRepository
from app.task.service import TaskCreate, TaskNotFoundError, TaskRuleError, TaskService
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
