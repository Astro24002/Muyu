import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/task.dart';
import '../task/task_query_repository.dart';
import '../tasks/task_status.dart';
import '../theme/muyu_theme.dart';

class AllTasksScreen extends StatefulWidget {
  const AllTasksScreen({
    super.key,
    required this.repository,
    required this.onTaskTap,
    this.members = const [],
  });

  final TaskQueryRepository repository;
  final ValueChanged<TaskItem> onTaskTap;
  final List<Map<String, dynamic>> members;

  @override
  State<AllTasksScreen> createState() => _AllTasksScreenState();
}

class _AllTasksScreenState extends State<AllTasksScreen> {
  static const filters = <String, String>{
    'open': '未完成',
    'all': '全部',
    'blocked': '阻塞',
    'review': '验收',
    'handoff_pending': '接棒',
    'done': '完成',
    'cancelled': '已取消',
  };

  final _search = TextEditingController();
  Timer? _debounce;
  List<TaskItem> _items = const [];
  String _status = 'open';
  String? _cursor;
  String? _error;
  bool _hasMore = false;
  bool _loading = false;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _requestVersion++;
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() => _load(more: false);

  Future<void> _load({required bool more}) async {
    if (more && (_loading || !_hasMore || _cursor == null || _error != null)) {
      return;
    }
    final version = ++_requestVersion;
    final after = more ? _cursor : null;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.repository.query(
        text: _search.text,
        status: _status,
        after: after,
      );
      if (!mounted || version != _requestVersion) return;
      final seen = <String>{
        if (more)
          for (final task in _items) task.id,
      };
      setState(() {
        _items = [
          if (more) ..._items,
          for (final task in page.items)
            if (seen.add(task.id)) task,
        ];
        _hasMore = page.hasMore;
        _cursor = page.nextCursor;
      });
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(
        () => _error = error is ApiException ? error.message : '加载失败，请重试',
      );
    } finally {
      if (mounted && version == _requestVersion) {
        setState(() => _loading = false);
      }
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _refresh();
    });
  }

  String _ownerName(String id) {
    for (final member in widget.members) {
      if (member['user_id'] != id) continue;
      final name = member['display_name'];
      if (name is String && name.trim().isNotEmpty) return name.trim();
    }
    return '协作成员';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('全部事情'),
        actions: [
          IconButton(
            key: const Key('all-tasks-refresh'),
            tooltip: '刷新',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MuyuSpacing.lg,
              MuyuSpacing.md,
              MuyuSpacing.lg,
              MuyuSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('all-tasks-search'),
                    controller: _search,
                    onChanged: _onSearch,
                    maxLength: 200,
                    buildCounter: (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                    decoration: const InputDecoration(
                      labelText: '搜索名称、分类、负责人、下一步',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ),
                const SizedBox(width: MuyuSpacing.sm),
                DropdownButton<String>(
                  key: const Key('all-tasks-status'),
                  value: _status,
                  items: [
                    for (final entry in filters.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null || value == _status) return;
                    setState(() => _status = value);
                    _refresh();
                  },
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MuyuSpacing.lg),
              child: Text(
                '${_error!}${_items.isEmpty ? '' : ' · 显示上次加载结果'}',
                key: const Key('all-tasks-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                key: const Key('all-tasks-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_items.isEmpty && !_loading)
                    const Padding(
                      padding: EdgeInsets.all(MuyuSpacing.xxl),
                      child: Center(child: Text('没有符合条件的事情')),
                    ),
                  for (final task in _items)
                    ListTile(
                      key: Key('all-tasks-task-${task.id}'),
                      title: Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${taskStatusLabel(task.status)} · ${_ownerName(task.currentHandlerId)}'
                        '${task.labels.isEmpty ? '' : ' · ${task.labels.first}'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => widget.onTaskTap(task),
                    ),
                  if (_hasMore)
                    TextButton(
                      key: const Key('all-tasks-load-more'),
                      onPressed: _loading || _error != null
                          ? null
                          : () => _load(more: true),
                      child: const Text('加载更多'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
