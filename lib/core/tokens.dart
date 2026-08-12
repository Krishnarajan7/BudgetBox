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

  /// Soft wash of [quill] for selected chips and highlights.
  Color get quillSoft => quill.withValues(alpha: 0.12);

  /// The book in daylight: warm paper-white and iron ink, with the accent
  /// being ink itself at full strength. Monochrome carries the identity;
  /// the three status hues are the only color on the page, which is what
  /// makes a verdict impossible to miss.
  static const day = LedgerColors(
    paper: Color(0xFFF7F5F0),
    paperRaised: Color(0xFFFFFFFF),
    ink: Color(0xFF1A1814),
    inkFaint: Color(0xFF6F6A60),
    rule: Color(0xFFE6E2D9),
    quill: Color(0xFF11100D),
    seal: Color(0xFFC93A24),
    jama: Color(0xFF1E8F5D),
    warn: Color(0xFFB07E1E),
  );

  /// The book at night — the app's primary identity. Moonlight monochrome:
  /// lacquer black, warm ivory ink, and the interactive accent is *light
  /// itself* — pure moonlit white, a weight brighter than the text around
  /// it. No brand hue to date the app or fight the numbers; the seal's
  /// vermilion and the two status inks are the only color, so when they
  /// appear they mean it.
  static const night = LedgerColors(
    paper: Color(0xFF0B0A08),
    paperRaised: Color(0xFF161511),
    ink: Color(0xFFEDE8DC),
    inkFaint: Color(0xFF97917F),
    rule: Color(0xFF272520),
    quill: Color(0xFFFFFDF6),
    seal: Color(0xFFE8402A),
    jama: Color(0xFF43C98D),
    warn: Color(0xFFF2A64B),
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
