import 'package:flutter/material.dart';

import '../life/life_controller.dart';
import '../life/life_repository.dart';
import '../theme/muyu_theme.dart';

class CheckinsScreen extends StatefulWidget {
  const CheckinsScreen({
    super.key,
    required this.controller,
    required this.viewerId,
    required this.canWrite,
    this.onOpenTask,
  });
  final LifeController controller;
  final String? viewerId;
  final bool canWrite;
  final ValueChanged<String>? onOpenTask;

  @override
  State<CheckinsScreen> createState() => _CheckinsScreenState();
}

class _CheckinsScreenState extends State<CheckinsScreen> {
  bool _anniversaries = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadCheckins();
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return RefreshIndicator(
        onRefresh: controller.loadCheckins,
        child: ListView(
          key: const PageStorageKey('checkins-list'),
          padding: const EdgeInsets.fromLTRB(
            MuyuSpacing.lg,
            MuyuSpacing.md,
            MuyuSpacing.lg,
            MuyuSpacing.xxl,
          ),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('日常打卡')),
                ButtonSegment(value: true, label: Text('纪念日')),
              ],
              selected: {_anniversaries},
              onSelectionChanged: (values) =>
                  setState(() => _anniversaries = values.first),
            ),
            if (controller.loadingCheckins) const LinearProgressIndicator(),
            if (controller.checkinsError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: MuyuSpacing.sm),
                child: Text(
                  controller.checkinsError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: MuyuSpacing.lg),
            if (_anniversaries) ...[
              if (controller.anniversaries.isEmpty &&
                  !controller.loadingCheckins)
                const Center(child: Text('暂无纪念日')),
              for (final item in controller.anniversaries) ...[
                ListTile(
                  key: Key('anniversary-${item.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.title),
                  subtitle: Text(
                    '${_kind(item.kind)} · ${item.nextOccurrence.year}-${item.nextOccurrence.month.toString().padLeft(2, '0')}-${item.nextOccurrence.day.toString().padLeft(2, '0')} · 提前 ${item.prepareDays} 天',
                  ),
                  trailing: Text(
                    item.daysUntil == 0 ? '就是今天' : '还有 ${item.daysUntil} 天',
                  ),
                  onTap: () => _openAnniversary(item),
                ),
                const Divider(height: 1),
              ],
              if (widget.canWrite) ...[
                const SizedBox(height: MuyuSpacing.xl),
                FilledButton.icon(
                  onPressed: controller.writing
                      ? null
                      : () => _openAnniversary(null),
                  icon: const Icon(Icons.add),
                  label: const Text('新增纪念日'),
                ),
              ],
            ] else ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'mine', label: Text('我的')),
                  ButtonSegment(value: 'other', label: Text('TA 的')),
                  ButtonSegment(value: 'all', label: Text('全部')),
                ],
                selected: {controller.habitOwner},
                onSelectionChanged: controller.loadingCheckins
                    ? null
                    : (values) => controller.changeHabitOwner(values.first),
              ),
              const SizedBox(height: MuyuSpacing.md),
              if (controller.habits.isEmpty && !controller.loadingCheckins)
                const Center(child: Text('暂无打卡项目')),
              for (final habit in controller.habits) ...[
                ListTile(
                  key: Key('habit-${habit.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(habit.title),
                  subtitle: Text(
                    '${_frequency(habit.frequency)} · ${habit.status == 'PAUSED'
                        ? '已暂停'
                        : habit.checkedIn
                        ? '本期已完成'
                        : '本期未完成'}',
                  ),
                  trailing:
                      widget.canWrite &&
                          habit.ownerId == widget.viewerId &&
                          habit.status == 'ACTIVE'
                      ? IconButton(
                          tooltip: habit.checkedIn ? '撤销本期打卡' : '打卡',
                          icon: Icon(
                            habit.checkedIn
                                ? Icons.undo
                                : Icons.check_circle_outline,
                          ),
                          onPressed: controller.writing
                              ? null
                              : () => _habitAction(
                                  habit,
                                  habit.checkedIn ? 'undo' : 'checkin',
                                ),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () => _openHabit(habit),
                ),
                const Divider(height: 1),
              ],
              if (widget.canWrite) ...[
                const SizedBox(height: MuyuSpacing.xl),
                FilledButton.icon(
                  onPressed: controller.writing ? null : () => _openHabit(null),
                  icon: const Icon(Icons.add),
                  label: const Text('新增习惯'),
                ),
              ],
            ],
          ],
        ),
      );
    },
  );

  Future<void> _habitAction(HabitItem habit, String action) async {
    final success = await widget.controller.writeCheckins((requestId) async {
      await widget.controller.repository.habitAction(
        habit.id,
        action,
        habit.version,
        requestId,
      );
    });
    if (!success && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('操作失败，请刷新后重试')));
    }
  }

  Future<void> _openHabit(HabitItem? item) => showDialog<void>(
    context: context,
    builder: (context) => _HabitDialog(
      controller: widget.controller,
      item: item,
      canWrite:
          widget.canWrite && (item == null || item.ownerId == widget.viewerId),
    ),
  );

  Future<void> _openAnniversary(AnniversaryItem? item) => showDialog<void>(
    context: context,
    builder: (context) => _AnniversaryDialog(
      controller: widget.controller,
      item: item,
      canWrite: widget.canWrite,
      onOpenTask: widget.onOpenTask,
    ),
  );

  static String _frequency(String value) => switch (value) {
    'DAILY' => '每日',
    'WEEKLY' => '每周',
    _ => '每月',
  };
  static String _kind(String value) => switch (value) {
    'BIRTHDAY' => '生日',
    'IMPORTANT_DAY' => '重要日子',
    _ => '纪念日',
  };
}

