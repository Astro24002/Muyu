# Cloud-Coordinated Collaboration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing password/P2P-era application with a PostgreSQL-backed, cloud-coordinated two-person workspace. Android authenticates with SMS and owns long-term devices; Web signs in only by Android QR approval. Android and Web stay current through REST synchronization plus WebSocket invalidations.

**Architecture:** FastAPI is a modular monolith backed only by PostgreSQL. REST is authoritative for reads, mutations, snapshots, and incremental synchronization; a WebSocket carries only workspace/cursor invalidations. Task content is stored as cloud plaintext by product decision. An Android Keystore signing key proves high-risk device approvals; it is not a task-content encryption key. Flutter shares task UI and sync logic across Android/Web while separating their authentication transports.

**Tech Stack:** Python 3.12, FastAPI, SQLAlchemy 2, Alembic, PostgreSQL 16, cryptography, pytest/httpx; Flutter/Dart, flutter_secure_storage, mobile_scanner, qr_flutter, web_socket_channel; Android Kotlin/Android Keystore; Docker Compose, Caddy, GitHub Actions.

---

## Scope and Release Boundary

- Android and Web are the release targets. Produce an Android debug APK for testing, a signed Android AAB when signing secrets are present, and a static Flutter Web bundle.
- Do not add an iOS target, IPA build, iOS signing workflow, or iOS device test in this release. Keep protocol payloads platform-neutral so an iOS client can be added later.
- PostgreSQL is the only database and search engine. Use PostgreSQL full-text search and pg_trgm; do not add Elasticsearch, OpenSearch, Redis, a message queue, or a second state store.
- This is an intentionally incompatible replacement. Provision an empty database and empty workspaces. Do not migrate legacy users, passwords, tokens, tasks, delays, or P2P histories.
- Do not delete a production database volume automatically. Source/runtime removal happens only after its replacement is verified; deployment instructions create a distinctly named new database/volume.

## Cross-Cutting Contracts

### Identity and authorization

| Principal | Authentication | Permitted role |
|---|---|---|
| Android mobile session | SMS OTP plus a registered ACTIVE device | Normal API calls for that user |
| Android high-risk action | ACTIVE device session plus Android Keystore signature over a server challenge | Device approval, recovery, phone change, Web-session approval/revocation |
| Web session | QR challenge approved by the same user's ACTIVE Android device | Normal API calls for that user, expires no later than 18 hours |
| Workspace member | ACTIVE membership in exactly one two-person workspace | Read and mutate that workspace only |

All phone number normalization uses E.164. A user has at most one active workspace. A workspace has at most two ACTIVE equal members. Server-side authorization always rechecks the user, device, membership, and relevant state within the mutation transaction.

### HTTP API conventions

- Prefix all replacement endpoints with `/api/v1`. Delete the legacy unversioned routes during the cutover task.
- Return RFC 9457-style JSON error bodies with stable machine-readable `code` values. Never return OTPs, bearer tokens, browser proofs, device signatures, or raw database errors.
- Every mutation accepts a UUID `request_id`. Persist its request fingerprint and completed response. A repeat with the same payload returns the original result; the same UUID with a different payload returns `409 idempotency_key_reused`.
- Every workspace-visible mutation allocates one increasing workspace `cursor` in the same transaction. The response includes the committed cursor.
- Use UTC ISO-8601 timestamps at the API boundary and store timestamptz in PostgreSQL.
- Set a request ID middleware value for logs. Redact authorization, cookie, OTP, QR nonce, QR proof, and signature values before logging.

### Error codes that clients must handle

| HTTP status | Code | Client behavior |
|---|---|---|
| 401 | `authentication_required`, `mobile_session_expired`, `web_session_expired` | Return to the correct platform login flow |
| 403 | `device_not_active`, `workspace_access_denied`, `approval_not_allowed` | Stop mutation and refresh principal/workspace state |
| 409 | `field_conflict`, `lifecycle_conflict`, `idempotency_key_reused`, `workspace_limit_reached` | Present conflict or explicit state error; never silently overwrite |
| 410 | `sync_cursor_expired`, `web_login_expired`, `approval_challenge_expired` | Fetch a snapshot or restart the approval flow |
| 422 | `invalid_otp`, `invalid_device_signature`, `invalid_request` | Keep form state and show a localized error |
| 429 | `otp_rate_limited` | Show retry-after time without exposing rate-limit internals |

## Repository Map Before Work Starts

| Area | Existing runtime to replace | Replacement ownership |
|---|---|---|
| Backend | `backend/app/auth` password/JWT routes, `user`, `task`, `activity` modules and old Alembic chain | `backend/app/{auth,devices,workspaces,web_login,tasks,sync,realtime}` |
| Backend tests | SQLite-oriented `backend/tests` fixtures and password/task tests | PostgreSQL integration fixtures and cloud protocol tests |
| Client | `client/lib/auth`, `core/api_client.dart`, `task` repositories/controllers, old login/account/task screens | Platform-aware auth/session layer plus shared workspace/task/sync feature packages |
| Deployment | `deploy/docker-compose.yml` and password-oriented env example | Caddy + FastAPI + private PostgreSQL deployment |
| Automation | password smoke scripts and current CI test jobs | OTP fake-provider/API smoke, Web QR protocol smoke, Android/Web build and integration jobs |

## Execution Sequence

- [ ] 1. Establish the cloud replacement baseline, configuration, and PostgreSQL-only test harness.
- [ ] 2. Create the fresh authoritative PostgreSQL schema and domain repositories.
- [ ] 3. Implement SMS OTP authentication, Android mobile sessions, and rate-limited provider abstraction.
- [ ] 4. Implement workspace creation, invitation, device enrollment, and signed partner approval.
- [ ] 5. Implement device-loss recovery, phone-number change, revocation, and audited state transitions.
- [ ] 6. Implement QR-approved Web sessions, secure browser cookies, and Web-session revocation.
- [ ] 7. Implement task mutation transactions, idempotency, field/lifecycle conflicts, and append-only operations.
- [ ] 8. Implement comments, delays, important dates, recurrence, soft deletion, and PostgreSQL search.
- [ ] 9. Implement snapshots, incremental synchronization, cursors, and content-free WebSocket notifications.
- [ ] 10. Build the Android identity bridge, SMS/device onboarding, and Android authorization flows.
- [ ] 11. Build the Web QR sign-in/session flow and platform-specific Flutter transports.
- [ ] 12. Rebuild shared Flutter task, sync, conflict, and manual-refresh experiences.
- [ ] 13. Replace deployment, security, backup, and operational documentation.
- [ ] 14. Replace CI, add protocol/integration coverage, and produce Android/Web artifacts.
- [ ] 15. Remove legacy runtime paths, perform the empty-workspace cutover, and run release verification.

---

## Task 1: Establish the Cloud Replacement Baseline, Configuration, and PostgreSQL-Only Test Harness

**Files:**
- Modify: `backend/pyproject.toml`
- Modify: `backend/app/core/config.py`
- Modify: `backend/app/main.py`
- Modify: `backend/app/db/session.py`
- Modify: `backend/tests/conftest.py`
- Modify: `Makefile`
- Modify: `.github/workflows/ci.yml`
- Create: `backend/tests/test_health.py`
- Create: `backend/app/core/logging.py`
- Create: `backend/app/httpapi/problem.py`
- Create: `docs/architecture/cloud-api-contract.md`

- [ ] **Step 1: Write failing configuration and health tests.**
  - Add a test fixture that requires a PostgreSQL URL, creates a disposable schema/database for the test run, and fails clearly when the URL is SQLite.
  - Add `test_health_reports_database_readiness` and `test_settings_reject_legacy_password_configuration_as_required_input`.
  - Define tests around typed settings rather than process-global settings mutations.

  ~~~python
  def test_health_reports_database_readiness(client: TestClient) -> None:
      response = client.get("/health/ready")
      assert response.status_code == 200
      assert response.json() == {"status": "ready"}
  ~~~

- [ ] **Step 2: Run the focused tests and record the expected red state.**
  - Run: `cd backend && pytest tests/test_health.py -q`.
  - Expected before implementation: the new readiness endpoint or PostgreSQL fixture is absent.

- [ ] **Step 3: Replace settings and database wiring.**
  - Add `cryptography` and `phonenumbers` as backend runtime dependencies; retain only packages needed by the replacement system.
  - Define explicit settings for `database_url`, `public_base_url`, `web_cookie_secure`, `otp_provider`, `otp_pepper`, `otp_ttl_seconds`, `otp_max_attempts`, `otp_phone_window_limit`, `otp_ip_window_limit`, `mobile_session_ttl_hours`, `web_session_ttl_hours`, `device_approval_ttl_seconds`, `web_login_ttl_seconds`, and `sync_retention_days`.
  - Reject SQLite at application startup and make non-production fake OTP mode explicit. Do not require or read `AUTH_PASSWORD`, legacy JWT secret names, or seeded user configuration.
  - Add a database readiness dependency and separate `/health/live` from `/health/ready`.
  - Add structured redaction helpers that remove the sensitive header/cookie/body keys listed in the cross-cutting contracts.
  - Do not seed users or workspaces in `main.py`.

  ~~~python
  class Settings(BaseSettings):
      database_url: PostgresDsn
      otp_pepper: SecretStr
      otp_provider: Literal["fake", "production"] = "fake"
      web_session_ttl_hours: Annotated[int, Field(ge=1, le=18)] = 18

      @model_validator(mode="after")
      def only_postgresql_is_supported(self) -> "Settings":
          if not self.database_url.unicode_string().startswith("postgresql"):
              raise ValueError("DATABASE_URL must use PostgreSQL")
          return self
  ~~~

