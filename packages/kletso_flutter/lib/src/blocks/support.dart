import 'package:flutter/material.dart';

import '../registry/build_context.dart';
import '../theme/kletso_theme.dart';

/// Gap sizes for `row`/`column`.
double kletsoGap(String gap) => switch (gap) {
  'sm' => 4,
  'lg' => 16,
  _ => 8,
};

/// Maps the protocol's `tone` to theme colours (background, foreground).
(Color, Color) kletsoTone(KletsoTheme t, String tone) => switch (tone) {
  'success' => (t.successSoft, t.text),
  'warning' => (t.warningSoft, t.text),
  'error' => (t.errorSoft, t.error),
  'info' => (t.infoSoft, t.info),
  _ => (t.background, t.text),
};

/// A small allowlisted icon vocabulary for `icon` props; unknown names render
/// nothing so the model cannot pick arbitrary glyphs.
IconData? kletsoIcon(String? name) => switch (name) {
  'chat' => Icons.chat_bubble_outline,
  'flag' => Icons.flag_outlined,
  'shopping_bag' => Icons.shopping_bag_outlined,
  'cart' => Icons.shopping_cart_outlined,
  'check' => Icons.check,
  'close' => Icons.close,
  'info' => Icons.info_outline,
  'warning' => Icons.warning_amber_outlined,
  'error' => Icons.error_outline,
  'star' => Icons.star_border,
  'flight' => Icons.flight,
  'hotel' => Icons.hotel_outlined,
  'calendar' => Icons.calendar_today_outlined,
  'clock' => Icons.schedule,
  'location' => Icons.place_outlined,
  'phone' => Icons.phone_outlined,
  'mail' => Icons.mail_outline,
  'link' => Icons.link,
  'refresh' => Icons.refresh,
  'arrow_right' => Icons.arrow_forward,
  'person' => Icons.person_outline,
  'receipt' => Icons.receipt_long_outlined,
  'truck' => Icons.local_shipping_outlined,
  'help' => Icons.help_outline,
  _ => null,
};

/// Allowlisted network image or its alt text.
Widget kletsoImage(
  KletsoBuildContext ctx,
  String src,
  String alt, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
}) {
  final t = ctx.theme;
  final uri = ctx.urlPolicy.check(src);
  if (uri == null) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      color: t.background,
      padding: const EdgeInsets.all(8),
      child: Text(alt, style: t.caption, textAlign: TextAlign.center),
    );
  }
  return Semantics(
    image: true,
    label: alt,
    child: Image.network(
      uri.toString(),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, _, _) => Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        color: t.background,
        child: Text(alt, style: t.caption, textAlign: TextAlign.center),
      ),
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : Container(width: width, height: height, color: t.background),
    ),
  );
}

/// Aspect ratio from the protocol string.
double kletsoAspect(String aspect) => switch (aspect) {
  '1:1' => 1,
  '4:3' => 4 / 3,
  '3:4' => 3 / 4,
  _ => 16 / 9,
};

/// Themed button used by `button`, `confirm`, `form`, `error`.
final class KletsoButton extends StatelessWidget {
  /// Creates a button.
  const KletsoButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = 'primary',
    this.icon,
    this.expanded = false,
  });

  /// Text.
  final String label;

  /// `primary`, `secondary`, `ghost` or `destructive`.
  final String variant;

  /// Optional leading icon name.
  final String? icon;

  /// `null` renders disabled.
  final VoidCallback? onPressed;

  /// Stretch to the available width.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final t = KletsoTheme.of(context);
    final (Color bg, Color fg, BorderSide side) = switch (variant) {
      'secondary' => (t.surface, t.text, BorderSide(color: t.line, width: 1.5)),
      'ghost' => (Colors.transparent, t.text, BorderSide.none),
      'destructive' => (t.error, t.onPrimary, BorderSide.none),
      _ => (t.primary, t.onPrimary, BorderSide.none),
    };
    final iconData = kletsoIcon(icon);
    final style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? Color.alphaBlend(t.surface.withValues(alpha: 0.6), bg)
            : states.contains(WidgetState.pressed) ||
                  states.contains(WidgetState.hovered)
            ? (variant == 'primary'
                  ? t.primaryHover
                  : Color.alphaBlend(t.text.withValues(alpha: 0.06), bg))
            : bg,
      ),
      foregroundColor: WidgetStateProperty.all(fg),
      textStyle: WidgetStateProperty.all(t.subtitle.copyWith(fontSize: 14)),
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      minimumSize: WidgetStateProperty.all(const Size(44, 44)),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: t.borderRadiusMd, side: side),
      ),
      elevation: WidgetStateProperty.all(0),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
    );
    final child = Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (iconData != null) ...<Widget>[
          Icon(iconData, size: 18),
          const SizedBox(width: 8),
        ],
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: TextButton(onPressed: onPressed, style: style, child: child),
    );
  }
}
