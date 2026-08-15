import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../feel.dart';
import '../tokens.dart';
import '../typography.dart';
import 'feel_glyph.dart';
import 'motion.dart';
import 'pen_marks.dart';

/// Opens the felt picker over everything: a dark room full of the book's
/// words, each a round of colour sized by how strongly it feels. You move
/// through the cloud, press the word that fits, it swells into its own
/// shape, and the arrow marks the day — then a second breath asks, all of
/// it optional, what the day was made of and why it sat that way.
Future<void> showFeelPicker(
  BuildContext context, {
  int? mood,
  int? energy,
  String? feelWord,
  String? feelWhy,
  String? feelTags,
  required void Function(int pleasant, int energy, String word) onCommit,
  void Function(String why, String tags)? onDetail,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    LedgerRoute<void>(
      fullscreenDialog: true,
      builder: (_) => FeelPickerPage(
        mood: mood,
        energy: energy,
        feelWord: feelWord,
        feelWhy: feelWhy,
        feelTags: feelTags,
        onCommit: onCommit,
        onDetail: onDetail,
      ),
    ),
  );
}

class FeelPickerPage extends StatefulWidget {
  const FeelPickerPage({
    super.key,
    this.mood,
    this.energy,
    this.feelWord,
    this.feelWhy,
    this.feelTags,
    required this.onCommit,
    this.onDetail,
  });

  final int? mood;
  final int? energy;
  final String? feelWord;
  final String? feelWhy;
  final String? feelTags;
  final void Function(int pleasant, int energy, String word) onCommit;

  /// Fired by "complete check-in" with the why (may be empty) and the
  /// picked tags comma-joined (may be empty). Null hides the second step.
  final void Function(String why, String tags)? onDetail;

  @override
  State<FeelPickerPage> createState() => _FeelPickerPageState();
}