- [ ] **Step 4: Make PostgreSQL the only local and CI test target.**
  - Update `Makefile` to expose `backend-test`, `backend-migrate`, `backend-smoke`, `client-test`, and `client-build` commands using the replacement environment variables.
  - Add a PostgreSQL service to CI test jobs and run Alembic upgrade before backend tests.
  - Configure test isolation with a unique schema per test worker or a transaction rollback fixture. Do not keep an SQLite fallback.
  - Create the API contract document with the version prefix, error envelope, cursor/idempotency rules, and the rule that content-bearing changes are REST-only.

- [ ] **Step 5: Verify and commit the baseline.**
  - Run: `cd backend && pytest tests/test_health.py -q`.
  - Run: `cd backend && alembic upgrade head` against a disposable PostgreSQL database.
  - Run: `cd backend && python -m compileall app`.
  - Commit: `chore: establish cloud postgres service baseline`.

## Task 2: Create the Fresh Authoritative PostgreSQL Schema and Domain Repositories

**Files:**
- Delete: `backend/alembic/versions/0001_users_sessions.py`
- Delete: `backend/alembic/versions/0002_task_core.py`
- Delete: `backend/alembic/versions/0003_delay_blocking.py`
- Create: `backend/alembic/versions/0001_cloud_workspace_schema.py`
- Create: `backend/app/db/models.py`
- Create: `backend/app/db/enums.py`
- Create: `backend/app/db/repositories/base.py`
- Create: `backend/app/workspaces/models.py`
- Create: `backend/app/tasks/models.py`
- Create: `backend/app/sync/models.py`
- Create: `backend/tests/db/test_cloud_schema.py`

- [ ] **Step 1: Write failing schema tests against PostgreSQL.**
  - Assert database constraints rather than only ORM validation:
    - one normalized phone number per user;
    - one active workspace membership per user;
    - no more than two active memberships in one workspace;
    - one request UUID per workspace mutation;
    - cursor uniqueness and ordering per workspace;
    - a Web session has a non-null approving device;
    - revoked devices cannot remain active Web-session approvers.
  - Include a migration test that upgrades an empty database to `head` and inspects required indexes.

  ~~~python
  def test_workspace_rejects_a_third_active_member(session: Session) -> None:
      workspace = make_workspace(session)
      add_active_member(session, workspace, make_user(session))
      add_active_member(session, workspace, make_user(session))
      with pytest.raises(IntegrityError):
          add_active_member(session, workspace, make_user(session))
          session.flush()
  ~~~

- [ ] **Step 2: Run the schema tests and confirm they fail before the new migration exists.**
  - Run: `cd backend && pytest tests/db/test_cloud_schema.py -q`.

- [ ] **Step 3: Define the replacement schema and indexes in one initial migration.**
  - Create these tables with UUID primary keys and timestamptz `created_at`/`updated_at` fields where applicable:
    - `users`: normalized phone, display name, status, last-login metadata;
    - `android_devices`: user, public signing key DER, label, platform, status, enrolled/revoked timestamps;
    - `mobile_sessions`: hashed opaque refresh/session token, user, device, expiration, revocation;
    - `workspaces` and `workspace_memberships`: workspace state, two-member membership, active uniqueness;
    - `workspace_invites`: inviter, invited phone, expiration, accepted/void state;
    - `device_authorization_requests` and `device_authorization_challenges`: candidate device, approving member/device, safety-code digest, signature challenge, expiry, state;
    - `recovery_requests` and `phone_change_requests`: dual-consent/recovery state with immutable audit links;
    - `web_login_challenges` and `web_sessions`: proof hashes, origin, approving device, expiry/revocation;
    - `idempotency_records`: workspace, request UUID, route/fingerprint, response status/body, expiry;
    - `workspace_cursors` and `workspace_change_log`: monotonic sequence, entity type/id, action, operation ID;
    - task/state/history tables listed in Tasks 7 and 8.
  - Use a PostgreSQL trigger for the two-active-member constraint or serialize membership changes with `SELECT ... FOR UPDATE` plus a unique partial index. Document the chosen enforcement inside the migration and test it under concurrent transactions.
  - Add partial indexes for active devices, active memberships, unexpired sessions, unexpired challenges, workspace/cursor lookup, and task list queries.
  - Enable `pg_trgm` in the same migration. Keep all task content/search columns in PostgreSQL.
  - Define enums in PostgreSQL and Python: `PENDING`/`ACTIVE`/`REVOKED` devices; `PENDING`/`ACCEPTED`/`EXPIRED`/`REVOKED` approvals; task lifecycle values; Web session state; change action.

  ~~~sql
  CREATE UNIQUE INDEX uq_active_workspace_member_per_user
      ON workspace_memberships (user_id)
      WHERE status = 'ACTIVE';

  CREATE UNIQUE INDEX uq_active_workspace_member_slot
      ON workspace_memberships (workspace_id, user_id)
      WHERE status = 'ACTIVE';
  ~~~

- [ ] **Step 4: Build model/repository boundaries that preserve transactional ownership.**
  - Keep SQLAlchemy table models in `app/db/models.py` and request/response/domain dataclasses in their feature packages.
  - Implement repository methods that receive an existing `Session`; services own transaction boundaries so one mutation can atomically change state, append history, allocate a cursor, and persist an idempotency response.
  - Add a `WorkspaceCursorRepository.allocate(session, workspace_id)` method that locks the workspace cursor row and returns the next integer.
  - Do not expose a repository method that commits independently.

- [ ] **Step 5: Verify migration and constraints, then commit.**
  - Run: `cd backend && alembic upgrade head` on an empty PostgreSQL database.
  - Run: `cd backend && pytest tests/db/test_cloud_schema.py -q`.
  - Run: `cd backend && alembic downgrade base && alembic upgrade head` on the disposable database.
  - Commit: `feat: add cloud workspace postgres schema`.

## Task 3: Implement SMS OTP Authentication, Android Mobile Sessions, and Rate-Limited Provider Abstraction

**Files:**
- Create: `backend/app/auth/otp.py`
- Create: `backend/app/auth/service.py`
- Create: `backend/app/auth/routes.py`
- Create: `backend/app/auth/schemas.py`
- Create: `backend/app/auth/dependencies.py`
- Create: `backend/app/auth/providers/base.py`
- Create: `backend/app/auth/providers/fake.py`
- Create: `backend/app/auth/providers/production.py`
- Create: `backend/app/auth/rate_limit.py`
- Create: `backend/tests/auth/test_sms_auth.py`
- Create: `backend/tests/auth/test_mobile_sessions.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Write failing SMS and session tests.**
  - Cover a full successful Android sequence: send OTP, verify OTP with candidate device metadata/public key, receive opaque mobile credentials, authenticate a protected endpoint.
  - Cover six-digit enforcement, E.164 normalization, five-minute expiry, one-use behavior, maximum attempts, per-phone and per-IP rate limits, wrong OTP, and provider delivery failure.
  - Assert no test log capture, response body, or persisted OTP row contains the plaintext code.
  - Test a new phone results in a user in `UNASSIGNED`/no-workspace state; an existing user receives a session for the supplied device only after device rules are satisfied in Task 4.

  ~~~python
  def test_otp_is_single_use(client: TestClient, fake_sms: FakeSmsProvider) -> None:
      client.post("/api/v1/auth/sms/send", json={"phone": "+8613800138000"})
      code = fake_sms.last_code_for("+8613800138000")
      first = client.post("/api/v1/auth/sms/verify", json=verify_payload(code))
      second = client.post("/api/v1/auth/sms/verify", json=verify_payload(code))
      assert first.status_code == 201
      assert second.status_code == 422
      assert second.json()["code"] == "invalid_otp"
  ~~~

- [ ] **Step 2: Run focused tests to confirm the old password routes cannot satisfy them.**
  - Run: `cd backend && pytest tests/auth/test_sms_auth.py tests/auth/test_mobile_sessions.py -q`.

- [ ] **Step 3: Implement safe OTP issuance and verification.**
  - Generate a cryptographically random six-digit code. Store only HMAC-SHA-256(code, OTP_PEPPER), phone, request metadata, attempt count, expiry, and consumption timestamp.
  - Build `SmsProvider` with a fake provider usable only in test/development and a production adapter selected by settings. The production adapter accepts provider credentials through environment settings and never logs its request body.
  - Enforce limits in PostgreSQL so API instances agree: lock or upsert counters keyed by normalized phone/window and hashed client IP/window. Return `429` plus `Retry-After`.
  - On successful verification, consume the challenge atomically, create/update the user, and create an opaque mobile session bound to a device record/candidate registration flow. Store only a SHA-256 token digest server-side; return raw credentials once.
  - Mobile normal requests use `Authorization: Bearer <opaque-token>`. The dependency resolves user/device/session and rejects expired, revoked, or non-ACTIVE devices.

  ~~~python
  class MobilePrincipal(BaseModel):
      user_id: UUID
      device_id: UUID
      workspace_id: UUID | None

  async def require_active_mobile_principal(
      authorization: Annotated[str, Header()],
      service: AuthService = Depends(get_auth_service),
  ) -> MobilePrincipal:
      return service.resolve_mobile_bearer(authorization)
  ~~~

- [ ] **Step 4: Publish exact authentication endpoints and abuse-resistant responses.**
  - Add:
    - `POST /api/v1/auth/sms/send`;
    - `POST /api/v1/auth/sms/verify`;
    - `POST /api/v1/auth/mobile/refresh`;
    - `POST /api/v1/auth/mobile/logout`;
    - `GET /api/v1/me`.
  - Return generic delivery acknowledgment for a well-formed phone regardless of whether it is registered. Do not expose account existence, invite existence, or device presence through OTP responses.
  - Set mobile session expiration explicitly; refresh rotates the opaque token and invalidates the old digest.

- [ ] **Step 5: Verify and commit.**
  - Run: `cd backend && pytest tests/auth/test_sms_auth.py tests/auth/test_mobile_sessions.py -q`.
  - Run: `cd backend && pytest -q`.
  - Run: `cd backend && ruff check app tests` if Ruff is added, otherwise `python -m compileall app`.
  - Commit: `feat: add sms mobile authentication`.

## Task 4: Implement Workspace Creation, Invitation, Device Enrollment, and Signed Partner Approval

**Files:**
- Create: `backend/app/devices/service.py`
- Create: `backend/app/devices/routes.py`
- Create: `backend/app/devices/schemas.py`
- Create: `backend/app/devices/signatures.py`
- Create: `backend/app/workspaces/service.py`
- Create: `backend/app/workspaces/routes.py`
- Create: `backend/app/workspaces/schemas.py`
- Create: `backend/tests/workspaces/test_onboarding.py`
- Create: `backend/tests/devices/test_device_approval.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Write failing onboarding and approval tests.**
  - Test A's first verified Android device creates the first workspace and ACTIVE member/device atomically.
  - Test A invites B by normalized phone even when B is not registered. Test B's first verified candidate device can accept only a matching invitation.
  - Test the A/B short-code comparison and signed final approval. The approval must atomically activate B's membership and device only after A signs an unexpired server challenge.
  - Test adding a replacement/second long-term device: the owner starts the request, the other active member must approve, self-approval is rejected, and a revoked/pending device cannot approve.
  - Test two registrations racing for the final member slot; exactly one becomes ACTIVE.
  - Test invalid key encoding, wrong curve, tampered challenge, replayed signature, expiry, and wrong approving device.

  ~~~python
  def test_partner_signature_is_required_to_activate_replacement_device(
      client: TestClient, active_pair: ActivePair
  ) -> None:
      request = start_replacement_request(client, active_pair.b_candidate_token)
      assert client.post(request.approve_url, json={"signature": "bad"}).status_code == 422
      assert get_device_status(request.candidate_device_id) == "PENDING"

      signature = active_pair.a_keystore.sign(request.challenge_bytes)
      response = approve_request(client, active_pair.a_token, request.id, signature)
      assert response.status_code == 200
      assert response.json()["device"]["status"] == "ACTIVE"
  ~~~

