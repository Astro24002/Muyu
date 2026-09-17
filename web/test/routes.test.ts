import { afterEach, describe, expect, it } from 'vitest';
import { navigate, parseHash } from '../src/app/routes';

describe('hash routes', () => {
  afterEach(() => {
    window.history.replaceState({}, '', '/');
  });

  it('parses canonical v1 routes and legacy aliases', () => {
    expect(parseHash('#/matters')).toEqual({ kind: 'matters', view: 'moment' });
    expect(parseHash('#/matters/quadrant')).toEqual({ kind: 'matters', view: 'quadrant' });
    expect(parseHash('#/matters/schedule')).toEqual({ kind: 'matters', view: 'schedule' });
    expect(parseHash('#/ledger')).toEqual({ kind: 'ledger' });
    expect(parseHash('#/checkins')).toEqual({ kind: 'checkins' });
    expect(parseHash('#/me')).toEqual({ kind: 'me' });
    expect(parseHash('#/all-tasks')).toEqual({ kind: 'all-tasks' });
    expect(parseHash('#/today')).toEqual({ kind: 'today' });
    expect(parseHash('#/tasks')).toEqual({ kind: 'tasks' });
    expect(parseHash('#/approvals')).toEqual({ kind: 'approvals' });
    expect(parseHash('#/activity')).toEqual({ kind: 'activity' });
    expect(parseHash('#/tasks/task-1')).toEqual({ kind: 'task', id: 'task-1' });
    expect(parseHash('#/unknown')).toEqual({ kind: 'today' });
  });

  it('navigates by changing only the location hash', () => {
    const pathname = window.location.pathname;

    navigate('approvals');
    expect(window.location.hash).toBe('#/approvals');
    expect(window.location.pathname).toBe(pathname);

    navigate({ kind: 'task', id: 'task-1' });
    expect(window.location.hash).toBe('#/tasks/task-1');
    expect(window.location.pathname).toBe(pathname);

    navigate({ kind: 'matters', view: 'schedule' });
    expect(window.location.hash).toBe('#/matters/schedule');
  });
});
