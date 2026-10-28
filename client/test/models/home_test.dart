import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/models/home.dart';

Map<String, dynamic> taskJson(String id, String status) => {
  'id': id,
  'workspace_id': 'workspace-1',
  'parent_task_id': null,
  'task_number': '26080001',
  'title': id,
  'description': '',
  'status': status,
  'quadrant': 'Q1',
  'labels': <String>[],
  'progress': status == 'IN_PROGRESS' ? 40 : null,
  'current_handler_id': 'user-1',
  'blocked_reason': status == 'BLOCKED' ? '等待确认' : null,
  'blocked_since': null,
  'resume_handler_id': null,
  'waiting_for_user_id': null,
  'reviewer_user_id': status == 'REVIEW' ? 'user-1' : null,
  'review_submitted_at': null,
  'reviewed_at': null,
  'review_rejection_reason': null,
  'planned_start_at': null,
  'due_at': null,
  'estimated_minutes': null,
  'completed_at': null,
  'created_by': 'user-1',
  'created_at': '2026-09-03T00:00:00Z',
  'updated_at': '2026-09-03T00:00:00Z',
  'delay_count': 0,
  'total_delay_minutes': 0,
  'version': 1,
  'status_version': 1,
  'field_versions': <String, int>{},
  'lifecycle_version': 1,
  'deleted_at': null,
};

Map<String, dynamic> approvalJson({String? taskId}) => {
  'id': 'approval-1',
  'workspace_id': 'workspace-1',
  'task_id': taskId,
  'comment_id': null,
  'requester_id': 'user-2',
  'approver_id': 'user-1',
  'request_type': 'TASK_UPDATE',
  'proposed_changes': <String, dynamic>{'title': '提议'},
  'base_field_versions': <String, dynamic>{'title': 1},
  'request_id': 'request-1',
  'status': 'PENDING',
  'created_at': '2026-09-14T00:00:00Z',
  'reviewed_at': null,
  'reviewed_by': null,
  'rejection_reason': null,
  'resolved_cursor': null,
};

