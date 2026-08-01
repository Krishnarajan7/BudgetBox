import 'package:flutter/material.dart';

/// Three faces, one job each:
/// Fraunces speaks (titles, hero amounts) · Hanken Grotesk works (UI text) ·
/// Spline Sans Mono keeps the books (every tabular amount).
abstract final class LedgerType {
  static const display = 'Fraunces';
  static const body = 'Hanken Grotesk';
  static const ledger = 'Spline Sans Mono';

  // Variable-font axes. Fraunces reads warmest at high optical size.
  static const _displayAxes = [
    FontVariation('wght', 560),
    FontVariation('opsz', 100),
    FontVariation('SOFT', 0),
    FontVariation('WONK', 1),
  ];

  /// ₹ hero on Today / Worth — the one number the screen exists for.
  static const heroAmount = TextStyle(
    fontFamily: display,
    fontVariations: _displayAxes,
    fontSize: 44,
    height: 1.05,
    letterSpacing: -0.5,
  );

  /// Screen titles and story lines.
  static const title = TextStyle(
    fontFamily: display,
    fontVariations: [
      FontVariation('wght', 540),
      FontVariation('opsz', 60),
      FontVariation('SOFT', 0),
      FontVariation('WONK', 1),
    ],
    fontSize: 26,
    height: 1.18,
    letterSpacing: -0.3,
  );

  /// The wordmark.
  static const wordmark = TextStyle(
    fontFamily: display,
    fontVariations: _displayAxes,
    fontSize: 17,
    letterSpacing: -0.2,
  );

  /// Body text, buttons, row titles.
  static const bodyText = TextStyle(
    fontFamily: body,
    fontVariations: [FontVariation('wght', 460)],
    fontSize: 15,
    height: 1.4,
  );

  /// Emphasised UI text (buttons, row names).
  static const bodyStrong = TextStyle(
    fontFamily: body,
    fontVariations: [FontVariation('wght', 640)],
    fontSize: 15,
    height: 1.35,
  );

  /// Small caption / label — sentence case, never all-caps rows.
  static const label = TextStyle(
    fontFamily: body,
    fontVariations: [FontVariation('wght', 600)],
    fontSize: 12,
    height: 1.3,
    letterSpacing: 0.5,
  );

  /// An amount inside a ledger row or column.
  static const amount = TextStyle(
    fontFamily: ledger,
    fontVariations: [FontVariation('wght', 460)],
    fontSize: 14,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  /// A day/section total.
  static const amountTotal = TextStyle(
    fontFamily: ledger,
    fontVariations: [FontVariation('wght', 560)],
    fontSize: 16,
    height: 1.3,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}
