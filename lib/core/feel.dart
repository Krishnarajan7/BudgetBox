/// The felt vocabulary and its geometry — no widgets, no context, testable.
///
/// Every word owns a spot on a square of feeling: **x is pleasantness**
/// (rough → good), **y is energy** (still → wired), each 0…1. The book
/// records the word plus its coordinates snapped to a 9×9 lattice, so the
/// month can be read back as weather. The picker never shows the square —
/// it shows the *words*, as a cloud of coloured rounds you move through,
/// and the coordinates ride along underneath.
library;

import 'dart:math' as math;
import 'dart:ui' show Color, Offset, lerpDouble;

/// One word: where it lives, and the one line that says what it means.
class FeelWord {
  const FeelWord(this.word, this.x, this.y, this.hint);

  final String word;
  final double x;
  final double y;

  /// A plain-English breath of a definition, shown when the word is chosen.
  final String hint;
}

/// The book's vocabulary — Krish's words, not a clinician's. Milder words
/// pool near the middle; the strong ones hold the corners. A starting hand,
/// not a cage.
const feelWords = <FeelWord>[
  // ——— wired + rough: the day ran hot and against him ———
  FeelWord('boiling', 0.06, 0.94, 'anger with nowhere left to put it'),
  FeelWord('rattled', 0.14, 0.82, 'shaken by something, not yet settled'),
  FeelWord('panicky', 0.08, 0.72, 'fear running faster than thought'),
  FeelWord('wound up', 0.22, 0.90, 'tight as a spring, ready to snap'),
  FeelWord('short-fused', 0.18, 0.66, 'one small thing away from snapping'),
  FeelWord('on edge', 0.30, 0.76, "braced for a blow that hasn't come"),
  FeelWord('anxious', 0.26, 0.60, 'worry humming under everything'),
  FeelWord('frayed', 0.36, 0.86, 'worn thin at the ends of patience'),
  FeelWord('scattered', 0.40, 0.68, 'pulled in six directions at once'),
  FeelWord('pressed', 0.34, 0.58, 'too much to do, too little room'),
  FeelWord('restless', 0.44, 0.78, "can't sit with it, whatever it is"),
  FeelWord('fed up', 0.12, 0.56, 'done with it, and past politeness'),

  // ——— wired + good: the day ran hot and with him ———
  FeelWord('alive', 0.94, 0.94, 'every light on and burning clean'),
  FeelWord('charged', 0.86, 0.88, 'full of power looking for a use'),
  FeelWord('on a roll', 0.90, 0.78, 'one thing landing after another'),
  FeelWord('keen', 0.72, 0.84, "leaning into what's coming"),
  FeelWord('eager', 0.64, 0.90, "can't wait to get at it"),
  FeelWord('sharp', 0.78, 0.68, 'seeing clearly and cutting true'),
  FeelWord('quick', 0.66, 0.72, 'the mind moving light and fast'),
  FeelWord('bright', 0.84, 0.60, 'lit from the inside, easy to see'),
  FeelWord('humming', 0.72, 0.58, 'everything running warm and smooth'),
  FeelWord('buoyant', 0.92, 0.66, 'hard to keep down to-day'),
  FeelWord('up for it', 0.58, 0.80, 'whatever it is — yes'),
  FeelWord('game', 0.56, 0.62, 'willing, even without a plan'),

  // ——— still + rough: the day sat low ———
  FeelWord('hollow', 0.06, 0.06, 'empty where something should be'),
  FeelWord('defeated', 0.10, 0.16, 'the fight went out, and lost'),
  FeelWord('drained', 0.18, 0.08, 'the tank ran dry hours ago'),
  FeelWord('heavy', 0.16, 0.28, 'carrying more than shows'),
  FeelWord('gloomy', 0.08, 0.38, 'the light low, and staying low'),
  FeelWord('low', 0.24, 0.20, 'down, quietly, for no one reason'),
  FeelWord('worn out', 0.30, 0.10, 'used up by the day'),
  FeelWord('weary', 0.34, 0.24, 'tired deeper than sleep fixes'),
  FeelWord('listless', 0.28, 0.36, 'no pull toward anything'),
  FeelWord('flat', 0.42, 0.30, 'the fizz gone out of things'),
  FeelWord('dull', 0.38, 0.42, 'grey inside, nothing catching'),
  FeelWord('foggy', 0.22, 0.44, 'thoughts moving through mist'),

  // ——— still + good: the day sat well ———
  FeelWord('at peace', 0.94, 0.06, 'nothing left to argue with'),
  FeelWord('rested', 0.84, 0.10, 'slept enough, finally'),
  FeelWord('settled', 0.90, 0.20, 'everything in its place, including you'),
  FeelWord('content', 0.78, 0.24, 'wanting nothing more than this'),
  FeelWord('easy', 0.68, 0.14, 'nothing pushing, nothing pulling'),
  FeelWord('mellow', 0.62, 0.26, 'soft at the edges, in a good way'),
  FeelWord('unhurried', 0.74, 0.36, 'the clock lost its authority'),
  FeelWord('quiet', 0.58, 0.38, 'the inside voice at a whisper'),
  FeelWord('calm', 0.84, 0.40, 'flat water, no wind'),
  FeelWord('at home', 0.92, 0.32, 'where you are is enough'),
  FeelWord('soft', 0.66, 0.44, 'guard down, and safe to keep it down'),

  // ——— the middle band: days that were simply days ———
  FeelWord('so-so', 0.40, 0.52, 'neither here nor there'),
  FeelWord('even', 0.50, 0.44, 'level, no tilt either way'),
  FeelWord('okay', 0.52, 0.56, 'fine — honestly, just fine'),
  FeelWord('steady', 0.62, 0.50, 'holding a straight line'),
  FeelWord('middling', 0.48, 0.34, 'an ordinary day doing ordinary things'),
];

