# Project Foundation And Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first runnable vertical slice: Go API, PostgreSQL migrations, Docker Compose, and Flutter Android/Web login with fixed two-user authentication and profile editing.

**Architecture:** Keep a single repository with `backend/`, `client/`, `deploy/`, and `docs/`. The Go API owns configuration, migrations, user seeding, password hashing, JWT issuance, refresh-session rotation, and HTTP error mapping; Flutter consumes the JSON API through injected clients and a session controller. PostgreSQL is the source of truth and Docker Compose is the local integration boundary.

**Tech Stack:** Go standard-library HTTP server, pgx/pgxpool, PostgreSQL, bcrypt, JWT, Flutter/Dart, Docker Compose.

**Spec:** `docs/superpowers/specs/2026-08-16-project-foundation-design.md`

**Progress Record:** `docs/05-development-status.md`

## Global Constraints

- The application has exactly two fixed users; no registration, invitation, multi-tenancy, RBAC, OAuth, password change, WebSocket, Push, Redis, MQ, or AI features.
- The fixed phone numbers are `15028180169` and `15068128726`; phone, user ID, and avatar key are immutable.
- The shared initial password comes from `AUTH_PASSWORD`; plaintext passwords and tokens never enter the database or repository.
- Access Token defaults to 15 minutes and Refresh Token defaults to 30 days; refresh rotates and revokes the prior session.
- API times use ISO 8601; database absolute timestamps use UTC; client display uses `Asia/Shanghai`.
- API errors use `{code,message,details}` and never expose SQL, passwords, or tokens.
- Every task ends with its focused test command and a small Git commit.
- Before implementation or scope changes, update `docs/05-development-status.md` or the relevant design/decision document; after each task, record tests, acceptance result, and next step there.

---

### Task 1: Repository And Runtime Skeleton

**Files:**
- Create: `.gitignore`, `Makefile`
- Create: `backend/go.mod`, `backend/cmd/server/main.go`
- Create: `backend/internal/config/config.go`, `backend/internal/config/config_test.go`
- Create: `deploy/docker-compose.yml`, `deploy/.env.example`
- Create: `backend/Dockerfile`

**Interfaces:**
- Produces `config.Load() (config.Config, error)` with validated runtime settings.
- Produces a `backend` Go module and an executable entry point that can later wire database and HTTP services.
- Produces Compose service names `db` and `api`, with PostgreSQL private to the Compose network.

- [ ] **Step 1: Write configuration tests first**

Test `config.Load` with a complete environment and assert parsed database URL, address, token durations, and required secrets. Add cases for missing `DATABASE_URL`, missing `AUTH_PASSWORD`, malformed duration, and an access secret shorter than 32 bytes.

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `cd backend && go test ./internal/config -run TestLoad -v`

Expected: FAIL because the module and `config.Load` do not exist.

- [ ] **Step 3: Implement validated configuration**

Define:

```go
type Config struct {
    DatabaseURL      string
    HTTPAddr         string
    AuthPassword     string
    JWTAccessSecret  []byte
    JWTRefreshSecret []byte
    AccessTokenTTL   time.Duration
    RefreshTokenTTL  time.Duration
}

func Load(getenv func(string) string) (Config, error)
```

Use defaults `:8080`, `15m`, and `720h`; reject empty required values, invalid durations, and secrets shorter than 32 bytes.

- [ ] **Step 4: Add module, entry point, Compose, and development commands**

Create the Go module with dependencies needed by later tasks, a `main` that loads config and exits with a clear error, Compose PostgreSQL healthcheck, API environment wiring, `.env.example`, Dockerfile, and Make targets `test`, `backend-test`, `compose-up`, and `compose-down`.

- [ ] **Step 5: Run tests and static checks**

Run: `cd backend && go test ./...`; `go vet ./...`; `docker compose -f ../deploy/docker-compose.yml config`

Expected: PASS, with Compose rendering a private `db` network and no committed secret values.

- [ ] **Step 6: Commit**

