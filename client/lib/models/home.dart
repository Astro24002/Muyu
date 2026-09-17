import 'task.dart';
import 'task_approval_request.dart';

class HomeTaskSection {
  HomeTaskSection({required Iterable<TaskItem> items, this.hasMore = false})
    : items = List.unmodifiable(items);

  final List<TaskItem> items;
  final bool hasMore;

  factory HomeTaskSection.fromJson(Object? value) => _fromJson(value);

  static HomeTaskSection _fromJson(
    Object? value, {
    Set<String>? allowedStatuses,
  }) {
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
      final task = TaskItem.fromJson(rawItem.cast<String, dynamic>());
      if (allowedStatuses != null && !allowedStatuses.contains(task.status)) {
        throw FormatException(
          'home task status ${task.status} is invalid for this section',
        );
      }
      items.add(task);
    }
    return HomeTaskSection(items: items, hasMore: hasMore);
  }
}

class HomeApprovalItem {
  HomeApprovalItem({required this.approvalRequest, this.task});

  final TaskApprovalRequest approvalRequest;
  final TaskItem? task;

  factory HomeApprovalItem.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('home approval item must be an object');
    }
    final rawRequest = value['approval_request'];
    final rawTask = value['task'];
    if (rawRequest is! Map) {
      throw const FormatException(
        'home approval item requires approval_request',
      );
    }
    if (rawTask != null && rawTask is! Map) {
      throw const FormatException('home approval item task must be an object');
    }
    final approvalRequest = TaskApprovalRequest.fromJson(
      rawRequest.cast<String, dynamic>(),
    );
    if (approvalRequest.status != 'PENDING') {
      throw const FormatException('home approval item request must be PENDING');
    }
    final task = rawTask == null
        ? null
        : TaskItem.fromJson(rawTask.cast<String, dynamic>());
    if (task == null && approvalRequest.taskId != null) {
      throw const FormatException(
        'home approval item task id requires a task snapshot',
      );
    }
    if (task != null) {
      if (task.deletedAt != null) {
        throw const FormatException(
          'home approval item task must not be deleted',
        );
      }
      if (approvalRequest.taskId == null || approvalRequest.taskId != task.id) {
        throw const FormatException(
          'home approval item task id does not match',
        );
      }
      if (task.workspaceId != approvalRequest.workspaceId) {
        throw const FormatException(
          'home approval item request and task workspace do not match',
        );
      }
      if (!_activeTaskStatuses.contains(task.status)) {
        throw FormatException(
          'home approval item task status ${task.status} is invalid',
        );
      }
    }
    return HomeApprovalItem(approvalRequest: approvalRequest, task: task);
  }

  bool isValidForWorkspace(String workspaceId) {
    if (workspaceId.isEmpty || approvalRequest.workspaceId != workspaceId) {
      return false;
    }
    return task == null || task!.workspaceId == workspaceId;
  }

  static const _activeTaskStatuses = {
    'TODO',
    'IN_PROGRESS',
    'BLOCKED',
    'REVIEW',
    'DONE',
    'CANCELLED',
  };
}

class HomeApprovalSection {
  HomeApprovalSection({
    required Iterable<HomeApprovalItem> items,
    this.hasMore = false,
  }) : items = List.unmodifiable(items);

  final List<HomeApprovalItem> items;
  final bool hasMore;

  factory HomeApprovalSection.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('home approval section must be an object');
    }
    final rawItems = value['items'];
    final hasMore = value['has_more'];
    if (rawItems is! List || hasMore is! bool) {
      throw const FormatException('home approval section has invalid fields');
    }
    final items = <HomeApprovalItem>[];
    for (final rawItem in rawItems) {
      items.add(HomeApprovalItem.fromJson(rawItem));
    }
    return HomeApprovalSection(items: items, hasMore: hasMore);
  }
}

class HomeWeek {
  const HomeWeek({
    required this.timezone,
    required this.start,
    required this.end,
  });

  final String timezone;
  final DateTime start;
  final DateTime end;

  factory HomeWeek.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('home week must be an object');
    }
    final timezone = value['timezone'];
    final rawStart = value['start'];
    final rawEnd = value['end'];
    if (timezone is! String ||
        timezone != 'UTC' ||
        rawStart is! String ||
        rawEnd is! String) {
      throw const FormatException('home week must use UTC boundaries');
    }
    final start = DateTime.tryParse(rawStart);
    final end = DateTime.tryParse(rawEnd);
    if (start == null ||
        end == null ||
        !start.isUtc ||
        !end.isUtc ||
        !end.isAfter(start)) {
      throw const FormatException('home week has invalid boundaries');
    }
    return HomeWeek(timezone: timezone, start: start, end: end);
  }
}

