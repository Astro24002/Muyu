import { useEffect, useRef, type JSX } from 'react';
import { App as LegacyApp } from '../app';
import type { ApiClient } from '../api/client';
import type { QrLoginController } from '../auth/qr-login';
import type { WorkspaceSyncController } from '../sync/workspace-sync';

export interface AppProps {
  api: ApiClient;
  login: QrLoginController;
  sync: WorkspaceSyncController;
}

export function App({ api, login, sync }: AppProps): JSX.Element {
  const legacyRootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const legacyRoot = legacyRootRef.current;
    if (!legacyRoot) return;

    const legacyApp = new LegacyApp({ api, login, sync });
    legacyApp.mount(legacyRoot);

    return () => {
      legacyApp.dispose();
      legacyRoot.replaceChildren();
    };
  }, [api, login, sync]);

  return (
    <div data-testid="muyu-app">
      <div ref={legacyRootRef} data-testid="legacy-app-root" />
    </div>
  );
}