```bash
git add .gitignore Makefile backend deploy
git commit -m "build: add Go and local PostgreSQL runtime skeleton"
```

### Task 2: PostgreSQL Schema, Migrations, And Fixed Users

**Files:**
- Create: `backend/migrations/000001_users_sessions.sql`
- Create: `backend/internal/db/migrate.go`, `backend/internal/db/migrate_test.go`
- Create: `backend/internal/user/model.go`, `backend/internal/user/repository.go`, `backend/internal/user/repository_test.go`
- Modify: `backend/cmd/server/main.go`

**Interfaces:**
- `db.RunMigrations(ctx context.Context, pool *pgxpool.Pool) error` applies versioned SQL once and fails startup on migration errors.
- `user.Repository` exposes `FindByPhone`, `FindByID`, `List`, and `UpdateProfile`.
- `user.SeedFixedUsers(ctx, repo, authPassword)` creates exactly the two configured users without resetting existing mutable fields.

- [ ] **Step 1: Write repository and seeding tests first**

Use a pgx-compatible mock for query expectations. Cover lookup by phone, stable two-user listing, profile update whitelist, empty-database seeding, repeated seeding, and preservation of a changed nickname/role/password hash on the second run.

- [ ] **Step 2: Run focused tests and verify they fail**

Run: `cd backend && go test ./internal/db ./internal/user -v`

Expected: FAIL because schema, repository, and seeding functions are absent.

- [ ] **Step 3: Add transactional schema migration**

Create `users` and `sessions` with UUID primary keys, unique phone, UTC timestamps, `revoked_at`, and foreign-key cascade from sessions to users. Add a migration lock/table so a migration runs once and concurrent API starts cannot partially apply it.

- [ ] **Step 4: Implement repository and fixed-user seed**

Use parameterized SQL only. Seed phone numbers `15028180169` and `15068128726`, deterministic avatar keys, and explicit default nickname/role values. Use `INSERT ... ON CONFLICT (phone) DO NOTHING`; never update password, nickname, role, or avatar for existing rows. Hash `AUTH_PASSWORD` before insertion.

- [ ] **Step 5: Wire startup order**

In `main`, connect with `pgxpool`, run migrations, seed users, then construct the HTTP server. Close the pool on shutdown and return a non-zero process result if any step fails.

- [ ] **Step 6: Run tests and database smoke check**

Run: `cd backend && go test ./...`; `docker compose -f deploy/docker-compose.yml up -d db`; run the migration/seed command twice and query `SELECT count(*) FROM users`.

Expected: tests pass and the count remains `2` after the second initialization.

- [ ] **Step 7: Commit**

```bash
git add backend/cmd/server/main.go backend/migrations backend/internal/db backend/internal/user
git commit -m "feat: add users sessions schema and fixed-user initialization"
```

### Task 3: Passwords, JWTs, And Refresh Sessions

**Files:**
- Create: `backend/internal/auth/password.go`, `backend/internal/auth/password_test.go`
- Create: `backend/internal/auth/token.go`, `backend/internal/auth/token_test.go`
- Create: `backend/internal/auth/service.go`, `backend/internal/auth/service_test.go`
- Create: `backend/internal/auth/session_repository.go`, `backend/internal/auth/session_repository_test.go`
- Modify: `backend/internal/user/repository.go`

**Interfaces:**
- `HashPassword(plain string) ([]byte, error)` and `ComparePassword(hash, plain []byte) error`.
- `TokenManager.IssueAccess(userID uuid.UUID, now time.Time) (string, error)` and `TokenManager.ParseAccess(token string) (AccessClaims, error)`.
- `AuthService.Login`, `Refresh`, and `Logout` return typed results and map invalid credentials/session state to `ErrUnauthenticated`.
- Session persistence exposes create, find-by-hash, and revoke operations.

- [ ] **Step 1: Write failing password and token tests**

Assert bcrypt hashes differ from plaintext, correct passwords verify, wrong passwords fail, access claims include user ID/type/expiry, wrong signing key fails, refresh claims cannot be accepted as access claims, and expired tokens fail.

