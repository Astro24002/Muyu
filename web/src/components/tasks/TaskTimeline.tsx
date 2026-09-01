import type { JSX } from 'react';
import type { ActivityEvent } from '../../api/types';

export type { ActivityEvent } from '../../api/types';

export interface TaskTimelineProps {
  events?: ActivityEvent[];
}

export function TaskTimeline({ events = [] }: TaskTimelineProps): JSX.Element {
  const sortedEvents = [...events].sort((left, right) => {
    const timeOrder = right.created_at.localeCompare(left.created_at);
    return timeOrder === 0 ? right.id.localeCompare(left.id) : timeOrder;
  });

  return (
    <section className="task-timeline" aria-labelledby="task-timeline-heading">
      <h3 id="task-timeline-heading">活动</h3>
      {sortedEvents.length === 0 ? (
        <p className="task-detail-empty">暂无活动</p>
      ) : (
        <ol className="task-timeline__list">
          {sortedEvents.map((event) => (
            <li className="task-timeline__item" key={event.id}>
              <div className="task-timeline__body">
                <strong>{eventLabel(event)}</strong>
                {event.body ? <p>{event.body}</p> : null}
                {event.note ? <p>{event.note}</p> : null}
              </div>
              <div className="task-timeline__meta">
                {actorLabel(event)}
                <time dateTime={event.created_at}>{formatEventDate(event.created_at)}</time>
              </div>
            </li>
          ))}
        </ol>
      )}
    </section>
  );
}

function eventLabel(event: ActivityEvent): string {
  if (event.kind === 'comment') return '添加评论';
  if (event.kind === 'delay') return event.reason ? `延期：${event.reason}` : '延期';
  if (event.operation_type) return operationLabel(event.operation_type);
  return '更新任务';
}

function operationLabel(value: string): string {
  const labels: Record<string, string> = {
    CREATE: '创建任务',
    UPDATE: '更新任务',
    PATCH: '更新任务',
    TRANSITION: '更新状态',
    DELETE: '删除任务',
    RESTORE: '恢复任务',
  };
  return labels[value] ?? value;
}

function actorLabel(event: ActivityEvent): string {
  const actor = event.actor_user_id ?? event.author_user_id;
  return actor ? `操作者：${actor}` : '系统记录';
}

function formatEventDate(value: string): string {
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? new Date(timestamp).toISOString().slice(0, 16).replace('T', ' ') : value;
}