- [ ] **Step 2: Run the focused tests in the red state.**
  - Run: `cd backend && pytest tests/workspaces/test_onboarding.py tests/devices/test_device_approval.py -q`.

- [ ] **Step 3: Implement platform-neutral device signing verification.**
  - Require an Android device public key encoded as base64 DER SubjectPublicKeyInfo for P-256 ECDSA/SHA-256.
  - Verify signatures with `cryptography` against a canonical, versioned byte payload containing action, request ID, target ID, server nonce, expiry, actor device ID, and workspace ID.
  - Store only public keys/signatures/challenge hashes. Android private key material never reaches an API request, database, log, or Web browser.
 - Issue short safety codes from random server entropy; store only an HMAC/digest. The mobile UI displays the code to both parties before final signature submission.
  - Set device-approval and recovery challenge lifetime to 10 minutes by default, with a maximum configured lifetime of 15 minutes. Persist the expiry and show the remaining time in both Android clients.
 - Explicitly reject completed, expired, wrong-action, wrong-workspace, or replayed challenges.

  ~~~python
  def signed_action_payload(
      *,
      action: str,
      approval_id: UUID,
      actor_device_id: UUID,
      workspace_id: UUID,
      nonce: bytes,
      expires_at: datetime,
  ) -> bytes:
      return canonical_json_bytes({
          "v": 1,
          "action": action,
          "approval_id": str(approval_id),
          "actor_device_id": str(actor_device_id),
          "workspace_id": str(workspace_id),
          "nonce": b64url(nonce),
          "expires_at": expires_at.isoformat(),
      })
  ~~~

- [ ] **Step 4: Implement workspace and device routes with transaction ownership.**
  - Add:
    - `POST /api/v1/workspaces` to create A's empty workspace;
    - `POST /api/v1/workspaces/{workspace_id}/invites`;
    - `POST /api/v1/workspace-invites/{invite_id}/accept`;
    - `GET /api/v1/devices/authorization-requests`;
    - `POST /api/v1/device-authorization-requests/{request_id}/begin-approval`;
    - `POST /api/v1/device-authorization-requests/{request_id}/approve`;
    - `GET /api/v1/workspaces/current`.
  - Keep initial A setup and B first-invite acceptance as the two explicitly allowed enrollment paths. All later long-term device enrollment requires the other workspace member's ACTIVE Android signature.
  - Make invitation and approval methods idempotent by request UUID. Publish a cursor/change record only after the membership/device transition commits.
  - Return only the caller's relevant public device/member fields; never return other members' raw public-key bytes in ordinary list responses.

- [ ] **Step 5: Verify and commit.**
  - Run: `cd backend && pytest tests/workspaces/test_onboarding.py tests/devices/test_device_approval.py -q`.
  - Run a two-transaction concurrency test against PostgreSQL.
  - Run: `cd backend && pytest -q`.
  - Commit: `feat: add two-person workspace device approval`.

## Task 5: Implement Device-Loss Recovery, Phone-Number Change, Revocation, and Audited State Transitions

