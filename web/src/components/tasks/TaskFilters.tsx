import type { JSX } from 'react';
import type { TaskQuadrant, TaskStatus } from '../../api/types';
import { TASK_QUADRANTS } from '../../tasks/task-model';
import { TASK_STATUSES } from '../../tasks/task-view-model';
import { statusLabel } from '../../tasks/task-status';

export interface TaskFilterValues {
  status: TaskStatus | '';
  quadrant: TaskQuadrant | '';
  label: string;
  owner: 'all' | 'mine' | 'other';
}

export const EMPTY_TASK_FILTERS: TaskFilterValues = {
  status: '',
  quadrant: '',
  label: '',
  owner: 'all',
};

export interface TaskFiltersProps {
  value: TaskFilterValues;
  onChange: (value: TaskFilterValues) => void;
  disabled?: boolean;
}

export function TaskFilters({ value, onChange, disabled = false }: TaskFiltersProps): JSX.Element {
  return (
    <div className="task-filters" data-task-filters>
      <label className="task-filters__field">
        <span>状态</span>
        <select
          aria-label="状态"
          value={value.status}
          disabled={disabled}
          onChange={(event) => onChange({ ...value, status: event.target.value as TaskFilterValues['status'] })}
        >
          <option value="">全部状态</option>
          {TASK_STATUSES.map((status) => <option key={status} value={status}>{statusLabel(status)}</option>)}
        </select>
      </label>

      <label className="task-filters__field">
        <span>四象限</span>
        <select
          aria-label="四象限"
          value={value.quadrant}
          disabled={disabled}
          onChange={(event) => onChange({ ...value, quadrant: event.target.value as TaskFilterValues['quadrant'] })}
        >
          <option value="">全部四象限</option>
          {TASK_QUADRANTS.map((quadrant) => <option key={quadrant} value={quadrant}>{quadrant}</option>)}
        </select>
      </label>

      <label className="task-filters__field task-filters__field--label">
        <span>分类</span>
        <input
          type="search"
          aria-label="分类"
          value={value.label}
          disabled={disabled}
          placeholder="筛选分类"
          onChange={(event) => onChange({ ...value, label: event.target.value })}
        />
      </label>

      <label className="task-filters__field">
        <span>负责人</span>
        <select
          aria-label="负责人"
          value={value.owner}
          disabled={disabled}
          onChange={(event) => onChange({ ...value, owner: event.target.value as TaskFilterValues['owner'] })}
        >
          <option value="all">全部负责人</option>
          <option value="mine">我负责</option>
          <option value="other">TA 负责</option>
        </select>
      </label>
    </div>
  );
}
