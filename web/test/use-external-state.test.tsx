import { act } from '@testing-library/react';
import type { JSX } from 'react';
import { describe, expect, it, vi } from 'vitest';
import type { QrLoginController, QrLoginState } from '../src/auth/qr-login';
import { useQrLoginState, useWorkspaceState } from '../src/app/use-external-state';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../src/sync/workspace-sync';
import { render } from './react-test-helpers';

describe('external service state hooks', () => {
  it('returns the controller workspace state and re-renders on subscription changes', () => {
    let current = emptyWorkspaceState();
    const listeners = new Set<() => void>();
    const sync = {
      get state(): WorkspaceSyncState { return current; },
      subscribe(listener: () => void): () => void {
        listeners.add(listener);
        return () => listeners.delete(listener);
      },
    } as unknown as WorkspaceSyncController;
    const observed = vi.fn();

    function Probe(): JSX.Element {
      const state = useWorkspaceState(sync);
      observed(state);
      return <output>{state.error ?? 'ready'}</output>;
    }

    const { getByText } = render(<Probe />);
    expect(observed).toHaveBeenLastCalledWith(current);
    expect(getByText('ready')).toBeInTheDocument();

    const next = { ...current, error: 'stale' };
    current = next;
    act(() => {
      for (const listener of listeners) listener();
    });

    expect(observed).toHaveBeenLastCalledWith(next);
    expect(getByText('stale')).toBeInTheDocument();
  });

  it('returns the controller QR state without maintaining a second copy', () => {
    let current: QrLoginState = { kind: 'signed_out' };
    const listeners = new Set<() => void>();
    const login = {
      get state(): QrLoginState { return current; },
      subscribe(listener: () => void): () => void {
        listeners.add(listener);
        return () => listeners.delete(listener);
      },
    } as unknown as QrLoginController;
    const observed = vi.fn();

    function Probe(): JSX.Element {
      const state = useQrLoginState(login);
      observed(state);
      return <output>{state.kind}</output>;
    }

    const { getByText } = render(<Probe />);
    expect(observed).toHaveBeenLastCalledWith(current);
    expect(getByText('signed_out')).toBeInTheDocument();

    const next: QrLoginState = { kind: 'signed_in', expiresAt: '2026-09-01T00:00:00.000Z' };
    current = next;
    act(() => {
      for (const listener of listeners) listener();
    });

    expect(observed).toHaveBeenLastCalledWith(next);
    expect(getByText('signed_in')).toBeInTheDocument();
  });
});

function emptyWorkspaceState(): WorkspaceSyncState {
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
