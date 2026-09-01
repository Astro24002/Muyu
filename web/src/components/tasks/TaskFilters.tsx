import type { JSX } from 'react';
import type { TaskQuadrant, TaskStatus } from '../../api/types';
import { TASK_QUADRANTS } from '../../tasks/task-model';
import { TASK_STATUSES } from '../../tasks/task-view-model';
import { taskStatusText } from './TaskStatusLabel';

export interface TaskFilterValues {
  status: TaskStatus | '';
  quadrant: TaskQuadrant | '';
  label: string;
  myOnly: boolean;
}

export const EMPTY_TASK_FILTERS: TaskFilterValues = {
  status: '',
  quadrant: '',
  label: '',
  myOnly: false,
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
          {TASK_STATUSES.map((status) => <option key={status} value={status}>{taskStatusText(status)}</option>)}
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
        <span>标签</span>
        <input
          type="search"
          aria-label="标签"
          value={value.label}
          disabled={disabled}
          placeholder="筛选标签"
          onChange={(event) => onChange({ ...value, label: event.target.value })}
        />
      </label>

      <label className="task-filters__mine">
        <input
          type="checkbox"
          checked={value.myOnly}
          disabled={disabled}
          onChange={(event) => onChange({ ...value, myOnly: event.target.checked })}
        />
        <span>只看我的任务</span>
      </label>
    </div>
  );
}