class HomeEntryCounts {
  HomeEntryCounts({
    required this.needsMe,
    required this.waitingOnOther,
    required this.dueThisWeek,
  }) {
    if (needsMe < 0 || waitingOnOther < 0 || dueThisWeek < 0) {
      throw const FormatException('home entry counts must be non-negative');
    }
  }

  final int needsMe;
  final int waitingOnOther;
  final int dueThisWeek;

  factory HomeEntryCounts.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('home entry counts must be an object');
    }
    final needsMe = value['needs_me'];
    final waitingOnOther = value['waiting_on_other'];
    final dueThisWeek = value['due_this_week'];
    if (needsMe is! int || waitingOnOther is! int || dueThisWeek is! int) {
      throw const FormatException('home entry counts have invalid fields');
    }
    return HomeEntryCounts(
      needsMe: needsMe,
      waitingOnOther: waitingOnOther,
      dueThisWeek: dueThisWeek,
    );
  }
}

class HomeEntries {
  HomeEntries({
    HomeApprovalSection? needsMe,
    HomeApprovalSection? waitingOnOther,
    HomeTaskSection? dueThisWeek,
  }) : needsMe = needsMe ?? HomeApprovalSection(items: const []),
       waitingOnOther = waitingOnOther ?? HomeApprovalSection(items: const []),
       dueThisWeek = dueThisWeek ?? HomeTaskSection(items: const []);

  final HomeApprovalSection needsMe;
  final HomeApprovalSection waitingOnOther;
  final HomeTaskSection dueThisWeek;

  factory HomeEntries.fromJson(Object? value) {
    if (value is! Map ||
        !value.containsKey('needs_me') ||
        !value.containsKey('waiting_on_other') ||
        !value.containsKey('due_this_week')) {
      throw const FormatException('home entries have invalid fields');
    }
    return HomeEntries(
      needsMe: HomeApprovalSection.fromJson(value['needs_me']),
      waitingOnOther: HomeApprovalSection.fromJson(value['waiting_on_other']),
      dueThisWeek: HomeTaskSection._fromJson(
        value['due_this_week'],
        allowedStatuses: _dueStatuses,
      ),
    );
  }

  static const _dueStatuses = {'TODO', 'IN_PROGRESS', 'BLOCKED', 'REVIEW'};
}

class MomentProjection {
  MomentProjection({
    HomeTaskSection? blocked,
    HomeTaskSection? mine,
    HomeTaskSection? other,
    HomeTaskSection? blockedTasks,
    HomeTaskSection? myTasks,
    HomeTaskSection? otherTasks,
    this.allTasksHasMore = false,
    bool? hasCanonicalSections,
  }) : blocked = blocked ?? blockedTasks ?? HomeTaskSection(items: const []),
       mine = mine ?? myTasks ?? HomeTaskSection(items: const []),
       other = other ?? otherTasks ?? HomeTaskSection(items: const []),
       hasCanonicalSections =
           hasCanonicalSections ??
           blocked != null || mine != null || other != null;

  final HomeTaskSection blocked;
  final HomeTaskSection mine;
  final HomeTaskSection other;
  final bool allTasksHasMore;
  final bool hasCanonicalSections;

  // Deprecated names retained for existing Android callers.
  HomeTaskSection get blockedTasks => blocked;
  HomeTaskSection get myTasks => mine;
  HomeTaskSection get otherTasks => other;

  factory MomentProjection.fromJson(
    Object? value, {
    bool requireCanonical = false,
  }) {
    if (value is! Map) {
      throw const FormatException('home moment projection must be an object');
    }
    final hasCanonical =
        value.containsKey('blocked') ||
        value.containsKey('mine') ||
        value.containsKey('other');
    final blocked = value.containsKey('blocked')
        ? HomeTaskSection._fromJson(
            value['blocked'],
            allowedStatuses: const {'BLOCKED'},
          )
        : _legacySection(value, 'blocked_tasks');
    final mine = value.containsKey('mine')
        ? HomeTaskSection._fromJson(
            value['mine'],
            allowedStatuses: const {'TODO', 'IN_PROGRESS', 'REVIEW'},
          )
        : _legacySection(value, 'my_tasks');
    final other = value.containsKey('other')
        ? HomeTaskSection._fromJson(
            value['other'],
            allowedStatuses: const {'TODO', 'IN_PROGRESS', 'REVIEW'},
          )
        : _legacySection(value, 'other_tasks');
    return MomentProjection(
      blocked: blocked,
      mine: mine,
      other: other,
      allTasksHasMore: _boolField(value, 'all_tasks_has_more'),
      hasCanonicalSections: hasCanonical,
    );
  }