- [ ] **Step 2: Run focused tests and verify they fail**

Run: `cd backend && go test ./internal/auth -run 'Test(Hash|Compare|Token)' -v`

Expected: FAIL because auth types and functions are absent.

- [ ] **Step 3: Implement password and token primitives**

Use bcrypt with a documented cost, separate access and refresh signing secrets, UUID subject, token type claim, issued-at, and expiry. Parse tokens with strict algorithm and type checks.

- [ ] **Step 4: Write failing service tests**

Cover successful login, wrong password, unknown phone, refresh rotation, expired/revoked refresh session, and idempotent logout. Assert the old refresh session is revoked before the new session is returned.

- [ ] **Step 5: Implement service and session repository**

Login loads the user by phone, compares password, creates a random refresh token, stores only its SHA-256 hash, and returns user plus access/refresh tokens. Refresh hashes the presented token, verifies session state, revokes it, and creates a replacement atomically. Logout revokes the matching session and succeeds when it is already revoked.

- [ ] **Step 6: Run all backend tests**

Run: `cd backend && go test ./...`; `go vet ./...`

Expected: PASS with no plaintext token/password assertions in logs or database arguments.

- [ ] **Step 7: Commit**

```bash
git add backend/internal/auth backend/internal/user
git commit -m "feat: implement password JWT and refresh-session services"
```

### Task 4: HTTP API, Middleware, And Error Contract

**Files:**
- Create: `backend/internal/httpapi/router.go`, `backend/internal/httpapi/middleware.go`
- Create: `backend/internal/httpapi/errors.go`, `backend/internal/httpapi/handlers_auth.go`, `backend/internal/httpapi/handlers_user.go`
- Create: `backend/internal/httpapi/router_test.go`, `backend/internal/httpapi/handlers_test.go`
- Modify: `backend/cmd/server/main.go`

**Interfaces:**
- Routes: `GET /healthz`, `POST /api/auth/login`, `POST /api/auth/refresh`, `POST /api/auth/logout`, `GET /api/me`, `PATCH /api/me`, `GET /api/users`.
- Middleware `RequireAccessToken` injects `user_id` into request context and rejects missing/invalid access tokens with `401`.
- Error writer emits `{code,message,details}` and a request ID header.

- [ ] **Step 1: Write handler tests first**

Use `httptest` and service fakes. Cover status codes and JSON for login success/invalid credentials, refresh, logout, protected `/api/me`, profile field whitelist, users listing, malformed JSON, and health check.

- [ ] **Step 2: Run focused HTTP tests and verify they fail**

Run: `cd backend && go test ./internal/httpapi -v`

Expected: FAIL because the router, handlers, middleware, and response types are absent.

- [ ] **Step 3: Implement error and request-ID middleware**

Generate or propagate `X-Request-ID`, set JSON content type, map domain errors to exact HTTP codes, and log only method/path/status/request ID.

- [ ] **Step 4: Implement routes and handlers**

Decode bounded request structs with `DisallowUnknownFields`, validate phone/password/profile fields, use the auth/user service interfaces, and return stable response structs. `PATCH /api/me` must reject immutable fields rather than silently ignore them.

- [ ] **Step 5: Wire router and graceful server shutdown**

Use the standard library HTTP server with read/write/idle timeouts, `SIGINT`/`SIGTERM` cancellation, and `/healthz` returning unhealthy until migrations and seeding have completed.

- [ ] **Step 6: Run tests and local API smoke test**

Run: `cd backend && go test ./...`; start the API against Compose and execute login, `/api/me`, profile patch, refresh, and logout with `curl`.

Expected: protected endpoints reject absent/refresh tokens, profile changes are visible through a second login, and revoked refresh tokens fail.

- [ ] **Step 7: Commit**

