import 'package:flutter/material.dart';

import '../data/models.dart';
import '../screens/profile.dart' show showProfileSheet;
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// Tappable surface with a small press-in scale, no ripple (matches the design).
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.label, this.selected});
  final Widget child;
  final VoidCallback? onTap;
  final String? label;
  final bool? selected;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.98 : 1,
          duration: const Duration(milliseconds: 140),
          curve: easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

enum BtnStyle { primary, ghost, soft }

class Btn extends StatelessWidget {
  const Btn({
    super.key,
    required this.label,
    this.onTap,
    this.style = BtnStyle.primary,
    this.height = 54,
    this.radius = 16,
    this.fontSize = 16,
    this.leading,
    this.trailing,
    this.color,
    this.expand = true,
    this.padding = 18,
  });

  final String label;
  final VoidCallback? onTap;
  final BtnStyle style;
  final double height;
  final double radius;
  final double fontSize;
  final Widget? leading;
  final Widget? trailing;
  final Color? color;
  final bool expand;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (style) {
      BtnStyle.primary => (C.ink, C.bg, null),
      BtnStyle.ghost => (C.surface, C.ink, C.line(0.1)),
      BtnStyle.soft => (C.surface2, C.ink, null),
    };
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled && style == BtnStyle.primary ? 0.3 : 1,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: padding),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            border: border == null ? null : Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Text(label, style: poppins(fontSize, weight: w600, color: color ?? fg)),
              if (trailing != null) ...[const SizedBox(width: 7), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

class Spark extends StatelessWidget {
  const Spark({super.key, this.color = C.limeDeep, this.size = 14});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Text('✦', style: TextStyle(color: color, fontSize: size, height: 1));
}

class KindTag extends StatelessWidget {
  const KindTag(this.text, {super.key, required this.bg, required this.fg, this.large = false, this.radius});
  KindTag.kind(Kind kind, {super.key, this.large = false, this.radius})
      : text = kind.label.toUpperCase(),
        bg = kindStyle(kind).bg,
        fg = kindStyle(kind).ink;

  final String text;
  final Color bg;
  final Color fg;
  final bool large;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: large ? 26 : 22,
      padding: EdgeInsets.symmetric(horizontal: large ? 8 : 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius ?? (large ? 8 : 6))),
      // widthFactor keeps the tag hugging its text even when the parent is wide.
      child: Center(
        widthFactor: 1,
        child: Text(
          text,
          style: poppins(large ? 10.5 : 9.5, weight: w600, color: fg, letterSpacing: large ? 0 : 0.475, lineHeight: 13),
        ),
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({
    super.key,
    required this.value,
    this.color = C.lime,
    this.track = C.surface2,
    this.height = 5,
  });
  final double value;
  final Color color;
  final Color track;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          Positioned.fill(child: ColoredBox(color: track)),
          FractionallySizedBox(
            widthFactor: value.clamp(0, 1).toDouble(),
            child: Container(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height / 2)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The user's initial in a circle (top right of Home / Today). Tap → profile.
class Avatar extends StatelessWidget {
  const Avatar({super.key, this.size = 40, this.interactive = true});
  final double size;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = kindStyle(Kind.personal);
    final name = state.userName.trim();
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: s.bg, shape: BoxShape.circle),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: poppins(size * 0.375, weight: w600, color: s.ink),
      ),
    );
    if (!interactive) return ExcludeSemantics(child: circle);
    return Pressable(
      onTap: () => showProfileSheet(context),
      label: 'Profile, $name',
      child: circle,
    );
  }
}

/// Text field look shared by the auth screen and the profile sheet.
InputDecoration chronoField(String hint, {Widget? suffix}) => InputDecoration(
      hintText: hint,
      hintStyle: poppins(15, color: C.ink3),
      filled: true,
      fillColor: C.surface,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      errorStyle: poppins(12, color: C.danger),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: C.line(0.12))),
      enabledBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: C.line(0.12))),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: C.line(0.28))),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: C.danger.withValues(alpha: 0.6))),
      focusedErrorBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.danger)),
    );

class Chip2 extends StatelessWidget {
  const Chip2(this.label, {super.key, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Pressable(
        onTap: onTap,
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: C.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: C.line(0.1)),
          ),
          child: Text(label, style: poppins(13, weight: w500)),
        ),
      ),
    );
  }
}

/// Bordered panel used for cards on Home, Today and Deadlines.
BoxDecoration panelBox({double radius = 20, double border = 0.08, Color color = C.surface}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: C.line(border)),
    );

TextStyle get metaStyle => poppins(11.5, weight: w500, color: C.ink2, letterSpacing: 0.46);
