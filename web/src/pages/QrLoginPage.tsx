import QRCode from 'qrcode';
import { CheckCircle2, LoaderCircle, RefreshCw, RotateCcw } from 'lucide-react';
import { useEffect, useRef, type JSX } from 'react';
import type { QrLoginController, QrLoginState } from '../auth/qr-login';
import { useQrLoginState } from '../app/use-external-state';
import { InlineError } from '../components/status/InlineError';
import { Button } from '../components/ui/Button';

export interface QrLoginPageProps {
  controller?: QrLoginController;
  login?: QrLoginController;
  state?: QrLoginState;
  onSignedIn?: () => void;
}

const EMPTY_LOGIN = {
  state: { kind: 'signed_out' } as const,
  start: async () => undefined,
  poll: async () => undefined,
  subscribe: () => () => undefined,
};

export function QrLoginPage({ controller: controllerProp, login: loginProp, state, onSignedIn }: QrLoginPageProps): JSX.Element {
  const controller = controllerProp ?? loginProp ?? EMPTY_LOGIN as unknown as QrLoginController;
  const liveState = useQrLoginState(controller);
  const currentState = state ?? liveState;
  const signedInNotified = useRef(false);

  useEffect(() => {
    if (currentState.kind !== 'signed_in') {
      signedInNotified.current = false;
      return;
    }
    if (signedInNotified.current || !onSignedIn) return;
    signedInNotified.current = true;
    onSignedIn();
  }, [currentState.kind, onSignedIn]);

  return (
    <main className="qr-login-page" aria-labelledby="qr-login-title" data-testid="qr-login-page">
      <div className="qr-login-page__panel">
        <div className="qr-login-page__brand" aria-hidden="true">MUYU</div>
        <h1 id="qr-login-title">二维码登录</h1>
        <p className="qr-login-page__intro">用手机确认后，在浏览器继续。</p>
        <LoginState state={currentState} controller={controller} />
      </div>
    </main>
  );
}

function LoginState({ state, controller }: { state: QrLoginState; controller: QrLoginController }): JSX.Element {
  if (state.kind === 'waiting_for_approval' || state.kind === 'exchanging') {
    return <ChallengeState state={state} controller={controller} />;
  }

  if (state.kind === 'creating') {
    return (
      <section className="qr-login-state" aria-busy="true" aria-live="polite">
        <div className="qr-login-status qr-login-status--loading">
          <LoaderCircle aria-hidden="true" size={17} strokeWidth={1.9} />
          <span>正在生成二维码。</span>
        </div>
      </section>
    );
  }

  if (state.kind === 'signed_in') {
    return (
      <section className="qr-login-state" aria-live="polite">
        <div className="qr-login-status qr-login-status--success">
          <CheckCircle2 aria-hidden="true" size={17} strokeWidth={1.9} />
          <span>登录成功。</span>
        </div>
      </section>
    );
  }

  if (state.kind === 'expired' || state.kind === 'failure') {
    return (
      <section className="qr-login-state">
        <InlineError message={state.message} />
        <RegenerateButton controller={controller} />
      </section>
    );
  }

  return (
    <section className="qr-login-state" aria-live="polite">
      <p className="qr-login-status">请生成二维码登录。</p>
      <RegenerateButton controller={controller} />
    </section>
  );
}

function ChallengeState({
  state,
  controller,
}: {
  state: Extract<QrLoginState, { kind: 'waiting_for_approval' | 'exchanging' }>;
  controller: QrLoginController;
}): JSX.Element {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const renderGenerationRef = useRef(0);
  const { challenge } = state;

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return undefined;
    const generation = ++renderGenerationRef.current;
    let active = true;

    const isCurrent = (): boolean => (
      active
      && generation === renderGenerationRef.current
      && canvasRef.current === canvas
      && canvas.isConnected
    );
    const invalidate = (): void => {
      active = false;
      if (renderGenerationRef.current === generation) renderGenerationRef.current += 1;
    };

    let renderPromise: Promise<HTMLCanvasElement>;
    try {
      renderPromise = QRCode.toCanvas(challenge.qr_payload, { margin: 1, width: 240 });
    } catch {
      if (isCurrent()) canvas.dataset.renderError = 'true';
      return invalidate;
    }

    void renderPromise
      .then((renderedCanvas) => {
        if (!isCurrent()) return;
        const context = canvas.getContext('2d');
        if (!context) throw new Error('QR canvas context unavailable');
        canvas.width = renderedCanvas.width;
        canvas.height = renderedCanvas.height;
        context.drawImage(renderedCanvas, 0, 0);
      })
      .catch(() => {
        if (isCurrent()) canvas.dataset.renderError = 'true';
      });

    return invalidate;
  }, [challenge.challenge_id, challenge.qr_payload]);

  const exchanging = state.kind === 'exchanging';
  return (
    <section className="qr-login-state qr-login-state--challenge" aria-busy={exchanging ? 'true' : undefined}>
      <canvas ref={canvasRef} className="qr-login__canvas" role="img" aria-label="登录二维码" />
      <dl className="qr-login__details">
        <div>
          <dt>安全码</dt>
          <dd><code>{challenge.safety_code}</code></dd>
        </div>
        <div>
          <dt>当前站点</dt>
          <dd>{challenge.origin}</dd>
        </div>
        <div>
          <dt>过期时间</dt>
          <dd>{formatExpiration(challenge.expires_at)}</dd>
        </div>
      </dl>
      <p className="qr-login-status" aria-live="polite">
        {exchanging ? '正在完成登录。' : '请在手机上确认登录。'}
      </p>
      <div className="qr-login__actions">
        <Button tone="neutral" disabled={exchanging} onClick={() => void controller.poll()}>
          <RefreshCw aria-hidden="true" size={16} strokeWidth={1.9} />
          检查授权状态
        </Button>
        {!exchanging ? <RegenerateButton controller={controller} /> : null}
      </div>
    </section>
  );
}

function RegenerateButton({ controller }: { controller: QrLoginController }): JSX.Element {
  return (
    <Button tone="primary" onClick={() => void controller.start()}>
      <RotateCcw aria-hidden="true" size={16} strokeWidth={1.9} />
      重新生成二维码
    </Button>
  );
}

function formatExpiration(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
}
