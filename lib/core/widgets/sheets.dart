import 'package:flutter/material.dart';

import '../tokens.dart';

/// The one way paper rises. Every bottom sheet in the app comes through
/// here so they all lift on the book's spring — never the Material default.
Future<T?> showLedgerSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollControlled,
    useSafeArea: true,
    sheetAnimationStyle: AnimationStyle(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    ),
    builder: builder,
  );
}

/// The sheet's grip — one quiet bar of rule ink.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: Gap.x3, bottom: Gap.x2),
        decoration: BoxDecoration(
          color: c.rule,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
