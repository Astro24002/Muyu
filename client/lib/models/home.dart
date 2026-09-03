import 'task.dart';

class HomeTaskSection {
  HomeTaskSection({required Iterable<TaskItem> items, this.hasMore = false})
    : items = List.unmodifiable(items);

  final List<TaskItem> items;
  final bool hasMore;

  factory HomeTaskSection.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('home task section must be an object');
    }
    final rawItems = value['items'];
    final hasMore = value['has_more'];
    if (rawItems is! List || hasMore is! bool) {
      throw const FormatException('home task section has invalid fields');
    }
    final items = <TaskItem>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) {
        throw const FormatException('home task item must be an object');
      }
      items.add(TaskItem.fromJson(rawItem.cast<String, dynamic>()));
    }
    return HomeTaskSection(items: items, hasMore: hasMore);
  }
}

class HomeResponse {
  HomeResponse({
    required this.currentTasks,
    required this.blockedTasks,
    required this.reviewTasks,
    required this.pendingApprovalCount,
  }) {
    if (pendingApprovalCount < 0) {
      throw const FormatException(
        'home pending approval count must be non-negative',
      );
    }
  }

  final HomeTaskSection currentTasks;
  final HomeTaskSection blockedTasks;
  final HomeTaskSection reviewTasks;
  final int pendingApprovalCount;

  factory HomeResponse.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('home response must be an object');
    }
    final pending = value['pending_approval_count'];
    if (pending is! int) {
      throw const FormatException(
        'home pending approval count must be an integer',
      );
    }
    return HomeResponse(
      currentTasks: HomeTaskSection.fromJson(value['current_tasks']),
      blockedTasks: HomeTaskSection.fromJson(value['blocked_tasks']),
      reviewTasks: HomeTaskSection.fromJson(value['review_tasks']),
      pendingApprovalCount: pending,
    );
  }

  bool isValidForWorkspace(String workspaceId) {
    if (workspaceId.isEmpty) return false;
    return [currentTasks, blockedTasks, reviewTasks].every(
      (section) =>
          section.items.every((task) => task.workspaceId == workspaceId),
    );
  }

  Iterable<TaskItem> get allTasks sync* {
    yield* currentTasks.items;
    yield* blockedTasks.items;
    yield* reviewTasks.items;
  }
}
