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

  /// The book opened in daylight: soft paper-white, iron ink, the lightning
  /// deepened so it still strikes against a bright page. Same identity as
  /// night, brighter room.
  static const day = LedgerColors(
    paper: Color(0xFFF5F4F8),
    paperRaised: Color(0xFFFFFFFF),
    ink: Color(0xFF16151D),
    inkFaint: Color(0xFF6A6875),
    rule: Color(0xFFE4E3EA),
    quill: Color(0xFF5B45E0),
    seal: Color(0xFFD23B24),
    jama: Color(0xFF1E8F5D),
    warn: Color(0xFFB07E1E),
  );

  /// The book at night — the app's primary identity. Lacquer black, ivory
  /// ink, and one strike of lightning violet doing all the interactive
  /// talking. The seal keeps its vermilion: red belongs to the stamp alone,
  /// which is exactly what keeps both colors loud.
  static const night = LedgerColors(
    paper: Color(0xFF0A0A0D),
    paperRaised: Color(0xFF15151B),
    ink: Color(0xFFF2EFE6),
    inkFaint: Color(0xFF9A97A8),
    rule: Color(0xFF26252E),
    quill: Color(0xFF7B68FF),
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
