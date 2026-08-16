# Project Foundation And Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first runnable vertical slice with Python 3.12/FastAPI, PostgreSQL migrations, Docker Compose, and Flutter Android/Web login for the two fixed users.

**Architecture:** Keep one repository with `backend/`, `client/`, `deploy/`, and `docs/`. FastAPI owns configuration, migrations, user seeding, password hashing, JWT issuance, refresh-session rotation, and HTTP error mapping; SQLAlchemy 2.0 is the database boundary and Alembic owns schema history. Flutter consumes the stable JSON API through injected clients and a session controller.

**Tech Stack:** Python 3.12, FastAPI, Uvicorn, SQLAlchemy 2.0, psycopg, Alembic, Pydantic Settings, bcrypt, PyJWT, pytest, HTTPX, Flutter/Dart, Docker Compose.

**Spec:** `docs/superpowers/specs/2026-08-16-project-foundation-design.md`

**Progress Record:** `docs/05-development-status.md`

## Global Constraints

- The application has exactly two fixed users; no registration, invitation, multi-tenancy, RBAC, OAuth, password change, WebSocket, Push, Redis, MQ, or AI features.
- The fixed phone numbers are `15028180169` and `15068128726`; phone, user ID, and avatar key are immutable.
- The shared initial password comes from `AUTH_PASSWORD`; plaintext passwords and tokens never enter the database or repository.
- Access Token defaults to 15 minutes and Refresh Token defaults to 30 days; refresh rotates and revokes the prior session.
- API times use ISO 8601; database absolute timestamps use UTC; client display uses `Asia/Shanghai`.
- API errors use `{code,message,details}` and never expose SQL, passwords, or tokens.
- Every task ends with its focused test command, a status-document update, and a small Git commit.

---

### Task 1: Python Runtime And Configuration Skeleton

**Files:**
- Create: `backend/pyproject.toml`, `backend/app/__init__.py`, `backend/app/main.py`
- Create: `backend/app/core/config.py`, `backend/tests/core/test_config.py`
- Create: `backend/Dockerfile`, `deploy/docker-compose.yml`, `deploy/.env.example`, `Makefile`

**Interfaces:**
- `Settings` is a Pydantic Settings model with validated `database_url`, secrets, token TTLs, `http_host`, and `http_port`.
- `get_settings() -> Settings` caches one settings instance for process lifetime.
- `app.main:create_app() -> FastAPI` returns an app with `/healthz`; it must not report healthy before startup initialization completes.

- [ ] **Step 1: Write configuration tests first**

Use `monkeypatch` to assert complete environment parsing, defaults (`0.0.0.0`, `8080`, 15 minutes, 30 days), missing required values, malformed durations, and secrets shorter than 32 bytes.

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `cd backend && python -m pytest tests/core/test_config.py -q`

Expected: FAIL because the package and `Settings` model do not exist.

- [ ] **Step 3: Implement settings and minimal FastAPI app**

Use `pydantic-settings` with explicit aliases for environment names. Parse TTLs as `timedelta`, reject empty required secrets, and expose a health flag controlled by application lifespan.

- [ ] **Step 4: Add package metadata and runtime files**

Declare Python `>=3.12`, runtime dependencies, and test dependencies in `pyproject.toml`. Add Uvicorn entry point, Python 3.12-slim Dockerfile, Compose PostgreSQL service with healthcheck, API service environment wiring, `.env.example`, and Make targets `test`, `backend-test`, `compose-up`, and `compose-down`.

- [ ] **Step 5: Run tests, lint-level checks, and Compose config**

Run: `cd backend && python -m pytest`; `python -m compileall app`; `docker compose -f ../deploy/docker-compose.yml config`

Expected: tests pass, bytecode compilation succeeds, and Compose renders without committed secret values.

- [ ] **Step 6: Update progress and commit**

Record the test commands and result in `docs/05-development-status.md`, then commit:

```bash
git add backend deploy Makefile docs/05-development-status.md
git commit -m "build: add Python runtime and local PostgreSQL skeleton"
```

### Task 2: SQLAlchemy Models, Alembic Migration, And Fixed Users

