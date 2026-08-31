export type Route =
  | { kind: 'today' }
  | { kind: 'tasks' }
  | { kind: 'approvals' }
  | { kind: 'activity' }
  | { kind: 'task'; id: string };

type RouteInput = Route | 'today' | 'tasks' | 'approvals' | 'activity';

export function parseHash(hash: string): Route {
  const path = hash.startsWith('#') ? hash.slice(1) : hash;

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
      : `/${route.kind}`;
  window.location.hash = path;
}
