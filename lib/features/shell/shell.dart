import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../add/add_sheet.dart';
import '../kural/kural_page.dart';
import '../add/fab_menu.dart';
import '../book/book_page.dart';
import '../plans/plans_page.dart';
import '../today/today_page.dart';
import '../worth/worth_page.dart';

/// The book's spine: today · book · [+] · plans · worth.
class LedgerShell extends StatefulWidget {
  const LedgerShell({super.key});

  @override
  State<LedgerShell> createState() => _LedgerShellState();
}

class _LedgerShellState extends State<LedgerShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // The day's kural greets the first opening — after the frame, so the
    // shell is standing before the page turns.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ref = ProviderScope.containerOf(context);
      maybeShowDailyKural(context, ref);
    });
  }

  static const _pages = [
    TodayPage(),
    BookPage(),
    PlansPage(),
    WorthPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The page runs underneath the floating bar — that's what the glass
      // blurs.
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: _PageTurn(index: _index, children: _pages),
      ),
      bottomNavigationBar: _LedgerNav(
        index: _index,
        onSelect: (i) {
          if (i != _index) HapticFeedback.selectionClick();
          setState(() => _index = i);
        },
        onAdd: () {
          HapticFeedback.lightImpact();
          showAddSheet(context);
        },
        onAddLong: () {
          HapticFeedback.mediumImpact();
          showFabMenu(context);
        },
      ),
    );
  }
}

/// Turns to another page of the book without closing the old one: every page
/// stays alive (its numbers keep their place; nothing re-counts from zero),
/// only paint and tickers rest while a page is face-down.
class _PageTurn extends StatefulWidget {
  const _PageTurn({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_PageTurn> createState() => _PageTurnState();
}

class _PageTurnState extends State<_PageTurn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  int _leaving = -1;

  /// Which way the book turns: +1 heading right along the bar, -1 back.
  int _dir = 1;

  @override
  void didUpdateWidget(_PageTurn old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _leaving = old.index;
      _dir = widget.index > old.index ? 1 : -1;
      if (Motion.reduced(context)) {
        _c.value = 1;
        _leaving = -1;
      } else {
        _c.forward(from: 0).whenComplete(() {
          if (mounted) setState(() => _leaving = -1);
        });
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Motion.curve.transform(_c.value);
        return Stack(
          fit: StackFit.expand,
          children: [
            for (final (i, page) in widget.children.indexed)
              if (i == widget.index)
                // The new page arrives from the side you're heading — a
                // page turned, not a scene swapped. The old one drifts the
                // other way underneath as it fades.
                Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(28 * (1 - t) * _dir, 0),
                    child: page,
                  ),
                )
              else
                Offstage(
                  offstage: i != _leaving,
                  child: TickerMode(
                    enabled: false,
                    child: IgnorePointer(
                      child: i == _leaving
                          ? Opacity(
                              opacity: 1 - t,
                              child: Transform.translate(
                                offset: Offset(-16 * t * _dir, 0),
                                child: page,
                              ),
                            )
                          : page,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

/// A floating pane of glass in moonlight.
///
/// One frosted plate hovering just off the bottom edge — the page's own
/// ledger lines drift by underneath, blurred through it. Four section names
/// sit on the glass with a pool of moonlight behind the open one; tap
/// another and the light *travels* there, sliding under the chop on its
/// way. The chop itself is the original: a moonlit square cut like a real
/// stamp, extruded on a hard shadow, pressed into the glass.
class _LedgerNav extends StatelessWidget {
  const _LedgerNav({
    required this.index,
    required this.onSelect,
    required this.onAdd,
    required this.onAddLong,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final VoidCallback onAddLong;

  static const _items = ['today', 'book', 'plans', 'worth'];
  static const _chopSlot = 78.0;
  static const _height = 64.0;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final reduced = Motion.reduced(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x3),
      child: DecoratedBox(
        // The float: the page's own darkness pooling underneath. Shadow
        // lives outside the clip so the glass stays clean.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.28),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              height: _height,
              decoration: BoxDecoration(
                // Frost, not paint: enough lacquer to hold the type, thin
                // enough that the page moves behind it.
                color: c.paperRaised.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: c.rule.withValues(alpha: 0.85)),
              ),
              child: LayoutBuilder(
                builder: (context, box) {
                  final tabW = (box.maxWidth - _chopSlot) / 4;
                  // Slots 0,1 sit left of the chop; 2,3 to its right.
                  double slotLeft(int i) =>
                      i * tabW + (i >= 2 ? _chopSlot : 0);
                  return Stack(
                    children: [
                      // The pool of moonlight, travelling between names.
                      AnimatedPositioned(
                        duration: reduced
                            ? Duration.zero
                            : const Duration(milliseconds: 300),
                        curve: Motion.curve,
                        left: slotLeft(index) + 8,
                        top: 13,
                        width: tabW - 16,
                        height: _height - 28,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.quillSoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          _tab(context, 0),
                          _tab(context, 1),
                          SizedBox(width: _chopSlot, child: _chop(c)),
                          _tab(context, 2),
                          _tab(context, 3),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The writing chop, as it always was: a moonlit square cut like a real
  /// stamp — face over a hard zero-blur edge, so pressing it visibly pushes
  /// the stamp into the page.
  Widget _chop(LedgerColors c) {
    return Center(
      child: Pressable(
        scale: 0.9,
        onTap: onAdd,
        onLongPress: onAddLong,
        child: Container(
          key: const ValueKey('nav-add'),
          width: 50,
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.quill,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Color.lerp(c.quill, const Color(0xFF000000), 0.45)!,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: PenPlus(size: 28, color: c.paper),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i) {
    final c = LedgerColors.of(context);
    final selected = index == i;
    return Expanded(
      child: Pressable(
        haptic: false,
        scale: 0.95,
        onTap: () => onSelect(i),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration:
                Motion.reduced(context) ? Duration.zero : Motion.spring,
            curve: Motion.curve,
            style: (selected ? LedgerType.bodyStrong : LedgerType.bodyText)
                .copyWith(
              fontSize: 13.5,
              color: selected ? c.quill : c.inkFaint,
            ),
            child: Text(_items[i]),
          ),
        ),
      ),
    );
  }
}
