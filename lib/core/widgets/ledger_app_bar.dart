import 'package:flutter/material.dart';

import '../../features/settings/settings_page.dart';
import '../../features/shelf/shelf_overlay.dart';
import '../tokens.dart';
import '../typography.dart';

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
          InkWell(
            onTap: () => showShelf(context),
            child: Row(
              children: [
                Text(title ?? 'BudgetBox',
                    style: LedgerType.wordmark.copyWith(color: c.ink)),
                const SizedBox(width: 2),
                Icon(Icons.expand_more, size: 14, color: c.inkFaint),
              ],
            ),
          ),
          const Spacer(),
          ?trailing,
          if (trailing != null) const SizedBox(width: Gap.x3),
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
            child: Icon(Icons.settings_outlined, size: 18, color: c.inkFaint),
          ),
        ],
      ),
    );
  }
}
