import '../core/api_client.dart';
import '../models/task.dart';
import '../models/home.dart';

class HomeEntryPage {
  HomeEntryPage({
    required this.count,
    required Iterable<TaskItem> tasks,
    Iterable<HomeApprovalItem> approvals = const [],
    required this.hasMore,
    required this.nextCursor,
  }) : tasks = List.unmodifiable(tasks),
       approvals = List.unmodifiable(approvals);

  final int count;
  final List<TaskItem> tasks;
  final List<HomeApprovalItem> approvals;
  final bool hasMore;
  final String? nextCursor;
}

class HomeEntryRepository {
  const HomeEntryRepository(this._api);

  final ApiClient _api;

  Future<HomeEntryPage> load({
    required String entry,
    String? afterCursor,
  }) async {
    if (!const {
      'needs_me',
      'waiting_on_other',
      'due_this_week',
      'due_soon',
    }.contains(entry)) {
      throw ArgumentError.value(entry, 'entry');
    }
    final path = Uri(
      path: '/api/v1/home/entries/$entry',
      queryParameters: {'limit': '50', 'after_cursor': ?afterCursor},
    ).toString();
    final value = await _api.request('GET', path, authenticated: true);
    if (value is! Map) {
      throw const FormatException('home entry page must be an object');
    }
    final count = value['count'];
    final items = value['items'];
    final hasMore = value['has_more'];
    final cursor = value['next_cursor'];
    if (count is! int ||
        count < 0 ||
        items is! List ||
        hasMore is! bool ||
        (cursor != null && cursor is! String) ||
        (hasMore && (cursor == null || cursor.isEmpty))) {
      throw const FormatException('home entry page has invalid fields');
    }
    final tasks = <TaskItem>[];
    final approvals = <HomeApprovalItem>[];
    for (final raw in items) {
      if (raw is! Map) {
        throw const FormatException('home entry item must be an object');
      }
      final item = raw.cast<String, dynamic>();
      if (entry != 'due_this_week' && entry != 'due_soon') {
        final approval = HomeApprovalItem.fromJson(item);
        approvals.add(approval);
        if (approval.task != null) tasks.add(approval.task!);
        continue;
      }
      final task = item['task'] ?? item;
      if (task is! Map) {
        throw const FormatException('home entry task must be an object');
      }
      tasks.add(TaskItem.fromJson(task.cast<String, dynamic>()));
    }
    return HomeEntryPage(
      count: count,
      tasks: tasks,
      approvals: approvals,
      hasMore: hasMore,
      nextCursor: cursor,
    );
  }
}
