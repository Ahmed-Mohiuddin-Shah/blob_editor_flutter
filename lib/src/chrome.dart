import 'dart:ui';

import 'package:flutter/material.dart';

/// Matches TS `themeMode`: light | dark | system.
enum BlobThemeMode { light, dark, system }

class BlobChromeColors {
  const BlobChromeColors({
    required this.foreground,
    required this.muted,
    required this.glass,
    required this.glassSolid,
    required this.glassBorder,
    required this.btn,
    required this.btnBorder,
  });

  final Color foreground;
  final Color muted;
  final Color glass;
  final Color glassSolid;
  final Color glassBorder;
  final Color btn;
  final Color btnBorder;

  static const light = BlobChromeColors(
    foreground: Color(0xFF000000),
    muted: Color(0xFF666666),
    glass: Color(0x8CFFFFFF),
    glassSolid: Color(0xB8FFFFFF),
    glassBorder: Color(0x14000000),
    btn: Color(0x0F000000),
    btnBorder: Color(0x1F000000),
  );

  static const dark = BlobChromeColors(
    foreground: Color(0xFFFFFFFF),
    muted: Color(0x9EFFFFFF),
    glass: Color(0x8C1A1A1A),
    glassSolid: Color(0xB81A1A1A),
    glassBorder: Color(0x1FFFFFFF),
    btn: Color(0x1AFFFFFF),
    btnBorder: Color(0x2EFFFFFF),
  );

  static BlobChromeColors resolve(BlobThemeMode mode, Brightness platform) {
    final darkMode = mode == BlobThemeMode.dark ||
        (mode == BlobThemeMode.system && platform == Brightness.dark);
    return darkMode ? dark : light;
  }
}

/// Frosted glass panel (backdrop blur + translucent fill).
class BlobGlass extends StatelessWidget {
  const BlobGlass({
    super.key,
    required this.colors,
    required this.borderRadius,
    required this.child,
    this.padding,
  });

  final BlobChromeColors colors;
  final BorderRadius borderRadius;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.glass,
            borderRadius: borderRadius,
            border: Border.all(color: colors.glassBorder),
          ),
          child: padding == null ? child : Padding(padding: padding!, child: child),
        ),
      ),
    );
  }
}