  static HomeTaskSection _legacySection(
    Map<Object?, Object?> value,
    String key,
  ) {
    if (!value.containsKey(key)) return HomeTaskSection(items: const []);
    return HomeTaskSection.fromJson(value[key]);
  }

  static bool _boolField(Map<Object?, Object?> value, String key) {
    final raw = value[key];
    if (raw == null) return false;
    if (raw is! bool) {
      throw FormatException('home moment $key must be a boolean');
    }
    return raw;
  }

  Iterable<TaskItem> get allTasks sync* {
    yield* blocked.items;
    yield* mine.items;
    yield* other.items;
  }
}

class HomeResponse {
  HomeResponse({
    required this.currentTasks,
    required this.blockedTasks,
    required this.reviewTasks,
    required this.pendingApprovalCount,
    MomentProjection? moment,
    int? needsActionCount,
    int? waitingOnOtherCount,
    int? weekDueCount,
    bool? hasMomentProjection,
    this.viewerUserId,
    this.asOf,
    this.week,
    HomeEntryCounts? entryCounts,
    HomeEntries? entries,
  }) {
    if (pendingApprovalCount < 0) {
      throw const FormatException(
        'home pending approval count must be non-negative',
      );
    }
    if (viewerUserId != null && viewerUserId!.trim().isEmpty) {
      throw const FormatException('home viewer user id must not be empty');
    }
    this.moment = moment ?? MomentProjection();
    this.needsActionCount = needsActionCount ?? pendingApprovalCount;
    this.waitingOnOtherCount = waitingOnOtherCount ?? 0;
    this.weekDueCount = weekDueCount ?? 0;
    this.hasMomentProjection = hasMomentProjection ?? moment != null;
    this.entryCounts =
        entryCounts ??
        HomeEntryCounts(
          needsMe: this.needsActionCount,
          waitingOnOther: this.waitingOnOtherCount,
          dueThisWeek: this.weekDueCount,
        );
    this.entries = entries ?? HomeEntries();
    if (this.needsActionCount < 0 ||
        this.waitingOnOtherCount < 0 ||
        this.weekDueCount < 0) {
      throw const FormatException('home moment counts must be non-negative');
    }
  }

  final HomeTaskSection currentTasks;
  final HomeTaskSection blockedTasks;
  final HomeTaskSection reviewTasks;
  final int pendingApprovalCount;
  late final MomentProjection moment;
  late final int needsActionCount;
  late final int waitingOnOtherCount;
  late final int weekDueCount;
  late final bool hasMomentProjection;
  late final String? viewerUserId;
  late final DateTime? asOf;
  late final HomeWeek? week;
  late final HomeEntryCounts entryCounts;
  late final HomeEntries entries;