**Files:**
- Create: `backend/app/recovery/service.py`
- Create: `backend/app/recovery/routes.py`
- Create: `backend/app/recovery/schemas.py`
- Create: `backend/app/audit/service.py`
- Create: `backend/app/audit/models.py`
- Create: `backend/tests/recovery/test_device_recovery.py`
- Create: `backend/tests/recovery/test_phone_change.py`
- Create: `backend/tests/devices/test_revocation.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Write failing recovery, phone-change, and revocation tests.**
  - Test one lost device: the owner passes SMS on the new Android device, requests enrollment, and the other workspace member approves with their ACTIVE device.
  - Test both users losing all devices: both pass SMS, each sees the same recovery safety code, both sign their recovery acceptance, and a single transaction activates the two new devices, revokes all former devices, and revokes all Web sessions.
  - Test that one participant alone cannot complete dual recovery, a recovery challenge expires, and a former device cannot approve after revocation.
  - Test phone change where the old phone/device is available: verify old and new phone OTP plus the other member's signed approval.
  - Test phone change where the old device is absent: use the same dual recovery procedure rather than a bypass.
  - Test revoking an Android device immediately invalidates its mobile session and every Web session approved by that device. A user may revoke their own Web sessions from any ACTIVE Android device; the other member cannot revoke that user's Web sessions.

- [ ] **Step 2: Run focused tests to establish the red state.**
  - Run: `cd backend && pytest tests/recovery tests/devices/test_revocation.py -q`.

- [ ] **Step 3: Implement explicit recovery state machines.**
  - Model recovery/phone-change stages as persisted enums, not inferred booleans. Each transition validates the prior state, expiry, candidate phone/user, and signer.
  - Lock all affected user, device, workspace-membership, and Web-session rows in a single transaction before final recovery activation.
  - Record immutable audit events for request creation, OTP verification, each approval, completion, rejection, expiry, Android device revocation, and Web-session revocation. Audit rows include actor user/device, subject IDs, action, timestamp, request ID, and non-secret metadata.
  - Define Android-device revocation authorization as: its owner from another ACTIVE Android device, or the other ACTIVE workspace member from an ACTIVE Android device. Reject a request that would leave a user with no active device outside the explicit recovery flow.
  - Define Web-session revocation authorization more narrowly: only the session owner through any of their ACTIVE Android devices. The approving device's revocation is an automatic exception that revokes dependent sessions.

  ~~~python
  def finalize_dual_recovery(session: Session, request_id: UUID) -> RecoveryResult:
      request = recovery_repo.lock_complete_request(session, request_id)
      require_two_distinct_member_signatures(request)
      revoke_all_workspace_devices_and_web_sessions(session, request.workspace_id)
      activate_recovery_devices(session, request)
      audit.record(session, action="dual_recovery_completed", request=request)
      return RecoveryResult(...)
  ~~~

- [ ] **Step 4: Add recovery and account-security routes.**
  - Add:
    - `POST /api/v1/recovery/device-loss`;
    - `POST /api/v1/recovery/{request_id}/begin-approval`;
    - `POST /api/v1/recovery/{request_id}/approve`;
    - `POST /api/v1/account/phone-change`;
    - `POST /api/v1/account/phone-change/{request_id}/approve`;
    - `POST /api/v1/devices/{device_id}/revoke`;
    - `GET /api/v1/audit/security`.
  - Return generic state names and safe countdowns; do not reveal QR proofs, OTPs, public-key material, session tokens, or audit internal IP data.
  - Expiry cleanup may mark stale rows terminal during reads or a scheduled application job; it must not create unauthorized state transitions.

- [ ] **Step 5: Verify and commit.**
  - Run: `cd backend && pytest tests/recovery tests/devices/test_revocation.py -q`.
  - Run: `cd backend && pytest -q`.
  - Commit: `feat: add device recovery and security revocation`.


## Task 6: Implement QR-Approved Web Sessions, Secure Browser Cookies, and Web-Session Revocation

**Files:**
- Create: `backend/app/web_login/service.py`
- Create: `backend/app/web_login/routes.py`
- Create: `backend/app/web_login/schemas.py`
- Create: `backend/app/web_login/cookies.py`
- Create: `backend/tests/web_login/test_qr_login.py`
- Create: `backend/tests/web_login/test_web_session_security.py`
- Modify: `backend/app/auth/dependencies.py`
- Modify: `backend/app/main.py`
- Modify: `backend/app/core/config.py`

- [ ] **Step 1: Write failing QR protocol and cookie-security tests.**
  - Test this complete protocol with a real generated P-256 test key: browser creates a challenge with an allowed origin and locally generated proof; Android scans the QR nonce; Android signs a server challenge; browser exchanges the original proof; the resulting cookie authenticates a Web-protected endpoint.
  - Assert the QR challenge expires in 120 seconds, the browser proof is one-use, the scan nonce cannot be substituted, and the origin must match the configured Web origin.
  - Assert session lifetime is capped at 18 hours, has no silent refresh endpoint, and an excessive requested duration cannot extend the cap.
  - Assert the cookie is `HttpOnly`, `Secure` in production mode, `SameSite=Lax`, path-scoped to `/`, and has no token in its JSON body.
  - Test owner-only Web-session revocation and automatic revocation after the approving Android device is revoked.

  ~~~python
  def test_browser_exchange_requires_the_original_proof(
      browser: TestClient, approved_web_challenge: ApprovedChallenge
  ) -> None:
      response = browser.post(
          f"/api/v1/web-login/challenges/{approved_web_challenge.id}/exchange",
          json={"browser_proof": "different-proof"},
      )
      assert response.status_code == 401
      assert response.json()["code"] == "web_login_proof_invalid"
  ~~~

- [ ] **Step 2: Run focused tests and confirm the absence of the new flow.**
  - Run: `cd backend && pytest tests/web_login -q`.

- [ ] **Step 3: Implement the browser proof and Android approval protocol.**
  - On challenge creation, accept an allowed browser origin and a SHA-256 hash of a high-entropy browser proof. Generate a random challenge ID, QR scan nonce, and six-digit safety code. Store only hashes/digests plus expiry.
  - Return a QR payload with version, challenge ID, scan nonce, origin, and expiry. Do not put the browser proof, a bearer token, task content, phone number, or session key in the QR payload.
  - Require the Android caller to be an ACTIVE mobile principal in the target workspace. The scan endpoint returns the origin, expiry, and safety code for visual comparison.
  - Reuse the versioned signed-action payload from Task 4 with action `WEB_LOGIN_APPROVE`. Verify the signature belongs to the signing Android device and that its user equals the Web-session owner.
  - On browser exchange, compare proof hashes in constant time, atomically consume the challenge, create a Web session linked to the approving device, and set the opaque cookie. Store only a digest of the cookie secret.

  ~~~python
  @router.post("/challenges", response_model=WebLoginChallengeCreated)
  def create_web_login_challenge(
      request: CreateWebLoginChallenge,
      service: WebLoginService = Depends(get_web_login_service),
  ) -> WebLoginChallengeCreated:
      return service.create_browser_challenge(
          origin=request.origin,
          browser_proof_hash=request.browser_proof_hash,
      )
  ~~~

- [ ] **Step 4: Add browser authentication and revocation boundaries.**
  - Add:
    - `POST /api/v1/web-login/challenges`;
    - `GET /api/v1/web-login/challenges/{challenge_id}` for browser status only;
    - `POST /api/v1/web-login/challenges/{challenge_id}/scan` for Android metadata retrieval;
    - `POST /api/v1/web-login/challenges/{challenge_id}/approve` for Android signed approval;
    - `POST /api/v1/web-login/challenges/{challenge_id}/exchange`;
    - `POST /api/v1/web-sessions/{session_id}/revoke`;
    - `GET /api/v1/web-sessions`.
  - Implement `require_web_principal` from the cookie separately from `require_active_mobile_principal`. A Web cookie authenticates normal workspace APIs but never substitutes for an Android device signature on high-risk endpoints.
  - Serve production Web and API from one Caddy origin. Permit CORS only for explicitly configured local development origins; reject arbitrary `Origin` headers on cookie-changing routes.
  - The static Web client contains no SMS login route and can never receive a mobile bearer token. The API's SMS result is a mobile-session credential, not a browser cookie; QR exchange is the only route that emits a Web cookie.
  - Set a global session expiry of no more than 18 hours from issuance. Do not rotate, refresh, or extend a Web session in the background.

- [ ] **Step 5: Verify and commit.**
  - Run: `cd backend && pytest tests/web_login -q`.
  - Run: `cd backend && pytest tests/recovery tests/devices/test_revocation.py -q` to confirm revocation linkage.
  - Inspect test response headers for cookie flags and absence of secret material.
  - Commit: `feat: add qr approved web sessions`.


## Task 7: Implement Task Mutation Transactions, Idempotency, Field/Lifecycle Conflicts, and Append-Only Operations

**Files:**
- Create: `backend/app/tasks/service.py`
- Create: `backend/app/tasks/routes.py`
- Create: `backend/app/tasks/schemas.py`
- Create: `backend/app/tasks/conflicts.py`
- Create: `backend/app/tasks/operations.py`
- Create: `backend/tests/tasks/test_task_mutations.py`
- Create: `backend/tests/tasks/test_task_conflicts.py`
- Create: `backend/tests/tasks/test_task_idempotency.py`
- Modify: `backend/app/db/models.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Write failing mutation and conflict tests.**
  - Create test cases for task creation, field update, status transition, completion, reopen, delete, restore, and duplicate request replay.
  - Test independent delayed writes from A and B where different scalar fields change from the same base versions; both commits must persist and the final state contains both changes.
  - Test same-field writes from the same base version; the second request returns `409 field_conflict` and persists a conflict record containing baseline/current/proposed values and operation references.
  - Test stale lifecycle actions using `base_lifecycle_version`; completion/reopen/delete/restore must return `409 lifecycle_conflict`, not overwrite a newer lifecycle state.
  - Test a deleted task rejects title/status/comment/delay mutation until an explicit restore operation occurs.
  - Test duplicate `request_id` after an unknown network outcome returns byte-for-byte equivalent successful JSON without adding another operation/cursor.
  - Test duplicate `request_id` with a different route/body returns `409 idempotency_key_reused`.

  ~~~python
  def test_different_field_updates_auto_merge(active_pair_client: PairClient) -> None:
      task = active_pair_client.create_task(title="Plan")
      a = active_pair_client.a.patch_task(
          task.id, {"title": "Plan release"},
          base_field_versions=task.field_versions,
      )
      b = active_pair_client.b.patch_task(
          task.id, {"description": "Ship by Friday"},
          base_field_versions=task.field_versions,
      )
      assert a.status_code == b.status_code == 200
      state = active_pair_client.get_task(task.id).json()
      assert state["title"] == "Plan release"
      assert state["description"] == "Ship by Friday"
  ~~~

- [ ] **Step 2: Run focused task tests and confirm the old task service does not meet the contract.**
  - Run: `cd backend && pytest tests/tasks/test_task_mutations.py tests/tasks/test_task_conflicts.py tests/tasks/test_task_idempotency.py -q`.

- [ ] **Step 3: Add current-state, history, conflict, and idempotency structures.**
  - Create:
    - `tasks` current-state rows with title, description, assignee/member-visible fields, due time, lifecycle status, `lifecycle_version`, per-field integer versions, creator/updater, deleted/restored timestamps;
    - `task_operations` immutable append-only rows with operation type, actor, request UUID, payload snapshot, before/after versions, and workspace cursor;
    - `task_conflicts` with task/field, baseline/current/proposed structured values, source operations, resolution status, resolver operation, and timestamps;
    - `idempotency_records` usage from Task 2.
  - Store field versions as a JSONB object with a fixed server-owned whitelist of mutable field names. Validate that a client supplies base versions only for fields it changes.
  - Define lifecycle transitions in one explicit mapping. Delete and restore increment `lifecycle_version` and produce operations; they never physically delete history.

  ~~~python
  LIFECYCLE_TRANSITIONS: dict[TaskStatus, set[TaskStatus]] = {
      TaskStatus.OPEN: {TaskStatus.COMPLETED, TaskStatus.DELETED},
      TaskStatus.COMPLETED: {TaskStatus.OPEN, TaskStatus.DELETED},
      TaskStatus.DELETED: {TaskStatus.OPEN},
  }
  ~~~

- [ ] **Step 4: Implement a single mutation wrapper for all task writes.**
  - Resolve the active workspace principal, lock the task row, check idempotency, validate all base versions, mutate only requested fields, append an operation, allocate a workspace cursor, append a minimal change-log record, persist the idempotency response, then commit.
 - For a same-field stale write, create the conflict record and return a stable `field_conflict` payload without changing the current field value. For different fields, apply the mutation and leave other newer fields untouched.
  - Treat conflict creation as a committed workspace write: append a `CONFLICT_CREATED` operation, allocate one cursor/change record, and persist the idempotent 409 response before commit. A conflict response therefore never causes an untracked server-side state change.
 - Add a conflict resolution endpoint that accepts either `current` or `proposed`, validates the conflict remains open, increments the field version, writes a `CONFLICT_RESOLVED` operation, and marks the conflict resolved in the same transaction.
  - Add:
    - `POST /api/v1/tasks`;
    - `GET /api/v1/tasks`;
    - `GET /api/v1/tasks/{task_id}`;
    - `PATCH /api/v1/tasks/{task_id}`;
    - `POST /api/v1/tasks/{task_id}/lifecycle`;
    - `POST /api/v1/tasks/{task_id}/restore`;
    - `GET /api/v1/tasks/{task_id}/conflicts`;
    - `POST /api/v1/tasks/{task_id}/conflicts/{conflict_id}/resolve`.
  - Return current values, field versions, lifecycle version, unresolved conflict summary, and commit cursor in all successful mutation responses.

  ~~~python
  class PatchTaskRequest(BaseModel):
      request_id: UUID
      changes: dict[str, JsonValue]
      base_field_versions: dict[str, int]

      @model_validator(mode="after")
      def versions_match_changed_fields(self) -> "PatchTaskRequest":
          if set(self.changes) != set(self.base_field_versions):
              raise ValueError("base versions must match changed fields")
          return self
  ~~~

- [ ] **Step 5: Verify concurrency behavior and commit.**
  - Run: `cd backend && pytest tests/tasks/test_task_mutations.py tests/tasks/test_task_conflicts.py tests/tasks/test_task_idempotency.py -q`.
  - Run PostgreSQL concurrency tests that submit competing updates in separate transactions.
  - Run: `cd backend && pytest -q`.
  - Commit: `feat: add transactional task conflict engine`.


## Task 8: Implement Comments, Delays, Important Dates, Recurrence, Soft Deletion, and PostgreSQL Search

