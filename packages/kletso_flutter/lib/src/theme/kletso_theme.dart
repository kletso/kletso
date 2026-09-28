import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:kletso_core/kletso_core.dart';

import 'kletso_tokens.g.dart';

/// Where the floating launcher sits.
enum KletsoLauncherPosition {
  /// Bottom-right corner (default).
  bottomRight,

  /// Bottom-left corner.
  bottomLeft,
}

/// Semantic theme every Kletso widget reads from. Roles map one-to-one to the
/// `--kl-*` design tokens and to the `theme` object of the session bootstrap
/// (see `docs/v1/04-ui-protocol.md` §6).
///
/// Register it on the host `ThemeData.extensions` or pass it to `KletsoChat`;
/// `KletsoTheme.of(context)` falls back to [KletsoTheme.light] when neither
/// was done so the SDK never asserts inside a host app.
@immutable
final class KletsoTheme extends ThemeExtension<KletsoTheme> {
  /// Creates a theme from explicit roles. Prefer [KletsoTheme.light] and
  /// [copyWith].
  const KletsoTheme({
    required this.primary,
    required this.onPrimary,
    required this.primaryHover,
    required this.primarySoft,
    required this.surface,
    required this.background,
    required this.text,
    required this.textMuted,
    required this.line,
    required this.bubbleUser,
    required this.bubbleBot,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.infoSoft,
    required this.successSoft,
    required this.warningSoft,
    required this.errorSoft,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusPill,
    required this.fontFamily,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.caption,
    required this.code,
    required this.launcherPosition,
    required this.launcherSize,
    required this.useHostFont,
  });

