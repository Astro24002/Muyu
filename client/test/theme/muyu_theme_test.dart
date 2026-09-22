import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muyu_client/theme/muyu_theme.dart';

void main() {
  test('maps the documented Web palette into the Material theme', () {
    final theme = muyuLightTheme();
    final scheme = theme.colorScheme;
    final extension = theme.extension<MuyuThemeExtension>();

    expect(theme.scaffoldBackgroundColor, const Color(0xfffaf9f3));
    expect(scheme.surface, const Color(0xffffffff));
    expect(scheme.onSurface, const Color(0xff1d2d29));
    expect(scheme.onSurfaceVariant, const Color(0xff7c8783));
    expect(scheme.primary, const Color(0xff225f50));
    expect(scheme.secondary, const Color(0xff2e7663));
    expect(scheme.outline, const Color(0xffdce3e0));
    expect(scheme.error, const Color(0xffa33b2e));
    expect(scheme.errorContainer, const Color(0xfffbeae7));
    expect(extension, isNotNull);
    expect(extension!.focusSurface, const Color(0xffe7f0ed));
    expect(extension.coral, const Color(0xffb2573b));
    expect(extension.coralSurface, const Color(0xfff3dfd7));
    expect(extension.sync, const Color(0xff52a083));
    expect(extension.disabled, const Color(0xffa3afaa));
    expect(extension.quadrantQ1, const Color(0xffb04a3a));
    expect(extension.quadrantQ2, const Color(0xffc47a20));
    expect(extension.quadrantQ3, const Color(0xff2e7663));
    expect(extension.quadrantQ4, const Color(0xff5f6f8a));
  });

  test('exposes the fixed spacing scale and themed FAB color', () {
    expect(MuyuSpacing.xs, 4.0);
    expect(MuyuSpacing.sm, 8.0);
    expect(MuyuSpacing.md, 12.0);
    expect(MuyuSpacing.lg, 16.0);
    expect(MuyuSpacing.xl, 24.0);
    expect(MuyuSpacing.xxl, 32.0);

    final theme = muyuLightTheme();
    expect(
      theme.floatingActionButtonTheme.backgroundColor,
      theme.colorScheme.primary,
    );
    expect(theme.cardTheme.elevation, 0);
  });
}