class _FeelPickerPageState extends State<FeelPickerPage>
    with TickerProviderStateMixin {
  /// The cloud is laid once and shared — same words, same room, every open.
  static final List<FeelBubble> _cloud = feelBubbleLayout();
  static const _canvas = Size(1400, 1600);

  final _view = TransformationController();

  FeelBubble? _picked;

  /// The arrival: rounds bloom outward from wherever the eye starts.
  late final AnimationController _arrive = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// The pick: the chosen round swelling into its word's own shape.
  late final AnimationController _swell = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final CurvedAnimation _swellEased = CurvedAnimation(
    parent: _swell,
    curve: Curves.easeOutCubic,
  );

  Offset _focus = Offset(_canvas.width / 2, _canvas.height / 2);
  bool _framed = false;

  /// 0 — the cloud; 1 — the second breath (context chips and the why).
  int _step = 0;

  late final Set<String> _tags = {
    for (final t in (widget.feelTags ?? '').split(','))
      if (t.trim().isNotEmpty) t.trim(),
  };
  late final TextEditingController _why = TextEditingController(
    text: widget.feelWhy ?? '',
  );

  @override
  void initState() {
    super.initState();
    // A marked day walks in on its own word.
    final existing = _existingBubble();
    if (existing != null) {
      _picked = existing;
      _focus = existing.center;
      _swell.value = 1;
    }
  }

  FeelBubble? _existingBubble() {
    if (widget.feelWord != null) {
      for (final b in _cloud) {
        if (b.word.word == widget.feelWord) return b;
      }
    }
    if (widget.mood != null && widget.energy != null) {
      final w = feelWordAt(from9(widget.mood!), from9(widget.energy!));
      for (final b in _cloud) {
        if (b.word.word == w.word) return b;
      }
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_framed) return;
    _framed = true;
    // Frame the room on the focus word before the first paint, then let
    // the rounds bloom in.
    final view = MediaQuery.sizeOf(context);
    _view.value = Matrix4.translationValues(
      (view.width / 2 - _focus.dx).clamp(view.width - _canvas.width, 0),
      (view.height / 2 - _focus.dy).clamp(view.height - _canvas.height, 0),
      0,
    );
    if (Motion.reduced(context)) {
      _arrive.value = 1;
    } else {
      _arrive.forward();
    }
  }

  @override
  void dispose() {
    _view.dispose();
    _arrive.dispose();
    _swellEased.dispose();
    _swell.dispose();
    _why.dispose();
    super.dispose();
  }

  void _pick(FeelBubble b) {
    if (_picked?.word.word == b.word.word) return;
    HapticFeedback.selectionClick();
    setState(() => _picked = b);
    if (Motion.reduced(context)) {
      _swell.value = 1;
    } else {
      _swell
        ..value = 0
        ..forward();
    }
  }

  void _commit() {
    final b = _picked;
    if (b == null) return;
    HapticFeedback.lightImpact();
    widget.onCommit(snap9(b.word.x), snap9(b.word.y), b.word.word);
    // The word is already saved; the second breath is optional on top.
    if (widget.onDetail == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _step = 1);
    }
  }

  void _complete() {
    HapticFeedback.lightImpact();
    widget.onDetail?.call(_why.text.trim(), _tags.join(','));
    Navigator.of(context).pop();
  }

  /// Each round's entrance slot: nearer the eye, earlier on stage.
  Interval _slot(FeelBubble b) {
    final d = (b.center - _focus).distance / 900;
    final start = (0.05 + 0.45 * d).clamp(0.0, 0.55);
    return Interval(start, (start + 0.45).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final still = Motion.reduced(context);
    return Scaffold(
      backgroundColor: const Color(0xFF060505),
      resizeToAvoidBottomInset: true,
      body: AnimatedSwitcher(
        duration: still ? const Duration(milliseconds: 1) : Motion.spring,
        switchInCurve: Motion.curve,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: _step == 0
            ? KeyedSubtree(key: const ValueKey('feel-cloud'), child: _cloudView(c))
            : KeyedSubtree(
                key: const ValueKey('feel-context'),
                child: _contextView(c),
              ),
      ),
    );
  }

  /// Step one: the room of words.
  Widget _cloudView(LedgerColors c) {
    final picked = _picked;
    return Stack(
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _view,
            constrained: false,
            scaleEnabled: false,
            child: SizedBox(
              width: _canvas.width,
              height: _canvas.height,
              child: AnimatedBuilder(
                animation: Listenable.merge([_arrive, _swellEased]),
                builder: (context, _) => Stack(
                  clipBehavior: Clip.none,
                  children: [for (final b in _cloud) _round(b)],
                ),
              ),
            ),
          ),
        ),
        // The room's one question, and the way out.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.x4, Gap.x3, Gap.x4, 0),
              child: Row(
                children: [
                  Pressable(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(Gap.x2),
                      child: PenCross(size: 18, color: c.ink),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'how did the day sit?',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 13,
                      color: c.inkFaint,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 34),
                ],
              ),
            ),
          ),
        ),
        // The chosen word, said plainly, and the arrow that marks it.
        Positioned(
          left: Gap.x4,
          right: Gap.x4,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: AnimatedSlide(
              offset: picked == null ? const Offset(0, 0.3) : Offset.zero,
              duration: Motion.reduced(context)
                  ? const Duration(milliseconds: 1)
                  : Motion.spring,
              curve: Motion.curve,
              child: AnimatedOpacity(
                opacity: picked == null ? 0 : 1,
                duration: Motion.reduced(context)
                    ? const Duration(milliseconds: 1)
                    : Motion.quick,
                child: picked == null
                    ? const SizedBox(height: 84)
                    : _pill(c, picked),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Step two: the second breath — what the day was made of, and why. All
  /// of it optional; the word is already in the book.
  Widget _contextView(LedgerColors c) {
    final b = _picked!;
    const inkFaint = Color(0xFF9A948A);
    const field = Color(0xFF1C1A16);
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.x4, Gap.x3, Gap.x4, 0),
            child: Row(
              children: [
                // Back to the cloud — the word can still change its mind.
                Pressable(
                  onTap: () => setState(() => _step = 0),
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.x2),
                    child: Transform.rotate(
                      angle: math.pi,
                      child: const PenArrow(
                        size: 20,
                        color: Color(0xFFF3EDE0),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Pressable(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(Gap.x2),
                    child: PenCross(size: 18, color: Color(0xFFF3EDE0)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Gap.x4, Gap.x2, Gap.x4, Gap.x4),
              children: [
                Row(
                  children: [
                    FeelBlob(word: b.word.word, color: b.color, size: 38),
                    const SizedBox(width: Gap.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            b.word.word,
                            style: LedgerType.title.copyWith(
                              fontSize: 26,
                              color: Color.lerp(
                                b.color,
                                const Color(0xFFF3EDE0),
                                0.35,
                              ),
                            ),
                          ),
                          Text(
                            b.word.hint,
                            style: LedgerType.bodyText.copyWith(
                              fontSize: 13,
                              color: inkFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                for (final group in feelTagGroups) ...[
                  const SizedBox(height: Gap.x6),
                  Text(
                    group.question,
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 14,
                      color: const Color(0xFFF3EDE0),
                    ),
                  ),
                  const SizedBox(height: Gap.x3),
                  Wrap(
                    spacing: Gap.x2,
                    runSpacing: Gap.x2,
                    children: [
                      for (final tag in group.tags) _tagChip(b, tag),
                    ],
                  ),
                ],
                const SizedBox(height: Gap.x6),
                Text(
                  'why did it sit that way?',
                  style: LedgerType.bodyStrong.copyWith(
                    fontSize: 14,
                    color: const Color(0xFFF3EDE0),
                  ),
                ),
                const SizedBox(height: Gap.x3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Gap.x4,
                    vertical: Gap.x3,
                  ),
                  decoration: BoxDecoration(
                    color: field,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _why,
                    maxLines: 4,
                    minLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    cursorColor: b.color,
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 14,
                      height: 1.5,
                      color: const Color(0xFFF3EDE0),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'a line is plenty. rough is fine.',
                      hintStyle: LedgerType.bodyText.copyWith(
                        fontSize: 14,
                        color: inkFaint,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.x4, Gap.x2, Gap.x4, Gap.x3),
            child: Pressable(
              key: const ValueKey('feel-complete'),
              haptic: false,
              onTap: _complete,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F3EA),
                  borderRadius: BorderRadius.circular(27),
                ),
                child: Center(
                  child: Text(
                    'complete check-in',
                    style: LedgerType.bodyStrong.copyWith(
                      fontSize: 16,
                      color: const Color(0xFF15130F),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// One context chip: dark at rest, the word's own colour when picked.
  Widget _tagChip(FeelBubble b, String tag) {
    final on = _tags.contains(tag);
    return Pressable(
      haptic: false,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => on ? _tags.remove(tag) : _tags.add(tag));
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.x3,
          vertical: Gap.x2,
        ),
        decoration: BoxDecoration(
          color: on ? b.color : const Color(0xFF1C1A16),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          tag,
          style: LedgerType.bodyStrong.copyWith(
            fontSize: 13,
            color: on ? const Color(0xFF191106) : const Color(0xFFD9D3C6),
          ),
        ),
      ),
    );
  }

  /// One word in the room.
  Widget _round(FeelBubble b) {
    final isPicked = _picked?.word.word == b.word.word;
    final arrive = _slot(b).transform(_arrive.value);
    // The chosen round grows a fifth and takes on its own shape; the rest
    // hold their ground.
    final swell = isPicked ? 1 + 0.20 * _swellEased.value : 1.0;
    final scale = arrive * swell;
    final d = b.radius * 2;
    final dark = const Color(0xFF191106);
    return Positioned(
      left: b.center.dx - b.radius,
      top: b.center.dy - b.radius,
      width: d,
      height: d,
      child: Transform.scale(
        scale: scale,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _pick(b),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Circle at rest; the word's own blob once chosen.
              if (isPicked)
                ClipPath(
                  clipper: _BlobClipper(b.word.word, _swellEased.value),
                  child: Container(
                    width: d,
                    height: d,
                    color: b.color,
                  ),
                )
              else
                Container(
                  width: d,
                  height: d,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: b.color,
                  ),
                ),
              if (isPicked)
                IgnorePointer(
                  child: Container(
                    width: d,
                    height: d,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: b.color.withValues(
                            alpha: 0.45 * _swellEased.value,
                          ),
                          blurRadius: 42,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  b.word.word,
                  textAlign: TextAlign.center,
                  style: LedgerType.title.copyWith(
                    fontSize: (b.radius * 0.30).clamp(14.0, 22.0),
                    color: dark,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(LedgerColors c, FeelBubble b) {
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.x4, Gap.x3, Gap.x3, Gap.x3),
      margin: const EdgeInsets.only(bottom: Gap.x3),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1A16),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          FeelBlob(word: b.word.word, color: b.color, size: 30),
          const SizedBox(width: Gap.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.word.word,
                  style: LedgerType.title.copyWith(
                    fontSize: 20,
                    color: Color.lerp(b.color, const Color(0xFFF3EDE0), 0.35),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  b.word.hint,
                  style: LedgerType.bodyText.copyWith(
                    fontSize: 13,
                    color: const Color(0xFF9A948A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.x3),
          Pressable(
            key: const ValueKey('feel-save'),
            haptic: false,
            onTap: _commit,
            child: Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFF7F3EA),
              ),
              child: const Center(
                child: PenArrow(size: 24, color: Color(0xFF15130F)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clips the chosen round from a circle into its word's own shape as the
/// swell runs — wobble 0 is a plain circle, 1 is the word's blob.
class _BlobClipper extends CustomClipper<Path> {
  const _BlobClipper(this.word, this.t);

  final String word;
  final double t;

  @override
  Path getClip(Size size) => feelBlobPath(word, size, wobble: t);

  @override
  bool shouldReclip(_BlobClipper old) => old.word != word || old.t != t;
}
