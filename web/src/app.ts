import type { ApiClient } from './api/client';
import type { QrLoginController } from './auth/qr-login';
import { WorkspaceSocket, type WebSocketFactory } from './realtime/workspace-socket';
import type { WorkspaceSyncController } from './sync/workspace-sync';
import { QrLoginView } from './ui/qr-login-view';
import { WorkspaceView } from './ui/workspace-view';

export interface AppDependencies {
  api: Pick<ApiClient, 'logoutWebSession'>;
  login: QrLoginController;
  sync: WorkspaceSyncController;
  socketFactory?: WebSocketFactory;
}

export class App {
  #root: Element | undefined;
  #active = false;
  #loggingOut = false;
  #loginView: (() => void) | undefined;
  #workspaceView: (() => void) | undefined;
  #socket: WorkspaceSocket | undefined;
  #fallbackTimer: ReturnType<typeof globalThis.setInterval> | undefined;

  constructor(private readonly dependencies: AppDependencies) {}

  mount(root: Element): void {
    this.disposeViews();
    this.#root = root;
    this.#active = true;
    void this.loadWorkspace();
  }

  dispose(): void {
    if (!this.#active) return;
    this.#active = false;
    this.disposeViews();
    this.dependencies.login.dispose();
    this.dependencies.sync.dispose();
    this.#root = undefined;
  }

  private async loadWorkspace(): Promise<void> {
    await this.dependencies.sync.loadSnapshot();
    if (!this.#active) return;
    if (this.dependencies.sync.state.snapshot) {
      this.showWorkspace();
    } else if (this.dependencies.sync.state.authRequired) {
      this.showLogin();
    } else {
      this.showRecoverableError();
    }
  }

  private showLogin(): void {
    const root = this.#root;
    if (!root || !this.#active) return;
    this.stopWorkspace();
    this.#loginView?.();
    this.#loginView = QrLoginView.mount(root, this.dependencies.login, () => void this.loadWorkspace());
    void this.dependencies.login.start();
  }

  private showWorkspace(): void {
    const root = this.#root;
    const snapshot = this.dependencies.sync.state.snapshot;
    if (!root || !snapshot || !this.#active) return;
    this.#loginView?.();
    this.#loginView = undefined;
    this.stopWorkspace();
    this.#workspaceView = WorkspaceView.mount(root, this.dependencies.sync, () => void this.logout());
    this.#socket = new WorkspaceSocket(snapshot.workspace_id, {
      factory: this.dependencies.socketFactory,
      onHint: (cursor) => {
        if (cursor > this.dependencies.sync.state.cursor) void this.dependencies.sync.pull();
      },
      onOpen: () => this.stopFallback(),
      onFailure: () => this.startFallback(),
    });
    this.#socket.connect();
  }

  private async logout(): Promise<void> {
    if (!this.#active || this.#loggingOut) return;
    this.#loggingOut = true;
    this.stopWorkspace();
    this.#loginView?.();
    this.#loginView = undefined;
    this.dependencies.login.stop();
    try {
      await this.dependencies.api.logoutWebSession();
    } catch {
      // The local session state is already cleared; still let the user sign in again.
    } finally {
      this.#loggingOut = false;
      if (this.#active) this.showLogin();
    }
  }

  private showRecoverableError(): void {
    const root = this.#root;
    if (!root || !this.#active) return;
    this.disposeViews();
    const page = document.createElement('main');
    page.className = 'app-error';
    const message = document.createElement('p');
    message.setAttribute('role', 'alert');
    message.textContent = this.dependencies.sync.state.error ?? '无法加载工作区，请检查网络后重试。';
    const retry = document.createElement('button');
    retry.type = 'button';
    retry.textContent = '重试';
    retry.addEventListener('click', () => void this.loadWorkspace());
    page.append(message, retry);
    root.replaceChildren(page);
  }

  private startFallback(): void {
    if (this.#fallbackTimer !== undefined || !this.#active) return;
    this.#fallbackTimer = globalThis.setInterval(() => {
      if (document.visibilityState === 'visible' && this.dependencies.sync.state.snapshot) void this.dependencies.sync.pull();
    }, 10_000);
  }

  private stopFallback(): void {
    if (this.#fallbackTimer !== undefined) globalThis.clearInterval(this.#fallbackTimer);
    this.#fallbackTimer = undefined;
  }

  private stopWorkspace(): void {
    this.#workspaceView?.();
    this.#workspaceView = undefined;
    this.#socket?.dispose();
    this.#socket = undefined;
    this.stopFallback();
  }

  private disposeViews(): void {
    this.#loginView?.();
    this.#loginView = undefined;
    this.stopWorkspace();
  }
}
