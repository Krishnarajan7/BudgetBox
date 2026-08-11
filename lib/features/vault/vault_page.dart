import 'dart:async';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/seal.dart';
import '../../core/widgets/sheets.dart';
import '../../data/repos/vault_repo.dart';

/// 'touched to-day' / 'touched yesterday' / 'touched 12 Jul' — how the sealed
/// book speaks of the last time a page was written.
String _touched(DateTime d) {
  final now = DateTime.now();
  final ago = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (ago <= 0) return 'touched to-day';
  if (ago == 1) return 'touched yesterday';
  return 'touched ${LedgerDates.ddMmm(d)}';
}

/// What a long-press on a sealed page decided.
enum _ItemMove { open, burn }

/// The one destructive confirm in the vault, shared by the list and the
/// editor. The burn button is the screen's seal — nothing else in view wears
/// vermilion while this sheet is up.
Future<bool> _confirmBurn(BuildContext context) async {
  final sure = await showLedgerSheet<bool>(
    context,
    builder: (sheetContext) {
      final c = LedgerColors.of(sheetContext);
      return Padding(
        padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetHandle(),
            const SizedBox(height: Gap.x2),
            Text(
              'Burn this page?',
              style: LedgerType.title.copyWith(fontSize: 22, color: c.ink),
            ),
            const SizedBox(height: Gap.x2),
            Text(
              'There is no undo inside the vault. The cipher goes, and '
              'whatever it was holding goes with it.',
              style: LedgerType.bodyText.copyWith(
                fontSize: 13,
                color: c.inkFaint,
              ),
            ),
            const SizedBox(height: Gap.x6),
            // Outlined in seal ink, shaped like the chop itself — the one
            // vermilion mark on the page, and it only ever means this.
            Pressable(
              scale: 0.97,
              onTap: () => Navigator.of(sheetContext).pop(true),
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: c.seal, width: 1.4),
                  borderRadius: BorderRadius.circular(Corner.key),
                ),
                child: Text(
                  'Burn it',
                  style: LedgerType.bodyStrong.copyWith(color: c.seal),
                ),
              ),
            ),
            const SizedBox(height: Gap.x2),
            Pressable(
              scale: 0.97,
              onTap: () => Navigator.of(sheetContext).pop(false),
              child: Container(
                height: 44,
                alignment: Alignment.center,
                child: Text(
                  'Keep it',
                  style: LedgerType.bodyStrong.copyWith(color: c.inkFaint),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  return sure ?? false;
}

/// The sealed book. Opens with a passphrase, never a toast; the key lives in
/// this page's state and dies when the page does — or when the app goes away
/// for longer than a moment.
class VaultPage extends ConsumerStatefulWidget {
  const VaultPage({super.key});

  @override
  ConsumerState<VaultPage> createState() => _VaultPageState();
}

enum _VaultState { checking, needsSetup, locked, open }

class _VaultPageState extends ConsumerState<VaultPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// How long the app may be out of sight before the vault seals itself.
  static const _grace = Duration(seconds: 20);

  /// How far apart the pages ink in when the book first opens.
  static const _rowStagger = Duration(milliseconds: 45);

  _VaultState _state = _VaultState.checking;
  SecretKey? _key;
  List<VaultOpenItem> _items = const [];
  bool _busy = false;
  bool _wrong = false;

  /// True for the beat between the right passphrase and the open view: the
  /// chop stamps down on the locked page before the book opens. The key and
  /// its pages wait here until the stamp lands.
  bool _stamping = false;
  SecretKey? _pendingKey;
  List<VaultOpenItem> _pendingItems = const [];

  /// True for the beat between asking to seal and the locked page returning:
  /// the contents fade out under the chop pressing down again.
  bool _closing = false;

  /// Set when the vault sealed itself in the background, so the locked page
  /// can say so quietly instead of pretending nothing happened.
  bool _sealedAway = false;

  /// When the app left the foreground with the vault still open.
  DateTime? _leftAt;
  Timer? _autoSeal;

  /// The editor route, while one is up — a background reseal has to take it
  /// down with the key, or the plaintext would sit there on screen.
  Route<void>? _editorRoute;

  /// Item ids that should ink in on the next build: everything on first
  /// open, only the rewritten ones after an editor visit.
  Set<int> _freshItems = const {};

  /// True right after unlocking, so the whole list writes itself in
  /// staggered; later re-inks land one at a time with no stagger.
  bool _staggerOpen = false;

  final _pass = TextEditingController();
  final _confirm = TextEditingController();

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: Motion.settle,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    // The key dies with the page — the vault re-seals itself.
    WidgetsBinding.instance.removeObserver(this);
    _autoSeal?.cancel();
    _shake.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // ————— the vault does not wait around —————

  /// Backgrounding the app used to leave the key sitting in memory with the
  /// pages on screen. Now the moment the app looks away for longer than a
  /// glance, the book shuts itself.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _autoSeal?.cancel();
      _autoSeal = null;
      final left = _leftAt;
      _leftAt = null;
      if (left != null && DateTime.now().difference(left) >= _grace) {
        _resealQuietly();
      }
      return;
    }
    if (!_holdsKey || _leftAt != null) return;
    // A timer covers the platforms that keep ticking while away; the elapsed
    // check on resume covers the ones that don't.
    _leftAt = DateTime.now();
    _autoSeal = Timer(_grace, _resealQuietly);
  }

  /// True whenever plaintext exists anywhere in this page's world.
  bool get _holdsKey => _key != null || _pendingKey != null;

  /// No stamp, no haptic — nobody was watching. The key is simply gone, and
  /// the locked page says so when Krish comes back.
  void _resealQuietly() {
    _autoSeal?.cancel();
    _autoSeal = null;
    _leftAt = null;
    if (!mounted || !_holdsKey) return;

    final route = _editorRoute;
    _editorRoute = null;
    if (route != null && route.isActive) {
      final nav = Navigator.of(context);
      nav.popUntil((r) => r == route); // anything stacked over the editor
      nav.pop(); // and the open page itself
    }

    setState(() {
      _key = null;
      _pendingKey = null;
      _pendingItems = const [];
      _items = const [];
      _freshItems = const {};
      _staggerOpen = false;
      _stamping = false;
      _closing = false;
      _sealedAway = true;
      _state = _VaultState.locked;
    });
  }

  // ————— opening and closing —————

  Future<void> _check() async {
    final setUp = await ref.read(vaultRepoProvider).isSetUp();
    if (!mounted) return;
    setState(
      () => _state = setUp ? _VaultState.locked : _VaultState.needsSetup,
    );
  }

  Future<void> _setUp() async {
    if (_busy) return;
    if (_pass.text.length < 6 || _pass.text != _confirm.text) {
      HapticFeedback.heavyImpact();
      setState(() => _wrong = true);
      await _shake.forward(from: 0);
      return;
    }
    setState(() => _busy = true);
    final key = await ref.read(vaultRepoProvider).setUp(_pass.text);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _pass.clear();
    _confirm.clear();
    setState(() {
      _key = key;
      _items = const [];
      _busy = false;
      _state = _VaultState.open;
    });
  }

  Future<void> _unlock() async {
    if (_busy || _stamping || _pass.text.isEmpty) return;
    setState(() {
      _busy = true;
      _wrong = false;
    });
    final key = await ref.read(vaultRepoProvider).unlock(_pass.text);
    if (!mounted) return;
    if (key == null) {
      HapticFeedback.heavyImpact();
      setState(() {
        _busy = false;
        _wrong = true;
      });
      await _shake.forward(from: 0);
      return;
    }
    final items = await ref.read(vaultRepoProvider).readAll(key);
    if (!mounted) return;
    _pass.clear();
    // The right passphrase earns the stamp: the chop lands on the locked
    // page first, then the book opens and its lines write themselves in.
    setState(() {
      _busy = false;
      _stamping = true;
      _sealedAway = false;
      _pendingKey = key;
      _pendingItems = items;
    });
  }

  /// Called by the chop the instant it touches the page.
  void _openAfterStamp() {
    final key = _pendingKey;
    if (!mounted || key == null) return;
    final items = _pendingItems;
    setState(() {
      _key = key;
      _items = items;
      _pendingKey = null;
      _pendingItems = const [];
      _stamping = false;
      _freshItems = {for (final i in items) i.id};
      _staggerOpen = true;
      _state = _VaultState.open;
    });
  }

  /// Closing deserves the same beat as opening, run backwards: the pages
  /// fade under the chop as it presses down, and only then does the locked
  /// cover come back.
  void _sealNow() {
    if (_closing || _key == null) return;
    HapticFeedback.lightImpact();
    setState(() => _closing = true);
  }

  /// The chop has landed; the key goes with it.
  void _sealed() {
    if (!mounted) return;
    setState(() {
      _key = null;
      _items = const [];
      _freshItems = const {};
      _staggerOpen = false;
      _closing = false;
      _sealedAway = false;
      _state = _VaultState.locked;
    });
  }

  // ————— the pages —————

  Future<void> _reload() async {
    final key = _key;
    if (key == null) return;
    final items = await ref.read(vaultRepoProvider).readAll(key);
    if (!mounted || _key == null) return;
    // Only pages that are new or rewritten since the last look re-ink.
    final before = {for (final i in _items) i.id: i.updatedAt};
    setState(() {
      _freshItems = {
        for (final i in items)
          if (before[i.id] != i.updatedAt) i.id,
      };
      _staggerOpen = false;
      _items = items;
    });
  }

  Future<void> _edit([VaultOpenItem? item]) async {
    final key = _key;
    if (key == null) return;
    final route = LedgerRoute<void>(
      builder: (_) => _VaultEditor(vaultKey: key, item: item),
    );
    _editorRoute = route;
    await Navigator.of(context).push(route);
    if (!mounted) return;
    if (identical(_editorRoute, route)) _editorRoute = null;
    await _reload();
  }

  /// Long-press: the three things worth doing to a sealed page without
  /// necessarily opening it.
  Future<void> _itemMenu(VaultOpenItem item) async {
    if (_closing) return;
    HapticFeedback.selectionClick();
    final move = await showLedgerSheet<_ItemMove>(
      context,
      builder: (_) => _ItemSheet(item: item),
    );
    if (!mounted || move == null) return;
    switch (move) {
      case _ItemMove.open:
        await _edit(item);
      case _ItemMove.burn:
        await _burn(item);
    }
  }

  Future<void> _burn(VaultOpenItem item) async {
    if (!await _confirmBurn(context)) return;
    await ref.read(vaultRepoProvider).deleteItem(item.id);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final showTools = _state == _VaultState.open && !_closing;
    return ModuleScaffold(
      title: 'Vault',
      trailing: showTools
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Pressable(
                  scale: 0.9,
                  onTap: () => _edit(),
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.x1),
                    child: Icon(Icons.add, size: 18, color: c.inkFaint),
                  ),
                ),
                const SizedBox(width: Gap.x3),
                Pressable(
                  scale: 0.9,
                  onTap: _sealNow,
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.x1),
                    child: Icon(
                      Icons.lock_outline,
                      size: 17,
                      color: c.inkFaint,
                    ),
                  ),
                ),
              ],
            )
          : null,
      // Opening rises onto the page; sealing reverses it — the leaving list
      // fades down while the chop inks back in. Closing feels like closing.
      child: AnimatedSwitcher(
        duration: Motion.spring,
        switchInCurve: Motion.curve,
        switchOutCurve: Motion.curve,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.015),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: switch (_state) {
          _VaultState.checking => const SizedBox.shrink(),
          _VaultState.needsSetup => _setup(c),
          _VaultState.locked => _lockedView(c),
          _VaultState.open => _openView(c),
        },
      ),
    );
  }

  Widget _shakeWrap(Widget child) {
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, kid) {
        final t = _shake.value;
        final dx = math.sin(t * math.pi * 5) * 12 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: kid);
      },
      child: child,
    );
  }

  Widget _passField(
    LedgerColors c,
    TextEditingController controller,
    String hint,
    VoidCallback onSubmit,
  ) {
    return TextField(
      controller: controller,
      obscureText: true,
      autofocus: true,
      onSubmitted: (_) => onSubmit(),
      style: LedgerType.bodyText.copyWith(color: c.ink, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: LedgerType.bodyText.copyWith(
          fontSize: 16,
          color: c.inkFaint,
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: _wrong ? c.warn : c.rule),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: _wrong ? c.warn : c.quill, width: 1.6),
        ),
      ),
    );
  }

  Widget _setup(LedgerColors c) {
    return ListView(
      key: const ValueKey('setup'),
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x8, Gap.page, Gap.x6),
      children: [
        Text(
          'Seal a vault.',
          style: LedgerType.title.copyWith(fontSize: 28, color: c.ink),
        ),
        const SizedBox(height: Gap.x2),
        Text(
          'Whatever goes in is encrypted with a passphrase only you know. '
          'Lose the passphrase and what is inside is gone — there is no '
          'reset, no recovery, no back door. That is the point.',
          style: LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
        ),
        const SizedBox(height: Gap.x6),
        _shakeWrap(
          Column(
            children: [
              _passField(
                c,
                _pass,
                'a passphrase, six characters or more',
                () {},
              ),
              const SizedBox(height: Gap.x3),
              _passField(c, _confirm, 'and again, to be sure', _setUp),
            ],
          ),
        ),
        SizedBox(
          height: Gap.x6,
          child: _wrong
              ? Padding(
                  padding: const EdgeInsets.only(top: Gap.x2),
                  child: Text(
                    _pass.text.length < 6
                        ? 'Six characters at least — it guards everything.'
                        : 'They do not match yet.',
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 12,
                      color: c.warn,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: Gap.x4),
        FilledButton(
          onPressed: _setUp,
          child: Text(_busy ? 'sealing…' : 'Seal it'),
        ),
      ],
    );
  }

  Widget _lockedView(LedgerColors c) {
    final lock = Icon(Icons.lock_outline, size: 22, color: c.seal);
    return ListView(
      key: const ValueKey('locked'),
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x12, Gap.page, Gap.x6),
      children: [
        Center(
          // Idle, the chop simply inks onto the cover. On the right
          // passphrase it stamps — and the stamp landing is what opens the
          // book, so the beat can never be skipped.
          child: _stamping
              ? StampIn(
                  key: const ValueKey('vault-open-stamp'),
                  size: 56,
                  onStamped: _openAfterStamp,
                  child: lock,
                )
              : InkIn(child: Seal(size: 56, child: lock)),
        ),
        if (_sealedAway) ...[
          const SizedBox(height: Gap.x4),
          Text(
            'Sealed itself while you were away — the key does not wait '
            'around.',
            textAlign: TextAlign.center,
            style: LedgerType.bodyText.copyWith(
              fontSize: 12,
              color: c.inkFaint,
            ),
          ),
        ],
        const SizedBox(height: Gap.x6),
        // The form steps back under the landing stamp.
        AnimatedOpacity(
          duration: Motion.quick,
          curve: Motion.curve,
          opacity: _stamping ? 0.25 : 1,
          child: IgnorePointer(
            ignoring: _stamping,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _shakeWrap(_passField(c, _pass, 'the passphrase', _unlock)),
                SizedBox(
                  height: Gap.x6,
                  child: _wrong
                      ? Padding(
                          padding: const EdgeInsets.only(top: Gap.x2),
                          child: Text(
                            'Not it.',
                            style: LedgerType.bodyText.copyWith(
                              fontSize: 12,
                              color: c.warn,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: Gap.x4),
                FilledButton(
                  onPressed: _unlock,
                  child: Text(_busy ? 'opening…' : 'Open the vault'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _openView(LedgerColors c) {
    return Stack(
      key: const ValueKey('open'),
      fit: StackFit.expand,
      children: [
        AnimatedOpacity(
          duration: Motion.quick,
          curve: Motion.curve,
          opacity: _closing ? 0 : 1,
          child: _items.isEmpty
              ? const EmptyPage(
                  line: 'Open, and empty.',
                  sub:
                      'Whatever you seal in here stays between you and '
                      'the passphrase.',
                )
              : _pages(c),
        ),
        // The chop presses back down over the fading pages — the same thud
        // that opened the book, closing it.
        if (_closing)
          IgnorePointer(
            child: Center(
              child: StampIn(
                key: const ValueKey('vault-close-stamp'),
                size: 56,
                onStamped: _sealed,
                child: Icon(Icons.lock_outline, size: 22, color: c.seal),
              ),
            ),
          ),
      ],
    );
  }

  Widget _pages(LedgerColors c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x4, Gap.page, Gap.x6),
      children: [
        InkIn(
          play: _staggerOpen,
          child: Text(
            'unsealed, for now',
            style: LedgerType.label.copyWith(color: c.inkFaint),
          ),
        ),
        const SizedBox(height: Gap.x2),
        // After the stamp the pages write themselves in, top to bottom;
        // later, only a rewritten page re-inks. Rows give under the thumb,
        // and hold for the long-press menu.
        for (final (i, item) in _items.indexed)
          InkIn(
            key: ValueKey(
              'vault-${item.id}-${item.updatedAt.millisecondsSinceEpoch}',
            ),
            play: _freshItems.contains(item.id),
            delay: _staggerOpen ? _rowStagger * (i + 1) : Duration.zero,
            child: Pressable(
              onTap: () => _edit(item),
              onLongPress: () => _itemMenu(item),
              child: LedgerLine(
                title: item.title.isEmpty ? '(untitled)' : item.title,
                detail: _touched(item.updatedAt),
                last: i == _items.length - 1,
              ),
            ),
          ),
      ],
    );
  }
}

/// Long-press on a sealed page: take the secret without opening it, open it
/// properly, or burn it. Copying never reveals the body on screen — the
/// clipboard gets it, the icon wears a check for a moment, and that is the
/// whole confirmation.
class _ItemSheet extends StatefulWidget {
  const _ItemSheet({required this.item});

  final VaultOpenItem item;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  bool _copied = false;
  int _copyStamp = 0;

  void _copy() {
    final item = widget.item;
    final secret = item.body.trim().isEmpty ? item.title : item.body;
    Clipboard.setData(ClipboardData(text: secret));
    HapticFeedback.lightImpact();
    final stamp = ++_copyStamp;
    setState(() => _copied = true);
    Future<void>.delayed(Motion.draw, () {
      if (mounted && stamp == _copyStamp) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final item = widget.item;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.page, 0, Gap.page, Gap.x6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHandle(),
          const SizedBox(height: Gap.x2),
          Text(
            item.title.isEmpty ? '(untitled)' : item.title,
            style: LedgerType.title.copyWith(fontSize: 20, color: c.ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            _touched(item.updatedAt),
            style: LedgerType.bodyText.copyWith(
              fontSize: 12,
              color: c.inkFaint,
            ),
          ),
          const SizedBox(height: Gap.x4),
          _SheetAction(
            label: _copied ? 'On the clipboard' : 'Copy the secret',
            sub: 'straight across, without opening the page',
            onTap: _copy,
            icon: AnimatedSwitcher(
              duration: Motion.quick,
              switchInCurve: Motion.curve,
              switchOutCurve: Motion.curve,
              child: _copied
                  ? Icon(
                      Icons.check,
                      key: const ValueKey('copied'),
                      size: 18,
                      color: c.quill,
                    )
                  : Icon(
                      Icons.copy_all_outlined,
                      key: const ValueKey('copy'),
                      size: 18,
                      color: c.inkFaint,
                    ),
            ),
          ),
          _SheetAction(
            label: 'Open it',
            sub: 'read it, rewrite it, seal it again',
            icon: Icon(Icons.edit_outlined, size: 18, color: c.inkFaint),
            onTap: () => Navigator.of(context).pop(_ItemMove.open),
          ),
          _SheetAction(
            label: 'Burn it',
            sub: 'the cipher goes, and nothing brings it back',
            tint: c.seal,
            icon: Icon(
              Icons.local_fire_department_outlined,
              size: 18,
              color: c.seal,
            ),
            onTap: () => Navigator.of(context).pop(_ItemMove.burn),
            last: true,
          ),
        ],
      ),
    );
  }
}

/// One ruled choice on a sheet: glyph, what it does, and a quiet line saying
/// what that means.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.label,
    required this.sub,
    required this.icon,
    required this.onTap,
    this.tint,
    this.last = false,
  });

  final String label;
  final String sub;
  final Widget icon;
  final VoidCallback onTap;
  final Color? tint;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.rule)),
        ),
        child: Row(
          children: [
            SizedBox(width: 26, child: Center(child: icon)),
            const SizedBox(width: Gap.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: LedgerType.bodyText.copyWith(color: tint ?? c.ink),
                  ),
                  Text(
                    sub,
                    style: LedgerType.bodyText.copyWith(
                      fontSize: 12,
                      color: c.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Write or rewrite one sealed item. Saving re-encrypts; nothing plaintext
/// ever touches the database.
class _VaultEditor extends ConsumerStatefulWidget {
  const _VaultEditor({required this.vaultKey, this.item});

  final SecretKey vaultKey;
  final VaultOpenItem? item;

  @override
  ConsumerState<_VaultEditor> createState() => _VaultEditorState();
}

class _VaultEditorState extends ConsumerState<_VaultEditor> {
  late final _title = TextEditingController(text: widget.item?.title ?? '');
  late final _body = TextEditingController(text: widget.item?.body ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    // The words go under seal: the fields dim as the cipher takes them.
    setState(() => _busy = true);
    final repo = ref.read(vaultRepoProvider);
    if (widget.item == null) {
      await repo.addItem(
        widget.vaultKey,
        title: _title.text.trim(),
        body: _body.text,
      );
    } else {
      await repo.updateItem(
        widget.vaultKey,
        widget.item!.id,
        title: _title.text.trim(),
        body: _body.text,
      );
    }
    if (!mounted) return;
    HapticFeedback.lightImpact();
    await Future<void>.delayed(Motion.quick);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final item = widget.item;
    if (item == null) return;
    if (!await _confirmBurn(context)) return;
    await ref.read(vaultRepoProvider).deleteItem(item.id);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return Scaffold(
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
                    child: Icon(Icons.arrow_back, size: 18, color: c.inkFaint),
                  ),
                  const Spacer(),
                  if (widget.item != null)
                    Pressable(
                      scale: 0.9,
                      onTap: _delete,
                      child: Icon(
                        Icons.local_fire_department_outlined,
                        size: 18,
                        color: c.inkFaint,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedOpacity(
                duration: Motion.quick,
                curve: Motion.curve,
                opacity: _busy ? 0.25 : 1,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                  children: [
                    TextField(
                      controller: _title,
                      style: LedgerType.title.copyWith(
                        fontSize: 24,
                        color: c.ink,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Untitled',
                        hintStyle: LedgerType.title.copyWith(
                          fontSize: 24,
                          color: c.inkFaint,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                    TextField(
                      controller: _body,
                      maxLines: null,
                      style: LedgerType.bodyText.copyWith(
                        fontSize: 15,
                        height: 1.55,
                        color: c.ink,
                      ),
                      decoration: InputDecoration(
                        hintText: 'What stays sealed…',
                        hintStyle: LedgerType.bodyText.copyWith(
                          fontSize: 15,
                          height: 1.55,
                          color: c.inkFaint,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.page),
              // Sealing should feel like pressing a stamp down.
              child: Pressable(
                scale: 0.97,
                onTap: _save,
                child: IgnorePointer(
                  child: FilledButton(
                    onPressed: _busy ? null : () {},
                    child: Text(_busy ? 'sealing…' : 'Seal it in'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
