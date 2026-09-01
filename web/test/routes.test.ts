import { afterEach, describe, expect, it } from 'vitest';
import { navigate, parseHash } from '../src/app/routes';

describe('hash routes', () => {
  afterEach(() => {
    window.history.replaceState({}, '', '/');
  });

  it('parses the supported routes and falls back to today', () => {
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
  });
});
