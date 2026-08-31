import type { ReactNode, JSX } from 'react';
import type { Route } from '../../app/routes';
import { TopNav, type PrimaryRoute } from './TopNav';

export interface AppShellProps {
  route: Route;
  onNavigate: (route: PrimaryRoute) => void;
  onLogout: () => void;
  onCreateTask?: () => void;
  pendingApprovalCount: number;
  children: ReactNode;
}

export function AppShell({
  route,
  onNavigate,
  onLogout,
  onCreateTask,
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
        pendingApprovalCount={pendingApprovalCount}
      />
      <div className="app-shell__body">
        <div className="app-content">{children}</div>
      </div>
    </div>
  );
}