class _HabitDialog extends StatefulWidget {
  const _HabitDialog({
    required this.controller,
    required this.item,
    required this.canWrite,
  });
  final LifeController controller;
  final HabitItem? item;
  final bool canWrite;

  @override
  State<_HabitDialog> createState() => _HabitDialogState();
}

class _HabitDialogState extends State<_HabitDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.item?.title,
  );
  late String _frequency = widget.item?.frequency ?? 'DAILY';
  late DateTime _start = widget.item?.startDate ?? DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.item == null ? '新增习惯' : '打卡项目'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            maxLength: 120,
            enabled: widget.canWrite && !_busy,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _frequency,
            decoration: const InputDecoration(labelText: '频率'),
            items: const [
              DropdownMenuItem(value: 'DAILY', child: Text('每日')),
              DropdownMenuItem(value: 'WEEKLY', child: Text('每周')),
              DropdownMenuItem(value: 'MONTHLY', child: Text('每月')),
            ],
            onChanged: !widget.canWrite || _busy
                ? null
                : (value) => setState(() => _frequency = value!),
          ),
          TextButton.icon(
            onPressed: !widget.canWrite || _busy ? null : _pickDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text('开始 ${_day(_start)}'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      if (widget.item != null && widget.canWrite) ...[
        TextButton(
          onPressed: _busy
              ? null
              : () => _action(
                  widget.item!.status == 'PAUSED' ? 'resume' : 'pause',
                ),
          child: Text(widget.item!.status == 'PAUSED' ? '恢复' : '暂停'),
        ),
        TextButton(onPressed: _busy ? null : _delete, child: const Text('删除')),
      ],
      if (widget.canWrite)
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(widget.item == null ? '新增' : '保存'),
        ),
    ],
  );

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) setState(() => _start = date);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '请填写名称');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final changes = <String, Object?>{
      'title': _title.text.trim(),
      'frequency': _frequency,
      'start_date': _day(_start),
    };
    final success = await widget.controller.writeCheckins((requestId) async {
      if (widget.item == null) {
        await widget.controller.repository.createHabit({
          'request_id': requestId,
          ...changes,
        });
      } else {
        await widget.controller.repository.updateHabit(widget.item!.id, {
          'request_id': requestId,
          'expected_version': widget.item!.version,
          'changes': changes,
        });
      }
    });
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = widget.controller.checkinsError;
      });
    }
  }

  Future<void> _action(String action) async {
    setState(() => _busy = true);
    final success = await widget.controller.writeCheckins((requestId) async {
      await widget.controller.repository.habitAction(
        widget.item!.id,
        action,
        widget.item!.version,
        requestId,
      );
    });
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = widget.controller.checkinsError;
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除习惯？'),
        content: Text('删除“${widget.item!.title}”及关联打卡记录？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final success = await widget.controller.writeCheckins(
      (requestId) => widget.controller.repository.deleteHabit(
        widget.item!.id,
        widget.item!.version,
        requestId,
      ),
    );
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = widget.controller.checkinsError;
      });
    }
  }
}