/// The word whose anchor lies nearest to (x, y). Never null — the field has
/// no unnamed ground.
FeelWord feelWordAt(double x, double y) {
  var best = feelWords.first;
  var bestD = double.infinity;
  for (final w in feelWords) {
    final dx = w.x - x, dy = w.y - y;
    final d = dx * dx + dy * dy;
    if (d < bestD) {
      bestD = d;
      best = w;
    }
  }
  return best;
}

/// Continuous 0…1 → lattice 1…9. The words are free; the record is ruled.
int snap9(double t) => (t.clamp(0.0, 1.0) * 8).round() + 1;

/// Lattice 1…9 → the centre of that column/row in 0…1.
double from9(int n) => (n.clamp(1, 9) - 1) / 8;

/// Pre-v11 moods were 1…5; they were re-ruled as (m-1)*2+1 so an old 3 is
/// to-day's 5. Kept for the backend seam and tests.
int legacyMoodToPleasant(int mood) => (mood.clamp(1, 5) - 1) * 2 + 1;

// ————— colour —————

// The four families, vivid — this surface is the one place in the book
// where colour speaks at full voice.
const feelEmber = Color(0xFFE2542F); // wired + rough — heat against him
const feelGold = Color(0xFFF2B33D); // wired + good — heat with him
const feelDeep = Color(0xFF5B6BD6); // still + rough — deep water
const feelMoss = Color(0xFF48B269); // still + good — grown ground

/// The pale sand that mild middle-of-the-field words wear.
const _feelPale = Color(0xFFE7DCC2);

/// How strongly a spot on the field feels — 0 at dead centre, 1 in a corner.
double feelIntensity(double x, double y) {
  final dx = (x - 0.5).abs() * 2, dy = (y - 0.5).abs() * 2;
  return math.max(dx, dy).clamp(0.0, 1.0);
}

