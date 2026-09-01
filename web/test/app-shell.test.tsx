import { describe, expect, it, vi } from 'vitest';
import type { ApiClient } from '../src/api/client';
import { App } from '../src/app/App';
import type { QrLoginController } from '../src/auth/qr-login';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../src/sync/workspace-sync';
import { cleanup, render } from './react-test-helpers';

describe('React app shell', () => {
  it('renders the React shell inside the browser root and cleans up', async () => {
    const appRoot = document.createElement('div');
    appRoot.id = 'app';
    document.body.append(appRoot);
    const loadSnapshot = vi.fn().mockResolvedValue(undefined);
    const loginDispose = vi.fn();
    const syncDispose = vi.fn();

    render(
      <App
        api={{} as ApiClient}
        login={{ dispose: loginDispose } as unknown as QrLoginController}
        sync={{ loadSnapshot, state: emptySyncState(), dispose: syncDispose } as unknown as WorkspaceSyncController}
      />,
      { container: appRoot },
    );

    const shell = appRoot.querySelector('[data-testid="muyu-app"]');
    expect(shell).toBeInTheDocument();
    expect(shell?.tagName).toBe('DIV');

    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(shell?.querySelectorAll('main')).toHaveLength(1);

    cleanup();

    expect(appRoot).toBeEmptyDOMElement();
    appRoot.remove();
    expect(document.body.contains(appRoot)).toBe(false);
  });

  it('disposes the login and sync dependencies with the React shell', () => {
    const appRoot = document.createElement('div');
    appRoot.id = 'app';
    document.body.append(appRoot);
    const loadSnapshot = vi.fn().mockResolvedValue(undefined);
    const loginDispose = vi.fn();
    const syncDispose = vi.fn();
    const { unmount } = render(
      <App
        api={{} as ApiClient}
        login={{ dispose: loginDispose } as unknown as QrLoginController}
        sync={{ loadSnapshot, state: emptySyncState(), dispose: syncDispose } as unknown as WorkspaceSyncController}
      />,
      { container: appRoot },
    );

    expect(loadSnapshot).toHaveBeenCalledTimes(1);

    unmount();

    expect(loginDispose).toHaveBeenCalledTimes(1);
    expect(syncDispose).toHaveBeenCalledTimes(1);
    expect(appRoot).toBeEmptyDOMElement();
    appRoot.remove();
  });
});

function emptySyncState(): WorkspaceSyncState {
  return {
    snapshot: null,
    cursor: 0,
    loading: false,
    stale: false,
    error: null,
    conflicts: [],
    authRequired: false,
  };
}
