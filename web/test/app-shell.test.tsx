import { describe, expect, it, vi } from 'vitest';
import type { ApiClient } from '../src/api/client';
import { App } from '../src/app/App';
import type { QrLoginController } from '../src/auth/qr-login';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../src/sync/workspace-sync';
import { cleanup, render } from './react-test-helpers';

describe('React app shell', () => {
  it('renders the React shell and leaves the legacy app root empty after cleanup', async () => {
    const legacyRoot = document.createElement('div');
    legacyRoot.id = 'app';
    document.body.append(legacyRoot);
    const loadSnapshot = vi.fn().mockResolvedValue(undefined);
    const loginDispose = vi.fn();
    const syncDispose = vi.fn();

    render(
      <App
        api={{} as ApiClient}
        login={{ dispose: loginDispose } as unknown as QrLoginController}
        sync={{ loadSnapshot, state: emptySyncState(), dispose: syncDispose } as unknown as WorkspaceSyncController}
      />,
      { container: legacyRoot },
    );

    const shell = legacyRoot.querySelector('[data-testid="muyu-app"]');
    expect(shell).toBeInTheDocument();
    expect(shell?.tagName).toBe('DIV');

    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(shell?.querySelectorAll('main')).toHaveLength(1);

    cleanup();

    expect(legacyRoot).toBeEmptyDOMElement();
    legacyRoot.remove();
    expect(document.body.contains(legacyRoot)).toBe(false);
  });

  it('keeps the legacy runtime mounted and disposes it with the React shell', () => {
    const legacyRoot = document.createElement('div');
    legacyRoot.id = 'app';
    document.body.append(legacyRoot);
    const loadSnapshot = vi.fn().mockResolvedValue(undefined);
    const loginDispose = vi.fn();
    const syncDispose = vi.fn();
    const { unmount } = render(
      <App
        api={{} as ApiClient}
        login={{ dispose: loginDispose } as unknown as QrLoginController}
        sync={{ loadSnapshot, state: emptySyncState(), dispose: syncDispose } as unknown as WorkspaceSyncController}
      />,
      { container: legacyRoot },
    );

    expect(loadSnapshot).toHaveBeenCalledTimes(1);

    unmount();

    expect(loginDispose).toHaveBeenCalledTimes(1);
    expect(syncDispose).toHaveBeenCalledTimes(1);
    expect(legacyRoot).toBeEmptyDOMElement();
    legacyRoot.remove();
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
