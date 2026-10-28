import { createRoot } from 'react-dom/client';
import './styles/tokens.css';
import './styles/global.css';
import { ApiClient } from './api/client';
import { App } from './app/App';
import { QrLoginController } from './auth/qr-login';
import { WorkspaceSyncController } from './sync/workspace-sync';
import { ApprovalPreviewPage } from './pages/ApprovalPreviewPage';
import { AndroidApprovalPreviewPage } from './pages/AndroidApprovalPreviewPage';
import { ApprovalCardOptionsPage } from './pages/ApprovalCardOptionsPage';
import { QuadrantPreviewPage } from './pages/QuadrantPreviewPage';
import { MattersPreviewPage } from './pages/MattersPreviewPage';

const api = new ApiClient();
const login = new QrLoginController(api);
const sync = new WorkspaceSyncController(api);
const root = document.querySelector('#app');

if (!root) throw new Error('Muyu app root not found');

root.classList.add('muyu-react-root');
const preview = new URLSearchParams(typeof window === 'undefined' ? '' : window.location.search).get('preview');
createRoot(root).render(import.meta.env.DEV && preview === 'approval-options'
  ? <ApprovalCardOptionsPage />
  : import.meta.env.DEV && preview === 'matters'
    ? <MattersPreviewPage />
  : import.meta.env.DEV && preview === 'quadrants'
    ? <QuadrantPreviewPage />
  : import.meta.env.DEV && preview === 'android-approvals'
    ? <AndroidApprovalPreviewPage />
  : import.meta.env.DEV && preview === 'approvals'
    ? <ApprovalPreviewPage />
  : <App api={api} login={login} sync={sync} />);
