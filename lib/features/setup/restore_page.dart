import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pen_marks.dart';
import '../../data/api/api_config.dart';
import '../../data/providers.dart';
import '../../data/sync/sync_engine.dart';
import '../lock/lock_page.dart';

/// The other door out of the first launch: *I have done this before.*
///
/// Without it, reinstalling meant walking the whole ritual again and hoping
/// the account names matched the ones upstream closely enough for the adopter
/// to marry them. That is a re-enactment, not a restore. Here the book simply
/// comes back: address, token, one pull, done.
///
/// What comes down is everything the server holds — entries, accounts,
/// budgets, goals, notes, journal, focus, events, the vault — plus the
/// preferences that travel. The PIN does not: it guards a device, not a book,
/// and is set again in Settings.
class RestorePage extends ConsumerStatefulWidget {
  const RestorePage({super.key});

  @override
  ConsumerState<RestorePage> createState() => _RestorePageState();
}

enum _Phase { asking, working, refused, empty }

class _RestorePageState extends ConsumerState<RestorePage> {
  final _url = TextEditingController();
  final _token = TextEditingController();

  _Phase _phase = _Phase.asking;

  /// What the page is saying about itself right now.
  String? _note;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  BbxConfig get _typed => BbxConfig(
        baseUrl: _url.text.trim().replaceAll(RegExp(r'/+$'), ''),
        token: _token.text.trim(),
      );

  Future<void> _restore() async {
    final config = _typed;
    if (!config.wired) {
      setState(() {
        _phase = _Phase.refused;
        _note = 'both the address and the token are needed';
      });
      return;
    }

    setState(() {
      _phase = _Phase.working;
      _note = 'reaching ${config.host}…';
    });

    // Prove the door opens before writing anything down.
    final problem = await SyncEngine.probe(config);
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _phase = _Phase.refused;
        _note = problem;
      });
      return;
    }

    final settings = ref.read(settingsRepoProvider);
    await settings.setServer(config.baseUrl, config.token);
    if (!mounted) return;

    setState(() => _note = 'taking the book back…');
    final engine = ref.read(syncEngineProvider)..reconfigure(config);
    await engine.syncNow();
    if (!mounted) return;

    final status = engine.status.value;
    if (status.phase == SyncPhase.offline || status.phase == SyncPhase.blocked) {
      setState(() {
        _phase = _Phase.refused;
        _note = status.lastError ?? 'the server stopped answering mid-way';
      });
      return;
    }

    final brought = await _countBack();
    if (!mounted) return;

    // An empty server is not a restore. The address is kept — whatever is
    // written from here will sync to it — but the ritual still has to happen.
    if (brought == 0) {
      setState(() {
        _phase = _Phase.empty;
        _note = 'that book is empty. The address is saved, so start a new '
            'book and it will keep itself there from now on.';
      });
      return;
    }

    // The server may predate the settings sync and hold no `setupDone`. It
    // plainly holds a book, though, so this phone is past its first launch.
    await settings.markSetupDone();
    if (!mounted) return;

    HapticFeedback.mediumImpact();
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 350),
        pageBuilder: (_, _, _) => const LockPage(),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
      (route) => false,
    );
  }

  /// How much of a book actually landed. Categories are excluded on purpose:
  /// both halves seed the same ten, so they prove nothing about whether
  /// anything came back.
  Future<int> _countBack() async {
    final db = ref.read(dbProvider);
    final counts = await Future.wait<int>([
      db.select(db.txns).get().then((r) => r.length),
      db.select(db.accounts).get().then((r) => r.length),
      db.select(db.budgets).get().then((r) => r.length),
      db.select(db.goals).get().then((r) => r.length),
      db.select(db.notes).get().then((r) => r.length),
      db.select(db.journalEntries).get().then((r) => r.length),
    ]);
    return counts.fold<int>(0, (a, b) => a + b);
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    final working = _phase == _Phase.working;
    final note = _note;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: Gap.x3),
                child: Row(
                  children: [
                    Text(
                      'the book comes back',
                      style: LedgerType.amount
                          .copyWith(fontSize: 12, color: c.inkFaint),
                    ),
                    const Spacer(),
                    if (!working)
                      Pressable(
                        onTap: () => Navigator.of(context).pop(),
                        child: Padding(
                          padding: const EdgeInsets.all(Gap.x1),
                          child:
                              PenCross(size: 15, color: c.inkFaint),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: Gap.x8),
                      InkIn(
                        child: Text(
                          'Where does it live?',
                          style: LedgerType.title
                              .copyWith(fontSize: 28, color: c.ink),
                        ),
                      ),
                      const SizedBox(height: Gap.x4),
                      InkIn(
                        delay: const Duration(milliseconds: 90),
                        child: _field(c, _url, 'https://…', enabled: !working),
                      ),
                      const SizedBox(height: Gap.x3),
                      InkIn(
                        delay: const Duration(milliseconds: 150),
                        child: _field(c, _token, 'bbx_…',
                            obscure: true, enabled: !working),
                      ),
                      const SizedBox(height: Gap.x3),
                      InkIn(
                        delay: const Duration(milliseconds: 210),
                        child: Text(
                          'The address of the book’s other half, and the one '
                          'token that opens it. Your lock is not kept there — '
                          'set a new PIN once you are back in.',
                          style: LedgerType.bodyText
                              .copyWith(fontSize: 13, color: c.inkFaint),
                        ),
                      ),
                      if (note != null) ...[
                        const SizedBox(height: Gap.x4),
                        Text(
                          note,
                          style: LedgerType.bodyText.copyWith(
                            fontSize: 13,
                            color: switch (_phase) {
                              _Phase.refused => c.seal,
                              _Phase.empty => c.warn,
                              _ => c.inkFaint,
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: Gap.x6),
                    ],
                  ),
                ),
              ),
              Pressable(
                onTap: working ? null : _restore,
                scale: 0.98,
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: working ? c.inkFaint : c.quill,
                    borderRadius: BorderRadius.circular(Corner.key),
                  ),
                  child: Text(
                    working ? 'bringing it back…' : 'Bring it back',
                    style: LedgerType.bodyStrong.copyWith(color: c.paper),
                  ),
                ),
              ),
              const SizedBox(height: Gap.x6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    LedgerColors c,
    TextEditingController controller,
    String hint, {
    bool obscure = false,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.url,
      style: LedgerType.bodyText.copyWith(fontSize: 16, color: c.ink),
      cursorColor: c.quill,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: LedgerType.bodyText.copyWith(
          fontSize: 16,
          color: c.inkFaint.withValues(alpha: 0.6),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.quill, width: 2),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.quill, width: 2),
        ),
        disabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: c.rule),
        ),
      ),
    );
  }
}
