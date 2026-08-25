export interface SocketLike {
  onopen: ((event: Event) => void) | null;
  onclose: ((event: CloseEvent) => void) | null;
  onerror: ((event: Event) => void) | null;
  onmessage: ((event: MessageEvent) => void) | null;
  close(): void;
}

export type WebSocketFactory = (url: string) => SocketLike;

export interface WorkspaceSocketOptions {
  factory?: WebSocketFactory;
  location?: Pick<Location, 'protocol' | 'host'> | URL;
  onHint?: (cursor: number) => void;
  onOpen?: () => void;
  onFailure?: () => void;
  setTimeout?: (handler: () => void, delay: number) => ReturnType<typeof globalThis.setTimeout>;
  clearTimeout?: (timer: ReturnType<typeof globalThis.setTimeout>) => void;
}

const RECONNECT_DELAYS = [1_000, 2_000, 5_000] as const;

export class WorkspaceSocket {
  readonly url: string;
  #factory: WebSocketFactory;
  #onHint: (cursor: number) => void;
  #onOpen: () => void;
  #onFailure: () => void;
  #setTimeout: (handler: () => void, delay: number) => ReturnType<typeof globalThis.setTimeout>;
  #clearTimeout: (timer: ReturnType<typeof globalThis.setTimeout>) => void;
  #socket: SocketLike | undefined;
  #reconnectTimer: ReturnType<typeof globalThis.setTimeout> | undefined;
  #reconnectAttempt = 0;
  #disposed = false;

  constructor(private readonly workspaceId: string, options: WorkspaceSocketOptions = {}) {
    const location = options.location ?? window.location;
    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    this.url = new URL('/api/v1/realtime', `${protocol}//${location.host}`).toString();
    const parsed = new URL(this.url);
    parsed.searchParams.set('workspace_id', workspaceId);
    this.url = parsed.toString();
    this.#factory = options.factory ?? ((url) => new WebSocket(url));
    this.#onHint = options.onHint ?? (() => undefined);
    this.#onOpen = options.onOpen ?? (() => undefined);
    this.#onFailure = options.onFailure ?? (() => undefined);
    this.#setTimeout = options.setTimeout ?? globalThis.setTimeout;
    this.#clearTimeout = options.clearTimeout ?? globalThis.clearTimeout;
  }

  connect(): void {
    if (this.#disposed || this.#socket) return;
    try {
      const socket = this.#factory(this.url);
      this.#socket = socket;
      socket.onopen = () => {
        if (this.#disposed || socket !== this.#socket) return;
        this.#reconnectAttempt = 0;
        this.#onOpen();
      };
      socket.onmessage = (event) => this.#handleMessage(event);
      socket.onerror = () => this.#handleFailure(socket);
      socket.onclose = () => this.#handleFailure(socket);
    } catch {
      this.#scheduleReconnect();
      this.#onFailure();
    }
  }

  dispose(): void {
    if (this.#disposed) return;
    this.#disposed = true;
    if (this.#reconnectTimer !== undefined) this.#clearTimeout(this.#reconnectTimer);
    this.#reconnectTimer = undefined;
    const socket = this.#socket;
    this.#socket = undefined;
    if (socket) {
      socket.onopen = null;
      socket.onmessage = null;
      socket.onerror = null;
      socket.onclose = null;
      socket.close();
    }
  }

  #handleMessage(event: MessageEvent): void {
    const hint = parseWorkspaceHint(event.data, this.workspaceId);
    if (this.#disposed || !hint) return;
    this.#onHint(hint.cursor);
  }

  #handleFailure(socket: SocketLike): void {
    if (this.#disposed || socket !== this.#socket) return;
    this.#socket = undefined;
    this.#onFailure();
    this.#scheduleReconnect();
  }

  #scheduleReconnect(): void {
    if (this.#disposed || this.#reconnectTimer !== undefined) return;
    const delay = RECONNECT_DELAYS[Math.min(this.#reconnectAttempt, RECONNECT_DELAYS.length - 1)];
    this.#reconnectAttempt += 1;
    this.#reconnectTimer = this.#setTimeout(() => {
      this.#reconnectTimer = undefined;
      this.connect();
    }, delay);
  }
}

function parseWorkspaceHint(value: unknown, workspaceId: string): { type: 'workspace.changed'; workspace_id: string; cursor: number } | undefined {
  if (typeof value !== 'string') return undefined;
  try {
    const hint: unknown = JSON.parse(value);
    if (!hint || typeof hint !== 'object') return undefined;
    const record = hint as Record<string, unknown>;
    if (record.type === 'workspace.changed'
      && record.workspace_id === workspaceId
      && typeof record.cursor === 'number'
      && Number.isSafeInteger(record.cursor)
      && record.cursor >= 0) {
      return record as { type: 'workspace.changed'; workspace_id: string; cursor: number };
    }
    return undefined;
  } catch {
    return undefined;
  }
}
