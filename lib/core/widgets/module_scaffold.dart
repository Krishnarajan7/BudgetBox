import 'package:flutter/material.dart';

import '../../features/shelf/shelf_overlay.dart';
import '../tokens.dart';
import '../typography.dart';

/// The frame every non-Money book lives in: module name up top (tap to open
/// the shelf and switch books), back always available, content below. Same
/// paper, same ink — a different book, the same box.
class ModuleScaffold extends StatelessWidget {
  const ModuleScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.fab,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Scaffold(
      floatingActionButton: fab,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x2, Gap.page, 0),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.arrow_back, size: 18, color: c.inkFaint),
                  ),
                  const SizedBox(width: Gap.x3),
                  InkWell(
                    onTap: () => showShelf(context),
                    child: Row(
                      children: [
                        Text(title,
                            style: LedgerType.wordmark.copyWith(color: c.ink)),
                        const SizedBox(width: 2),
                        Icon(Icons.expand_more, size: 14, color: c.inkFaint),
                      ],
                    ),
                  ),
                  const Spacer(),
                  ?trailing,
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
