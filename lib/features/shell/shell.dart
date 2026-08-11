import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../add/add_sheet.dart';
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

  static const _pages = [
    TodayPage(),
    BookPage(),
    PlansPage(),
    WorthPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
    duration: Motion.quick,
    value: 1,
  );
  int _leaving = -1;

  @override
  void didUpdateWidget(_PageTurn old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _leaving = old.index;
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
                Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, 5 * (1 - t)),
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
                          ? Opacity(opacity: 1 - t, child: page)
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

  static const _items = [
    (Icons.today_outlined, 'today'),
    (Icons.menu_book_outlined, 'book'),
    (Icons.fact_check_outlined, 'plans'),
    (Icons.show_chart, 'worth'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(top: BorderSide(color: c.rule)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              _tab(context, 0),
              _tab(context, 1),
              Expanded(
                child: Center(
                  child: Pressable(
                    scale: 0.9,
                    onTap: onAdd,
                    onLongPress: onAddLong,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: c.quill,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(Icons.add, color: c.paper, size: 28),
                    ),
                  ),
                ),
              ),
              _tab(context, 2),
              _tab(context, 3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, int i) {
    final c = LedgerColors.of(context);
    final selected = index == i;
    final (icon, label) = _items[i];
    return Expanded(
      child: Pressable(
        haptic: false,
        scale: 0.97,
        onTap: () => onSelect(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.0 : 0.92,
              duration: Motion.quick,
              curve: Motion.curve,
              child: Icon(icon,
                  size: 20, color: selected ? c.ink : c.inkFaint),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: Motion.quick,
              style: LedgerType.label.copyWith(
                color: selected ? c.ink : c.inkFaint,
              ),
              child: Text(label),
            ),
            const SizedBox(height: 3),
            // A 3px underline dot marks the open page — the spine's ribbon.
            AnimatedContainer(
              duration: Motion.quick,
              curve: Motion.curve,
              width: selected ? 12 : 0,
              height: 2.5,
              decoration: BoxDecoration(
                color: c.quill,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
