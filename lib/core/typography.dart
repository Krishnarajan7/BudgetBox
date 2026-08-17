import 'package:flutter/material.dart';

/// Three faces, one job each:
/// Absans headlines and carries the hero figures (titles, the wordmark, the
/// one big number a screen exists for) · Subjectivity works (UI text) ·
/// Spline Sans Mono keeps the books (every tabular amount — its digits are
/// the only bundled ones with uniform widths, so columns stay columns).
abstract final class LedgerType {
  /// Absans (Collletttivo, OFL) — a single-weight early-grotesque with just
  /// enough quirk to feel hand-set.
  static const headline = 'Absans';

  /// Subjectivity (Alex Slobzheninov, OFL) — geometric with calligraphic
  /// tails on a, j, y, t. Static weights: Regular 400, Medium 500, Bold 700
  /// are bundled; anything else would be faked by the engine.
  static const body = 'Subjectivity';
  static const ledger = 'Spline Sans Mono';

  /// ₹ hero on Today / Worth — the one number the screen exists for. A lone
  /// figure, never a column, so the headline face can carry it and the
  /// numerals match the words above them.
  static const heroAmount = TextStyle(
    fontFamily: headline,
    fontSize: 44,
    height: 1.05,
    letterSpacing: -0.5,
  );

  /// A count carried inside a mark — the streak's figure in its flame.
  static const markCount = TextStyle(
    fontFamily: headline,
    fontSize: 22,
    height: 1,
    letterSpacing: -0.5,
  );

  /// Screen titles and story lines. Absans ships one weight — no axes to
  /// pull; the size and the air around it do the emphasis.
  static const title = TextStyle(
    fontFamily: headline,
    fontSize: 26,
    height: 1.18,
    letterSpacing: -0.3,
  );

  /// The wordmark.
  static const wordmark = TextStyle(
    fontFamily: headline,
    fontSize: 17,
    letterSpacing: -0.2,
  );

  /// Body text, buttons, row titles.
  static const bodyText = TextStyle(
    fontFamily: body,
    fontWeight: FontWeight.w400,
    fontSize: 15,
    height: 1.4,
  );

  /// Emphasised UI text (buttons, row names).
  static const bodyStrong = TextStyle(
    fontFamily: body,
    fontWeight: FontWeight.w500,
    fontSize: 15,
    height: 1.35,
  );

  /// Small caption / label — sentence case, never all-caps rows.
  static const label = TextStyle(
    fontFamily: body,
    fontWeight: FontWeight.w500,
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
