import { Activity, ClipboardCheck, MonitorSmartphone } from 'lucide-react';
import type { JSX } from 'react';
import { navigate } from '../app/routes';
import type { WebSessionApi } from '../components/account/web-session-api';
import { WebSessionPanel } from '../components/account/WebSessionPanel';

export function MyPage({ sessionApi, onAuthRequired }: { sessionApi?: WebSessionApi; onAuthRequired?: () => void }): JSX.Element {
  return (
    <main className="my-page" data-my-page>
      <header className="my-page__header"><p className="my-page__eyebrow">账户与 Workspace</p><h1>我的</h1></header>
      <nav className="my-page__links" aria-label="我的入口">
        <button type="button" onClick={() => navigate('approvals')}><ClipboardCheck aria-hidden="true" size={17} />审批</button>
        <button type="button" onClick={() => navigate('activity')}><Activity aria-hidden="true" size={17} />动态</button>
        <button type="button" onClick={() => navigate('me')}><MonitorSmartphone aria-hidden="true" size={17} />设备与会话</button>
      </nav>
      {sessionApi ? <WebSessionPanel api={sessionApi} onAuthRequired={onAuthRequired} /> : null}
    </main>
  );
}
