import type { JSX } from 'react';
import type { ApiClient } from '../api/client';
import type { QrLoginController } from '../auth/qr-login';
import type { WorkspaceSyncController } from '../sync/workspace-sync';

export interface AppProps {
  api: ApiClient;
  login: QrLoginController;
  sync: WorkspaceSyncController;
}

export function App({ api, login, sync }: AppProps): JSX.Element {
  return <main data-testid="muyu-app" />;
}
