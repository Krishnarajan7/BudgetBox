import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../calendar/calendar_page.dart';
import '../focus/focus_page.dart';
import '../journal/journal_page.dart';
import '../notes/notes_page.dart';
import '../vault/vault_page.dart';

/// Tap the wordmark: the box opens. Bound books route; unbound sleeves wait
/// their turn.
Future<void> showShelf(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'shelf',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, _, _) => const _Shelf(),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween(begin: const Offset(0, -0.06), end: Offset.zero)
            .animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

class _Spine {
  const _Spine(this.name, this.sub, {this.builder, this.subIcon});

  final String name;
  final String sub;

  /// Null = Money (pop back to it). A builder routes to that book.
  final WidgetBuilder? builder;
  final IconData? subIcon;

  bool get bound => name == 'Money' || builder != null;
}

class _Shelf extends StatelessWidget {
  const _Shelf();

  static final _spines = <_Spine>[
    const _Spine('Money', 'this book'),
    _Spine('Calendar', 'open', builder: (_) => const CalendarPage()),
    _Spine('Notes', 'open', builder: (_) => const NotesPage()),
    _Spine('Focus', 'open', builder: (_) => const FocusPage()),
    _Spine('Journal', 'open', builder: (_) => const JournalPage()),
    _Spine('Vault', 'sealed', subIcon: Icons.lock_outline,
        builder: (_) => const VaultPage()),
  ];

  void _go(BuildContext context, _Spine s) {
    // Close the shelf, then land in the chosen book. Money means "back to
    // the root shell" — pop any open module page beneath the shelf.
    Navigator.of(context).pop();
    if (s.builder != null) {
      Navigator.of(context).push(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, _, _) => s.builder!(context),
          transitionsBuilder: (_, anim, _, child) {
            final curved =
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.02),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        ),
      );
    } else {
      // Money: unwind to the shell.
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: c.paperRaised,
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(Corner.sheet + 4)),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(Gap.page, Gap.x4, Gap.page, Gap.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('the box',
                    style: LedgerType.label.copyWith(color: c.inkFaint)),
                const SizedBox(height: Gap.x2),
                for (final (i, s) in _spines.indexed)
                  InkWell(
                    onTap: s.bound ? () => _go(context, s) : null,
                    child: Container(
                      decoration: BoxDecoration(
                        border: i == _spines.length - 1
                            ? null
                            : Border(bottom: BorderSide(color: c.rule)),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: Gap.x3),
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 34,
                            decoration: BoxDecoration(
                              color: s.bound ? c.seal : null,
                              border: s.bound
                                  ? null
                                  : Border.all(color: c.rule, width: 1.5),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: Gap.x3),
                          Text(
                            s.name,
                            style: s.bound
                                ? LedgerType.bodyStrong.copyWith(color: c.ink)
                                : LedgerType.bodyText
                                    .copyWith(color: c.inkFaint),
                          ),
                          const Spacer(),
                          if (s.subIcon != null) ...[
                            Icon(s.subIcon, size: 12, color: c.inkFaint),
                            const SizedBox(width: 4),
                          ],
                          Text(s.sub,
                              style: LedgerType.bodyText
                                  .copyWith(fontSize: 12, color: c.inkFaint)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
