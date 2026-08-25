# Cloud API Contract

The cloud API is versioned under `/api/v1`. All task-content mutations use
authoritative REST endpoints. WebSocket messages are advisory invalidation hints
only; clients re-fetch through REST after a hint.

Every error response uses this stable envelope and carries the request ID in
the `X-Request-ID` response header:

```json
{
  "code": "workspace_access_denied",
  "message": "workspace access denied",
  "details": {}
}
```

Mutation requests require a body `request_id` UUID. The server stores one
result per workspace and key, returning that result for retries. Change feeds
use opaque cursors scoped to one workspace; a client consumes changes strictly
after its supplied cursor. Cursor expiry is reported as a problem response and
requires a full REST resynchronization.

Authentication, device approvals, task operations, web sessions, and sync
endpoints are defined in later implementation tasks. Their responses must not
place task content in logs, WebSocket payloads, or error details.
