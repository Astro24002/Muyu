import './styles.css';
import { ApiClient } from './api/client';
import { App } from './app';
import { QrLoginController } from './auth/qr-login';
import { WorkspaceSyncController } from './sync/workspace-sync';

const api = new ApiClient();
const app = new App({
  api,
  login: new QrLoginController(api),
  sync: new WorkspaceSyncController(api),
});

app.mount(document.querySelector('#app')!);
