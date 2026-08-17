import 'package:budgetbox/core/feel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the lattice', () {
    test('snap9 rules the continuum onto 1…9', () {
      expect(snap9(0), 1);
      expect(snap9(1), 9);
      expect(snap9(0.5), 5);
      expect(snap9(0.49), 5); // nearest node, not floor
      // Out-of-band drags (rubber-banded past the edge) still land inside.
      expect(snap9(-0.2), 1);
      expect(snap9(1.3), 9);
    });

    test('from9 and snap9 are inverse on the nodes', () {
      for (var n = 1; n <= 9; n++) {
        expect(snap9(from9(n)), n);
      }
    });

    test('old 1…5 moods re-rule onto the odd nodes', () {
      expect(legacyMoodToPleasant(1), 1);
      expect(legacyMoodToPleasant(2), 3);
      expect(legacyMoodToPleasant(3), 5);
      expect(legacyMoodToPleasant(4), 7);
      expect(legacyMoodToPleasant(5), 9);
    });
  });

  group('the vocabulary', () {
    test('every corner speaks its own quadrant', () {
      // Nearest-anchor lookup at the four corners lands on corner words.
      expect(feelWordAt(0.05, 0.95).word, 'boiling');
      expect(feelWordAt(0.95, 0.95).word, 'alive');
      expect(feelWordAt(0.05, 0.05).word, 'hollow');
      expect(feelWordAt(0.95, 0.05).word, 'at peace');
    });

    test('the middle of an ordinary day has a mild word', () {
      const mild = {'so-so', 'even', 'okay', 'steady', 'middling'};
      expect(mild.contains(feelWordAt(0.5, 0.5).word), isTrue);
    });

    test('no word is repeated and every word has a home on the field', () {
      final names = feelWords.map((w) => w.word).toSet();
      expect(names.length, feelWords.length);
      for (final w in feelWords) {
        expect(w.x, inInclusiveRange(0, 1));
        expect(w.y, inInclusiveRange(0, 1));
        expect(w.hint.trim(), isNotEmpty);
      }
    });
  });

  group('the cloud', () {
    test('packs without overlap and stays inside its canvas', () {
      final cloud = feelBubbleLayout();
      expect(cloud.length, feelWords.length);
      for (final b in cloud) {
        expect(b.center.dx, inInclusiveRange(b.radius, 1400 - b.radius));
        expect(b.center.dy, inInclusiveRange(b.radius, 1600 - b.radius));
      }
      for (var i = 0; i < cloud.length; i++) {
        for (var j = i + 1; j < cloud.length; j++) {
          final dist = (cloud[i].center - cloud[j].center).distance;
          expect(
            dist,
            greaterThanOrEqualTo(cloud[i].radius + cloud[j].radius - 1),
            reason:
                '${cloud[i].word.word} and ${cloud[j].word.word} overlap',
          );
        }
      }
    });

    test('is deterministic — the same room every open', () {
      final a = feelBubbleLayout();
      final b = feelBubbleLayout();
      for (var i = 0; i < a.length; i++) {
        expect(a[i].center, b[i].center);
        expect(a[i].radius, b[i].radius);
      }
    });

    test('strong words draw bigger rounds than mild ones', () {
      final byWord = {
        for (final b in feelBubbleLayout()) b.word.word: b.radius,
      };
      expect(byWord['boiling']!, greaterThan(byWord['okay']!));
      expect(byWord['alive']!, greaterThan(byWord['steady']!));
    });
  });

  group('the weather', () {
    test('each corner leans toward its own ink', () {
      final ember = feelAtmosphere(0, 1);
      final gold = feelAtmosphere(1, 1);
      final deep = feelAtmosphere(0, 0);
      final moss = feelAtmosphere(1, 0);
      expect(ember.r, greaterThan(ember.b)); // heat, not water
      expect(gold.r, greaterThan(gold.b));
      expect(gold.g, greaterThan(ember.g)); // gold sits warmer than ember
      expect(deep.b, greaterThan(deep.r)); // water, not heat
      expect(moss.g, greaterThan(moss.r)); // ground
    });

    test('the centre keeps quieter counsel than the corners', () {
      double spread(double x, double y) {
        final c = feelAtmosphere(x, y);
        final hi = [c.r, c.g, c.b].reduce((a, b) => a > b ? a : b);
        final lo = [c.r, c.g, c.b].reduce((a, b) => a < b ? a : b);
        return hi - lo;
      }

      // Saturation (channel spread) grows from centre to corner.
      expect(spread(0.5, 0.5), lessThan(spread(0.05, 0.95)));
      expect(spread(0.5, 0.5), lessThan(spread(0.95, 0.05)));
    });
  });

  group('the story line', () {
    test('chips and why fold into one said-back line', () {
      expect(
        feltStoryLine('resting,alone,home', 'Just sleeping'),
        'resting · alone · home — Just sleeping',
      );
      expect(feltStoryLine('resting,alone', null), 'resting · alone');
      expect(feltStoryLine(null, 'long day'), 'long day');
      expect(feltStoryLine('', '  '), isNull);
      expect(feltStoryLine(null, null), isNull);
      // Stray commas and spaces from hand-edited tags never show.
      expect(feltStoryLine(' resting , ,home ', ''), 'resting · home');
    });
  });
}