**Files:**
- Create: `backend/app/tasks/comments.py`
- Create: `backend/app/tasks/delays.py`
- Create: `backend/app/tasks/recurrence.py`
- Create: `backend/app/tasks/search.py`
- Create: `backend/tests/tasks/test_comments.py`
- Create: `backend/tests/tasks/test_delays.py`
- Create: `backend/tests/tasks/test_important_dates.py`
- Create: `backend/tests/tasks/test_recurrence.py`
- Create: `backend/tests/tasks/test_search.py`
- Modify: `backend/app/tasks/service.py`
- Modify: `backend/app/tasks/routes.py`
- Modify: `backend/app/db/models.py`
- Modify: `backend/alembic/versions/0001_cloud_workspace_schema.py` or add a new forward migration if Task 2 has been committed

- [ ] **Step 1: Write failing behavior tests.**
  - Test that comments and delays are append-only records and are rejected when their task is deleted.
  - Test that a delay records actor, prior due time, next due time, reason, and operation/cursor; it never overwrites history.
  - Test important-date tasks retain their date/countdown semantics and are visible in current task state.
  - Test daily, weekly, and monthly recurring task definitions create at most one unresolved occurrence at a time; completing the occurrence materializes the next eligible one exactly once under concurrent completion requests.
  - Test soft deletion hides a task from normal list/search, preserves history, and restore returns it to normal behavior.
  - Test PostgreSQL full-text matching for title/description and typo-tolerant title matching with pg_trgm. Assert search never crosses workspace boundaries.

- [ ] **Step 2: Run focused tests to establish the red state.**
  - Run: `cd backend && pytest tests/tasks/test_comments.py tests/tasks/test_delays.py tests/tasks/test_important_dates.py tests/tasks/test_recurrence.py tests/tasks/test_search.py -q`.

- [ ] **Step 3: Implement supporting task records and deterministic recurrence.**
  - Create `task_comments`, `delay_records`, `important_date_details`, and `recurrence_rules` tables. Each references its workspace/task and has actor/operation/cursor linkage.
  - Restrict recurrence to explicit product-supported schedules: daily, weekly with weekday set, and monthly with day-of-month policy. Store the IANA timezone used to calculate the next occurrence.
  - Use a unique partial index or advisory lock on `(recurrence_rule_id) WHERE occurrence_is_unresolved` so two concurrent completions cannot produce two future unresolved tasks.
  - Keep `TaskDeleted`/restore as operation types. A delete does not erase comments, delays, conflicts, activity, or recurrence history.
  - Generate a weighted `tsvector` from title/description and a GIN index; add a trigram index to normalized title. Query with parameterized PostgreSQL functions only.

  ~~~sql
  CREATE INDEX ix_tasks_search_fts
      ON tasks USING gin (search_document);

  CREATE INDEX ix_tasks_title_trgm
      ON tasks USING gin (normalized_title gin_trgm_ops);
  ~~~

- [ ] **Step 4: Expose feature routes and state projections.**
  - Add:
    - `POST /api/v1/tasks/{task_id}/comments` and `GET /api/v1/tasks/{task_id}/comments`;
    - `POST /api/v1/tasks/{task_id}/delays` and `GET /api/v1/tasks/{task_id}/delays`;
    - `POST /api/v1/tasks/{task_id}/important-date`;
    - `POST /api/v1/tasks/{task_id}/recurrence`;
    - `GET /api/v1/tasks/search?q=...`.
  - Route every write through Task 7's mutation wrapper so it receives an operation, cursor, change log, audit metadata, and idempotency record.
  - Calculate countdown values on read from the stored important date/timezone rather than persisting stale countdown integers.
  - Present recurrence instances as ordinary task records with immutable origin/rule linkage; clients do not calculate future instances.

- [ ] **Step 5: Verify and commit.**
  - Run: `cd backend && pytest tests/tasks/test_comments.py tests/tasks/test_delays.py tests/tasks/test_important_dates.py tests/tasks/test_recurrence.py tests/tasks/test_search.py -q`.
  - Run a query-plan test or `EXPLAIN` fixture to confirm search uses a PostgreSQL index for representative data.
  - Run: `cd backend && pytest -q`.
  - Commit: `feat: add task history recurrence and postgres search`.


## Task 9: Implement Snapshots, Incremental Synchronization, Cursors, and Content-Free WebSocket Notifications

**Files:**
- Create: `backend/app/sync/service.py`
- Create: `backend/app/sync/routes.py`
- Create: `backend/app/sync/schemas.py`
- Create: `backend/app/realtime/hub.py`
- Create: `backend/app/realtime/routes.py`
- Create: `backend/tests/sync/test_snapshot.py`
- Create: `backend/tests/sync/test_changes.py`
- Create: `backend/tests/realtime/test_workspace_notifications.py`
- Modify: `backend/app/tasks/service.py`
- Modify: `backend/app/workspaces/service.py`
- Modify: `backend/app/main.py`

- [ ] **Step 1: Write failing sync and realtime tests.**
  - Assert an initial snapshot returns all current workspace projections and a cursor.
  - Assert a changes request after that cursor returns ordered changes only from that workspace and a new cursor.
  - Assert a cursor older than configured retention returns `410 sync_cursor_expired` with no partial misleading list.
  - Assert every task, member, device, invitation, conflict, comment, delay, important-date, and recurrence write emits exactly one corresponding workspace change record in the same committed transaction.
  - Test a WebSocket notification is delivered only after commit and contains only `type`, `workspace_id`, and `cursor`, never title, description, comment, phone, or task payload.
  - Test reconnect/manual polling is idempotent when the client requests a cursor already at head.

  ~~~python
  def test_websocket_never_transports_task_content(
      websocket_client: WebSocketTestClient, active_workspace: Workspace
  ) -> None:
      create_task_for_workspace(active_workspace, title="Sensitive title")
      message = websocket_client.receive_json()
      assert message == {
          "type": "workspace.changed",
          "workspace_id": str(active_workspace.id),
          "cursor": 1,
      }
  ~~~

- [ ] **Step 2: Run focused tests and confirm no existing route satisfies cursor semantics.**
  - Run: `cd backend && pytest tests/sync tests/realtime -q`.

- [ ] **Step 3: Implement canonical snapshot and change representations.**
  - Add:
    - `GET /api/v1/workspaces/current/snapshot`;
    - `GET /api/v1/workspaces/current/changes?after_cursor=<int>&limit=<int>`;
    - `GET /api/v1/realtime` WebSocket endpoint.
  - A snapshot contains the current workspace, active members/devices relevant to the caller, current non-deleted tasks, important-date/recurrence projections, unresolved conflicts, and a head cursor.
  - A change record identifies resource type/id/action/operation/cursor and includes a current resource projection only where clients need it to update local cache. It does not expose security secrets or private server-only audit metadata.
  - Retain change records for the configured period. Before pruning, compute the oldest available cursor; an older request gets `410` and client must fetch a complete snapshot.
  - Allocate the cursor and insert the change row before committing the business transaction. Publish to the realtime hub only after commit succeeds.

  ~~~python
  class WorkspaceChanged(BaseModel):
      type: Literal["workspace.changed"] = "workspace.changed"
      workspace_id: UUID
      cursor: int
  ~~~

- [ ] **Step 4: Implement single-instance WebSocket ownership safely.**
  - Authenticate native Android WebSocket connections from the bearer authorization header; authenticate browser connections from the same-origin Web cookie.
  - Never pass bearer tokens as URL query values. Use the explicit authorization header for native clients and redact all request headers in WebSocket errors/logs.
  - Maintain in-memory subscriptions keyed by workspace for the initial single-API-instance deployment. On disconnect, remove the subscription. Do not introduce Redis.
  - Require clients to pull `/changes` after every notification; the hub is a hint mechanism, not an event store or source of truth.
  - Add a deployment note that horizontal API scaling requires a later cross-instance invalidation backend and is out of scope for this release.

- [ ] **Step 5: Verify and commit.**
  - Run: `cd backend && pytest tests/sync tests/realtime -q`.
  - Run: `cd backend && pytest -q`.
  - Commit: `feat: add cursor sync and workspace websocket hints`.


## Task 10: Build the Android Identity Bridge, SMS/Device Onboarding, and Android Authorization Flows

**Files:**
- Modify: `client/pubspec.yaml`
- Modify: `client/android/app/src/main/AndroidManifest.xml`
- Modify: `client/android/app/src/main/kotlin/com/muyu/app/MainActivity.kt`
- Create: `client/android/app/src/main/kotlin/com/muyu/app/DeviceKeyManager.kt`
- Create: `client/lib/platform/device_signing_key.dart`
- Create: `client/lib/platform/device_signing_key_android.dart`
- Create: `client/lib/platform/device_signing_key_unsupported.dart`
- Create: `client/lib/auth/mobile_auth_repository.dart`
- Create: `client/lib/auth/mobile_session_store.dart`
- Create: `client/lib/auth/mobile_login_controller.dart`
- Create: `client/lib/workspace/device_authorization_repository.dart`
- Create: `client/lib/screens/mobile_phone_login_screen.dart`
- Create: `client/lib/screens/device_approval_screen.dart`
- Create: `client/test/platform/device_signing_key_test.dart`
- Create: `client/test/auth/mobile_login_controller_test.dart`
- Create: `client/test/workspace/device_authorization_test.dart`

- [ ] **Step 1: Write failing Dart controller/repository tests and Android bridge contract tests.**
  - Mock the method channel to test generated public-key registration, canonical server-payload signing, unavailable-key failure, and no private-key export API.
  - Test mobile phone entry, OTP request state, wrong/expired/rate-limited OTP presentation, successful secure token storage, and resumed authenticated session.
  - Test first-workspace creation, invite acceptance, pending-device display, six-digit code comparison, partner approval request, successful activation, and rejected/expired state.
  - Test scan parsing rejects malformed, expired, non-HTTPS, or incorrect-version QR payloads before an API request.

  ~~~dart
  test("signs server payload without exposing a private key", () async {
    final key = FakeDeviceSigningKey();
    final signature = await key.sign(Uint8List.fromList([1, 2, 3]));
    expect(signature, isNotEmpty);
    expect(key.privateKeyWasRead, isFalse);
  });
  ~~~

