import QRCode from 'qrcode';
import type { QrLoginController, QrLoginState } from '../auth/qr-login';

export class QrLoginView {
  static mount(root: Element, controller: QrLoginController, onSignedIn: () => void): () => void {
    let signedInNotified = false;
    const render = (state: QrLoginState) => {
      root.replaceChildren();
      const section = document.createElement('section');
      section.className = 'qr-login';
      const heading = document.createElement('h1');
      heading.textContent = '二维码登录';
      section.append(heading);

      const status = document.createElement('p');
      status.setAttribute('aria-live', 'polite');
      section.append(status);

      if (state.kind === 'waiting_for_approval' || state.kind === 'exchanging') {
        const canvas = document.createElement('canvas');
        canvas.setAttribute('aria-label', '登录二维码');
        section.append(canvas);
        void QRCode.toCanvas(canvas, state.challenge.qr_payload, { margin: 1, width: 240 });
        appendDetail(section, '安全码', state.challenge.safety_code);
        appendDetail(section, '当前站点', state.challenge.origin);
        appendDetail(section, '过期时间', new Date(state.challenge.expires_at).toLocaleString());
        status.textContent = state.kind === 'exchanging' ? '正在完成登录。' : '请在手机上确认登录。';
        appendButton(section, '检查授权状态', 'poll', () => void controller.poll());
      } else if (state.kind === 'creating') {
        status.textContent = '正在生成二维码。';
      } else if (state.kind === 'signed_in') {
        status.textContent = '登录成功。';
        if (!signedInNotified) {
          signedInNotified = true;
          onSignedIn();
        }
      } else if (state.kind === 'expired' || state.kind === 'failure') {
        status.textContent = state.message;
      } else {
        status.textContent = '请生成二维码登录。';
      }

      if (state.kind !== 'signed_in') appendButton(section, '重新生成二维码', 'retry', () => void controller.start());
      root.append(section);
    };

    const unsubscribe = controller.subscribe(render);
    render(controller.state);
    return () => unsubscribe();
  }
}

function appendDetail(parent: Element, label: string, value: string): void {
  const detail = document.createElement('p');
  detail.textContent = `${label}: ${value}`;
  parent.append(detail);
}

function appendButton(parent: Element, label: string, action: string, handler: () => void): void {
  const button = document.createElement('button');
  button.type = 'button';
  button.dataset.action = action;
  button.textContent = label;
  button.addEventListener('click', handler);
  parent.append(button);
}
