// Design tokens taken from the CHRONO Figma file (html.to.design variables).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/models.dart';

class C {
  static const bg = Color(0xFF121116);
  static const bgDeep = Color(0xFF0B0B0E);
  static const surface = Color(0xFF1C1B22);
  static const surface2 = Color(0xFF26252D);
  static const surface3 = Color(0xFF33323B);
  static const sheet = Color(0xFF1A1920);

  static const ink = Color(0xFFEDEBF2);
  static const ink2 = Color(0xFFA9A6B3);
  static const ink3 = Color(0xFF85828F);

  static const lime = Color(0xFFC8F169);
  static const limeInk = Color(0xFF141508);
  static const limeTag = Color(0xFF3F4A12);
  static const limeDeep = Color(0xFF4A6300);
  static const limeSoft = Color(0xFFDDF79A);
  static const green = Color(0xFF4FD18B);
  static const danger = Color(0xFFFF8FA3);

  static Color line(double opacity) => ink.withValues(alpha: opacity);
}

class KindStyle {
  const KindStyle(this.bg, this.ink, this.bar);
  final Color bg;
  final Color ink;
  final Color bar;
}

const _kindStyles = {
  Kind.lecture: KindStyle(Color(0xFF1E2A4A), Color(0xFFDCE5FF), Color(0xFF7C9CFF)),
  Kind.focus: KindStyle(Color(0xFF173326), Color(0xFFD4F5E2), Color(0xFF4FD18B)),
  Kind.task: KindStyle(Color(0xFF3A1E2B), Color(0xFFFFDCE9), Color(0xFFF27BA8)),
  Kind.personal: KindStyle(Color(0xFF2B2147), Color(0xFFE9E0FF), Color(0xFFB194FF)),
  Kind.breakTime: KindStyle(Color(0xFF26252B), Color(0xFFD6D4DD), Color(0xFF8A8794)),
};

KindStyle kindStyle(Kind k) => _kindStyles[k]!;

const addedStyle = KindStyle(C.lime, C.limeInk, C.limeInk);

/// Poppins with Figma-style line height given in pixels.
TextStyle poppins(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = C.ink,
  double? lineHeight,
  double letterSpacing = 0,
  FontStyle? style,
  TextDecoration? decoration,
}) {
  return GoogleFonts.poppins(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: lineHeight == null ? null : lineHeight / size,
    letterSpacing: letterSpacing,
    fontStyle: style,
    decoration: decoration,
    decorationColor: color,
  );
}

const w400 = FontWeight.w400;
const w500 = FontWeight.w500;
const w600 = FontWeight.w600;
const w700 = FontWeight.w700;

const easeOut = Cubic(0.22, 1, 0.36, 1);
