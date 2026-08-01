import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

ThemeData _ledgerTheme(LedgerColors c, Brightness brightness) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: LedgerType.body,
  );

  return base.copyWith(
    scaffoldBackgroundColor: c.paper,
    canvasColor: c.paper,
    dividerColor: c.rule,
    splashFactory: InkSparkle.splashFactory,
    extensions: [c],
    colorScheme: base.colorScheme.copyWith(
      primary: c.quill,
      onPrimary: c.paper,
      secondary: c.jama,
      error: c.seal,
      surface: c.paper,
      onSurface: c.ink,
      outline: c.rule,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: c.ink,
      displayColor: c.ink,
      fontFamily: LedgerType.body,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.paper,
      foregroundColor: c.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: LedgerType.wordmark.copyWith(color: c.ink),
    ),
    dividerTheme: DividerThemeData(color: c.rule, thickness: 1, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.paperRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Corner.sheet)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.quill,
        foregroundColor: c.paper,
        textStyle: LedgerType.bodyStrong,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corner.key),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.inkFaint,
        textStyle: LedgerType.bodyStrong,
      ),
    ),
  );
}

ThemeData ledgerDayTheme() => _ledgerTheme(LedgerColors.day, Brightness.light);
ThemeData ledgerNightTheme() =>
    _ledgerTheme(LedgerColors.night, Brightness.dark);
