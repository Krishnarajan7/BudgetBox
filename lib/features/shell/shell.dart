import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../add/add_sheet.dart';
import '../add/fab_menu.dart';
import '../book/book_page.dart';
import '../plans/plans_page.dart';
import '../today/today_page.dart';
import '../worth/worth_page.dart';

/// The book's spine: Today · Book · [+] · Plans · Worth.
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
      body: SafeArea(bottom: false, child: _pages[_index]),
      bottomNavigationBar: _LedgerNav(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
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
    (Icons.today_outlined, 'Today'),
    (Icons.menu_book_outlined, 'Book'),
    (Icons.space_dashboard_outlined, 'Plans'),
    (Icons.show_chart, 'Worth'),
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
                  child: GestureDetector(
                    onTap: onAdd,
                    onLongPress: onAddLong,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: c.quill,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: c.ink.withValues(alpha: 0.28),
                            offset: const Offset(0, 3),
                            blurRadius: 0,
                          ),
                        ],
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
      child: InkWell(
        onTap: () => onSelect(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: selected ? c.ink : c.inkFaint),
            const SizedBox(height: 2),
            Text(
              label,
              style: LedgerType.label.copyWith(
                color: selected ? c.ink : c.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

