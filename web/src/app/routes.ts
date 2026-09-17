export type Route =
  | { kind: 'matters'; view?: 'moment' | 'quadrant' | 'schedule' }
  | { kind: 'all-tasks' }
  | { kind: 'ledger' }
  | { kind: 'checkins' }
  | { kind: 'me' }
  | { kind: 'today' }
  | { kind: 'tasks' }
  | { kind: 'approvals' }
  | { kind: 'activity' }
  | { kind: 'task'; id: string };

type RouteInput = Route | 'matters' | 'ledger' | 'checkins' | 'me' | 'today' | 'tasks' | 'all-tasks' | 'approvals' | 'activity';

export function parseHash(hash: string): Route {
  const path = hash.startsWith('#') ? hash.slice(1) : hash;

  if (path === '/matters' || path === '/matters/moment') return { kind: 'matters', view: 'moment' };
  if (path === '/matters/quadrant') return { kind: 'matters', view: 'quadrant' };
  if (path === '/matters/schedule') return { kind: 'matters', view: 'schedule' };
  if (path === '/ledger') return { kind: 'ledger' };
  if (path === '/checkins') return { kind: 'checkins' };
  if (path === '/me') return { kind: 'me' };
  if (path === '/all-tasks') return { kind: 'all-tasks' };
  if (path === '/today') return { kind: 'today' };
  if (path === '/tasks') return { kind: 'tasks' };
  if (path === '/approvals') return { kind: 'approvals' };
  if (path === '/activity') return { kind: 'activity' };

  const taskMatch = /^\/tasks\/([^/]+)$/.exec(path);
  if (taskMatch) {
    try {
      return { kind: 'task', id: decodeURIComponent(taskMatch[1]) };
    } catch {
      return { kind: 'today' };
    }
  }

  return { kind: 'today' };
}

export function navigate(route: RouteInput): void {
  const path = typeof route === 'string'
    ? `/${route}`
    : route.kind === 'task'
      ? `/tasks/${encodeURIComponent(route.id)}`
      : route.kind === 'today'
        ? '/today'
        : route.kind === 'tasks'
          ? '/tasks'
          : route.kind === 'matters'
            ? `/matters/${route.view ?? 'moment'}`
            : `/${route.kind}`;
  window.location.hash = path;
}
