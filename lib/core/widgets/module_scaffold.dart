import 'package:flutter/material.dart';

import '../../features/shelf/shelf_overlay.dart';
import '../tokens.dart';
import '../typography.dart';
import 'motion.dart';
import 'pen_marks.dart';

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
                  Pressable(
                    scale: 0.9,
                    onTap: () => Navigator.of(context).pop(),
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: PenChevron(size: 16, color: c.inkFaint),
                    ),
                  ),
                  const SizedBox(width: Gap.x3),
                  Pressable(
                    scale: 0.97,
                    onTap: () => showShelf(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            style: LedgerType.wordmark.copyWith(color: c.ink)),
                        const SizedBox(width: 2),
                        PenChevron(size: 12, color: c.inkFaint),
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
