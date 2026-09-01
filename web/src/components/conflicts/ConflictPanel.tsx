import type { JSX } from 'react';
import type { TaskConflict } from '../../tasks/task-model';
import { Button } from '../ui/Button';

export interface ConflictPanelProps {
  conflicts: TaskConflict[];
  busy: boolean;
  onResolve: (conflictId: string, resolution: 'current' | 'proposed') => void;
}

export function ConflictPanel({ conflicts, busy, onResolve }: ConflictPanelProps): JSX.Element {
  return (
    <section className="conflict-panel" aria-labelledby="conflict-panel-heading">
      <h3 id="conflict-panel-heading">待处理冲突</h3>
      {conflicts.length === 0 ? (
        <p className="task-detail-empty">暂无待处理冲突</p>
      ) : (
        <div className="conflict-panel__list">
          {conflicts.map((conflict) => (
            <article className="conflict-item" key={conflict.id}>
              <p className="conflict-item__field">字段：{conflict.field}</p>
              <div className="conflict-item__values">
                <span>当前值：{displayValue(conflict.current)}</span>
                <span>提议值：{displayValue(conflict.proposed)}</span>
              </div>
              <div className="conflict-item__actions">
                <Button tone="neutral" disabled={busy} onClick={() => onResolve(conflict.id, 'current')}>
                  保留当前
                </Button>
                <Button tone="primary" disabled={busy} onClick={() => onResolve(conflict.id, 'proposed')}>
                  采用提议
                </Button>
              </div>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}

function displayValue(value: unknown): string {
  if (value === null || value === undefined || value === '') return '未设置';
  if (typeof value === 'string') return value;
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}
