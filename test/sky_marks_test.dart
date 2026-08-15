import 'package:budgetbox/core/widgets/sky_marks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('which shape the sky is', () {
    test('clear is a sun by day and a moon at night', () {
      expect(skyShapeFor(0, night: false), SkyShape.sun);
      expect(skyShapeFor(1, night: false), SkyShape.sun);
      expect(skyShapeFor(0, night: true), SkyShape.moon);
    });

    test('part cloud keeps the sun in it, but not after dark', () {
      expect(skyShapeFor(2, night: false), SkyShape.partCloud);
      expect(skyShapeFor(2, night: true), SkyShape.cloud);
      expect(skyShapeFor(3, night: false), SkyShape.cloud);
    });

    test('the wet and the wild', () {
      expect(skyShapeFor(51, night: false), SkyShape.rain);
      expect(skyShapeFor(65, night: false), SkyShape.rain);
      expect(skyShapeFor(82, night: false), SkyShape.rain);
      expect(skyShapeFor(95, night: false), SkyShape.storm);
      expect(skyShapeFor(45, night: false), SkyShape.fog);
      expect(skyShapeFor(73, night: false), SkyShape.snow);
    });

    test('a code nobody has heard of is still a cloud, not a crash', () {
      expect(skyShapeFor(4242, night: false), SkyShape.cloud);
    });
  });

  testWidgets('every shape draws', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0B0A08),
          body: Center(
            child: RepaintBoundary(
              child: ColoredBox(
                color: const Color(0xFF0B0A08),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final shape in SkyShape.values)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: SkyMark(
                            shape: shape,
                            color: const Color(0xFFEDE8DC),
                            size: 36,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(RepaintBoundary).first,
      matchesGoldenFile('goldens/sky.png'),
    );
  });
}
