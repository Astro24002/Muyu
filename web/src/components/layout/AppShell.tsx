import type { ReactNode, JSX } from 'react';
import type { Route } from '../../app/routes';
import type { WebSessionViewApi } from '../../ui/web-session-view';
import { TopNav, type PrimaryRoute } from './TopNav';

export interface AppShellProps {
  route: Route;
  onNavigate: (route: PrimaryRoute) => void;
  onLogout: () => void;
  onCreateTask?: () => void;
  sessionApi?: WebSessionViewApi;
  onAuthRequired?: () => void;
  pendingApprovalCount: number;
  children: ReactNode;
}

export function AppShell({
  route,
  onNavigate,
  onLogout,
  onCreateTask,
  sessionApi,
  onAuthRequired,
  pendingApprovalCount,
  children,
}: AppShellProps): JSX.Element {
  return (
    <div className="app-shell">
      <TopNav
        route={route}
        onNavigate={onNavigate}
        onLogout={onLogout}
        onCreateTask={onCreateTask}
        sessionApi={sessionApi}
        onAuthRequired={onAuthRequired}
        pendingApprovalCount={pendingApprovalCount}
      />
      <div className="app-shell__body">
        <div className="app-content">{children}</div>
      </div>
    </div>
  );
}