class _AnniversaryDialog extends StatefulWidget {
  const _AnniversaryDialog({
    required this.controller,
    required this.item,
    required this.canWrite,
    this.onOpenTask,
  });
  final LifeController controller;
  final AnniversaryItem? item;
  final bool canWrite;
  final ValueChanged<String>? onOpenTask;

  @override
  State<_AnniversaryDialog> createState() => _AnniversaryDialogState();
}

class _AnniversaryDialogState extends State<_AnniversaryDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.item?.title,
  );
  late DateTime _date = widget.item?.anchorDate ?? DateTime.now();
  late String _kind = widget.item?.kind ?? 'ANNIVERSARY';
  late int _prepareDays = widget.item?.prepareDays ?? 7;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.item == null ? '新增纪念日' : '纪念日'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            maxLength: 160,
            enabled: widget.canWrite && !_busy,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: '类型'),
            items: const [
              DropdownMenuItem(value: 'ANNIVERSARY', child: Text('纪念日')),
              DropdownMenuItem(value: 'BIRTHDAY', child: Text('生日')),
              DropdownMenuItem(value: 'IMPORTANT_DAY', child: Text('重要日子')),
            ],
            onChanged: !widget.canWrite || _busy
                ? null
                : (value) => setState(() => _kind = value!),
          ),
          TextButton.icon(
            onPressed: !widget.canWrite || _busy ? null : _pickDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text('原始日期 ${_day(_date)}'),
          ),
          DropdownButtonFormField<int>(
            initialValue: _prepareDays,
            decoration: const InputDecoration(labelText: '提前准备'),
            items: [
              for (final days in [0, 1, 3, 7, 14, 30])
                DropdownMenuItem(value: days, child: Text('$days 天')),
            ],
            onChanged: !widget.canWrite || _busy
                ? null
                : (value) => setState(() => _prepareDays = value!),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
      if (widget.item != null && widget.canWrite) ...[
        TextButton(onPressed: _busy ? null : _delete, child: const Text('删除')),
        TextButton(
          onPressed: _busy ? null : _prepare,
          child: const Text('生成准备事项'),
        ),
      ],
      if (widget.canWrite)
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(widget.item == null ? '新增' : '保存'),
        ),
    ],
  );

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) setState(() => _date = date);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '请填写名称');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final changes = <String, Object?>{
      'title': _title.text.trim(),
      'kind': _kind,
      'anchor_date': _day(_date),
      'prepare_days': _prepareDays,
    };
    final success = await widget.controller.writeCheckins((requestId) async {
      if (widget.item == null) {
        await widget.controller.repository.createAnniversary({
          'request_id': requestId,
          ...changes,
        });
      } else {
        await widget.controller.repository.updateAnniversary(widget.item!.id, {
          'request_id': requestId,
          'expected_version': widget.item!.version,
          'changes': changes,
        });
      }
    });
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = widget.controller.checkinsError;
      });
    }
  }

  Future<void> _prepare() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? taskId;
    final success = await widget.controller.writeCheckins((requestId) async {
      taskId = await widget.controller.repository.prepareAnniversary(
        widget.item!.id,
        requestId,
      );
    });
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
      if (taskId != null) widget.onOpenTask?.call(taskId!);
    } else {
      setState(() {
        _busy = false;
        _error = widget.controller.checkinsError;
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除纪念日？'),
        content: Text('删除“${widget.item!.title}”不会删除已生成的准备事项。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final success = await widget.controller.writeCheckins(
      (requestId) => widget.controller.repository.deleteAnniversary(
        widget.item!.id,
        widget.item!.version,
        requestId,
      ),
    );
    if (!mounted) return;
    if (success) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = widget.controller.checkinsError;
      });
    }
  }
}

String _day(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
