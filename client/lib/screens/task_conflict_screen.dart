import 'package:flutter/material.dart';

import '../models/task_conflict.dart';
import '../theme/muyu_theme.dart';

class TaskConflictScreen extends StatelessWidget {
  const TaskConflictScreen({
    super.key,
    required this.conflict,
    required this.onResolve,
  });

  final TaskConflict conflict;
  final Future<void> Function(Object? value) onResolve;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('需要确认的修改')),
    body: ListView(
      padding: const EdgeInsets.all(MuyuSpacing.xl),
      children: [
        Text(conflict.target, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: MuyuSpacing.xl),
        _ValueRow(label: '修改前', value: conflict.baseline),
        _ValueRow(label: '服务器当前值', value: conflict.current),
        _ValueRow(label: '你的修改', value: conflict.proposed),
        const SizedBox(height: MuyuSpacing.xl),
        FilledButton(
          onPressed: () => onResolve(conflict.current),
          child: const Text('保留服务器当前值'),
        ),
        OutlinedButton(
          onPressed: () => onResolve(conflict.proposed),
          child: const Text('使用我的修改'),
        ),
      ],
    ),
  );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value});

  final String label;
  final Object? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: MuyuSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 120, child: Text(label)),
        Expanded(child: SelectableText('${value ?? ''}')),
      ],
    ),
  );
}
