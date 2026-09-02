import 'package:flutter/material.dart';

class TaskSystemAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TaskSystemAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.titleContent,
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? titleContent;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      key: const Key('task-system-app-bar'),
      leading: leading,
      title: KeyedSubtree(
        key: const Key('task-system-title'),
        child: titleContent ?? Text(title, style: theme.textTheme.titleLarge),
      ),
      actions: actions,
      centerTitle: titleContent != null,
      titleSpacing: leading == null ? 16 : null,
      backgroundColor: theme.colorScheme.surface,
      foregroundColor: theme.colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          thickness: 1,
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}
