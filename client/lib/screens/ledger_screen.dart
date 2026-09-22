import 'package:flutter/material.dart';

import '../life/life_controller.dart';
import '../life/life_repository.dart';
import '../theme/muyu_theme.dart';

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({
    super.key,
    required this.controller,
    required this.members,
    required this.viewerId,
    required this.canWrite,
  });
  final LifeController controller;
  final List<Map<String, dynamic>> members;
  final String? viewerId;
  final bool canWrite;

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadLedger();
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final summary = controller.summary;
      final entries = controller.entries
          .where((item) => _filter == 'ALL' || item.type == _filter)
          .toList();
      return Stack(
        children: [
          RefreshIndicator(
            onRefresh: controller.loadLedger,
            child: ListView(
              key: const PageStorageKey('ledger-list'),
              padding: const EdgeInsets.fromLTRB(
                MuyuSpacing.lg,
                MuyuSpacing.md,
                MuyuSpacing.lg,
                MuyuSpacing.xxl,
              ),
              children: [
                Text(
                  '把共同的日常，一笔一笔记下来。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: MuyuSpacing.xl),
                _monthlySummary(context, controller, summary),
                if (controller.loadingLedger) const LinearProgressIndicator(),
                if (controller.ledgerError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: MuyuSpacing.sm,
                    ),
                    child: Text(
                      controller.ledgerError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: MuyuSpacing.xl),
                _categoryDistribution(context, controller, summary),
                const SizedBox(height: MuyuSpacing.xl),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '每一笔日常',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      '${entries.length} 笔记录',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: MuyuSpacing.md),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ALL', label: Text('全部')),
                    ButtonSegment(value: 'EXPENSE', label: Text('支出')),
                    ButtonSegment(value: 'INCOME', label: Text('收入')),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (value) =>
                      setState(() => _filter = value.first),
                ),
                const SizedBox(height: MuyuSpacing.md),
                if (entries.isEmpty && !controller.loadingLedger)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: MuyuSpacing.xl),
                    child: Center(child: Text('本月暂无账目')),
                  ),
                for (var index = 0; index < entries.length; index++) ...[
                  if (index == 0 ||
                      entries[index].date != entries[index - 1].date)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: MuyuSpacing.lg,
                        bottom: MuyuSpacing.sm,
                      ),
                      child: Text(
                        '${entries[index].date.month}月${entries[index].date.day}日',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    child: ListTile(
                      key: Key('ledger-entry-${entries[index].id}'),
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      title: Text(
                        entries[index].title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${entries[index].category} · ${entries[index].payerName}${entries[index].type == 'EXPENSE' ? ' 付款' : ' 收款'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        '${entries[index].type == 'EXPENSE' ? '-' : '+'}¥${entries[index].formattedAmount}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      onTap: () => _openEntry(entries[index]),
                    ),
                  ),
                  const SizedBox(height: MuyuSpacing.sm),
                ],
              ],
            ),
          ),
          if (widget.canWrite)
            Positioned(
              right: MuyuSpacing.lg,
              bottom: MuyuSpacing.lg,
              child: FloatingActionButton(
                key: const Key('ledger-create-fab'),
                tooltip: '记一笔',
                heroTag: 'ledger-create',
                onPressed: controller.writing ? null : () => _openEntry(null),
                child: const Icon(Icons.add),
              ),
            ),
        ],
      );
    },
  );

  Widget _monthlySummary(
    BuildContext context,
    LifeController controller,
    LedgerSummary? summary,
  ) {
    final onDark = Theme.of(context).colorScheme.onPrimary;
    return Container(
      key: const Key('ledger-monthly-summary'),
      padding: const EdgeInsets.all(MuyuSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '上个月',
                onPressed: () => controller.changeMonth(-1),
                icon: Icon(Icons.chevron_left, color: onDark),
              ),
              Expanded(
                child: Text(
                  '${controller.month.year} 年 ${controller.month.month.toString().padLeft(2, '0')} 月',
                  style: TextStyle(color: onDark, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '下个月',
                onPressed: () => controller.changeMonth(1),
                icon: Icon(Icons.chevron_right, color: onDark),
              ),
            ],
          ),
          const SizedBox(height: MuyuSpacing.sm),
          Text('共同支出', style: TextStyle(color: onDark.withValues(alpha: 0.8))),
          const SizedBox(height: MuyuSpacing.sm),
          Text(
            summary == null ? '¥ --' : '¥ ${_format(summary.expenseMinor)}',
            style: TextStyle(
              color: onDark,
              fontSize: 32,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: MuyuSpacing.md),
          Wrap(
            spacing: MuyuSpacing.lg,
            runSpacing: MuyuSpacing.sm,
            children: [
              _amount(context, '收入', summary?.incomeMinor),
              _amount(context, '收支结余', summary?.balanceMinor),
            ],
          ),
          if (summary != null && summary.payerTotals.isNotEmpty) ...[
            Divider(
              height: MuyuSpacing.xxl,
              color: onDark.withValues(alpha: 0.2),
            ),
            Wrap(
              spacing: MuyuSpacing.lg,
              runSpacing: MuyuSpacing.sm,
              children: [
                for (final row in summary.payerTotals)
                  _amount(
                    context,
                    '${row['display_name']}支出',
                    row['amount_minor'] as int,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _amount(BuildContext context, String label, int? amount) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary
              .withValues(alpha: 0.75),
          fontSize: 11,
        ),
      ),
      Text(
        amount == null ? '¥ --' : '¥${_format(amount)}',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  Widget _categoryDistribution(
    BuildContext context,
    LifeController controller,
    LedgerSummary? summary,
  ) {
    const colors = [
      Color(0xff6b8565),
      Color(0xffadbfa0),
      Color(0xffd2b796),
      Color(0xffc7d3c5),
    ];
    final categories =
        summary?.categories
            .where((row) => (row['amount_minor'] as int) > 0)
            .toList() ??
        [];
    final total = categories.fold<int>(
      0,
      (sum, row) => sum + (row['amount_minor'] as int),
    );
    return Column(
      key: const Key('ledger-category-distribution'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '支出去向',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '${controller.month.month} 月 · ${controller.entries.where((item) => item.type == 'EXPENSE').length} 笔',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: MuyuSpacing.md),
        if (total > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (var index = 0; index < categories.length; index++)
                    Expanded(
                      flex: categories[index]['amount_minor'] as int,
                      child: ColoredBox(
                        color: colors[index % colors.length],
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MuyuSpacing.md),
          Wrap(
            spacing: MuyuSpacing.md,
            runSpacing: MuyuSpacing.sm,
            children: [
              for (var index = 0; index < categories.length; index++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 7,
                      color: colors[index % colors.length],
                    ),
                    const SizedBox(width: MuyuSpacing.xs),
                    Text(
                      '${categories[index]['category']} ${(100 * (categories[index]['amount_minor'] as int) / total).round()}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
            ],
          ),
        ] else
          Text('本月暂无支出分类', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Future<void> _openEntry(LedgerItem? item) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _LedgerEntryDialog(
        controller: widget.controller,
        item: item,
        members: widget.members,
        viewerId: widget.viewerId,
        canWrite: widget.canWrite,
      ),
    );
  }

  static String _format(int minor) => (minor / 100).toStringAsFixed(2);
}

class _LedgerEntryDialog extends StatefulWidget {
  const _LedgerEntryDialog({
    required this.controller,
    required this.item,
    required this.members,
    required this.viewerId,
    required this.canWrite,
  });
  final LifeController controller;
  final LedgerItem? item;
  final List<Map<String, dynamic>> members;
  final String? viewerId;
  final bool canWrite;

  @override
  State<_LedgerEntryDialog> createState() => _LedgerEntryDialogState();
}

class _LedgerEntryDialogState extends State<_LedgerEntryDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.item?.title,
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.item?.formattedAmount,
  );
  late final TextEditingController _category = TextEditingController(
    text: widget.item?.category,
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.item?.note,
  );
  late String _type = widget.item?.type ?? 'EXPENSE';
  late String? _payer = widget.item?.payerId ?? widget.viewerId;
  late DateTime _date = widget.item?.date ?? DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _category.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memberIds = widget.members
        .map((item) => item['user_id'] as String)
        .toSet();
    final payer = memberIds.contains(_payer)
        ? _payer
        : (memberIds.isEmpty ? null : memberIds.first);
    return AlertDialog(
      title: Text(widget.item == null ? '记一笔' : '账目详情'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'EXPENSE', label: Text('支出')),
                  ButtonSegment(value: 'INCOME', label: Text('收入')),
                ],
                selected: {_type},
                onSelectionChanged: !widget.canWrite || _busy
                    ? null
                    : (values) => setState(() => _type = values.first),
              ),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                enabled: widget.canWrite && !_busy,
                decoration: const InputDecoration(labelText: '金额（元）'),
              ),
              TextField(
                controller: _title,
                maxLength: 200,
                enabled: widget.canWrite && !_busy,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              TextField(
                controller: _category,
                maxLength: 80,
                enabled: widget.canWrite && !_busy,
                decoration: const InputDecoration(labelText: '分类'),
              ),
              DropdownButtonFormField<String>(
                initialValue: payer,
                decoration: InputDecoration(
                  labelText: _type == 'EXPENSE' ? '付款人' : '收款人',
                ),
                items: [
                  for (final member in widget.members)
                    DropdownMenuItem(
                      value: member['user_id'] as String,
                      child: Text(member['display_name'] as String? ?? '成员'),
                    ),
                ],
                onChanged: !widget.canWrite || _busy
                    ? null
                    : (value) => setState(() => _payer = value),
              ),
              TextButton.icon(
                onPressed: !widget.canWrite || _busy ? null : _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                ),
              ),
              TextField(
                controller: _note,
                maxLength: 5000,
                maxLines: 2,
                enabled: widget.canWrite && !_busy,
                decoration: const InputDecoration(labelText: '备注（选填）'),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        if (widget.item != null && widget.canWrite)
          TextButton(
            onPressed: _busy ? null : _delete,
            child: const Text('删除'),
          ),
        if (widget.canWrite)
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(widget.item == null ? '添加' : '保存'),
          ),
      ],
    );
  }

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
    final amount = _amount.text.trim();
    final parsed = RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(amount);
    if (!parsed ||
        int.tryParse(amount.split('.').first) == null ||
        _title.text.trim().isEmpty ||
        _category.text.trim().isEmpty ||
        (widget.members.isEmpty
            ? _payer == null
            : !widget.members.any(
                (member) =>
                    member['user_id'] ==
                    (_payer ?? widget.members.first['user_id']),
              ))) {
      setState(() => _error = '请填写有效金额、名称、分类和付款/收款人');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final date =
        '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
    final changes = <String, Object?>{
      'type': _type,
      'amount': amount,
      'title': _title.text.trim(),
      'category': _category.text.trim(),
      'payer_or_payee_id': _payer ?? widget.members.first['user_id'],
      'date': date,
      'note': _note.text.trim(),
    };
    final success = await widget.controller.writeLedger((requestId) async {
      if (widget.item == null) {
        await widget.controller.repository.createLedger({
          'request_id': requestId,
          ...changes,
        });
      } else {
        await widget.controller.repository.updateLedger(widget.item!.id, {
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
        _error = widget.controller.ledgerError;
      });
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除账目？'),
        content: Text('删除“${widget.item!.title}”后，本月汇总也会更新。'),
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
    final success = await widget.controller.writeLedger(
      (requestId) => widget.controller.repository.deleteLedger(
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
        _error = widget.controller.ledgerError;
      });
    }
  }
}