**Files:**
- Create: `backend/alembic.ini`, `backend/alembic/env.py`, `backend/alembic/versions/0001_users_sessions.py`
- Create: `backend/app/db/session.py`, `backend/app/db/base.py`
- Create: `backend/app/user/models.py`, `backend/app/user/repository.py`, `backend/app/user/service.py`
- Create: `backend/tests/db/test_migrations.py`, `backend/tests/user/test_repository.py`, `backend/tests/user/test_service.py`
- Modify: `backend/app/main.py`

**Interfaces:**
- `run_migrations()` invokes Alembic upgrade to head before the app is healthy.
- `UserRepository.find_by_phone`, `find_by_id`, `list_users`, and `update_profile` use SQLAlchemy sessions and parameterized ORM expressions.
- `seed_fixed_users(session, auth_password)` creates exactly the two users with `INSERT ... ON CONFLICT` semantics and never resets existing mutable fields.

- [ ] **Step 1: Write repository and seed tests first**

Use a temporary PostgreSQL database in Compose for integration tests. Cover lookup by phone, stable two-user listing, profile update whitelist, empty-database seeding, repeated seeding, and preservation of changed nickname/role/password hash on the second run.

- [ ] **Step 2: Run focused tests and verify they fail**

Run: `cd backend && python -m pytest tests/db tests/user -q`

Expected: FAIL because the models, migration, and repository do not exist.

- [ ] **Step 3: Add SQLAlchemy metadata and Alembic revision**

Create `users` and `sessions` with UUID keys, unique phone, UTC timestamps, `revoked_at`, and a foreign key from sessions to users. Configure Alembic from `DATABASE_URL`, with transactional upgrade and a clear failure path.

- [ ] **Step 4: Implement repository and fixed-user seed service**

Use bcrypt before persistence. Seed phones `15028180169` and `15068128726`, deterministic avatar keys, and explicit defaults. Query first and insert only missing rows; never overwrite an existing password, nickname, role, or avatar.

- [ ] **Step 5: Wire lifespan startup order**

Open the SQLAlchemy engine, run Alembic, seed users, then set the health flag. Dispose the engine during shutdown; any migration or seed exception prevents healthy status.

- [ ] **Step 6: Run integration verification**

Run: `make compose-up`; `cd backend && python -m pytest`; execute the seed path twice and query `SELECT count(*) FROM users`.

Expected: tests pass and the count remains `2` after the second initialization.

- [ ] **Step 7: Update progress and commit**

Record migration and seed verification in the progress document, then commit:

```bash
git add backend docs/05-development-status.md
git commit -m "feat: add SQLAlchemy schema and fixed-user initialization"
```

### Task 3: Passwords, JWTs, And Refresh Sessions

**Files:**
- Create: `backend/app/auth/passwords.py`, `backend/app/auth/tokens.py`, `backend/app/auth/service.py`, `backend/app/auth/session_repository.py`
- Create: `backend/tests/auth/test_passwords.py`, `backend/tests/auth/test_tokens.py`, `backend/tests/auth/test_service.py`
- Modify: `backend/app/user/repository.py`

**Interfaces:**
- `hash_password(plain: str) -> str` and `verify_password(plain: str, hashed: str) -> bool`.
- `TokenManager.issue_access(user_id: UUID, now: datetime) -> str` and `parse_access(token: str) -> AccessClaims`.
- `AuthService.login`, `refresh`, and `logout` return typed results and map invalid credentials/session state to `UnauthenticatedError`.
- Session persistence exposes create, find-by-hash, and revoke operations, with refresh rotation in one database transaction.

- [ ] **Step 1: Write failing password and token tests**

Assert bcrypt hashes differ from plaintext, correct passwords verify, wrong passwords fail, access claims include user ID/type/expiry, wrong signing key fails, refresh claims cannot be accepted as access claims, and expired tokens fail.

- [ ] **Step 2: Run focused tests and verify they fail**

Run: `cd backend && python -m pytest tests/auth/test_passwords.py tests/auth/test_tokens.py -q`

Expected: FAIL because auth modules are absent.

