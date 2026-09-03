# Task 4 Fix 4 Report

Completed the concrete findings from the fix3 review in the existing worktree.

- Added standalone canonical six-state status contracts and labels for Web and Flutter, while keeping `WAITING` and `COMPLETED` as read-boundary aliases only.
- Hardened Web and Flutter change envelopes: unknown resource types, null non-conflict resources, missing task workspace identity, invalid conflict statuses, foreign resources, and resource ID mismatches are rejected before cursor advancement. Null `task_conflict` tombstones retain action-first semantics.
- Required complete 409 field-conflict projections: non-negative cursor, non-empty conflicts, exact workspace/status identity, and a complete canonical current task snapshot. Flutter now reconciles every changes page through the projected cursor and refreshes on malformed or non-progressing responses without leaving the recovered state stale.
- Added REVIEW/status contract coverage and backend HTTP/domain replay assertions for unchanged side-effect counts. The sync-required `public_display_name` helper is staged separately from the pre-existing profile service so the HEAD sync import remains standalone.

Verification:

- Web typecheck: pass.
- Focused Web tests: 107 passed across 8 files.
- Flutter sync/status tests: 37 passed.
- Dart format check: pass; Flutter analyze: no issues.
- Focused backend approval/sync target: 83 passed, 5 legacy failures.

The backend failures are pre-existing tests that still request `WAITING` transitions, plus one old `IN_PROGRESS -> DONE` expectation: `test_lightweight_contract.py` (2), `test_two_person_task_domain.py` (3). They are outside this fix round and were not changed.
