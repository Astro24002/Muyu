# Web Development

The browser client is a TypeScript + Vite single-page application. FastAPI
provides JSON and WebSocket APIs only; the browser does not create an offline
fact store or submit writes while disconnected.

## Local startup

Run the API and Vite development server in separate terminals:

```bash
# terminal 1
cd backend
DATABASE_URL=postgresql+psycopg://muyu:change-this-local-database-password@localhost:5432/muyu_cloud \
  uvicorn app.main:create_app --factory --reload --port 8080

# terminal 2
cd web
npm ci
npm run dev
```

Vite serves the browser client on its development port and proxies `/api` and
the realtime WebSocket path to `http://localhost:8080`. Production Caddy uses
the same-origin `/api` paths, so no API secret is bundled into the static
files.

Sign in to the browser by scanning its QR code with an approved Android device.
The browser keeps the proof only in memory and receives an HttpOnly session
cookie after approval. Android remains the active QR approval client; there is
no browser SMS-login flow. Sessions expire after the server-defined maximum and
can be revoked from any approved Android device.

Use the refresh control to request the latest cursor. WebSocket messages are
notifications only; REST snapshot/change responses remain the source of truth.