- [ ] **Step 3: Implement password and token primitives**

Use bcrypt, separate access and refresh secrets, UUID subject, token type, issued-at, and expiry claims. Parse JWTs with strict algorithm and type checks.

- [ ] **Step 4: Write failing service tests**

Cover successful login, wrong password, unknown phone, refresh rotation, expired/revoked refresh session, and idempotent logout. Assert the old refresh session is revoked before the new session is returned.

- [ ] **Step 5: Implement auth service and session repository**

Login loads by phone, verifies the password, generates a cryptographically random refresh token, stores only its SHA-256 hash, and returns user plus tokens. Refresh hashes the presented token, checks expiry/revocation, revokes it, and creates a replacement atomically. Logout is idempotent.

- [ ] **Step 6: Run all backend tests and update progress**

Run: `cd backend && python -m pytest`; `python -m compileall app`; record results in `docs/05-development-status.md`.

- [ ] **Step 7: Commit**

```bash
git add backend docs/05-development-status.md
git commit -m "feat: implement password JWT and refresh-session services"
```

### Task 4: FastAPI Routes, Middleware, And Error Contract

**Files:**
- Create: `backend/app/httpapi/errors.py`, `backend/app/httpapi/dependencies.py`, `backend/app/auth/routes.py`, `backend/app/user/routes.py`
- Create: `backend/tests/httpapi/test_auth_routes.py`, `backend/tests/httpapi/test_user_routes.py`
- Modify: `backend/app/main.py`

**Interfaces:**
- Routes: `GET /healthz`, `POST /api/auth/login`, `POST /api/auth/refresh`, `POST /api/auth/logout`, `GET /api/me`, `PATCH /api/me`, `GET /api/users`.
- `require_access_token` injects the authenticated user ID and rejects missing/invalid access tokens with `401`.
- Exception handlers emit `{code,message,details}` and an `X-Request-ID` header.

- [ ] **Step 1: Write route tests first**

Use FastAPI `TestClient`/HTTPX and dependency overrides. Cover login success/invalid credentials, refresh, logout, protected `/api/me`, profile field whitelist, users listing, malformed JSON, and health check.

- [ ] **Step 2: Run focused tests and verify they fail**

Run: `cd backend && python -m pytest tests/httpapi -q`

Expected: FAIL because routes and exception handlers are absent.

- [ ] **Step 3: Implement errors, request IDs, and authentication dependency**

Generate or propagate `X-Request-ID`, set JSON content type, map domain errors to exact HTTP codes, and log only method/path/status/request ID.

- [ ] **Step 4: Implement request/response schemas and routes**

Use Pydantic models with strict field sets, validate phone/password/profile fields, call service interfaces, and reject immutable fields instead of silently ignoring them.

- [ ] **Step 5: Run API smoke verification**

Run: `cd backend && python -m pytest`; start the Compose API and execute login, `/api/me`, profile patch, refresh, and logout with `curl`.

Expected: protected endpoints reject absent/refresh tokens, profile changes are visible through a second login, and revoked refresh tokens fail.

- [ ] **Step 6: Update progress and commit**

```bash
git add backend docs/05-development-status.md
git commit -m "feat: expose authentication and user profile API"
```

### Task 5: Flutter Client Shell And Session Flow

**Files:**
- Create: `client/` Flutter project files using `flutter create --platforms=android,web client`
- Create/Modify: `client/lib/core/config.dart`, `client/lib/core/api_client.dart`, `client/lib/auth/token_store.dart`, `client/lib/auth/auth_repository.dart`, `client/lib/auth/session_controller.dart`
- Create/Modify: `client/lib/models/user.dart`, `client/lib/screens/login_screen.dart`, `client/lib/screens/account_screen.dart`, `client/lib/app.dart`, `client/test/auth/session_controller_test.dart`, `client/test/widget/login_screen_test.dart`

**Interfaces:**
- `ApiClient.request` handles JSON, bearer headers, one refresh retry on `401`, and typed `ApiException`.
- `TokenStore` exposes `read`, `write`, and `clear`.
- `AuthRepository` exposes `login`, `refresh`, `logout`, `me`, `users`, and `updateProfile`.
- `SessionController` exposes observable states `signedOut`, `loading`, `signedIn`, and `failure`.

