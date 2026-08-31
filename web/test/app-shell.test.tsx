import { describe, expect, it } from 'vitest';
import type { ApiClient } from '../src/api/client';
import { App } from '../src/app/App';
import type { QrLoginController } from '../src/auth/qr-login';
import type { WorkspaceSyncController } from '../src/sync/workspace-sync';
import { cleanup, render } from './react-test-helpers';

describe('React app shell', () => {
  it('renders the React shell and leaves the legacy app root empty after cleanup', () => {
    const legacyRoot = document.createElement('div');
    legacyRoot.id = 'app';
    document.body.append(legacyRoot);

    render(
      <App
        api={{} as ApiClient}
        login={{} as QrLoginController}
        sync={{} as WorkspaceSyncController}
      />,
      { container: legacyRoot },
    );

    expect(legacyRoot.querySelector('[data-testid="muyu-app"]')).toBeInTheDocument();

    cleanup();

    expect(legacyRoot).toBeEmptyDOMElement();
  });
});
