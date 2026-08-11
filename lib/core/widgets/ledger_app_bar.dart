import 'package:flutter/material.dart';

import '../../features/settings/settings_page.dart';
import '../../features/shelf/shelf_overlay.dart';
import '../tokens.dart';
import '../typography.dart';
import 'motion.dart';
import 'pen_marks.dart';

/// Wordmark (tap → the shelf) · optional trailing · gear (→ the box's
/// settings). Every root screen wears this.
class LedgerAppBar extends StatelessWidget {
  const LedgerAppBar({super.key, this.title, this.trailing});

  /// Defaults to the wordmark; a section name (Book, Plans…) elsewhere.
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.x2),
      child: Row(
        children: [
          Pressable(
            scale: 0.97,
            onTap: () => showShelf(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title ?? 'BudgetBox',
                    style: LedgerType.wordmark.copyWith(color: c.ink)),
                const SizedBox(width: 3),
                PenChevron(size: 12, color: c.inkFaint),
              ],
            ),
          ),
          const Spacer(),
          ?trailing,
          if (trailing != null) const SizedBox(width: Gap.x3),
          Pressable(
            scale: 0.9,
            onTap: () => Navigator.of(context).push(
              LedgerRoute<void>(builder: (_) => const SettingsPage()),
            ),
            // The box's mark: adjustments drawn as dots on rules, the way a
            // ledger would show its settings — never Material's machine gear.
            child: PenSliders(size: 17, color: c.inkFaint),
          ),
        ],
      ),
    );
  }
}
