# Task 1 Report: Web工程与 API 客户端边界

## Status

DONE_WITH_CONCERNS

## Files changed

- `web/package.json`, `web/package-lock.json`: Vite/TypeScript/Vitest package with required scripts and dependencies.
- `web/tsconfig.json`, `web/vite.config.ts`, `web/index.html`, `web/.gitignore`: strict browser build/test configuration, same-origin `/api` proxy to `http://localhost:8080` with WebSocket support.
- `web/src/config.ts`: `VITE_API_BASE_URL` configuration with same-origin fallback.
- `web/src/api/types.ts`: snake_case API boundary types for web login, sync, and task payloads.
- `web/src/api/client.ts`: typed `ApiClient`, `ApiError`, request normalization, JSON problem parsing, and endpoint methods.
- `web/src/main.ts`, `web/src/style.css`: minimal Vite entrypoint required for builds.
- `web/test/setup.ts`, `web/test/api-client.test.ts`: focused API client tests.

## Verification

Initial focused test command before implementation:

```text
npm test -- --run test/api-client.test.ts
FAIL: npm could not find web/package.json (expected pre-scaffold failure)
```

Final commands from `web/`:

```text
npm test -- --run test/api-client.test.ts
Test Files  1 passed; Tests 4 passed

npm run typecheck
tsc --noEmit exited 0

npm run build
vite build exited 0; production assets generated in dist/
```

## Decisions

- Requests always use `credentials: 'include'` and `Accept: application/json`; object bodies are JSON encoded and receive `Content-Type: application/json`.
- Caller-provided headers are merged after defaults, preserving explicit overrides.
- Non-2xx responses expose only safe API problem fields, with `REQUEST_FAILED` / `请求失败，请稍后重试` fallback for invalid or non-JSON bodies.
- Endpoint methods keep backend snake_case at the wire boundary while offering the specified camelCase TypeScript inputs.

## Concerns

- `TaskItem` includes an index signature because the backend snapshot contains a broad evolving field set; later tasks may tighten individual fields as UI usage is added.
- Vite 8 emits no warnings with the ESM URL-based root configuration; generated `web/dist/` is ignored by `.gitignore`.
