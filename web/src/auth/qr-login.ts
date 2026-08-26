import type { ApiClient } from '../api/client';
import { ApiError } from '../api/client';
import type { WebChallenge } from '../api/types';

export type QrLoginState =
  | { kind: 'signed_out' }
  | { kind: 'creating' }
  | { kind: 'waiting_for_approval'; challenge: WebChallenge }
  | { kind: 'exchanging'; challenge: WebChallenge }
  | { kind: 'signed_in'; expiresAt: string }
  | { kind: 'expired'; message: string }
  | { kind: 'failure'; message: string };

type TimerHandle = ReturnType<typeof globalThis.setInterval>;

export interface QrLoginOptions {
  clock?: () => number;
  setInterval?: (handler: () => void, timeout: number) => TimerHandle;
  clearInterval?: (timer: TimerHandle) => void;
  origin?: () => string;
  crypto?: Crypto;
}

export class QrLoginController {
  #api: ApiClient;
  #clock: () => number;
  #setInterval: (handler: () => void, timeout: number) => TimerHandle;
  #clearInterval: (timer: TimerHandle) => void;
  #origin: () => string;
  #crypto: Crypto;
  #state: QrLoginState = { kind: 'signed_out' };
  #listeners = new Set<(state: QrLoginState) => void>();
  #timer: TimerHandle | undefined;
  #challenge: WebChallenge | undefined;
  #browserProof: string | undefined;
  #pollingGeneration: number | undefined;
  #disposed = false;
  #generation = 0;

  constructor(api: ApiClient, options: QrLoginOptions = {}) {
    this.#api = api;
    this.#clock = options.clock ?? Date.now;
    this.#setInterval = options.setInterval ?? ((handler, timeout) => globalThis.setInterval(handler, timeout));
    this.#clearInterval = options.clearInterval ?? ((timer) => globalThis.clearInterval(timer));
    this.#origin = options.origin ?? (() => window.location.origin);
    this.#crypto = options.crypto ?? globalThis.crypto;
  }

  get state(): QrLoginState {
    return this.#state;
  }

  subscribe(listener: (state: QrLoginState) => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  async start(): Promise<void> {
    if (this.#disposed || this.#state.kind === 'exchanging') return;
    const generation = ++this.#generation;
    this.#stopPolling();
    this.#pollingGeneration = undefined;
    this.#challenge = undefined;
    this.#browserProof = undefined;
    this.#setState({ kind: 'creating' });
    try {
      const proof = this.#newProof();
      this.#browserProof = proof;
      const challenge = await this.#api.createWebChallenge({
        origin: this.#origin(),
        browserProofHash: await this.#sha256(proof),
      });
      if (this.#disposed || generation !== this.#generation) return;
      if (this.#hasExpired(challenge.expires_at)) {
        this.#expire();
        return;
      }
      this.#challenge = challenge;
      this.#setState({ kind: 'waiting_for_approval', challenge });
      this.#timer = this.#setInterval(() => void this.poll(), 2_000);
    } catch {
      if (!this.#disposed && generation === this.#generation) this.#fail('无法生成二维码，请重试。');
    }
  }

  async poll(): Promise<void> {
    const challenge = this.#challenge;
    if (this.#disposed || !challenge || this.#isTerminal()) return;
    const generation = this.#generation;
    if (this.#pollingGeneration === generation) return;
    if (this.#hasExpired(challenge.expires_at)) {
      this.#expire();
      return;
    }
    this.#pollingGeneration = generation;
    try {
      const status = await this.#api.getWebChallengeStatus(challenge.challenge_id);
      if (this.#disposed || generation !== this.#generation || this.#challenge?.challenge_id !== challenge.challenge_id) return;
      if (status.status === 'APPROVED') {
        await this.#exchange(challenge, generation);
      } else if (status.status === 'EXPIRED' || status.status === 'REVOKED' || this.#hasExpired(status.expires_at)) {
        this.#expire();
      }
    } catch (error) {
      if (this.#disposed || generation !== this.#generation) return;
      if (error instanceof ApiError && (error.status === 401 || error.status === 410)) this.#expire();
      else this.#fail('无法检查授权状态，请重试。');
    } finally {
      if (this.#pollingGeneration === generation) this.#pollingGeneration = undefined;
    }
  }

  stop(): void {
    ++this.#generation;
    this.#stopPolling();
    this.#pollingGeneration = undefined;
    this.#challenge = undefined;
    this.#browserProof = undefined;
    this.#setState({ kind: 'signed_out' });
  }

  dispose(): void {
    if (this.#disposed) return;
    this.stop();
    this.#disposed = true;
    this.#listeners.clear();
  }

  async #exchange(challenge: WebChallenge, generation: number): Promise<void> {
    const proof = this.#browserProof;
    if (!proof) {
      this.#fail('二维码已失效，请重新生成。');
      return;
    }
    this.#stopPolling();
    this.#setState({ kind: 'exchanging', challenge });
    try {
      const session = await this.#api.exchangeWebChallenge(challenge.challenge_id, proof);
      if (this.#disposed || generation !== this.#generation) return;
      this.#browserProof = undefined;
      this.#challenge = undefined;
      this.#setState({ kind: 'signed_in', expiresAt: session.expires_at });
    } catch (error) {
      if (this.#disposed || generation !== this.#generation) return;
      if (error instanceof ApiError && (error.status === 401 || error.status === 410)) this.#expire();
      else this.#fail('无法完成登录，请重新生成二维码。');
    }
  }

  #newProof(): string {
    const bytes = this.#crypto.getRandomValues(new Uint8Array(32));
    let binary = '';
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  async #sha256(value: string): Promise<string> {
    const digest = await this.#crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
    return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('');
  }

  #hasExpired(expiresAt: string): boolean {
    const time = Date.parse(expiresAt);
    return Number.isNaN(time) || time <= this.#clock();
  }

  #isTerminal(): boolean {
    return this.#state.kind === 'signed_out' || this.#state.kind === 'signed_in' || this.#state.kind === 'expired' || this.#state.kind === 'failure';
  }

  #expire(): void {
    this.#stopPolling();
    this.#browserProof = undefined;
    this.#challenge = undefined;
    this.#setState({ kind: 'expired', message: '二维码已失效，请重新生成。' });
  }

  #fail(message: string): void {
    this.#stopPolling();
    this.#browserProof = undefined;
    this.#challenge = undefined;
    this.#setState({ kind: 'failure', message });
  }

  #stopPolling(): void {
    if (this.#timer !== undefined) this.#clearInterval(this.#timer);
    this.#timer = undefined;
  }

  #setState(state: QrLoginState): void {
    this.#state = state;
    for (const listener of this.#listeners) listener(state);
  }
}
