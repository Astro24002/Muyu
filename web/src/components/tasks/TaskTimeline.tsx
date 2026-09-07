import type { JSX } from 'react';
import type { ActivityEvent } from '../../api/types';
import { activityLabel } from '../../tasks/activity-label';
import { Button } from '../ui/Button';

export type { ActivityEvent } from '../../api/types';

export type TaskActivityStatus = 'idle' | 'loading' | 'success' | 'error';

export interface TaskActivityState {
  status: TaskActivityStatus;
  events: ActivityEvent[];
  error?: string;
  retryable?: boolean;
}

export interface TaskTimelineProps {
  events?: ActivityEvent[];
  activityState?: TaskActivityState;
  onRetry?: () => void;
}

export function TaskTimeline({ events = [], activityState, onRetry }: TaskTimelineProps): JSX.Element {
  const state = activityState ?? { status: 'success' as const, events };
  const sortedEvents = [...state.events].sort((left, right) => {
    const timeOrder = right.created_at.localeCompare(left.created_at);
    return timeOrder === 0 ? right.id.localeCompare(left.id) : timeOrder;
  });

  return (
    <section className="task-timeline" aria-labelledby="task-timeline-heading">
      <h3 id="task-timeline-heading">活动</h3>
      {state.status === 'loading' ? (
        <p className="task-detail-status" role="status" aria-live="polite">正在加载活动记录…</p>
      ) : state.status === 'error' ? (
        <div className="task-detail-error task-timeline__error" role="alert">
          <p>{state.error ?? '活动记录加载失败，请重试。'}</p>
          {state.retryable !== false && onRetry ? <Button tone="neutral" onClick={onRetry}>重试</Button> : null}
        </div>
      ) : sortedEvents.length === 0 ? (
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
  return activityLabel(value);
}

function actorLabel(event: ActivityEvent): string {
  const actor = event.actor_user_id ?? event.author_user_id;
  return actor ? `操作者：${actor}` : '系统记录';
}

function formatEventDate(value: string): string {
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? new Date(timestamp).toISOString().slice(0, 16).replace('T', ' ') : value;
}