void main() {
  test('parses bounded action sections and validates their workspace', () {
    final home = HomeResponse.fromJson({
      'current_tasks': {
        'items': [taskJson('current', 'TODO')],
        'has_more': true,
      },
      'blocked_tasks': {
        'items': [taskJson('blocked', 'BLOCKED')],
        'has_more': false,
      },
      'review_tasks': {
        'items': [taskJson('review', 'REVIEW')],
        'has_more': false,
      },
      'pending_approval_count': 2,
    });

    expect(home.currentTasks.items.single.id, 'current');
    expect(home.currentTasks.hasMore, isTrue);
    expect(home.blockedTasks.items.single.status, 'BLOCKED');
    expect(home.reviewTasks.items.single.status, 'REVIEW');
    expect(home.pendingApprovalCount, 2);
    expect(home.needsActionCount, 2);
    expect(home.waitingOnOtherCount, 0);
    expect(home.weekDueCount, 0);
    expect(home.hasMomentProjection, isFalse);
    expect(home.isValidForWorkspace('workspace-1'), isTrue);
    expect(home.isValidForWorkspace('workspace-other'), isFalse);
  });

  test('parses the additive moment projection and top counts', () {
    final home = HomeResponse.fromJson({
      'current_tasks': {
        'items': [taskJson('current', 'TODO')],
        'has_more': false,
      },
      'blocked_tasks': {'items': [], 'has_more': false},
      'review_tasks': {'items': [], 'has_more': false},
      'pending_approval_count': 4,
      'moment': {
        'blocked_tasks': {
          'items': [taskJson('moment-blocked', 'BLOCKED')],
          'has_more': false,
        },
        'my_tasks': {
          'items': [taskJson('moment-mine', 'IN_PROGRESS')],
          'has_more': false,
        },
        'other_tasks': {
          'items': [taskJson('moment-other', 'TODO')],
          'has_more': true,
        },
        'all_tasks_has_more': true,
      },
      'needs_action_count': 3,
      'waiting_on_other_count': 2,
      'week_due_count': 5,
    });

    expect(home.hasMomentProjection, isTrue);
    expect(home.moment.blockedTasks.items.single.id, 'moment-blocked');
    expect(home.moment.myTasks.items.single.status, 'IN_PROGRESS');
    expect(home.moment.otherTasks.items.single.id, 'moment-other');
    expect(home.moment.otherTasks.hasMore, isTrue);
    expect(home.moment.allTasksHasMore, isTrue);
    expect(home.needsActionCount, 3);
    expect(home.waitingOnOtherCount, 2);
    expect(home.weekDueCount, 5);
    expect(home.isValidForWorkspace('workspace-1'), isTrue);
    expect(home.allTasks.map((task) => task.id), contains('moment-other'));
  });

  test('rejects malformed action sections', () {
    expect(
      () => HomeResponse.fromJson({'pending_approval_count': 0}),
      throwsFormatException,
    );
    expect(
      () => HomeResponse.fromJson({
        'current_tasks': {'items': [], 'has_more': false},
        'blocked_tasks': {'items': [], 'has_more': false},
        'review_tasks': {'items': [], 'has_more': false},
        'pending_approval_count': -1,
      }),
      throwsFormatException,
    );
  });

  test('parses canonical moment metadata and taskless approval entries', () {
    final home = HomeResponse.fromJson({
      'viewer_user_id': 'user-1',
      'as_of': '2026-09-14T10:00:00Z',
      'week': {
        'timezone': 'Asia/Shanghai',
        'start': '2026-09-13T16:00:00Z',
        'end': '2026-09-20T16:00:00Z',
      },
      'entry_counts': {
        'needs_me': 1,
        'waiting_on_other': 0,
        'due_this_week': 2,
        'due_soon': 1,
      },
      'current_tasks': {'items': [], 'has_more': false},
      'blocked_tasks': {'items': [], 'has_more': false},
      'review_tasks': {'items': [], 'has_more': false},
      'pending_approval_count': 1,
      'moment': {
        'blocked': {'items': [], 'has_more': false},
        'mine': {
          'items': [taskJson('mine', 'IN_PROGRESS')],
          'has_more': false,
        },
        'other': {'items': [], 'has_more': false},
        'all_tasks_has_more': false,
      },
      'needs_action_count': 1,
      'waiting_on_other_count': 0,
      'week_due_count': 2,
      'entries': {
        'needs_me': {
          'items': [
            {'approval_request': approvalJson(), 'task': null},
          ],
          'has_more': false,
        },
        'waiting_on_other': {'items': [], 'has_more': false},
        'due_this_week': {
          'items': [taskJson('due', 'TODO')],
          'has_more': false,
        },
        'due_soon': {
          'items': [taskJson('due-soon', 'TODO')],
          'has_more': false,
        },
      },
    });

    expect(home.viewerUserId, 'user-1');
    expect(home.asOf, DateTime.parse('2026-09-14T10:00:00Z'));
    expect(home.week?.timezone, 'Asia/Shanghai');
    expect(home.week?.start, DateTime.utc(2026, 9, 13, 16));
    expect(home.entryCounts.needsMe, 1);
    expect(home.entryCounts.dueSoon, 1);
    expect(home.dueSoonCount, 1);
    expect(home.entries.needsMe.items.single.task, isNull);
    expect(home.entries.dueSoon.items.single.id, 'due-soon');
    expect(home.moment.mine.items.single.id, 'mine');
    expect(home.allTasks.map((task) => task.id), ['mine', 'due', 'due-soon']);
    expect(home.isValidForWorkspace('workspace-1'), isTrue);
  });

  test('keeps review tasks in the owner moment section', () {
    final home = HomeResponse.fromJson({
      'viewer_user_id': 'user-1',
      'entry_counts': {
        'needs_me': 0,
        'waiting_on_other': 0,
        'due_this_week': 0,
      },
      'moment': {
        'blocked': {'items': [], 'has_more': false},
        'mine': {
          'items': [taskJson('review-mine', 'REVIEW')],
          'has_more': false,
        },
        'other': {'items': [], 'has_more': false},
      },
    });

    expect(home.moment.mine.items.single.status, 'REVIEW');
  });

  test('falls back to legacy counts and moment aliases when canonical fields are absent', () {
    final home = HomeResponse.fromJson({
      'viewer_user_id': 'user-1',
      'current_tasks': {'items': [], 'has_more': false},
      'blocked_tasks': {'items': [], 'has_more': false},
      'review_tasks': {'items': [], 'has_more': false},
      'pending_approval_count': 2,
      'needs_action_count': 3,
      'waiting_on_other_count': 4,
      'week_due_count': 5,
      'moment': {
        'blocked_tasks': {
          'items': [taskJson('legacy-blocked', 'BLOCKED')],
          'has_more': false,
        },
        'my_tasks': {'items': [], 'has_more': false},
        'other_tasks': {'items': [], 'has_more': false},
        'all_tasks_has_more': true,
      },
    });

    expect(home.viewerUserId, 'user-1');
    expect(home.asOf, isNull);
    expect(home.week, isNull);
    expect(home.entryCounts.needsMe, 3);
    expect(home.entryCounts.waitingOnOther, 4);
    expect(home.entryCounts.dueThisWeek, 5);
    expect(home.entries.needsMe.items, isEmpty);
    expect(home.moment.blocked.items.single.id, 'legacy-blocked');
    expect(home.moment.blockedTasks.items.single.id, 'legacy-blocked');
    expect(home.moment.hasCanonicalSections, isFalse);
  });

  test(
    'rejects invalid canonical counts, week timezone, and approval task shape',
    () {
      final base = {
        'viewer_user_id': 'user-1',
        'as_of': '2026-09-14T10:00:00Z',
        'week': {
          'timezone': 'UTC',
          'start': '2026-09-14T00:00:00Z',
          'end': '2026-09-21T00:00:00Z',
        },
        'entry_counts': {
          'needs_me': 0,
          'waiting_on_other': 0,
          'due_this_week': 0,
        },
        'current_tasks': {'items': [], 'has_more': false},
        'blocked_tasks': {'items': [], 'has_more': false},
        'review_tasks': {'items': [], 'has_more': false},
        'pending_approval_count': 0,
        'moment': {
          'blocked': {'items': [], 'has_more': false},
          'mine': {'items': [], 'has_more': false},
          'other': {'items': [], 'has_more': false},
          'all_tasks_has_more': false,
        },
        'needs_action_count': 0,
        'waiting_on_other_count': 0,
        'week_due_count': 0,
        'entries': {
          'needs_me': {'items': [], 'has_more': false},
          'waiting_on_other': {'items': [], 'has_more': false},
          'due_this_week': {'items': [], 'has_more': false},
        },
      };

      final negativeCounts = Map<String, dynamic>.from(base);
      negativeCounts['entry_counts'] = {
        'needs_me': -1,
        'waiting_on_other': 0,
        'due_this_week': 0,
      };
      expect(
        () => HomeResponse.fromJson(negativeCounts),
        throwsFormatException,
      );

      final unknownTimezone = Map<String, dynamic>.from(base);
      unknownTimezone['week'] = {
        'timezone': 'Unknown/Timezone',
        'start': '2026-09-14T00:00:00Z',
        'end': '2026-09-21T00:00:00Z',
      };
      expect(
        () => HomeResponse.fromJson(unknownTimezone),
        throwsFormatException,
      );

      final reversedWeek = Map<String, dynamic>.from(base);
      reversedWeek['week'] = {
        'timezone': 'UTC',
        'start': '2026-09-21T00:00:00Z',
        'end': '2026-09-14T00:00:00Z',
      };
      expect(() => HomeResponse.fromJson(reversedWeek), throwsFormatException);

      final invalidTask = Map<String, dynamic>.from(base);
      invalidTask['entries'] = {
        'needs_me': {
          'items': [
            {
              'approval_request': approvalJson(taskId: 'task-1'),
              'task': taskJson('different-task', 'TODO'),
            },
          ],
          'has_more': false,
        },
        'waiting_on_other': {'items': [], 'has_more': false},
        'due_this_week': {'items': [], 'has_more': false},
      };
      expect(() => HomeResponse.fromJson(invalidTask), throwsFormatException);

      final taskIdWithoutSnapshot = Map<String, dynamic>.from(base);
      taskIdWithoutSnapshot['entries'] = {
        'needs_me': {
          'items': [
            {'approval_request': approvalJson(taskId: 'task-1'), 'task': null},
          ],
          'has_more': false,
        },
        'waiting_on_other': {'items': [], 'has_more': false},
        'due_this_week': {'items': [], 'has_more': false},
      };
      expect(
        () => HomeResponse.fromJson(taskIdWithoutSnapshot),
        throwsFormatException,
      );
    },
  );

  test('rejects non-map canonical fields', () {
    expect(
      () => HomeResponse.fromJson({'entry_counts': []}),
      throwsFormatException,
    );
    expect(() => HomeWeek.fromJson([]), throwsFormatException);
    expect(() => HomeApprovalItem.fromJson([]), throwsFormatException);
  });
}
