import 'package:flutter/material.dart';

/// The Ledger's palette. Two illuminations of one book: the day page and the
/// night page (lamplight, not inversion). No raw hex outside this file.
@immutable
class LedgerColors extends ThemeExtension<LedgerColors> {
  const LedgerColors({
    required this.paper,
    required this.paperRaised,
    required this.ink,
    required this.inkFaint,
    required this.rule,
    required this.quill,
    required this.seal,
    required this.jama,
    required this.warn,
    required this.heat,
    required this.chartInks,
  });

  /// App background — warm unbleached paper / indigo-black night desk.
  final Color paper;

  /// Sheets, the keypad, raised surfaces.
  final Color paperRaised;

  /// Primary text — iron-gall ink / moonlit paper.
  final Color ink;

  /// Secondary text, captions, labels.
  final Color inkFaint;

  /// The ruled ledger hairlines.
  final Color rule;

  /// The pen: interactive ink — links, active states, the FAB, focus.
  final Color quill;

  /// The vermilion stamp. Reserved: seals, over-budget verdicts, destructive
  /// confirm. More than twice on one screen means the screen is wrong.
  final Color seal;

  /// Credit/income marks and on-pace status. Small marks, never floods.
  final Color jama;

  /// Projected-to-overrun status.
  final Color warn;

  /// The ink-wash for density surfaces (the month grid): iron-gall indigo,
  /// the ink the book is written in. It says "how much writing", never
  /// good/bad — that judgement belongs to the three status hues.
  final Color heat;

  /// The drawer of print inks for anything categorical — chart slices,
  /// composition strips: iron-gall indigo, verdigris, sepia, madder.
  /// Matched in lightness and CVD-validated against both card surfaces.
  /// Identity only, assigned in fixed order and never cycled: whatever
  /// needs a fifth ink folds into rule-grey instead.
  final List<Color> chartInks;

  /// Soft wash of [quill] for selected chips and highlights.
  Color get quillSoft => quill.withValues(alpha: 0.12);

  /// The book in daylight: ivory cooled toward stone — print, not cream.
  /// The yellow is deliberately pulled out of the paper (cream + serif is
  /// the default every generator ships now); what remains reads as a cold
  /// press sheet under iron ink. The accent is still ink itself at full
  /// strength; the three status hues stay the only color on the page.
  static const day = LedgerColors(
    paper: Color(0xFFF3F3EE),
    paperRaised: Color(0xFFFFFFFF),
    ink: Color(0xFF181816),
    inkFaint: Color(0xFF6B6A62),
    rule: Color(0xFFE2E1D8),
    quill: Color(0xFF100F0E),
    seal: Color(0xFFC93A24),
    jama: Color(0xFF1E8F5D),
    warn: Color(0xFFB07E1E),
    heat: Color(0xFF33418F),
    chartInks: [
      Color(0xFF3D4DA8),
      Color(0xFF0B8060),
      Color(0xFFA85C22),
      Color(0xFF8A4488),
    ],
  );

  /// The book at night — the app's primary identity: the iron-gall bottle.
  /// Ledger ink dries blue-black, so the night page is genuinely
  /// indigo-black — the one hue this book owns, not the warm lacquer every
  /// premium dark mode ships. The text keeps its warm ivory (paper
  /// remembers daylight) while the interactive accent is cool moonlight —
  /// warm words under cold light is the tension that makes the page read
  /// as a desk at night. The seal's vermilion and the two status inks stay
  /// the only color, so when they appear they mean it.
  static const night = LedgerColors(
    paper: Color(0xFF0A0C12),
    paperRaised: Color(0xFF141824),
    ink: Color(0xFFE9E7DE),
    inkFaint: Color(0xFF8E9099),
    rule: Color(0xFF232838),
    quill: Color(0xFFF8FAFF),
    seal: Color(0xFFE8402A),
    jama: Color(0xFF43C98D),
    warn: Color(0xFFF2A64B),
    heat: Color(0xFF8E9EEA),
    chartInks: [
      Color(0xFF6B7BD4),
      Color(0xFF2FA88F),
      Color(0xFFC08145),
      Color(0xFFA868AE),
    ],
  );

  static LedgerColors of(BuildContext context) =>
      Theme.of(context).extension<LedgerColors>()!;

  @override
  LedgerColors copyWith({
    Color? paper,
    Color? paperRaised,
    Color? ink,
    Color? inkFaint,
    Color? rule,
    Color? quill,
    Color? seal,
    Color? jama,
    Color? warn,
    Color? heat,
    List<Color>? chartInks,
  }) {
    return LedgerColors(
      paper: paper ?? this.paper,
      paperRaised: paperRaised ?? this.paperRaised,
      ink: ink ?? this.ink,
      inkFaint: inkFaint ?? this.inkFaint,
      rule: rule ?? this.rule,
      quill: quill ?? this.quill,
      seal: seal ?? this.seal,
      jama: jama ?? this.jama,
      warn: warn ?? this.warn,
      heat: heat ?? this.heat,
      chartInks: chartInks ?? this.chartInks,
    );
  }

  @override
  LedgerColors lerp(LedgerColors? other, double t) {
    if (other == null) return this;
    return LedgerColors(
      paper: Color.lerp(paper, other.paper, t)!,
      paperRaised: Color.lerp(paperRaised, other.paperRaised, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkFaint: Color.lerp(inkFaint, other.inkFaint, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      quill: Color.lerp(quill, other.quill, t)!,
      seal: Color.lerp(seal, other.seal, t)!,
      jama: Color.lerp(jama, other.jama, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      heat: Color.lerp(heat, other.heat, t)!,
      chartInks: [
        for (var i = 0; i < chartInks.length; i++)
          Color.lerp(
            chartInks[i],
            other.chartInks.length > i ? other.chartInks[i] : chartInks[i],
            t,
          )!,
      ],
    );
  }
}

/// 4-based spacing scale.
abstract final class Gap {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x12 = 48;

  /// The page's side margin.
  static const double page = 20;
}

/// One radius per role — never one radius everywhere.
abstract final class Corner {
  /// The page and its rows: ledger geometry.
  static const double row = 0;

  /// Sheets and the keypad.
  static const double sheet = 22;

  /// Keys and small raised blocks.
  static const double key = 12;

  /// Chips and pills.
  static const double chip = 999;

  /// The seal's chop-mark.
  static const double stamp = 6;
}