  /// The Kletso light theme from the design tokens.
  factory KletsoTheme.light({bool useHostFont = false}) {
    const family = KletsoTokens.fontFamily;
    final String? fam = useHostFont ? null : family;
    final pkg = useHostFont ? null : 'kletso_flutter';
    TextStyle style(
      double size,
      double height,
      FontWeight weight,
      Color color,
    ) => TextStyle(
      fontFamily: fam,
      package: pkg,
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      color: color,
    );
    return KletsoTheme(
      primary: KletsoTokens.dutchOrange,
      onPrimary: KletsoTokens.paper,
      primaryHover: KletsoTokens.orangeDark,
      primarySoft: KletsoTokens.orange100,
      surface: KletsoTokens.paper,
      background: KletsoTokens.cream,
      text: KletsoTokens.deepNavy,
      textMuted: KletsoTokens.gray600,
      line: KletsoTokens.gray200,
      bubbleUser: KletsoTokens.orange100,
      bubbleBot: KletsoTokens.paper,
      success: KletsoTokens.green,
      warning: KletsoTokens.amber,
      error: KletsoTokens.red,
      info: KletsoTokens.blue,
      infoSoft: KletsoTokens.blue100,
      successSoft: KletsoTokens.softMint,
      warningSoft: KletsoTokens.butterYellow,
      errorSoft: const Color(0xFFFDE2E2),
      radiusSm: KletsoTokens.radiusSm,
      radiusMd: KletsoTokens.radiusMd,
      radiusLg: KletsoTokens.radiusLg,
      radiusPill: KletsoTokens.radiusPill,
      fontFamily: family,
      title: style(18, 26, FontWeight.w700, KletsoTokens.deepNavy),
      subtitle: style(15, 22, FontWeight.w600, KletsoTokens.deepNavy),
      body: style(14, 20, FontWeight.w400, KletsoTokens.deepNavy),
      caption: style(12, 16, FontWeight.w400, KletsoTokens.gray600),
      code: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        height: 20 / 13,
        color: KletsoTokens.deepNavy,
      ),
      launcherPosition: KletsoLauncherPosition.bottomRight,
      launcherSize: 56,
      useHostFont: useHostFont,
    );
  }

  /// Applies the project's widget branding from the session bootstrap
  /// (`KletsoSessionBootstrap.theme`) on top of [base] (default [light]).
  /// Unknown or malformed keys are ignored.
  factory KletsoTheme.fromServer(JsonMap theme, {KletsoTheme? base}) {
    final b = base ?? KletsoTheme.light();
    Color? color(String key) {
      final v = theme[key];
      if (v is! String) return null;
      final hex = v.replaceFirst('#', '');
      final full = hex.length == 6 ? 'FF$hex' : hex;
      if (full.length != 8) return null;
      final n = int.tryParse(full, radix: 16);
      return n == null ? null : Color(n);
    }

    final radius = theme['radius'];
    final r = radius is num ? radius.toDouble() : null;
    final launcher = theme['launcher'];
    final position = launcher is Map && launcher['position'] == 'bottomLeft'
        ? KletsoLauncherPosition.bottomLeft
        : null;
    final family = theme['fontFamily'];
    final primary = color('primary');
    final text = color('text');
    return b.copyWith(
      primary: primary,
      onPrimary: color('onPrimary'),
      primarySoft: primary == null ? null : Color.lerp(primary, b.surface, 0.8),
      primaryHover: primary == null ? null : Color.lerp(primary, b.text, 0.15),
      surface: color('surface'),
      background: color('background'),
      text: text,
      textMuted: color('textMuted'),
      bubbleUser: primary == null ? null : Color.lerp(primary, b.surface, 0.8),
      radiusLg: r,
      radiusMd: r == null ? null : (r * 0.75).roundToDouble(),
      radiusSm: r == null ? null : (r * 0.5).roundToDouble(),
      fontFamily: family is String && family.isNotEmpty ? family : null,
      launcherPosition: position,
      title: text == null ? null : b.title.copyWith(color: text),
      subtitle: text == null ? null : b.subtitle.copyWith(color: text),
      body: text == null ? null : b.body.copyWith(color: text),
      code: text == null ? null : b.code.copyWith(color: text),
    );
  }

  /// The Kletso dark theme: navy surfaces, cream text, the same orange.
  factory KletsoTheme.dark({bool useHostFont = false}) {
    final base = KletsoTheme.light(useHostFont: useHostFont);
    const background = KletsoTokens.deepNavy;
    const surface = KletsoTokens.navyLight;
    const text = KletsoTokens.cream;
    final textMuted = Color.lerp(
      KletsoTokens.cream,
      KletsoTokens.navyLight,
      0.35,
    )!;
    final line = Color.lerp(KletsoTokens.navyLight, KletsoTokens.cream, 0.18)!;
    Color soft(Color tone) => Color.lerp(surface, tone, 0.28)!;
    return base.copyWith(
      surface: surface,
      background: background,
      text: text,
      textMuted: textMuted,
      line: line,
      bubbleUser: Color.lerp(surface, KletsoTokens.dutchOrange, 0.35),
      bubbleBot: surface,
      primarySoft: soft(KletsoTokens.dutchOrange),
      infoSoft: soft(KletsoTokens.blue),
      successSoft: soft(KletsoTokens.green),
      warningSoft: soft(KletsoTokens.amber),
      errorSoft: soft(KletsoTokens.red),
      title: base.title.copyWith(color: text),
      subtitle: base.subtitle.copyWith(color: text),
      body: base.body.copyWith(color: text),
      caption: base.caption.copyWith(color: textMuted),
      code: base.code.copyWith(color: text),
    );
  }

  /// [light] or [dark] for [brightness].
  factory KletsoTheme.forBrightness(
    Brightness brightness, {
    bool useHostFont = false,
  }) => brightness == Brightness.dark
      ? KletsoTheme.dark(useHostFont: useHostFont)
      : KletsoTheme.light(useHostFont: useHostFont);

  /// The theme in scope; when the host registered none, [light] or [dark]
  /// following the ambient `ThemeData.brightness`. Never throws.
  static KletsoTheme of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<KletsoTheme>() ??
        KletsoTheme.forBrightness(theme.brightness);
  }

  /// Whether this is the dark variant (used to pick the Material brightness).
  bool get isDark => background.computeLuminance() < 0.3;

  /// Primary action colour (Dutch Orange).
  final Color primary;

  /// Text/icon colour on [primary].
  final Color onPrimary;

  /// [primary] when pressed or hovered.
  final Color primaryHover;

  /// Tinted [primary] for chips and highlights.
  final Color primarySoft;

  /// Cards, bubbles, inputs.
  final Color surface;

  /// The chat background.
  final Color background;

  /// Primary text.
  final Color text;

  /// Secondary text.
  final Color textMuted;

  /// Borders and dividers.
  final Color line;

  /// User bubble background.
  final Color bubbleUser;

  /// Assistant bubble background.
  final Color bubbleBot;

  /// Positive state.
  final Color success;

  /// Caution state.
  final Color warning;

  /// Failure state.
  final Color error;

  /// Informational state.
  final Color info;

  /// Tinted [info] background.
  final Color infoSoft;

  /// Tinted [success] background.
  final Color successSoft;

  /// Tinted [warning] background.
  final Color warningSoft;

  /// Tinted [error] background.
  final Color errorSoft;

  /// Small radius (chips, inputs).
  final double radiusSm;

  /// Medium radius (buttons, bubbles).
  final double radiusMd;

  /// Large radius (cards, sheet).
  final double radiusLg;

  /// Pill radius.
  final double radiusPill;

  /// Font family name used by the text styles.
  final String fontFamily;

  /// Card and surface titles.
  final TextStyle title;

  /// Subtitles and list titles.
  final TextStyle subtitle;

  /// Message text.
  final TextStyle body;

  /// Timestamps, helper text.
  final TextStyle caption;

  /// Inline and block code.
  final TextStyle code;

  /// Launcher corner.
  final KletsoLauncherPosition launcherPosition;

  /// Launcher diameter.
  final double launcherSize;

  /// Whether text styles leave `fontFamily` unset to inherit the host font.
  final bool useHostFont;

  /// Border radius helpers.
  BorderRadius get borderRadiusSm => BorderRadius.circular(radiusSm);

  /// Medium [BorderRadius].
  BorderRadius get borderRadiusMd => BorderRadius.circular(radiusMd);

  /// Large [BorderRadius].
  BorderRadius get borderRadiusLg => BorderRadius.circular(radiusLg);

  /// A Material [ColorScheme] derived from the roles so Material widgets
  /// inside the chat (inputs, switches, progress) match.
  ColorScheme get colorScheme => ColorScheme.fromSeed(
    brightness: isDark ? Brightness.dark : Brightness.light,
    seedColor: primary,
    primary: primary,
    onPrimary: onPrimary,
    surface: surface,
    onSurface: text,
    error: error,
    outline: line,
  );

  /// A [ThemeData] for the chat subtree: Material 3, the derived
  /// [colorScheme], this extension registered, fonts applied.
  ThemeData materialTheme(ThemeData host) {
    final extensions =
        host.extensions.values.where((e) => e is! KletsoTheme).toList()
          ..add(this);
    return host.copyWith(
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: surface,
      dividerColor: line,
      textTheme: useHostFont
          ? host.textTheme
          : host.textTheme.apply(
              fontFamily: fontFamily,
              package: 'kletso_flutter',
            ),
      extensions: extensions,
    );
  }

  @override
  KletsoTheme copyWith({
    Color? primary,
    Color? onPrimary,
    Color? primaryHover,
    Color? primarySoft,
    Color? surface,
    Color? background,
    Color? text,
    Color? textMuted,
    Color? line,
    Color? bubbleUser,
    Color? bubbleBot,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? infoSoft,
    Color? successSoft,
    Color? warningSoft,
    Color? errorSoft,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusPill,
    String? fontFamily,
    TextStyle? title,
    TextStyle? subtitle,
    TextStyle? body,
    TextStyle? caption,
    TextStyle? code,
    KletsoLauncherPosition? launcherPosition,
    double? launcherSize,
    bool? useHostFont,
  }) => KletsoTheme(
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    primaryHover: primaryHover ?? this.primaryHover,
    primarySoft: primarySoft ?? this.primarySoft,
    surface: surface ?? this.surface,
    background: background ?? this.background,
    text: text ?? this.text,
    textMuted: textMuted ?? this.textMuted,
    line: line ?? this.line,
    bubbleUser: bubbleUser ?? this.bubbleUser,
    bubbleBot: bubbleBot ?? this.bubbleBot,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    info: info ?? this.info,
    infoSoft: infoSoft ?? this.infoSoft,
    successSoft: successSoft ?? this.successSoft,
    warningSoft: warningSoft ?? this.warningSoft,
    errorSoft: errorSoft ?? this.errorSoft,
    radiusSm: radiusSm ?? this.radiusSm,
    radiusMd: radiusMd ?? this.radiusMd,
    radiusLg: radiusLg ?? this.radiusLg,
    radiusPill: radiusPill ?? this.radiusPill,
    fontFamily: fontFamily ?? this.fontFamily,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    body: body ?? this.body,
    caption: caption ?? this.caption,
    code: code ?? this.code,
    launcherPosition: launcherPosition ?? this.launcherPosition,
    launcherSize: launcherSize ?? this.launcherSize,
    useHostFont: useHostFont ?? this.useHostFont,
  );

  @override
  KletsoTheme lerp(ThemeExtension<KletsoTheme>? other, double t) {
    if (other is! KletsoTheme) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => lerpDouble(a, b, t)!;
    TextStyle s(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return KletsoTheme(
      primary: c(primary, other.primary),
      onPrimary: c(onPrimary, other.onPrimary),
      primaryHover: c(primaryHover, other.primaryHover),
      primarySoft: c(primarySoft, other.primarySoft),
      surface: c(surface, other.surface),
      background: c(background, other.background),
      text: c(text, other.text),
      textMuted: c(textMuted, other.textMuted),
      line: c(line, other.line),
      bubbleUser: c(bubbleUser, other.bubbleUser),
      bubbleBot: c(bubbleBot, other.bubbleBot),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      error: c(error, other.error),
      info: c(info, other.info),
      infoSoft: c(infoSoft, other.infoSoft),
      successSoft: c(successSoft, other.successSoft),
      warningSoft: c(warningSoft, other.warningSoft),
      errorSoft: c(errorSoft, other.errorSoft),
      radiusSm: d(radiusSm, other.radiusSm),
      radiusMd: d(radiusMd, other.radiusMd),
      radiusLg: d(radiusLg, other.radiusLg),
      radiusPill: d(radiusPill, other.radiusPill),
      fontFamily: t < 0.5 ? fontFamily : other.fontFamily,
      title: s(title, other.title),
      subtitle: s(subtitle, other.subtitle),
      body: s(body, other.body),
      caption: s(caption, other.caption),
      code: s(code, other.code),
      launcherPosition: t < 0.5 ? launcherPosition : other.launcherPosition,
      launcherSize: d(launcherSize, other.launcherSize),
      useHostFont: t < 0.5 ? useHostFont : other.useHostFont,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KletsoTheme &&
          primary == other.primary &&
          onPrimary == other.onPrimary &&
          primaryHover == other.primaryHover &&
          primarySoft == other.primarySoft &&
          surface == other.surface &&
          background == other.background &&
          text == other.text &&
          textMuted == other.textMuted &&
          line == other.line &&
          bubbleUser == other.bubbleUser &&
          bubbleBot == other.bubbleBot &&
          success == other.success &&
          warning == other.warning &&
          error == other.error &&
          info == other.info &&
          infoSoft == other.infoSoft &&
          successSoft == other.successSoft &&
          warningSoft == other.warningSoft &&
          errorSoft == other.errorSoft &&
          radiusSm == other.radiusSm &&
          radiusMd == other.radiusMd &&
          radiusLg == other.radiusLg &&
          radiusPill == other.radiusPill &&
          fontFamily == other.fontFamily &&
          title == other.title &&
          subtitle == other.subtitle &&
          body == other.body &&
          caption == other.caption &&
          code == other.code &&
          launcherPosition == other.launcherPosition &&
          launcherSize == other.launcherSize &&
          useHostFont == other.useHostFont;

  @override
  int get hashCode => Object.hashAll(<Object?>[
    primary,
    onPrimary,
    primaryHover,
    primarySoft,
    surface,
    background,
    text,
    textMuted,
    line,
    bubbleUser,
    bubbleBot,
    success,
    warning,
    error,
    info,
    infoSoft,
    successSoft,
    warningSoft,
    errorSoft,
    radiusSm,
    radiusMd,
    radiusLg,
    radiusPill,
    fontFamily,
    title,
    subtitle,
    body,
    caption,
    code,
    launcherPosition,
    launcherSize,
    useHostFont,
  ]);
}
