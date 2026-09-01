import { AlertCircle, ArrowLeft, LoaderCircle, RotateCcw } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState, type JSX } from 'react';
import type { ActivityEvent, TaskItem } from '../api/types';
import { navigate } from '../app/routes';
import { ActivityRow } from '../components/activity/ActivityRow';
import { Button } from '../components/ui/Button';
import { loadWorkspaceActivity, type GetTaskActivity } from '../tasks/activity-view-model';

export interface ActivityPageProps {
  tasks: TaskItem[];
  getTaskActivity: GetTaskActivity;
  workspaceKey?: string;
  onBackToToday?: () => void;
  onRetry?: () => void;
}

type ActivityLoadState =
  | { status: 'loading'; events: ActivityEvent[]; failedTaskIds: string[] }
  | { status: 'ready'; events: ActivityEvent[]; failedTaskIds: string[] };

export function ActivityPage({
  tasks,
  getTaskActivity,
  workspaceKey = 'workspace',
  onBackToToday,
  onRetry,
}: ActivityPageProps): JSX.Element {
  const [retryCount, setRetryCount] = useState(0);
  const [state, setState] = useState<ActivityLoadState>({ status: 'loading', events: [], failedTaskIds: [] });
  const requestSequence = useRef(0);
  const activeTasks = useMemo(() => tasks.filter((task) => !task.deleted_at), [tasks]);
  const taskTitles = useMemo(() => new Map(activeTasks.map((task) => [task.id, task.title])), [activeTasks]);

  useEffect(() => {
    const sequence = ++requestSequence.current;
    let active = true;
    setState({ status: 'loading', events: [], failedTaskIds: [] });

    const requestActivity = async (taskId: string): Promise<ActivityEvent[]> => {
      const events = await getTaskActivity(taskId);
      return events.map((event) => ({ ...event, task_id: taskId }));
    };

    void loadWorkspaceActivity(activeTasks, requestActivity)
      .then((result) => {
        if (!active || sequence !== requestSequence.current) return;
        setState({ status: 'ready', ...result });
      })
      .catch(() => {
        if (!active || sequence !== requestSequence.current) return;
        setState({
          status: 'ready',
          events: [],
          failedTaskIds: activeTasks.map((task) => task.id),
        });
      });

    return () => {
      active = false;
    };
  }, [activeTasks, getTaskActivity, retryCount, workspaceKey]);

  const retry = useCallback((): void => {
    onRetry?.();
    setRetryCount((count) => count + 1);
  }, [onRetry]);

  const backToToday = useCallback((): void => {
    if (onBackToToday) {
      onBackToToday();
      return;
    }
    navigate('today');
  }, [onBackToToday]);

  const hasPartialFailure = state.status === 'ready' && state.failedTaskIds.length > 0;
  const hasEvents = state.events.length > 0;

  return (
    <main className="activity-page approvals-page" data-activity-page data-workspace-key={workspaceKey}>
      <header className="activity-page__intro approvals-page__intro">
        <p>最近动态</p>
        <h1>动态</h1>
        <p>集中查看任务最近发生的变化。</p>
      </header>

      {state.status === 'loading' ? (
        <div className="activity-page__status" role="status" aria-live="polite">
          <LoaderCircle aria-hidden="true" size={16} strokeWidth={1.9} />
          <span>正在加载动态</span>
        </div>
      ) : null}

      {hasPartialFailure ? (
        <div className="activity-page__notice" role="alert" aria-live="assertive">
          <AlertCircle aria-hidden="true" size={16} strokeWidth={1.9} />
          <span>{hasEvents ? '部分动态暂时无法加载' : '动态暂时无法加载'}</span>
          <Button tone="quiet" onClick={retry}>
            <RotateCcw aria-hidden="true" size={15} strokeWidth={1.9} />
            重试
          </Button>
        </div>
      ) : null}

      {state.status === 'ready' && hasEvents ? (
        <section className="activity-page__section task-timeline" aria-labelledby="activity-list-heading">
          <h2 id="activity-list-heading">最近记录</h2>
          <ol className="activity-page__list task-timeline__list">
            {state.events.map((event, index) => {
              const taskId = typeof event.task_id === 'string' ? event.task_id : '';
              return (
                <ActivityRow
                  key={`${event.id}-${index}`}
                  event={event}
                  taskTitle={taskTitles.get(taskId) ?? '未命名任务'}
                />
              );
            })}
          </ol>
        </section>
      ) : null}

      {state.status === 'ready' && !hasEvents && !hasPartialFailure ? (
        <section className="activity-page__empty" aria-live="polite">
          <p>还没有可展示的动态</p>
          <Button tone="quiet" onClick={backToToday}>
            <ArrowLeft aria-hidden="true" size={15} strokeWidth={1.9} />
            回到今天
          </Button>
        </section>
      ) : null}
    </main>
  );
}
