import { useCallback, useSyncExternalStore } from 'react';
import type { QrLoginController, QrLoginState } from '../auth/qr-login';
import type { WorkspaceSyncController, WorkspaceSyncState } from '../sync/workspace-sync';

const SIGNED_OUT: QrLoginState = { kind: 'signed_out' };

export function useWorkspaceState(sync: WorkspaceSyncController): WorkspaceSyncState {
  const subscribe = useCallback((onStoreChange: () => void) => {
    if (typeof sync.subscribe !== 'function') return () => undefined;
    return sync.subscribe(() => onStoreChange());
  }, [sync]);
  const getSnapshot = useCallback(() => sync.state, [sync]);

  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}

export function useQrLoginState(login: QrLoginController): QrLoginState {
  const subscribe = useCallback((onStoreChange: () => void) => {
    if (typeof login.subscribe !== 'function') return () => undefined;
    return login.subscribe(() => onStoreChange());
  }, [login]);
  const getSnapshot = useCallback(() => login.state ?? SIGNED_OUT, [login]);

  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);
}
