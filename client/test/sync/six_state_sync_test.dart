import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/task.dart';
import 'package:muyu_client/models/workspace_change.dart';
import 'package:muyu_client/models/workspace_snapshot.dart';
import 'package:muyu_client/sync/workspace_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> taskJson({
  required String id,
  required String status,
  String? blockedReason,
  String? blockedSince,
  String? resumeHandlerId,
  String? waitingForUserId,
  String? reviewerUserId,
  String? reviewSubmittedAt,
  String? reviewedAt,
  String? reviewRejectionReason,
}) => {
  'id': id,
  'parent_task_id': null,
  'task_number': '26090001',
  'title': '同步任务',
  'description': '完整元数据',
  'status': status,
  'current_handler_id': 'user-1',
  'quadrant': 'Q1',
  'labels': <String>['同步'],
  'blocked_reason': blockedReason,
  'blocked_since': blockedSince,
  'resume_handler_id': resumeHandlerId,
  'waiting_for_user_id': waitingForUserId,
  'planned_start_at': null,
  'due_at': null,
  'estimated_minutes': 30,
  'completed_at': null,
  'reviewer_user_id': reviewerUserId,
  'review_submitted_at': reviewSubmittedAt,
  'reviewed_at': reviewedAt,
  'review_rejection_reason': reviewRejectionReason,
  'created_by': 'user-1',
  'version': 4,
  'status_version': 3,
  'field_versions': <String, int>{'title': 2, 'status': 3},
  'lifecycle_version': 3,
  'created_at': '2026-09-02T00:00:00Z',
  'updated_at': '2026-09-02T11:00:00Z',
  'delay_count': 0,
  'total_delay_minutes': 0,
  'deleted_at': null,
};

