import type { JSX } from 'react';
import type { ActivityEvent } from '../../api/types';

export interface ActivityRowProps {
  event: ActivityEvent;
  taskTitle: string;
}

export function ActivityRow({ event, taskTitle }: ActivityRowProps): JSX.Element {
  const body = event.body ?? event.note ?? event.reason;

  return (
    <li className="activity-row task-timeline__item" data-activity-row>
      <div className="activity-row__body task-timeline__body">
        <div className="activity-row__heading">
          <strong>{activityLabel(event)}</strong>
          <span aria-hidden="true">·</span>
          <span>{taskTitle}</span>
        </div>
        {body ? <p>{body}</p> : null}
      </div>
      <div className="activity-row__meta task-timeline__meta">
        <span>{actorLabel(event)}</span>
        <time dateTime={event.created_at}>{formatActivityTime(event.created_at)}</time>
      </div>
    </li>
  );
}

function activityLabel(event: ActivityEvent): string {
  if (event.kind === 'comment') return '添加评论';
  if (event.kind === 'delay') return '延期任务';

  const labels: Record<string, string> = {
    CREATE: '创建任务',
    UPDATE: '更新任务',
    PATCH: '更新任务',
    TRANSITION: '更新状态',
    DELETE: '删除任务',
    RESTORE: '恢复任务',
  };
  return labels[event.operation_type ?? ''] ?? '更新任务';
}

function actorLabel(event: ActivityEvent): string {
  const actor = event.actor_user_id ?? event.author_user_id;
  return actor ? `操作者：${actor}` : '系统记录';
}

function formatActivityTime(value: string): string {
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp)
    ? new Date(timestamp).toISOString().slice(0, 16).replace('T', ' ')
    : value;
}
