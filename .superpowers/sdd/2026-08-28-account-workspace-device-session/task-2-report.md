# Task 2 Implementation Report

## Scope

Implemented first-login Workspace bootstrap, two-person partner binding, invite
acceptance, and first-versus-subsequent Android-device enrollment behavior.

Changed files:

- `backend/app/workspaces/bootstrap_service.py`: added transactional bootstrap
  state projection, partner binding, invite acceptance, E.164 normalization,
  masked invite summaries, and persisted idempotency replay.
- `backend/app/workspaces/routes.py`: added bootstrap and bind-partner routes,
  switched invite acceptance to the bootstrap service, and allowed pending
  devices to read/accept invitations while preserving active-device binding
  authorization.
- `backend/app/workspaces/schemas.py`: added validated request bodies carrying
  UUID request IDs.
- `backend/app/auth/service.py`: classifies a newly enrolled device by the
  account's existing Android-device count; the first is `ACTIVE` and later
  devices are `PENDING` regardless of Workspace membership.
- `backend/tests/httpapi/test_workspace_bootstrap_flow.py`: added HTTP flow,
  persistence, idempotency, direct first-device acceptance, pending-device
  acceptance, and self-binding regression tests.

The Task 1 `BootstrapState`, `BootstrapPayload`, `BootstrapDevice`,
`BootstrapWorkspace`, `BootstrapInvite`, public device-status mapping, and
`0002_device_session_indexes` migration were reused without modification.
Task 4 self-revoke behavior was not changed.

## TDD Evidence

After writing the new HTTP tests and before the implementation, the focused
run against the disposable PostgreSQL test container failed at the missing
routes as expected:

```text
python -m pytest -q tests/httpapi/test_workspace_bootstrap_flow.py
6 failed, 1 warning
```

The first host attempt could not run because `pytest` is not installed on the
host. A second attempt using the default host database credentials reached
fixture setup but failed authentication; the meaningful red run above used
the repository's running PostgreSQL test container.

After implementation and the masking correction:

```text
python -m pytest -q tests/httpapi/test_workspace_bootstrap_flow.py
6 passed, 1 warning
```

## Verification

Focused bootstrap, existing workspace, onboarding, and compilation checks:

```text
python -m compileall -q app
python -m pytest -q tests/httpapi/test_workspace_bootstrap_flow.py tests/httpapi/test_workspace_bootstrap.py tests/workspaces/test_onboarding.py
8 passed, 1 warning
```

Existing auth and mobile-session regressions:

```text
python -m pytest -q tests/httpapi/test_workspace_bootstrap.py tests/workspaces/test_onboarding.py tests/auth/test_sms_auth.py tests/auth/test_mobile_sessions.py
13 passed, 1 warning
```

Full backend suite:

```text
python -m pytest -q
77 passed, 3 skipped, 1 warning
```

`git diff --check` passed. The warning is the existing Starlette TestClient
deprecation notice.

## Concerns

- The brief names `tests/domain/test_workspace_service.py`, but this checkout
  has no such file; the existing WorkspaceService onboarding coverage is
  `tests/workspaces/test_onboarding.py`, which was run successfully.
- The host has no Python test dependencies, so verification used the existing
  `muyu-phase3-test` container with PostgreSQL test container credentials.
- The legacy invite-accept request shape now requires `request_id` and returns
  the bootstrap payload as specified by Task 2; callers must send the new
  request body contract.

## Commit

Commit message: `feat: bootstrap two-person workspace binding`
