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
    expect(home.isValidForWorkspace('workspace-1'), isTrue);
    expect(home.isValidForWorkspace('workspace-other'), isFalse);
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
}