/// A word's colour: its quadrant blend at full voice in the corners, paling
/// to warm sand toward the middle — a strong feeling is a strong colour, an
/// ordinary one sits quiet.
Color feelBubbleColor(double x, double y) {
  final cx = x.clamp(0.0, 1.0), cy = y.clamp(0.0, 1.0);
  final low = Color.lerp(feelDeep, feelMoss, cx)!;
  final high = Color.lerp(feelEmber, feelGold, cx)!;
  final vivid = Color.lerp(low, high, cy)!;
  final t = lerpDouble(0.35, 1.0, feelIntensity(cx, cy))!;
  return Color.lerp(_feelPale, vivid, t)!;
}

/// The old name, kept for the month grid and small chips — a shade deeper
/// than the bubble so tiny marks don't shout.
Color feelAtmosphere(double x, double y) {
  final c = feelBubbleColor(x, y);
  return Color.lerp(c, const Color(0xFF14120E), 0.22)!;
}

// ————— the second breath: context —————

/// One group of context chips on the check-in's second page.
class FeelTagGroup {
  const FeelTagGroup(this.question, this.tags);

  final String question;
  final List<String> tags;
}

/// What the day was made of when it felt that way — Krish's life, not a
/// wellness template. Multi-pick, all optional, comma-joined into
/// `feelTags` on the page.
const feelTagGroups = <FeelTagGroup>[
  FeelTagGroup('what were you doing?', [
    'working',
    'studying',
    'building',
    'resting',
    'riding',
    'eating',
    'out',
    'scrolling',
    'chores',
    'travelling',
  ]),
  FeelTagGroup('who were you with?', [
    'alone',
    'family',
    'friends',
    'colleagues',
    'online',
  ]),
  FeelTagGroup('where were you?', [
    'home',
    'office',
    'outside',
    'on the road',
  ]),
];

// ————— the cloud —————

/// One round in the picker's cloud: the word, where it sits on the big
/// canvas, how large it is, and the colour it wears.
class FeelBubble {
  const FeelBubble(this.word, this.center, this.radius, this.color);

  final FeelWord word;
  final Offset center;
  final double radius;
  final Color color;
}

/// Lays the vocabulary out as a packed cloud on a large pannable canvas —
/// strong words big, mild words small, neighbours nudged apart until nothing
/// overlaps. Deterministic: same input, same cloud, every launch.
List<FeelBubble> feelBubbleLayout({
  double width = 1400,
  double height = 1600,
  double minRadius = 52,
  double maxRadius = 86,
  double gap = 10,
}) {
  final pos = <Offset>[];
  final rad = <double>[];
  // Keep the biggest round fully inside the canvas from the start.
  final inset = maxRadius + gap;
  for (final w in feelWords) {
    pos.add(
      Offset(
        inset + w.x * (width - 2 * inset),
        inset + (1 - w.y) * (height - 2 * inset),
      ),
    );
    rad.add(lerpDouble(minRadius, maxRadius, feelIntensity(w.x, w.y))!);
  }
  // Relax: push overlapping pairs apart, then pull strays back inside the
  // canvas, over and over until the cloud settles with both true.
  for (var iter = 0; iter < 200; iter++) {
    var moved = false;
    for (var i = 0; i < pos.length; i++) {
      for (var j = i + 1; j < pos.length; j++) {
        final d = pos[j] - pos[i];
        final dist = d.distance;
        final want = rad[i] + rad[j] + gap;
        if (dist >= want || dist == 0) continue;
        moved = true;
        final push = d / dist * ((want - dist) / 2);
        pos[i] -= push;
        pos[j] += push;
      }
    }
    for (var i = 0; i < pos.length; i++) {
      final clamped = Offset(
        pos[i].dx.clamp(rad[i] + gap, width - rad[i] - gap),
        pos[i].dy.clamp(rad[i] + gap, height - rad[i] - gap),
      );
      if (clamped != pos[i]) {
        moved = true;
        pos[i] = clamped;
      }
    }
    if (!moved) break;
  }
  return [
    for (final (i, w) in feelWords.indexed)
      FeelBubble(w, pos[i], rad[i], feelBubbleColor(w.x, w.y)),
  ];
}
