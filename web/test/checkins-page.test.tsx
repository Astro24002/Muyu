import { fireEvent, screen, waitFor } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { Anniversary, Habit } from '../src/api/types';
import { CheckinsPage } from '../src/pages/CheckinsPage';
import { render } from './react-test-helpers';

const habit: Habit = {
  id: 'habit-1', workspace_id: 'workspace-1', owner_id: 'viewer', title: '阅读', note: null,
  frequency: 'DAILY', start_date: '2026-01-01', status: 'ACTIVE', version: 1,
  current_period_key: '2026-09-18', checked_in: false, current_checkin: null, checkins: [],
  recent_days: ['2026-09-18', '2026-09-19', '2026-09-20', '2026-09-21', '2026-09-22', '2026-09-23', '2026-09-24'],
  recent_checkin_days: ['2026-09-18', '2026-09-22'],
  deleted_at: null,
};
const anniversary: Anniversary = {
  id: 'anniversary-1', workspace_id: 'workspace-1', title: '认识纪念日', anchor_date: '2020-10-01',
  kind: 'ANNIVERSARY', prepare_days: 7, note: null, next_occurrence: '2026-10-01', days_until: 13,
  is_today: false, version: 1,
};

describe('CheckinsPage', () => {
  it('checks in through the owner action and renders anniversary preparation', async () => {
    const api = {
      listHabits: vi.fn().mockResolvedValue([habit]),
      listAnniversaries: vi.fn().mockResolvedValue([anniversary]),
      habitAction: vi.fn().mockResolvedValue({ ...habit, checked_in: true, version: 2 }),
      prepareAnniversary: vi.fn().mockResolvedValue({ task: { id: 'task-1' }, cursor: 4, source_key: 'anniversary:anniversary-1:2026-10-01' }),
    };
    render(<CheckinsPage api={api as never} viewerId="viewer" canWrite />);
    await waitFor(() => expect(screen.getByText('阅读')).toBeInTheDocument());
    expect(screen.getAllByRole('listitem', { name: /已打卡|没有打卡记录/ })).toHaveLength(7);
    expect(screen.getByRole('listitem', { name: '2026-09-22 已打卡' })).toBeInTheDocument();
    expect(screen.getByRole('listitem', { name: '2026-09-23 没有打卡记录' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: '打卡' }));
    await waitFor(() => expect(api.habitAction).toHaveBeenCalledWith('habit-1', 'checkin', { requestId: expect.any(String), expectedVersion: 1 }));
    fireEvent.click(screen.getByRole('tab', { name: '纪念日' }));
    await waitFor(() => expect(screen.getByText('认识纪念日')).toBeInTheDocument());
    fireEvent.click(screen.getByRole('button', { name: '生成准备事项' }));
    await waitFor(() => expect(api.prepareAnniversary).toHaveBeenCalledWith('anniversary-1', expect.any(String)));
  });

  it('edits and confirms deletion through the habit API', async () => {
    const api = {
      listHabits: vi.fn().mockResolvedValue([habit]),
      listAnniversaries: vi.fn().mockResolvedValue([]),
      patchHabit: vi.fn().mockResolvedValue({ ...habit, title: '散步', version: 2 }),
      deleteHabit: vi.fn().mockResolvedValue({ ...habit, status: 'DELETED', deleted_at: '2026-09-18T00:00:00Z' }),
    };
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    render(<CheckinsPage api={api as never} viewerId="viewer" canWrite />);
    await waitFor(() => expect(screen.getByText('阅读')).toBeInTheDocument());
    fireEvent.click(screen.getByRole('button', { name: /阅读/ }));
    fireEvent.change(screen.getByLabelText('习惯名称'), { target: { value: '散步' } });
    fireEvent.click(screen.getByRole('button', { name: '保存' }));
    await waitFor(() => expect(api.patchHabit).toHaveBeenCalledWith('habit-1', expect.objectContaining({ expectedVersion: 1, changes: expect.objectContaining({ title: '散步' }) })));
    fireEvent.click(screen.getByRole('button', { name: /阅读/ }));
    fireEvent.click(screen.getByRole('button', { name: '删除' }));
    await waitFor(() => expect(api.deleteHabit).toHaveBeenCalledWith('habit-1', { requestId: expect.any(String), expectedVersion: 1, confirm: true }));
  });
});
