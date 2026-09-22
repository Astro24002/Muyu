import 'package:flutter/material.dart';

import '../theme/muyu_theme.dart';

class TaskSystemAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TaskSystemAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
    this.titleContent,
    this.showBrand = false,
    this.eyebrow = '此刻的协作清单',
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? titleContent;
  final bool showBrand;
  final String eyebrow;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      key: const Key('task-system-app-bar'),
      toolbarHeight: kToolbarHeight,
      leading: leading,
      title: KeyedSubtree(
        key: const Key('task-system-title'),
        child: showBrand
            ? _BrandTitle(title: title, eyebrow: eyebrow)
            : titleContent ?? Text(title, style: theme.textTheme.titleLarge),
      ),
      actions: actions,
      centerTitle: false,
      titleSpacing: leading == null
          ? titleContent == null
                ? MuyuSpacing.lg
                : MediaQuery.sizeOf(context).width >= 360
                ? MuyuSpacing.xl
                : MuyuSpacing.lg
          : null,
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

class _BrandTitle extends StatelessWidget {
  const _BrandTitle({required this.title, required this.eyebrow});

  final String title;
  final String eyebrow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final coral =
        theme.extension<MuyuThemeExtension>()?.coral ?? theme.colorScheme.error;
    final titleParts = title.split('→');
    return Semantics(
      label: title,
      header: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            key: const Key('workspace-brand-mark'),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                Icons.north_east,
                size: 20,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: MuyuSpacing.sm),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    height: 14 / 10,
                    letterSpacing: 0,
                  ),
                ),
                Text.rich(
                  key: const Key('workspace-brand-title'),
                  TextSpan(
                    children: [
                      TextSpan(text: titleParts.first),
                      if (titleParts.length > 1) ...[
                        TextSpan(
                          text: '→',
                          style: TextStyle(color: coral),
                        ),
                        TextSpan(text: titleParts.skip(1).join('→')),
                      ],
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontSize: 20,
                    height: 22 / 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
