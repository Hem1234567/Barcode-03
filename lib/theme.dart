import 'package:flutter/cupertino.dart';

/// Light: white background / black text.  Dark: black background / white text.
class AppColors {
  static bool isDark(BuildContext c) =>
      CupertinoTheme.brightnessOf(c) == Brightness.dark;
  static Color bg(BuildContext c) =>
      isDark(c) ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  static Color text(BuildContext c) =>
      isDark(c) ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  static Color subtext(BuildContext c) =>
      isDark(c) ? const Color(0x99FFFFFF) : const Color(0x99000000);
  static Color surface(BuildContext c) =>
      isDark(c) ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
  static const accent = CupertinoColors.activeBlue;
}

CupertinoThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  final fg = dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  TextStyle s(double size, FontWeight w, [double ls = -0.4]) => TextStyle(
      inherit: false,
      color: fg,
      fontSize: size,
      fontWeight: w,
      letterSpacing: ls,
      fontFamily: '.SF Pro Text');
  return CupertinoThemeData(
    brightness: b,
    primaryColor: AppColors.accent,
    scaffoldBackgroundColor: bg,
    barBackgroundColor: bg.withOpacity(0.85),
    textTheme: CupertinoTextThemeData(
      primaryColor: AppColors.accent,
      textStyle: s(17, FontWeight.w400),
      navTitleTextStyle: s(17, FontWeight.w600),
      navLargeTitleTextStyle: s(34, FontWeight.w700, 0.4),
      tabLabelTextStyle: s(10, FontWeight.w500, 0.1),
    ),
  );
}