- [ ] **Step 2: Run focused Flutter tests and confirm the existing password login cannot pass them.**
  - Run: `cd client && flutter test test/platform/device_signing_key_test.dart test/auth/mobile_login_controller_test.dart test/workspace/device_authorization_test.dart`.

- [ ] **Step 3: Add the Android Keystore method-channel implementation.**
  - Add a `MethodChannel("muyu/device-signing-key")` with:
    - `getOrCreatePublicKey` returning base64 DER SubjectPublicKeyInfo;
    - `sign` accepting server-supplied canonical bytes/base64 and returning base64 DER ECDSA signature;
    - `deleteKey` for local cleanup only after the user explicitly revokes/removes the device.
  - Generate a non-exportable P-256 key pair in Android Keystore under an installation-specific alias. Require user authentication when hardware/device capability supports it, but do not block supported devices that lack biometric hardware.
  - Do not implement an export, backup, synchronization, or Web transfer method for private key material.
  - Add Android Internet and camera permissions. Add `mobile_scanner` for QR scans, `qr_flutter` for Web QR display, and `web_socket_channel` for realtime. Remove obsolete local/P2P crypto packages only in Task 15 after replacements compile.
  - Add Android Internet and camera permissions. Add `mobile_scanner` for QR scans, `qr_flutter` for Web QR display, `web_socket_channel` for realtime, and `shared_preferences` for the display-only workspace cache. Remove obsolete local/P2P crypto packages only in Task 15 after replacements compile.

  ~~~kotlin
  private fun sign(payload: ByteArray): ByteArray {
      val privateKey = keyStore.getKey(alias, null) as PrivateKey
      return Signature.getInstance("SHA256withECDSA").run {
          initSign(privateKey)
          update(payload)
          sign()
      }
  }
  ~~~

- [ ] **Step 4: Implement Android-only authentication and approval UI.**
  - Use `flutter_secure_storage` only for opaque mobile session/refresh credentials; no OTP, signature payload, or private key is persisted in Dart storage.
  - Implement phone number, SMS code, retry-after, logout, and session-expired screens. The first successful Android session guides the user to create a workspace or accept a matching invite.
  - Implement approval, recovery, and phone-change screens that show the backend-issued short safety code, explicit expiry, actor/device labels, and an approve/reject command. Approval invokes the method-channel signer over the exact server payload.
  - Implement a QR scanner screen for Web authorization. It displays origin plus safety code before signing and sends the scan/approval to the backend.
  - Keep Android-specific imports behind platform boundaries so `flutter build web` does not import Android MethodChannel implementation.

- [ ] **Step 5: Verify Android builds and commit.**
  - Run: `cd client && dart format --set-exit-if-changed lib test`.
  - Run focused Flutter tests from Step 2.
  - Run: `cd client && flutter analyze`.
  - Run: `cd client && flutter build apk --debug --dart-define=API_BASE_URL=https://example.invalid/api/v1`.
  - Commit: `feat: add android sms identity and device approval`.


## Task 11: Build the Web QR Sign-In/Session Flow and Platform-Specific Flutter Transports

**Files:**
- Modify: `client/pubspec.yaml`
- Modify: `client/lib/main.dart`
- Modify: `client/lib/app.dart`
- Modify: `client/lib/core/api_client.dart`
- Create: `client/lib/core/api_transport.dart`
- Create: `client/lib/core/api_transport_mobile.dart`
- Create: `client/lib/core/api_transport_web.dart`
- Create: `client/lib/auth/web_login_repository.dart`
- Create: `client/lib/auth/web_session_controller.dart`
- Create: `client/lib/screens/web_qr_login_screen.dart`
- Create: `client/lib/screens/web_session_expired_screen.dart`
- Create: `client/test/auth/web_login_repository_test.dart`
- Create: `client/test/auth/web_session_controller_test.dart`
- Create: `client/test/core/api_transport_test.dart`

- [ ] **Step 1: Write failing browser-flow and transport tests.**
  - Test that a Web launch with no valid cookie displays QR login and never displays a phone number/SMS form.
  - Test that challenge creation uses an in-memory high-entropy browser proof, renders the supplied QR payload/safety code, polls status until approved/expired, exchanges exactly once, and then loads `/me`.
  - Test that a browser proof is discarded on expiry, cancel, logout, and browser session teardown; it is never placed in local storage, secure storage, URL, analytics, or logs.
  - Test that Web requests use same-origin cookies and do not attach Android mobile bearer credentials. Test Android requests attach only the opaque mobile bearer and do not depend on browser cookie behavior.
  - Test 401/410 states clear the Web session controller and return to QR login.

  ~~~dart
  testWidgets("web has QR login but no SMS entry", (tester) async {
    await tester.pumpWidget(const MuyuApp(platform: AppPlatform.web));
    expect(find.byType(WebQrLoginScreen), findsOneWidget);
    expect(find.text("短信验证码"), findsNothing);
  });
  ~~~

- [ ] **Step 2: Run focused tests in the red state.**
  - Run: `cd client && flutter test test/auth/web_login_repository_test.dart test/auth/web_session_controller_test.dart test/core/api_transport_test.dart`.

- [ ] **Step 3: Separate platform API transports.**
  - Define an `ApiTransport` interface for JSON requests, file-free response parsing, and authenticated WebSocket setup.
  - Implement mobile transport with bearer credentials from `MobileSessionStore`. Implement Web transport with `BrowserClient`/same-origin cookie credentials. Do not expose a common accessor that lets Web code read mobile credentials.
  - For local Web development, explicitly opt into credentialed requests only for the configured development API origin. Production uses the same origin through Caddy.
  - Generate the browser proof with browser cryptographic random bytes through `package:web` Web Crypto or a small platform abstraction; hash it before challenge creation. Keep only the raw proof in controller memory until exchange.

  ~~~dart
  abstract interface class ApiTransport {
    Future<ApiResponse> send(ApiRequest request);
    Stream<WorkspaceChanged> openWorkspaceHints();
  }

  final class WebApiTransport implements ApiTransport {
    WebApiTransport(this._client);

    final BrowserClient _client;
  }
  ~~~

- [ ] **Step 4: Implement Web QR login and session lifecycle.**
  - On the Web login screen, create a challenge on first render; display a QR code from the server payload, origin, short safety code, and a countdown.
  - Poll challenge status at a bounded interval while visible. On approval, exchange the in-memory proof, allow the HttpOnly cookie to be set by the browser, then fetch the authenticated profile/workspace snapshot.
  - Never parse, display, or persist the cookie value in Dart. Browser logout calls the server logout/revoke route and clears in-memory UI state; no client-side cookie deletion workaround is used.
  - Make 18-hour session expiry visible: a session-expired screen returns directly to a new QR challenge. There is no hidden refresh timer.
  - Add a session/device settings entry for Android only; Web can display its current session expiry but cannot use a Web cookie to approve, recover, add devices, or revoke other sessions.

- [ ] **Step 5: Verify Web build and commit.**
  - Run: `cd client && dart format --set-exit-if-changed lib test`.
  - Run focused Flutter tests from Step 2.
  - Run: `cd client && flutter analyze`.
  - Run: `cd client && flutter build web --release --dart-define=API_BASE_URL=/`.
  - Commit: `feat: add web qr session flow`.


## Task 12: Rebuild Shared Flutter Task, Sync, Conflict, and Manual-Refresh Experiences

**Files:**
- Modify: `client/lib/models/task.dart`
- Create: `client/lib/models/workspace_snapshot.dart`
- Create: `client/lib/models/workspace_change.dart`
- Create: `client/lib/models/task_conflict.dart`
- Create: `client/lib/sync/workspace_cache.dart`
- Create: `client/lib/sync/workspace_sync_repository.dart`
- Create: `client/lib/sync/workspace_sync_controller.dart`
- Create: `client/lib/task/cloud_task_repository.dart`
- Create: `client/lib/task/task_mutation_journal.dart`
- Create: `client/lib/task/task_controller.dart`
- Modify: `client/lib/screens/main_shell.dart`
- Modify: `client/lib/screens/task_list_screen.dart`
- Modify: `client/lib/screens/task_detail_screen.dart`
- Modify: `client/lib/screens/task_form_screen.dart`
- Modify: `client/lib/screens/task_action_dialogs.dart`
- Create: `client/lib/screens/task_conflict_screen.dart`
- Create: `client/lib/screens/sync_status_banner.dart`
- Create: `client/test/sync/workspace_sync_controller_test.dart`
- Create: `client/test/task/cloud_task_repository_test.dart`
- Create: `client/test/task/task_conflict_screen_test.dart`
- Create: `client/test/screens/manual_refresh_test.dart`

- [ ] **Step 1: Write failing sync and task UI tests.**
  - Test first launch fetches a snapshot, persists a compact cache keyed by workspace ID, and renders its cursor/time.
  - Test a `workspace.changed` hint triggers `/changes` pull rather than treating the WebSocket payload as task data.
  - Test foreground resume, browser focus/reconnect, a 30-second visible polling interval, and the manual-refresh control all call the same pull routine without duplicate application of a change.
  - Test loss of network never creates a local write queue. Cached content remains readable with a visible stale state and disabled mutation controls; a new task/edit action reports connection unavailable rather than storing a future command.
  - Test a mutation network timeout keeps the exact request ID/body in a small in-flight journal, then retries that same request or refreshes task state. It never generates a second request ID for the same user action.
  - Test different-field server success updates local state; `field_conflict` opens a conflict screen with baseline/current/proposed details; `lifecycle_conflict` refreshes and explains that current state changed.
  - Test deleted tasks show history and restore action but hide normal field edits, comments, delays, and completion until restored.

  ~~~dart
  test("websocket hint causes a cursor pull, not direct state mutation", () async {
    await controller.start();
    hints.add(const WorkspaceChanged(workspaceId: "w1", cursor: 12));
    await pumpEventQueue();
    expect(repository.requestedAfterCursors, contains(11));
    expect(controller.state.tasks.single.title, "Server title");
  });
  ~~~

