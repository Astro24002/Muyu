import { createRoot } from 'react-dom/client';
import './styles/tokens.css';
import './styles/global.css';
import { ApiClient } from './api/client';
import { App } from './app/App';
import { QrLoginController } from './auth/qr-login';
import { WorkspaceSyncController } from './sync/workspace-sync';

const api = new ApiClient();
const login = new QrLoginController(api);
const sync = new WorkspaceSyncController(api);
const root = document.querySelector('#app');

if (!root) throw new Error('Muyu app root not found');

root.classList.add('muyu-react-root');
createRoot(root).render(<App api={api} login={login} sync={sync} />);
