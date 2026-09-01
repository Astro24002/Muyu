import { Plus } from 'lucide-react';
import { useId, useState, type FormEvent, type JSX } from 'react';
import type { TaskItem, TaskQuadrant } from '../../api/types';
import { useWorkspaceState } from '../../app/use-external-state';
import { parseTaskLabelsInput, TASK_QUADRANTS } from '../../tasks/task-model';
import type { WorkspaceSyncController } from '../../sync/workspace-sync';
import { Button } from '../ui/Button';

export type CreateTaskHandler = (
  title: string,
  description: string,
  quadrant: TaskQuadrant,
  labels: string[],
) => void | Promise<void>;

export interface TaskComposerProps {
  sync: WorkspaceSyncController;
  onCreateTask?: CreateTaskHandler;
  busy?: boolean;
  onRequestExpand?: () => void;
}

interface TaskDraft {
  title: string;
  description: string;
  quadrant: TaskItem['quadrant'] | '';
  labels: string;
}

const EMPTY_DRAFT: TaskDraft = { title: '', description: '', quadrant: '', labels: '' };

export function TaskComposer({ sync, onCreateTask, busy = false, onRequestExpand }: TaskComposerProps): JSX.Element {
  const state = useWorkspaceState(sync);
  const [expanded, setExpanded] = useState(false);
  const [draft, setDraft] = useState<TaskDraft>(EMPTY_DRAFT);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const titleId = useId();
  const descriptionId = useId();
  const quadrantId = useId();
  const labelsId = useId();
  const errorId = useId();
  const disabled = busy || submitting || state.loading || state.stale || state.authRequired;

  const updateDraft = <K extends keyof TaskDraft>(field: K, value: TaskDraft[K]): void => {
    setDraft((current) => ({ ...current, [field]: value }));
    if (error) setError(null);
  };

  const expand = (): void => {
    setExpanded(true);
    onRequestExpand?.();
  };

  const submit = async (event: FormEvent<HTMLFormElement>): Promise<void> => {
    event.preventDefault();
    if (disabled) return;

    if (!draft.title.trim()) {
      setError('请输入任务标题。');
      return;
    }
    if (!draft.quadrant) {
      setError('请选择四象限。');
      return;
    }

    let labels: string[];
    try {
      labels = draft.labels.trim() ? parseTaskLabelsInput(draft.labels) : [];
    } catch (parseError) {
      setError(parseError instanceof Error ? parseError.message : '任务标签格式无效。');
      return;
    }

    const previousError = sync.state.error;
    setSubmitting(true);
    setError(null);
    try {
      const create = onCreateTask ?? ((title: string, description: string, quadrant: TaskQuadrant, nextLabels: string[]) => sync.createTask(title, description, quadrant, nextLabels));
      await create(draft.title.trim(), draft.description, draft.quadrant, labels);
      const currentError = sync.state.error;
      if (currentError && currentError !== previousError) {
        setError(currentError);
        return;
      }
      setDraft(EMPTY_DRAFT);
    } catch (submitError) {
      setError(submitError instanceof Error ? submitError.message : '无法创建任务，请检查网络后重试。');
    } finally {
      setSubmitting(false);
    }
  };

  if (!expanded) {
    return (
      <div className="task-composer task-composer--collapsed" data-task-composer>
        <Button
          className="task-composer__trigger"
          tone="neutral"
          disabled={disabled}
          data-task-composer-trigger
          onClick={expand}
        >
          <Plus aria-hidden="true" size={16} strokeWidth={1.9} />
          <span>记下一件事</span>
        </Button>
      </div>
    );
  }

  return (
    <div className="task-composer task-composer--expanded" data-task-composer>
      <form
        className="task-composer__form"
        onSubmit={(event) => void submit(event)}
        aria-busy={submitting ? 'true' : undefined}
        aria-live={submitting ? 'polite' : undefined}
      >
        <div className="task-composer__field">
          <label htmlFor={titleId}>任务标题</label>
          <input
            id={titleId}
            type="text"
            value={draft.title}
            disabled={disabled}
            aria-invalid={error === '请输入任务标题。' ? 'true' : undefined}
            aria-describedby={error ? errorId : undefined}
            onChange={(event) => updateDraft('title', event.target.value)}
          />
        </div>
        <div className="task-composer__field">
          <label htmlFor={descriptionId}>下一步描述</label>
          <textarea
            id={descriptionId}
            value={draft.description}
            disabled={disabled}
            onChange={(event) => updateDraft('description', event.target.value)}
          />
        </div>
        <div className="task-composer__field">
          <label htmlFor={quadrantId}>四象限</label>
          <select
            id={quadrantId}
            value={draft.quadrant}
            disabled={disabled}
            aria-invalid={error === '请选择四象限。' ? 'true' : undefined}
            aria-describedby={error ? errorId : undefined}
            onChange={(event) => updateDraft('quadrant', event.target.value as TaskDraft['quadrant'])}
          >
            <option value="">请选择四象限</option>
            {TASK_QUADRANTS.map((quadrant) => <option key={quadrant} value={quadrant}>{quadrant}</option>)}
          </select>
        </div>
        <div className="task-composer__field">
          <label htmlFor={labelsId}>标签</label>
          <input
            id={labelsId}
            type="text"
            value={draft.labels}
            disabled={disabled}
            placeholder="用逗号分隔标签"
            aria-describedby={error ? errorId : undefined}
            onChange={(event) => updateDraft('labels', event.target.value)}
          />
        </div>
        {error ? <p id={errorId} className="task-composer__error" role="alert">{error}</p> : null}
        <Button type="submit" tone="primary" disabled={disabled}>
          {submitting ? '正在保存' : '创建任务'}
        </Button>
      </form>
    </div>
  );
}
