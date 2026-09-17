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
      return RefreshIndicator(
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
            Row(
              children: [
                IconButton(
                  tooltip: '上个月',
                  onPressed: () => controller.changeMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    '${controller.month.year} 年 ${controller.month.month} 月',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '下个月',
                  onPressed: () => controller.changeMonth(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            if (controller.loadingLedger) const LinearProgressIndicator(),
            if (controller.ledgerError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: MuyuSpacing.sm),
                child: Text(
                  controller.ledgerError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: MuyuSpacing.md),
            Wrap(
              spacing: MuyuSpacing.lg,
              runSpacing: MuyuSpacing.md,
              children: [
                _amount(context, '共同支出', summary?.expenseMinor),
                _amount(context, '共同收入', summary?.incomeMinor),
                _amount(context, '收支结余', summary?.balanceMinor),
              ],
            ),
            const SizedBox(height: MuyuSpacing.lg),
            if (summary != null && summary.payerTotals.isNotEmpty) ...[
              Text('双方付款', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: MuyuSpacing.sm),
              for (final row in summary.payerTotals)
                Text(
                  '${row['display_name']}  ¥${_format(row['amount_minor'] as int)}',
                ),
              const SizedBox(height: MuyuSpacing.lg),
            ],
            if (summary != null && summary.categories.isNotEmpty) ...[
              Text('支出分类', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: MuyuSpacing.sm),
              for (final row in summary.categories)
                Text(
                  '${row['category']}  ¥${_format(row['amount_minor'] as int)}',
                ),
              const SizedBox(height: MuyuSpacing.lg),
            ],
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
            for (final item in entries) ...[
              ListTile(
                key: Key('ledger-entry-${item.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${item.category} · ${item.payerName} · ${item.date.month}月${item.date.day}日',
                ),
                trailing: Text(
                  '${item.type == 'EXPENSE' ? '-' : '+'}¥${item.formattedAmount}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                onTap: () => _openEntry(item),
              ),
              const Divider(height: 1),
            ],
            if (widget.canWrite) ...[
              const SizedBox(height: MuyuSpacing.xl),
              FilledButton.icon(
                onPressed: controller.writing ? null : () => _openEntry(null),
                icon: const Icon(Icons.add),
                label: const Text('记一笔'),
              ),
            ],
          ],
        ),
      );
    },
  );

  Widget _amount(BuildContext context, String label, int? amount) => SizedBox(
    width: 100,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          '¥${_format(amount ?? 0)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );

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
