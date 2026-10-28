import 'package:flutter/material.dart';

@immutable
class MuyuThemeExtension extends ThemeExtension<MuyuThemeExtension> {
  const MuyuThemeExtension({
    required this.focusSurface,
    required this.sageSurface,
    required this.warmSurface,
    required this.taskSurface,
    required this.taskOutline,
    required this.coral,
    required this.coralSurface,
    required this.sync,
    required this.disabled,
    required this.quadrantQ1,
    required this.quadrantQ2,
    required this.quadrantQ3,
    required this.quadrantQ4,
  });

  final Color focusSurface;
  final Color sageSurface;
  final Color warmSurface;
  final Color taskSurface;
  final Color taskOutline;
  final Color coral;
  final Color coralSurface;
  final Color sync;
  final Color disabled;
  final Color quadrantQ1;
  final Color quadrantQ2;
  final Color quadrantQ3;
  final Color quadrantQ4;

  @override
  MuyuThemeExtension copyWith({
    Color? focusSurface,
    Color? sageSurface,
    Color? warmSurface,
    Color? taskSurface,
    Color? taskOutline,
    Color? coral,
    Color? coralSurface,
    Color? sync,
    Color? disabled,
    Color? quadrantQ1,
    Color? quadrantQ2,
    Color? quadrantQ3,
    Color? quadrantQ4,
  }) => MuyuThemeExtension(
    focusSurface: focusSurface ?? this.focusSurface,
    sageSurface: sageSurface ?? this.sageSurface,
    warmSurface: warmSurface ?? this.warmSurface,
    taskSurface: taskSurface ?? this.taskSurface,
    taskOutline: taskOutline ?? this.taskOutline,
    coral: coral ?? this.coral,
    coralSurface: coralSurface ?? this.coralSurface,
    sync: sync ?? this.sync,
    disabled: disabled ?? this.disabled,
    quadrantQ1: quadrantQ1 ?? this.quadrantQ1,
    quadrantQ2: quadrantQ2 ?? this.quadrantQ2,
    quadrantQ3: quadrantQ3 ?? this.quadrantQ3,
    quadrantQ4: quadrantQ4 ?? this.quadrantQ4,
  );

  @override
  MuyuThemeExtension lerp(covariant MuyuThemeExtension? other, double t) {
    if (other == null) return this;
    return MuyuThemeExtension(
      focusSurface: Color.lerp(focusSurface, other.focusSurface, t)!,
      sageSurface: Color.lerp(sageSurface, other.sageSurface, t)!,
      warmSurface: Color.lerp(warmSurface, other.warmSurface, t)!,
      taskSurface: Color.lerp(taskSurface, other.taskSurface, t)!,
      taskOutline: Color.lerp(taskOutline, other.taskOutline, t)!,
      coral: Color.lerp(coral, other.coral, t)!,
      coralSurface: Color.lerp(coralSurface, other.coralSurface, t)!,
      sync: Color.lerp(sync, other.sync, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      quadrantQ1: Color.lerp(quadrantQ1, other.quadrantQ1, t)!,
      quadrantQ2: Color.lerp(quadrantQ2, other.quadrantQ2, t)!,
      quadrantQ3: Color.lerp(quadrantQ3, other.quadrantQ3, t)!,
      quadrantQ4: Color.lerp(quadrantQ4, other.quadrantQ4, t)!,
    );
  }
}

class MuyuSpacing {
  const MuyuSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class MuyuChartPalette {
  const MuyuChartPalette._();

  static const categories = <Color>[
    Color(0xff6b8565),
    Color(0xffadbfa0),
    Color(0xffd2b796),
    Color(0xffc7d3c5),
  ];
}

// Paper and surface tokens from the confirmed prototype palette.
const _page = Color(0xfff7f7f1);
const _surface = Color(0xffffffff);
const _text = Color(0xff1d2d29);
const _body = Color(0xff25312e);
const _muted = Color(0xff7c8783);
const _brand = Color(0xff225f50);
const _interactive = Color(0xff2e7663);
const _focusSurface = Color(0xffe7f0ed);
const _sageSurface = Color(0xffe4ebd9);
const _warmSurface = Color(0xfff2eee5);
const _taskSurface = _page;
const _taskOutline = Color(0xffebece5);
const _coral = Color(0xffb2573b);
const _coralSurface = Color(0xfff3dfd7);
const _outline = Color(0xffdce3e0);
const _error = Color(0xffa33b2e);
const _errorSurface = Color(0xfffbeae7);
const _sync = Color(0xff52a083);
const _disabled = Color(0xffa3afaa);
const _quadrantQ1 = Color(0xffb04a3a);
const _quadrantQ2 = Color(0xffc47a20);
const _quadrantQ3 = Color(0xff2e7663);
const _quadrantQ4 = Color(0xff5f6f8a);

TextTheme _muyuTextTheme() => const TextTheme(
  titleLarge: TextStyle(
    color: _text,
    fontSize: 24,
    height: 32 / 24,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  ),
  titleMedium: TextStyle(
    color: _text,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  ),
  bodyLarge: TextStyle(
    color: _body,
    fontSize: 14,
    height: 20 / 14,
    letterSpacing: 0,
  ),
  bodyMedium: TextStyle(
    color: _body,
    fontSize: 14,
    height: 20 / 14,
    letterSpacing: 0,
  ),
  bodySmall: TextStyle(
    color: _muted,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 0,
  ),
  labelLarge: TextStyle(
    color: _body,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  ),
  labelMedium: TextStyle(
    color: _muted,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  ),
);

ThemeData muyuLightTheme() {
  final scheme = const ColorScheme.light(
    primary: _brand,
    onPrimary: _surface,
    primaryContainer: _focusSurface,
    onPrimaryContainer: _text,
    secondary: _interactive,
    onSecondary: _surface,
    secondaryContainer: _focusSurface,
    onSecondaryContainer: _text,
    surface: _surface,
    onSurface: _text,
    surfaceContainerHighest: _focusSurface,
    onSurfaceVariant: _muted,
    outline: _outline,
    error: _error,
    onError: _surface,
    errorContainer: _errorSurface,
    onErrorContainer: _error,
  );
  final textTheme = _muyuTextTheme();
  const controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(14)),
  );

  return ThemeData(
    colorScheme: scheme,
    brightness: Brightness.light,
    useMaterial3: true,
    scaffoldBackgroundColor: _page,
    canvasColor: _page,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: _page,
      foregroundColor: _text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: const CardThemeData(
      color: _surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: _outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: MuyuSpacing.lg,
        vertical: MuyuSpacing.md,
      ),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: _outline),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: _outline),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: _interactive, width: 2),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: _error),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: _error, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: _page,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: _focusSurface,
      labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _brand,
      foregroundColor: _surface,
      elevation: 1,
      focusElevation: 2,
      hoverElevation: 2,
      shape: CircleBorder(),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: _surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: controlShape,
    ),
    dividerTheme: const DividerThemeData(
      color: _outline,
      thickness: 1,
      space: 1,
    ),
    extensions: const [
      MuyuThemeExtension(
        focusSurface: _focusSurface,
        sageSurface: _sageSurface,
        warmSurface: _warmSurface,
        taskSurface: _taskSurface,
        taskOutline: _taskOutline,
        coral: _coral,
        coralSurface: _coralSurface,
        sync: _sync,
        disabled: _disabled,
        quadrantQ1: _quadrantQ1,
        quadrantQ2: _quadrantQ2,
        quadrantQ3: _quadrantQ3,
        quadrantQ4: _quadrantQ4,
      ),
    ],
  );
}
