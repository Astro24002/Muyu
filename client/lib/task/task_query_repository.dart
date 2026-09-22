import '../core/api_client.dart';
import '../models/task.dart';

class TaskQueryPage {
  TaskQueryPage({
    required Iterable<TaskItem> items,
    required this.hasMore,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<TaskItem> items;
  final bool hasMore;
  final String? nextCursor;
}

class TaskQueryRepository {
  const TaskQueryRepository(this._api);

  final ApiClient _api;

  Future<TaskQueryPage> query({
    String text = '',
    String status = 'open',
    String? after,
  }) async {
    final path = Uri(
      path: '/api/v1/tasks',
      queryParameters: {
        'status': status,
        'limit': '50',
        if (text.trim().isNotEmpty) 'q': text.trim(),
        'after': ?after,
      },
    ).toString();
    final response = await _api.request('GET', path, authenticated: true);
    if (response is! Map) {
      throw const FormatException('task query response must be an object');
    }
    final items = response['items'];
    final hasMore = response['has_more'];
    final cursor = response['next_cursor'];
    if (items is! List ||
        hasMore is! bool ||
        (cursor != null && cursor is! String) ||
        (hasMore && (cursor == null || cursor.isEmpty))) {
      throw const FormatException('task query response has invalid fields');
    }
    return TaskQueryPage(
      items: items.map((item) {
        if (item is! Map) {
          throw const FormatException('task query item must be an object');
        }
        return TaskItem.fromJson(item.cast<String, dynamic>());
      }),
      hasMore: hasMore,
      nextCursor: cursor,
    );
  }
}
