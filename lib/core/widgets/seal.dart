import 'package:flutter/material.dart';

import '../tokens.dart';

/// The vermilion chop-mark. The app's only celebration.
class Seal extends StatelessWidget {
  const Seal({super.key, this.size = 44, this.child});

  final double size;

  /// Defaults to a check mark scaled to the seal.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Transform.rotate(
      angle: -5 * 3.14159 / 180,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(color: c.seal, width: size * 0.055 + 1.2),
          borderRadius: BorderRadius.circular(size * 0.22),
        ),
        alignment: Alignment.center,
        child: child ??
            Icon(Icons.check, color: c.seal, size: size * 0.48, weight: 700),
      ),
    );
  }
}