  factory HomeResponse.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('home response must be an object');
    }
    final hasLegacy =
        value.containsKey('current_tasks') &&
        value.containsKey('blocked_tasks') &&
        value.containsKey('review_tasks') &&
        value.containsKey('pending_approval_count');
    final hasCanonical =
        value.containsKey('viewer_user_id') ||
        value.containsKey('as_of') ||
        value.containsKey('week') ||
        value.containsKey('entry_counts') ||
        value.containsKey('entries') ||
        _hasCanonicalMoment(value['moment']);
    if (!hasLegacy && !hasCanonical) {
      throw const FormatException('home response is missing its fields');
    }

    final rawCounts = value['entry_counts'];
    final entryCounts = rawCounts == null
        ? null
        : HomeEntryCounts.fromJson(rawCounts);
    final rawPending = value['pending_approval_count'];
    if (rawPending != null && rawPending is! int) {
      throw const FormatException(
        'home pending approval count must be an integer',
      );
    }
    final pending = rawPending as int? ?? entryCounts?.needsMe ?? 0;
    final currentTasks = value.containsKey('current_tasks')
        ? HomeTaskSection.fromJson(value['current_tasks'])
        : HomeTaskSection(items: const []);
    final blockedTasks = value.containsKey('blocked_tasks')
        ? HomeTaskSection.fromJson(value['blocked_tasks'])
        : HomeTaskSection(items: const []);
    final reviewTasks = value.containsKey('review_tasks')
        ? HomeTaskSection.fromJson(value['review_tasks'])
        : HomeTaskSection(items: const []);
    final rawMoment = value['moment'];
    final moment = rawMoment == null
        ? null
        : MomentProjection.fromJson(rawMoment);
    final rawAsOf = value['as_of'];
    if (rawAsOf != null && rawAsOf is! String) {
      throw const FormatException('home as_of must be an ISO date');
    }
    final asOf = rawAsOf == null ? null : DateTime.tryParse(rawAsOf);
    if (rawAsOf != null && asOf == null) {
      throw const FormatException('home as_of must be an ISO date');
    }
    final rawViewerUserId = value['viewer_user_id'];
    if (rawViewerUserId != null && rawViewerUserId is! String) {
      throw const FormatException('home viewer user id must be a string');
    }
    final rawWeek = value['week'];
    final week = rawWeek == null ? null : HomeWeek.fromJson(rawWeek);
    final rawEntries = value['entries'];
    final entries = rawEntries == null
        ? null
        : HomeEntries.fromJson(rawEntries);
    return HomeResponse(
      currentTasks: currentTasks,
      blockedTasks: blockedTasks,
      reviewTasks: reviewTasks,
      pendingApprovalCount: pending,
      moment: moment,
      needsActionCount: _count(value, 'needs_action_count', pending),
      waitingOnOtherCount: _count(
        value,
        'waiting_on_other_count',
        entryCounts?.waitingOnOther ?? 0,
      ),
      weekDueCount: _count(
        value,
        'week_due_count',
        entryCounts?.dueThisWeek ?? 0,
      ),
      hasMomentProjection: rawMoment != null,
      viewerUserId: rawViewerUserId as String?,
      asOf: asOf,
      week: week,
      entryCounts: entryCounts,
      entries: entries,
    );
  }

  bool isValidForWorkspace(String workspaceId) {
    if (workspaceId.isEmpty) return false;
    final taskSections = [
      currentTasks,
      blockedTasks,
      reviewTasks,
      moment.blocked,
      moment.mine,
      moment.other,
      entries.dueThisWeek,
    ];
    if (!taskSections.every(
      (section) =>
          section.items.every((task) => task.workspaceId == workspaceId),
    )) {
      return false;
    }
    return entries.needsMe.items.every(
          (item) => item.isValidForWorkspace(workspaceId),
        ) &&
        entries.waitingOnOther.items.every(
          (item) => item.isValidForWorkspace(workspaceId),
        );
  }

  Iterable<TaskItem> get allTasks sync* {
    final seen = <String>{};
    final tasks = <TaskItem>[
      ...currentTasks.items,
      ...blockedTasks.items,
      ...reviewTasks.items,
      ...moment.allTasks,
      ...entries.dueThisWeek.items,
    ];
    for (final item in entries.needsMe.items) {
      if (item.task != null) tasks.add(item.task!);
    }
    for (final item in entries.waitingOnOther.items) {
      if (item.task != null) tasks.add(item.task!);
    }
    for (final task in tasks) {
      if (seen.add(task.id)) yield task;
    }
  }

  static bool _hasCanonicalMoment(Object? value) {
    if (value is! Map) return false;
    return value.containsKey('blocked') ||
        value.containsKey('mine') ||
        value.containsKey('other');
  }

  static int _count(Map<Object?, Object?> value, String key, int fallback) {
    final raw = value[key];
    if (raw == null) return fallback;
    if (raw is! int) {
      throw FormatException('home $key must be an integer');
    }
    if (raw < 0) {
      throw FormatException('home $key must be non-negative');
    }
    return raw;
  }
}

// Contract terminology aliases. The concrete classes above keep the public
// API readable while allowing callers to use either naming convention.
typedef HomeEntryItem = HomeApprovalItem;
typedef HomeEntryCount = HomeEntryCounts;
typedef HomeEntryProjection = HomeEntries;
typedef MomentSection = HomeTaskSection;
