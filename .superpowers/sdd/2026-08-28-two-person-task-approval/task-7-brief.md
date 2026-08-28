# Task 7 Brief — Android task detail and approval inbox UI

## Objective

Build the Android task workflow on top of the typed models and controller APIs delivered by Task 6. Keep the UI lightweight: one Workspace with exactly two users, one derived task owner (`current_handler_id`), and one approval request addressed to the other member. Screens must never construct raw approval payloads or bypass the controller.

## Required behavior

- Show task number (`YYMMNNNN`) and parent/subtask relationship. Subtasks use the same `TaskItem` model and the server's one-level nesting rule.
- Show the task owner, status, quadrant label (`Q1`-`Q4`) and progress only while status is `IN_PROGRESS`.
- Progress choices are `20`, `40`, `60`, `80`; TODO displays `0` and DONE displays `100`; do not show an editable progress control for other statuses.
- The owner may edit task fields directly. The other Workspace member submits an approval request and sees a visible pending state without optimistic task mutation.
- Quadrant edits by the non-owner also go through approval. The server remains authoritative for all permissions and versions.
- Render comments including soft-deleted tombstones. Comment authors can delete their own comments; the task owner can request deletion of the other user's comment and the author can approve/reject it.
- Add an approval inbox entry from the Workspace or “我的” area. The approval screen has incoming (“待我审批”) and outgoing (“我发起的请求”) sections.
- Incoming pending requests show approve/reject actions only to the derived approver. Outgoing pending requests show cancel only to the requester. Resolved states are read-only and show rejection/conflict/cancel details.
- Unverified/read-only devices can view tasks, comments and approval requests but must not see enabled write or approval actions. Derive current user from `WorkspaceSnapshot.viewerUserId`, never from member ordering.

## Files

- Create `client/lib/screens/task_approval_screen.dart`.
- Modify `client/lib/screens/cloud_workspace_screen.dart` and `client/lib/screens/task_detail_screen.dart`.
- Add/modify focused widget tests under `client/test/screens/`.

## Verification

Run with `/home/muyu/develop/flutter/bin/flutter`:

```bash
flutter test test/screens/task_approval_screen_test.dart test/screens/task_detail_screen_test.dart test/screens/cloud_workspace_screen_test.dart
flutter analyze
flutter test
```

Do not run Flutter Web integration tests; Flutter reports Web devices are unsupported for integration tests. Keep existing test doubles source-compatible where possible.

## Commit

Commit the UI slice as:

```text
feat: add Android task approval workflow
```

Write a short report beside this brief with changed files, user-visible behavior and exact verification output.
