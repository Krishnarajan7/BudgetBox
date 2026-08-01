import 'package:flutter/material.dart';

import '../icons.dart';
import '../tokens.dart';

/// A category's drawn mark: a small line icon in faint ink. The single way
/// categories are rendered anywhere in the app — never an emoji.
class CatMark extends StatelessWidget {
  const CatMark(this.iconKey, {super.key, this.size = 15, this.color});

  final String? iconKey;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Icon(
      LedgerIcons.resolve(iconKey),
      size: size,
      color: color ?? c.inkFaint,
    );
  }
}