```bash
git add backend/cmd/server/main.go backend/internal/httpapi
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

Create the Android/Web project, then test successful login, invalid login, refresh recovery, refresh failure clearing storage, and logout. Use fake API and in-memory token store implementations.

- [ ] **Step 2: Run Flutter tests and verify they fail**

Run: `cd client && flutter test test/auth/session_controller_test.dart`

Expected: FAIL because the session controller and repository interfaces are absent.

- [ ] **Step 3: Implement models, token storage, API client, and repository**

Use JSON serialization with explicit fields, configurable `API_BASE_URL`, platform-safe token storage, and exactly one refresh retry for a failed authenticated request. Never log authorization headers or token bodies.

- [ ] **Step 4: Implement session controller and screens**

Render a login form with phone/password validation, a loading state, a user-readable authentication error, and an account screen showing the current user and both users. Add editable nickname/role fields, save/error state, and a logout action.

- [ ] **Step 5: Run Flutter tests and static analysis**

Run: `cd client && dart format --output=none --set-exit-if-changed .`; `flutter analyze`; `flutter test`

Expected: PASS for controller and widget tests with no analyzer errors.

- [ ] **Step 6: Verify Web and Android builds**

Run: `cd client && flutter build web --dart-define=API_BASE_URL=http://localhost:8080`; `flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8080`

Expected: both builds complete and the login screen opens without runtime configuration errors.

- [ ] **Step 7: Commit**

```bash
git add client
git commit -m "feat: add Flutter login and account shell"
```

### Task 6: Compose Integration, CI, And End-To-End Acceptance

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `deploy/docker-compose.yml`, `deploy/.env.example`, `Makefile`, `docs/README.md`
- Create: `backend/internal/httpapi/e2e_test.go` or `scripts/smoke-auth.sh`

**Interfaces:**
- Compose starts a healthy API only after PostgreSQL migration and fixed-user seeding succeed.
- CI runs backend tests/vet and Flutter format/analyze/test on every push.
- Smoke test accepts `API_BASE_URL` and credentials through environment variables and does not print secrets.

- [ ] **Step 1: Write the smoke acceptance script**

Exercise health, both fixed-user logins, `/api/users`, profile update, refresh rotation, and logout. Fail if a revoked refresh token succeeds or if the user count is not exactly two.

- [ ] **Step 2: Run the script against a clean Compose database and verify failure before wiring**

Run: `make compose-down`; `make compose-up`; `API_BASE_URL=http://localhost:8080 ./scripts/smoke-auth.sh`

Expected: the script initially fails until the API container, migration command, and environment loading are wired.

- [ ] **Step 3: Finish Compose and CI wiring**

Add API healthcheck, dependency condition on healthy PostgreSQL, persistent database volume, non-secret environment template, and CI jobs for Go and Flutter. Keep PostgreSQL ports unexposed in the Compose file.

- [ ] **Step 4: Run the complete verification suite**

Run: `make test`; `make compose-down`; `make compose-up`; `API_BASE_URL=http://localhost:8080 ./scripts/smoke-auth.sh`; `cd client && flutter build web --dart-define=API_BASE_URL=http://localhost:8080`.

Expected: all tests pass, smoke flow completes for both users, the API remains healthy after restart, and the second startup does not duplicate users or reset profile data.

- [ ] **Step 5: Update project index and commit**

Document the local commands and current Phase 0/1 status in `docs/README.md`, then commit:

```bash
git add .github deploy Makefile docs/README.md scripts
git commit -m "ci: verify local authentication deployment flow"
```

## Self-Review Checklist

- Spec coverage: runtime skeleton (Task 1), schema/seed (Task 2), auth semantics (Task 3), API contract (Task 4), client flow (Task 5), and end-to-end acceptance (Task 6).
- Placeholder scan: no unresolved placeholder or unspecified implementation step is required by this plan.
- Type consistency: `Config`, `TokenManager`, `TokenStore`, `AuthRepository`, and `SessionController` interfaces are named once and consumed consistently by later tasks.
- Scope: no task introduces task management, events, recurring work, comments, conflict UI, analytics, or production ECS deployment.
