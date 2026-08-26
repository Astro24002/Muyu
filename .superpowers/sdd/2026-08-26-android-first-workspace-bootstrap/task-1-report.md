# Task 1 Implementation Report

## Scope

Added backend characterization and security regression tests for the first-workspace bootstrap contract:

- `backend/tests/httpapi/test_workspace_bootstrap.py` covers an authenticated ACTIVE Android device querying an empty current workspace, creating one workspace, observing the owner membership, querying it again, and receiving `409 workspace_limit_reached` on repeat creation. The file contains its own minimal `FakeSmsProvider` helper.
- `backend/tests/web_login/test_qr_login.py` covers QR scanning by an ACTIVE device whose ACTIVE user has no ACTIVE workspace membership. The service must raise `WebLoginConflict` with code `workspace_access_denied` and status `403`.

No production files were modified. Existing route, workspace-service, and web-login membership checks satisfy the fixed API/security contract.

## Verification

Focused command against the disposable `muyu-task1-postgres` container:

```text
4 passed, 1 warning in 1.86s
```

The same command also ran `python -m compileall -q app alembic` successfully.

Full backend command against that disposable database:

```text
55 passed, 2 skipped, 1 warning in 13.14s
```

The repository `make backend-test` default URL could not authenticate to the currently running local PostgreSQL service (`password authentication failed for user "muyu"`); no application or credential files were changed.

## Commit

The focused test changes are committed as `test: cover first workspace bootstrap contract`.