- [ ] **Step 1: Generate Flutter shell and write controller tests**

Create the Android/Web project, then test successful login, invalid login, refresh recovery, refresh failure clearing storage, and logout with fake API and in-memory token store implementations.

- [ ] **Step 2: Run Flutter tests and verify they fail**

Run: `cd client && flutter test test/auth/session_controller_test.dart`

Expected: FAIL because the session controller and repository interfaces are absent.

- [ ] **Step 3: Implement models, token storage, API client, and repository**

Use explicit JSON fields, configurable `API_BASE_URL`, platform-safe token storage, and exactly one refresh retry for a failed authenticated request. Never log authorization headers or token bodies.

- [ ] **Step 4: Implement session controller and screens**

Render login validation, loading, user-readable errors, an account screen with current/both users, editable nickname/role fields, save/error state, and logout.

- [ ] **Step 5: Run Flutter tests, analysis, and builds**

Run: `cd client && dart format --output=none --set-exit-if-changed .`; `flutter analyze`; `flutter test`; `flutter build web --dart-define=API_BASE_URL=http://localhost:8080`; `flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080`.

Expected: tests and analysis pass, and both builds complete.

- [ ] **Step 6: Update progress and commit**

```bash
git add client docs/05-development-status.md
git commit -m "feat: add Flutter login and account shell"
```

### Task 6: Compose Integration, CI, And End-To-End Acceptance

**Files:**
- Create: `.github/workflows/ci.yml`, `scripts/smoke-auth.sh`
- Modify: `deploy/docker-compose.yml`, `deploy/.env.example`, `Makefile`, `docs/README.md`, `docs/05-development-status.md`

**Interfaces:**
- Compose starts a healthy API only after PostgreSQL migration and fixed-user seeding succeed.
- CI runs Python tests/compile checks and Flutter format/analyze/test on every push.
- Smoke test accepts `API_BASE_URL` and credentials through environment variables and does not print secrets.

- [ ] **Step 1: Write the smoke acceptance script**

Exercise health, both fixed-user logins, `/api/users`, profile update, refresh rotation, and logout. Fail if a revoked refresh token succeeds or if user count is not exactly two.

- [ ] **Step 2: Run the script against a clean Compose database**

Run: `make compose-down`; `make compose-up`; `API_BASE_URL=http://localhost:8080 ./scripts/smoke-auth.sh`

Expected: the script completes only after API health, migration, seed, and all auth flows are wired.

- [ ] **Step 3: Finish Compose and CI wiring**

Add API healthcheck, dependency condition on healthy PostgreSQL, persistent database volume, non-secret environment template, and CI jobs. Keep PostgreSQL ports unexposed in Compose.

- [ ] **Step 4: Run the complete verification suite**

Run: `make test`; `make compose-down`; `make compose-up`; `API_BASE_URL=http://localhost:8080 ./scripts/smoke-auth.sh`; `cd client && flutter build web --dart-define=API_BASE_URL=http://localhost:8080`.

Expected: all tests pass, smoke flow completes for both users, API remains healthy after restart, and repeated startup does not duplicate users or reset profile data.

- [ ] **Step 5: Update project index and commit**

```bash
git add .github deploy Makefile docs/README.md docs/05-development-status.md scripts
git commit -m "ci: verify local authentication deployment flow"
```

## Self-Review Checklist

- Spec coverage: runtime skeleton (Task 1), schema/seed (Task 2), auth semantics (Task 3), API contract (Task 4), client flow (Task 5), and end-to-end acceptance (Task 6).
- Placeholder scan: no unresolved placeholder or unspecified implementation step is required by this plan.
- Type consistency: `Settings`, `TokenManager`, `TokenStore`, `AuthRepository`, and `SessionController` interfaces are named once and consumed consistently by later tasks.
- Scope: no task introduces task management, events, recurring work, comments, conflict UI, analytics, or production ECS deployment.