- [ ] **Step 2: Run focused Flutter tests and confirm the old repositories lack this contract.**
  - Run: `cd client && flutter test test/sync/workspace_sync_controller_test.dart test/task/cloud_task_repository_test.dart test/task/task_conflict_screen_test.dart test/screens/manual_refresh_test.dart`.

- [ ] **Step 3: Implement cache and synchronization state management.**
  - Add a small persistent cache using `shared_preferences` containing only the latest server snapshot/change-applied projection, cursor, fetch timestamp, and workspace ID. It is a display cache, not an event store or source for mutations.
  - Store in-flight mutation records separately with route, body, request ID, original submit timestamp, and no secret credentials. On restart, reconcile only records created before an attempted HTTP request; replay them unchanged or fetch snapshot after a definitive server response.
  - Make the sync controller the sole owner of snapshot replacement, ordered change application, WebSocket lifecycle, polling, and stale state. It rejects gaps/out-of-order change data by fetching a full snapshot.
  - Treat `410 sync_cursor_expired`, JSON decode failure, or invariant mismatch as a cache replacement signal. Do not attempt to repair with client-side conflict rules.

  ~~~dart
  sealed class SyncState {
    const SyncState();
  }

  final class ReadySyncState extends SyncState {
    const ReadySyncState({
      required this.snapshot,
      required this.isStale,
      required this.lastSyncedAt,
    });

    final WorkspaceSnapshot snapshot;
    final bool isStale;
    final DateTime lastSyncedAt;
  }
  ~~~

- [ ] **Step 4: Rebuild task and collaboration screens around server authority.**
  - Update task create/edit UI to submit only changed fields with the field-version map received from the server and a generated UUID request ID.
  - Add clear lifecycle commands for complete, reopen, delete, and restore. The command dialogs show that delete preserves history and that restore is required before normal edits.
  - Add comment, delay, important-date, and recurrence forms matching the supported server schedule types. The task detail view renders append-only histories from API data.
  - Add search with debounced server queries, result highlighting from server response, and no client-side cross-workspace index.
  - Add a compact sync status banner containing last sync time, stale/error state, and an icon-only manual-refresh button with tooltip. It must be usable on Android and Web, fit narrow screens, and not obscure task controls.
  - Add the conflict screen: display field name plus baseline/current/proposed values, explain the conflict, allow current/proposed selection, and submit the server conflict-resolution endpoint with a new request ID.
  - Use API state after every successful write and after every conflict/timeout reconciliation; do not manufacture local completion, delay, or recurrence outcomes.

- [ ] **Step 5: Verify client behavior and commit.**
  - Run: `cd client && dart format --set-exit-if-changed lib test`.
  - Run focused Flutter tests from Step 2.
  - Run: `cd client && flutter test`.
  - Run: `cd client && flutter analyze`.
  - Run both: `flutter build apk --debug --dart-define=API_BASE_URL=https://example.invalid` and `flutter build web --release --dart-define=API_BASE_URL=/`.
  - Commit: `feat: add cloud task sync and conflict experience`.


## Task 13: Replace Deployment, Security, Backup, and Operational Documentation

**Files:**
- Modify: `backend/Dockerfile`
- Modify: `deploy/docker-compose.yml`
- Modify: `deploy/.env.example`
- Create: `deploy/Caddyfile`
- Create: `deploy/web.Dockerfile`
- Create: `deploy/postgres/postgresql.conf`
- Create: `deploy/postgres/pgbackrest.conf`
- Create: `deploy/backup/Dockerfile`
- Create: `deploy/scripts/backup-verify.sh`
- Create: `deploy/scripts/restore-drill.sh`
- Create: `docs/operations/deployment.md`
- Create: `docs/operations/backups-and-recovery.md`
- Create: `docs/operations/sms-provider.md`
- Create: `docs/operations/release-checklist.md`

- [ ] **Step 1: Write deployment configuration checks before replacing Compose.**
  - Add a shell/config test that renders Compose and asserts only Caddy has public ports, PostgreSQL has no host port, API is on an internal network, and the API service has exactly one replica in this release.
  - Assert production configuration fails without PostgreSQL URL, OTP pepper, production SMS credentials, allowed public origin, cookie-secure setting, backup repository credentials, and encryption key/cipher passphrase.
  - Assert `docker compose config` contains no legacy `AUTH_PASSWORD`, legacy JWT settings, seeded user variables, or P2P relay configuration.
  - Add a test fixture that verifies Caddy serves Flutter static assets, proxies `/api` and `/api/v1/realtime` to FastAPI, and does not cache authenticated API responses.

- [ ] **Step 2: Run configuration checks to establish the red state.**
  - Run: `docker compose --env-file deploy/.env.example -f deploy/docker-compose.yml config`.
  - Run: `rg -n "AUTH_PASSWORD|P2P|NEARBY|legacy" deploy backend/Dockerfile` and record currently active legacy references.