void main() {
  test(
    'round-trips BLOCKED and REVIEW metadata through the workspace cache',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final blocked = TaskItem.fromJson(
        taskJson(
          id: 'blocked',
          status: 'BLOCKED',
          blockedReason: '等待资料',
          blockedSince: '2026-09-02T10:00:00Z',
          resumeHandlerId: 'user-1',
          waitingForUserId: 'user-2',
        ),
      );
      final review = TaskItem.fromJson(
        taskJson(
          id: 'review',
          status: 'REVIEW',
          reviewerUserId: 'user-2',
          reviewSubmittedAt: '2026-09-02T11:00:00Z',
          reviewRejectionReason: '补充订单截图',
        ),
      );
      final snapshot = WorkspaceSnapshot(
        workspaceId: 'workspace-1',
        cursor: 19,
        tasks: [blocked, review],
        conflicts: [
          {
            'id': 'conflict-1',
            'task_id': 'review',
            'field': 'status',
            'proposed_payload': {
              'target_status': 'IN_PROGRESS',
              'review_rejection_reason': '补充订单截图',
            },
            'field_versions': {'title': 2},
            'status_version': 3,
            'lifecycle_version': 3,
          },
        ],
      );
      final cache = SharedPreferencesWorkspaceCache(preferences);

      await cache.write(snapshot);
      final restored = await cache.read('workspace-1');

      expect(restored?.cursor, 19);
      expect(restored?.tasks[0].status, 'BLOCKED');
      expect(restored?.tasks[0].blockedReason, '等待资料');
      expect(restored?.tasks[0].blockedSince, DateTime.utc(2026, 9, 2, 10));
      expect(restored?.tasks[0].resumeHandlerId, 'user-1');
      expect(restored?.tasks[0].waitingForUserId, 'user-2');
      expect(restored?.tasks[0].fieldVersions, {'title': 2, 'status': 3});
      expect(restored?.tasks[0].statusVersion, 3);
      expect(restored?.tasks[0].lifecycleVersion, 3);
      expect(restored?.tasks[1].status, 'REVIEW');
      expect(restored?.tasks[1].reviewerUserId, 'user-2');
      expect(
        restored?.tasks[1].reviewSubmittedAt,
        DateTime.utc(2026, 9, 2, 11),
      );
      expect(restored?.tasks[1].reviewRejectionReason, '补充订单截图');
      expect(restored?.conflicts.single['proposed_payload'], {
        'target_status': 'IN_PROGRESS',
        'review_rejection_reason': '补充订单截图',
      });
    },
  );

  test('normalizes legacy statuses on read and never writes them back', () {
    final legacy = TaskItem.fromJson(
      taskJson(id: 'legacy-blocked', status: 'WAITING'),
    );
    final completed = TaskItem.fromJson(
      taskJson(id: 'legacy-done', status: 'COMPLETED'),
    );

    expect(legacy.status, 'BLOCKED');
    expect(completed.status, 'DONE');
    expect(legacy.toJson()['status'], 'BLOCKED');
    expect(completed.toJson()['status'], 'DONE');
    expect(jsonEncode(legacy.toJson()), isNot(contains('WAITING')));
    expect(jsonEncode(completed.toJson()), isNot(contains('COMPLETED')));
  });

  test('rejects malformed change metadata before a cursor can be applied', () {
    expect(
      () => WorkspaceChanges.fromJson({
        'workspace_id': 'workspace-1',
        'cursor': 7,
        'changes': [
          {
            'cursor': 7,
            'resource_type': 'task_conflict',
            'resource_id': 'conflict-1',
            'action': 'UNKNOWN',
            'resource': null,
          },
        ],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects null and unknown non-conflict change resources', () {
    for (final resourceType in ['task', 'approval_request', 'comment']) {
      expect(
        () => WorkspaceChanges.fromJson({
          'workspace_id': 'workspace-1',
          'cursor': 7,
          'changes': [
            {
              'cursor': 7,
              'resource_type': resourceType,
              'resource_id': '$resourceType-1',
              'action': 'UPDATED',
              'resource': null,
            },
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    }

    expect(
      () => WorkspaceChanges.fromJson({
        'workspace_id': 'workspace-1',
        'cursor': 7,
        'changes': [
          {
            'cursor': 7,
            'resource_type': 'future_resource',
            'resource_id': 'future-1',
            'action': 'UPDATED',
            'resource': {'id': 'future-1'},
          },
        ],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a task change without workspace identity', () {
    final resource = taskJson(id: 'task-1', status: 'TODO');
    expect(
      () => WorkspaceChanges.fromJson({
        'workspace_id': 'workspace-1',
        'cursor': 7,
        'changes': [
          {
            'cursor': 7,
            'resource_type': 'task',
            'resource_id': 'task-1',
            'action': 'UPDATED',
            'resource': resource,
          },
        ],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('retains null task_conflict tombstones at the parsing boundary', () {
    final changes = WorkspaceChanges.fromJson({
      'workspace_id': 'workspace-1',
      'cursor': 7,
      'changes': [
        {
          'cursor': 7,
          'resource_type': 'task_conflict',
          'resource_id': 'conflict-1',
          'action': 'UPDATED',
          'resource': null,
        },
      ],
    });

    expect(changes.changes.single.conflict, isNull);
  });

  test('rejects an unknown task conflict status in a changes envelope', () {
    final changes = WorkspaceChanges.fromJson({
      'workspace_id': 'workspace-1',
      'cursor': 7,
      'changes': [
        {
          'cursor': 7,
          'resource_type': 'task_conflict',
          'resource_id': 'conflict-1',
          'action': 'UPDATED',
          'resource': {
            'id': 'conflict-1',
            'workspace_id': 'workspace-1',
            'task_id': 'task-1',
            'field': 'title',
            'status': 'UNKNOWN',
          },
        },
      ],
    });

    expect(
      changes.isValidFor(workspaceId: 'workspace-1', afterCursor: 6),
      isFalse,
    );
  });

  test('retains resource workspace identity while parsing changes', () {
    final parsed = WorkspaceChanges.fromJson({
      'workspace_id': 'workspace-1',
      'cursor': 7,
      'changes': [
        {
          'cursor': 7,
          'resource_type': 'task',
          'resource_id': 'task-1',
          'action': 'UPDATED',
          'resource': {
            ...taskJson(id: 'task-1', status: 'TODO'),
            'workspace_id': 'workspace-1',
          },
        },
      ],
    });

    expect(parsed.changes.single.task?.workspaceId, 'workspace-1');
  });

  test(
    'rejects a task change whose resource identity does not match its task',
    () {
      final changes = WorkspaceChanges(
        workspaceId: 'workspace-1',
        cursor: 7,
        changes: [
          WorkspaceChange(
            cursor: 7,
            resourceType: 'task',
            resourceId: 'task-1',
            action: 'updated',
            task: TaskItem.fromJson({
              ...taskJson(id: 'task-2', status: 'TODO'),
              'workspace_id': 'workspace-1',
            }),
          ),
        ],
      );

      expect(
        changes.isValidFor(workspaceId: 'workspace-1', afterCursor: 6),
        isFalse,
      );
    },
  );
}
