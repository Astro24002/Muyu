import { useCallback, useEffect, useRef } from 'react';
import { WorkspaceSocket, type WebSocketFactory } from '../realtime/workspace-socket';
import type { WorkspaceSyncController } from '../sync/workspace-sync';

export interface WorkspaceRealtimeOptions {
  socketFactory?: WebSocketFactory;
  fallbackIntervalMs?: number;
}

type WorkspaceRealtimeInput = WorkspaceRealtimeOptions | WebSocketFactory;
type TimerHandle = ReturnType<typeof globalThis.setInterval>;

export function useWorkspaceRealtime(
  sync: WorkspaceSyncController,
  workspaceId: string | null,
  input: WorkspaceRealtimeInput = {},
): () => void {
  const socketFactory = typeof input === 'function' ? input : input.socketFactory;
  const fallbackIntervalMs = typeof input === 'function' ? 10_000 : input.fallbackIntervalMs ?? 10_000;
  const stopRef = useRef<() => void>(() => undefined);

  useEffect(() => {
    let active = true;
    let fallbackTimer: TimerHandle | undefined;
    let socket: WorkspaceSocket | undefined;
    let stopped = false;
    let reconnecting = false;
    let fallbackPullInFlight = false;
    let fallbackPullPending = false;

    const stopFallback = (): void => {
      if (fallbackTimer !== undefined) globalThis.clearInterval(fallbackTimer);
      fallbackTimer = undefined;
      fallbackPullPending = false;
    };

    const requestFallbackPull = (): void => {
      if (!active || !sync.state.snapshot || typeof sync.pull !== 'function') return;
      if (fallbackPullInFlight) {
        fallbackPullPending = true;
        return;
      }

      fallbackPullInFlight = true;
      let request: Promise<void>;
      try {
        request = Promise.resolve(sync.pull());
      } catch (error) {
        request = Promise.reject(error);
      }
      void request.catch(() => undefined).finally(() => {
        fallbackPullInFlight = false;
        if (!active) {
          fallbackPullPending = false;
          return;
        }
        if (fallbackPullPending) {
          fallbackPullPending = false;
          requestFallbackPull();
        }
      });
    };

    const startFallback = (): void => {
      if (!active || fallbackTimer !== undefined) return;
      fallbackTimer = globalThis.setInterval(() => {
        if (!active || typeof document === 'undefined' || document.visibilityState !== 'visible') return;
        if (!sync.state.snapshot || typeof sync.pull !== 'function') return;
        requestFallbackPull();
      }, fallbackIntervalMs);
    };

    const stop = (): void => {
      if (stopped) return;
      stopped = true;
      stopFallback();
      socket?.dispose();
      socket = undefined;
      if (stopRef.current === stop) stopRef.current = () => undefined;
    };

    stopRef.current = stop;
    if (workspaceId) {
      socket = new WorkspaceSocket(workspaceId, {
        factory: socketFactory,
        onHint: (cursor) => {
          if (!active || cursor <= sync.state.cursor || typeof sync.pull !== 'function') return;
          void sync.pull(cursor);
        },
        onOpen: () => {
          const wasReconnecting = reconnecting;
          reconnecting = false;
          if (wasReconnecting && typeof sync.pull === 'function') void sync.pull();
          stopFallback();
        },
        onFailure: () => {
          reconnecting = true;
          startFallback();
        },
      });
      socket.connect();
    }

    return () => {
      active = false;
      stop();
    };
  }, [fallbackIntervalMs, socketFactory, sync, workspaceId]);

  return useCallback(() => {
    stopRef.current();
  }, []);
}