- [ ] **Step 3: Build the new single-instance production topology.**
  - Build Flutter Web in `deploy/web.Dockerfile`, serve its static output through Caddy, and proxy API/WebSocket traffic under the same TLS origin.
  - Run FastAPI behind Caddy on an internal network only. Configure trusted proxy headers, allowed hosts, production log redaction, and a single Uvicorn/Gunicorn application instance so in-memory realtime subscriptions remain valid.
  - Run PostgreSQL 16 on a private Compose network with a new `muyu_cloud_pgdata` named volume and a new empty `muyu_cloud` database. Do not mount or reuse any legacy volume.
  - Configure Caddy automatic HTTPS for the production domain, HTTP-to-HTTPS redirects, HSTS after domain verification, security headers compatible with Flutter Web, and WebSocket upgrade proxying.
  - Set cookie secure mode true in production. Local development uses a separate explicit environment file with an HTTP origin and insecure-cookie override that cannot be used by production Compose.

  ~~~caddy
  example.com {
      encode zstd gzip
      handle /api/* {
          reverse_proxy api:8080
      }
      handle /api/v1/realtime {
          reverse_proxy api:8080
      }
      handle {
          root * /srv
          try_files {path} /index.html
          file_server
      }
  }
  ~~~

- [ ] **Step 4: Make encrypted backup and point-in-time recovery operational.**
  - Configure PostgreSQL WAL archiving to a pgBackRest repository with repository encryption enabled and credentials supplied only at runtime.
  - Schedule full/differential backups and WAL archival in the dedicated backup service; retain a documented rolling window sized by the configured storage budget.
  - Write `backup-verify.sh` to restore a latest backup into a temporary PostgreSQL container/network, run `pg_isready` and a read-only migration/schema check, then remove only that explicit temporary container/volume.
  - Write `restore-drill.sh` to perform a time-targeted restore into a separately named drill database and compare row counts/cursor continuity against a supplied expected checkpoint. It must refuse to target the production database name.
  - Document operator steps for initial backup, daily backup verification, periodic restore drill, encryption-key rotation, losing backup credentials, and a rollback that keeps the new and legacy data volumes separate.

- [ ] **Step 5: Document safe production operation and commit.**
  - Document DNS/TLS, environment secret injection, SMS provider templates/rate limits, database migrations, backup monitoring, log redaction verification, Android app API URL, Web origin, and the one-instance WebSocket limitation.
  - Include a release checklist that names Android debug APK, signed Android AAB, and Flutter Web bundle as deliverables; explicitly states no iOS artifact is produced.
  - Run: `docker compose --env-file deploy/.env.example -f deploy/docker-compose.yml config`.
  - Run the configuration checks from Step 1 and `shellcheck` on deployment scripts if available.
  - Commit: `feat: add cloud deployment and recovery operations`.


## Task 14: Replace CI, Add Protocol/Integration Coverage, and Produce Android/Web Artifacts

**Files:**
- Modify: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`
- Modify: `Makefile`
- Delete: `scripts/smoke-auth.sh`
- Delete: `scripts/smoke-tasks.sh`
- Delete: `scripts/smoke-delay-blocking.sh`
- Create: `scripts/smoke-cloud-protocol.sh`
- Create: `backend/tests/e2e/test_cloud_protocol.py`
- Create: `client/integration_test/mobile_cloud_flow_test.dart`
- Create: `client/integration_test/web_session_flow_test.dart`
- Create: `docs/operations/build-artifacts.md`

- [ ] **Step 1: Write failing end-to-end protocol tests before retiring old smoke scripts.**
  - Use a PostgreSQL test database and fake SMS provider to run this sequence:
    1. A completes SMS registration and creates a workspace;
    2. A invites B;
    3. B completes SMS and is activated by A's signed approval;
    4. A creates a task and B receives it through snapshot/change pull;
    5. A and B make conflicting same-field writes and resolve the conflict;
    6. a browser QR challenge is approved by A's Android key fixture and exchanges a secure cookie;
    7. revoking the approving device revokes the browser session;
    8. a stale cursor forces a snapshot.
  - Use generated test P-256 keys and test client request bodies, never real phone numbers, OTP providers, browser cookies, Android private keys, or production signing values.
  - Add Android integration coverage for mobile session resume, refresh/manual sync status, and scanner payload validation. Add Chrome/Web integration coverage for QR-login UI state using a mocked approved challenge; backend protocol tests verify the actual cryptographic cross-client exchange.

- [ ] **Step 2: Run tests in the red state and ensure the old scripts are not treated as release proof.**
  - Run: `cd backend && pytest tests/e2e/test_cloud_protocol.py -q`.
  - Run: `cd client && flutter test integration_test/web_session_flow_test.dart -d chrome` where Chrome is available.
  - Run: `rg -n "smoke-auth|smoke-tasks|smoke-delay" Makefile .github deploy docs`.

- [ ] **Step 3: Replace CI test jobs with the cloud contract.**
  - Backend CI starts PostgreSQL 16, runs Alembic upgrade, executes the complete pytest suite, and runs the end-to-end protocol test with `OTP_PROVIDER=fake` and generated non-production secrets.
  - Client CI runs `flutter pub get`, format check, analyzer, unit/widget tests, and the Chrome integration test.
  - Add a Linux Android-emulator job that starts the test API, runs `mobile_cloud_flow_test.dart`, and uploads logcat/test output on failure. Keep camera hardware out of emulator acceptance by testing QR payload parsing and backend approval protocol separately.
  - Add a CI assertion that no runtime dependency/import references legacy P2P/local event-store packages or old password endpoint paths.
  - Make `make verify` run backend migration/tests, client analysis/tests, and deployment configuration rendering in the same order as CI.

  ~~~yaml
  services:
    postgres:
      image: postgres:16
      env:
        POSTGRES_DB: muyu_test
        POSTGRES_USER: muyu
        POSTGRES_PASSWORD: test-only-password
      ports:
        - 5432:5432
  ~~~

- [ ] **Step 4: Define reproducible deliverables and signing behavior.**
  - PR CI builds and uploads:
    - `client/build/app/outputs/flutter-apk/app-debug.apk`;
    - `client/build/web` as a compressed static artifact.
  - Protected release workflow accepts a version/tag, verifies all test jobs succeeded, materializes Android keystore credentials from protected secrets into a temporary file, builds a signed release AAB, uploads `app-release.aab`, and removes the temporary key file in an always-run cleanup step.
  - Fail a release build if Android signing secrets are absent or invalid; never silently publish an unsigned release AAB.
  - Document exact artifact names, SHA-256 checksum generation, source commit/version mapping, and installation/testing use for the debug APK. Do not add an IPA, Xcode setup, iOS runner, or iOS artifact job.

- [ ] **Step 5: Verify local/CI-equivalent commands and commit.**
  - Run: `make verify` against a local disposable PostgreSQL service.
  - Run: `cd client && flutter build apk --debug --dart-define=API_BASE_URL=https://example.invalid/api/v1`.
  - Run: `cd client && flutter build web --release --dart-define=API_BASE_URL=/`.
  - Run: `sh scripts/smoke-cloud-protocol.sh` against the disposable stack.
  - Commit: `ci: add cloud protocol verification and android web artifacts`.


## Task 15: Remove Legacy Runtime Paths, Perform the Empty-Workspace Cutover, and Run Release Verification

**Files:**
- Delete after replacement imports are removed: `backend/app/auth/passwords.py`
- Delete after replacement imports are removed: `backend/app/auth/tokens.py`
- Delete after replacement imports are removed: `backend/app/auth/session_repository.py`
- Delete after replacement imports are removed: `backend/app/user`
- Delete after replacement imports are removed: `backend/app/task`
- Delete after replacement imports are removed: `backend/app/activity`
- Delete after replacement tests are removed/replaced: `backend/tests/auth/test_passwords.py`
- Delete after replacement tests are removed/replaced: `backend/tests/auth/test_tokens.py`
- Delete after replacement tests are removed/replaced: `backend/tests/user`
- Delete after replacement tests are removed/replaced: `backend/tests/task`
- Delete after replacement API tests are added: `backend/tests/httpapi`
- Delete/replace after new client imports are complete: `client/lib/auth/auth_repository.dart`, `client/lib/auth/session_controller.dart`, `client/lib/auth/token_store.dart`, `client/lib/task/task_repository.dart`, `client/lib/task/task_controller.dart`, `client/lib/screens/login_screen.dart`
- Modify: `backend/app/main.py`
- Modify: `client/lib/app.dart`
- Modify: `client/lib/main.dart`
- Modify: `docs/operations/release-checklist.md`
- Create: `docs/operations/legacy-removal-verification.md`
- Create: `scripts/assert-no-legacy-runtime.sh`

- [ ] **Step 1: Write failing legacy-removal assertions before deleting files.**
  - Add a script/test that searches runtime source, dependency manifests, Compose, CI, smoke scripts, and generated API route registration for:
    - password login/password hash;
    - fixed-user seeding;
    - old JWT/token endpoint paths;
    - P2P/nearby/local event-store runtime imports and routes;
    - SQLite test fallback;
    - Elasticsearch/OpenSearch/Redis/MQ configuration.
  - Assert the only allowed matches are historical design documents or this implementation plan, never executable runtime paths.
  - Add an application route test that enumerates all registered routes and requires every non-health endpoint to begin with `/api/v1`.

- [ ] **Step 2: Run the assertions in the red state and inspect all matches manually.**
  - Run: `sh scripts/assert-no-legacy-runtime.sh`.
  - Run: `cd backend && pytest tests/test_main.py tests/test_main_startup.py -q`.
  - Classify every match as runtime, test-only replacement target, or historical documentation. Do not delete a historical architecture decision solely because it mentions the previous P2P design.

- [ ] **Step 3: Remove old runtime and replace application bootstrap.**
  - Remove old modules/tests only after all new imports and API tests pass. Keep `backend/app/auth/__init__.py` as the replacement auth package and delete only password/JWT implementation files.
  - Make `main.py` register only replacement routers, health routes, CORS/security middleware, startup schema migration check, and realtime shutdown cleanup. Remove fixed-user seeds and automatic legacy table creation.
  - Replace the client's old password/account/session controller wiring with the platform-aware mobile/Web session controllers from Tasks 10 and 11.
  - Remove local/P2P packages and dependencies found by the assertion script. Do not remove future-facing protocol documentation or the cloud architecture/specification records.
  - Replace old smoke scripts with `scripts/smoke-cloud-protocol.sh` from Task 14 and update the Makefile to call only new commands.

- [ ] **Step 4: Cut over to an empty cloud workspace.**
  - Stop any old local stack and deploy the new Compose project with its new project name, new PostgreSQL volume/database, and production secrets. Do not run an in-place data migration.
  - Apply the new Alembic head, verify the database has zero users/workspaces/tasks, and verify API health/readiness.
  - Register A through Android SMS, create a workspace, invite B, approve B's first device, and verify both mobile sessions see the same workspace.
  - From B's Android device, scan the Web QR challenge, approve it, verify Web task read/write with the 18-hour cookie, then revoke that Web session from B's Android device.
  - Create an important-date task, delay it, create a daily/weekly/monthly rule in separate test tasks, perform one conflicting edit, resolve it, and verify both Android and Web converge after a manual refresh and WebSocket hint.
  - Verify deleted task history remains visible through detail/history and restore is required before normal edits.

- [ ] **Step 5: Run final evidence checks and commit the cutover.**
  - Run: `sh scripts/assert-no-legacy-runtime.sh`.
  - Run: `make verify`.
  - Run: `docker compose -f deploy/docker-compose.yml config`.
  - Run: `cd backend && pytest -q`.
  - Run: `cd client && flutter test` and `flutter analyze`.
  - Verify artifacts and checksums:
    - debug APK for internal Android installation;
    - signed release AAB only from protected signing workflow;
    - Flutter Web static bundle.
  - Update `docs/operations/release-checklist.md` with the observed version, commit, migration head, artifact SHA-256 values, backup verification timestamp, and explicit “iOS not included in this release”.
  - Commit: `chore: remove legacy runtime and complete cloud cutover`.

## Verification Matrix

| Requirement | Primary evidence |
|---|---|
| PostgreSQL is authoritative and empty on first release | Task 2 migration test, Task 15 zero-row cutover check |
| SMS-only Android authentication | Task 3 backend tests, Task 10 mobile widget tests, fake-provider smoke |
| Phone is unique; max two equal members | Task 2 database constraints, Task 4 concurrency test |
| New long-term device requires other member | Task 4 signed approval tests, Task 10 approval UI test |
| Both devices lost requires dual recovery | Task 5 recovery tests and cutover walkthrough |
| Web login only by QR | Task 6 protocol tests, Task 11 Web UI test, no-SMS runtime assertion |
| Web session max 18 hours and revocable by owner Android | Task 6 cookie/revocation tests, Task 15 walkthrough |
| No plaintext private key leaves Android | Task 4 signature verification, Task 10 MethodChannel test, source assertion |
| Cloud plaintext task coordination | Task 7/8 PostgreSQL task projections; no client content encryption layer |
| Atomic task writes and idempotency | Task 7 transaction/concurrency/idempotency tests |
| Explicit same-field conflict resolution | Task 7 conflict tests, Task 12 conflict screen test |
| Soft delete preserves history | Task 7/8 delete/restore/history tests, Task 15 walkthrough |
| Server-authoritative sync, no offline queue | Task 9 cursor tests, Task 12 stale/no-queue tests |
| WebSocket has no content | Task 9 payload assertion and log redaction test |
| PG FTS/trigram instead of ES | Task 8 index/query-plan test, dependency/config assertion |
| Backups and restore drills | Task 13 scripts and operator checklist |
| Android/Web release artifacts | Task 14 CI artifacts and Task 15 checksums |
| iOS deferred without current build | Task 14 workflow inspection and release checklist |

## Execution Notes

- Implement each task in order because later clients depend on the exact server schemas, error codes, signatures, cursors, and session boundaries defined earlier.
- Keep every task's focused tests in the same commit as the implementation. Do not mark a task complete based only on compilation.
- When a task adds a migration after the initial cloud migration has landed, create a forward-only Alembic revision and test upgrade from the previous head. Never edit an applied production migration.
- Use separate local environment files for fake SMS/HTTP development and production. Never copy production secrets into tests, APK build arguments, Web static assets, or source control.
- The first production deployment is a new empty workspace/database. Existing users and data remain outside the new runtime only until the operator explicitly retires the old deployment after Task 15 verification.
