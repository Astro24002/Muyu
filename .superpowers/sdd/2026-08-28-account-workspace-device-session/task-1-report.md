# Task 1 Implementation Report

## Scope

Locked the account, two-person Workspace, Android-device, and WebSession
domain contracts without adding a WebDevice table or changing existing
primary keys or Workspace slot constraints.

Changed files:

- `backend/app/db/enums.py`: added `BootstrapState` and the public
  `PublicDeviceStatus` vocabulary while preserving persisted
  `DeviceStatus` and `WebSessionStatus` values.
- `backend/app/workspaces/bootstrap_schemas.py`: added bootstrap response
  models, public device-status translation, and first-versus-subsequent
  device enrollment classification.
- `backend/app/db/models.py`: declared composite `(status, expires_at)`
  indexes for `WebSession` and `WebLoginChallenge`.
- `backend/alembic/versions/0002_workspace_device_session_indexes.py`: added
  idempotent upgrade/downgrade support for those cleanup indexes. The
  revision identifier is intentionally shorter than the descriptive filename
  because the existing Alembic version table uses `VARCHAR(32)`.
- `backend/tests/domain/test_workspace_device_session_contract.py`: added
  contract coverage for first/subsequent device states, public status values,
  persisted enum compatibility, WebSession/device separation, current-device
  revoke error code, and cleanup indexes.

## TDD Evidence

Initial red run, using the disposable PostgreSQL test container because the
host has no pytest installation:

```text
python -m pytest -q tests/domain/test_workspace_device_session_contract.py
3 failed, 3 passed
```

The expected failures were the missing `app.workspaces.bootstrap_schemas`
module and missing composite cleanup indexes.

After the minimal implementation:

```text
python -m pytest -q tests/domain/test_workspace_device_session_contract.py
6 passed
```

## Verification

Focused contract and existing database schema tests, against the disposable
`muyu-task1-postgres` PostgreSQL container:

```text
python -m pytest -q tests/domain/test_workspace_device_session_contract.py tests/db/test_cloud_schema.py
12 passed
```

The required focused command plus compilation also passed:

```text
python -m pytest -q tests/domain/test_workspace_device_session_contract.py
6 passed
python -m compileall -q app
```

The migration check used a temporary schema and completed an upgrade to head,
downgrade to the previous revision, upgrade to head again, and downgrade to
base:

```text
upgrade/downgrade cycle: PASS
```

`git diff --check` passed.

## Not Run / Risks

- The exact host command `cd backend && pytest -q ...` cannot start because
  `pytest` is not installed on the host. The same command was run inside the
  repository's disposable PostgreSQL test container.
- The full backend suite was not completed: the available test-dependency
  image lacks `cryptography`, so collection stopped with import errors in
  existing device/auth/HTTP tests. This is an environment image issue, not a
  failure in the Task 1 focused contract tests.
- First-device classification is exposed as a domain helper for the next
  authentication/bootstrap task; the existing authentication flow remains
  unchanged in this contract-only task.

## Commit

`feat: define workspace device and web session contracts`
