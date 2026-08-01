import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../core/widgets/module_scaffold.dart';
import '../../core/widgets/seal.dart';
import '../../data/repos/vault_repo.dart';

/// The sealed book. Opens with a passphrase, never a toast; the key lives in
/// this page's state and dies when the page does.
class VaultPage extends ConsumerStatefulWidget {
  const VaultPage({super.key});

  @override
  ConsumerState<VaultPage> createState() => _VaultPageState();
}

enum _VaultState { checking, needsSetup, locked, open }

class _VaultPageState extends ConsumerState<VaultPage>
    with SingleTickerProviderStateMixin {
  _VaultState _state = _VaultState.checking;
  SecretKey? _key;
  List<VaultOpenItem> _items = const [];
  bool _busy = false;
  bool _wrong = false;

  final _pass = TextEditingController();
  final _confirm = TextEditingController();

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    // The key dies with the page — the vault re-seals itself.
    _shake.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final setUp = await ref.read(vaultRepoProvider).isSetUp();
    if (!mounted) return;
    setState(
        () => _state = setUp ? _VaultState.locked : _VaultState.needsSetup);
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
    if (_busy || _pass.text.isEmpty) return;
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
    HapticFeedback.mediumImpact();
    _pass.clear();
    setState(() {
      _key = key;
      _items = items;
      _busy = false;
      _state = _VaultState.open;
    });
  }

  void _sealNow() {
    HapticFeedback.lightImpact();
    setState(() {
      _key = null;
      _items = const [];
      _state = _VaultState.locked;
    });
  }

  Future<void> _reload() async {
    final key = _key;
    if (key == null) return;
    final items = await ref.read(vaultRepoProvider).readAll(key);
    if (mounted) setState(() => _items = items);
  }

  Future<void> _edit([VaultOpenItem? item]) async {
    final key = _key;
    if (key == null) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => _VaultEditor(vaultKey: key, item: item),
        transitionsBuilder: (_, anim, _, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.02),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return ModuleScaffold(
      title: 'Vault',
      trailing: _state == _VaultState.open
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _edit(),
                  child: Icon(Icons.add, size: 18, color: c.inkFaint),
                ),
                const SizedBox(width: Gap.x4),
                InkWell(
                  onTap: _sealNow,
                  child:
                      Icon(Icons.lock_outline, size: 17, color: c.inkFaint),
                ),
              ],
            )
          : null,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
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

  Widget _passField(LedgerColors c, TextEditingController controller,
      String hint, VoidCallback onSubmit) {
    return TextField(
      controller: controller,
      obscureText: true,
      autofocus: true,
      onSubmitted: (_) => onSubmit(),
      style: LedgerType.bodyText.copyWith(color: c.ink, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            LedgerType.bodyText.copyWith(fontSize: 16, color: c.inkFaint),
        enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: _wrong ? c.seal : c.rule)),
        focusedBorder: UnderlineInputBorder(
            borderSide:
                BorderSide(color: _wrong ? c.seal : c.quill, width: 1.6)),
      ),
    );
  }

  Widget _setup(LedgerColors c) {
    return ListView(
      key: const ValueKey('setup'),
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x8, Gap.page, Gap.x6),
      children: [
        Text('Seal a vault.',
            style: LedgerType.title.copyWith(fontSize: 28, color: c.ink)),
        const SizedBox(height: Gap.x2),
        Text(
          'Whatever goes in is encrypted with a passphrase only you know. '
          'Lose the passphrase and what is inside is gone — there is no '
          'reset, no recovery, no back door. That is the point.',
          style:
              LedgerType.bodyText.copyWith(fontSize: 13, color: c.inkFaint),
        ),
        const SizedBox(height: Gap.x6),
        _shakeWrap(Column(
          children: [
            _passField(c, _pass, 'a passphrase, six characters or more',
                () {}),
            const SizedBox(height: Gap.x3),
            _passField(c, _confirm, 'and again, to be sure', _setUp),
          ],
        )),
        SizedBox(
          height: 24,
          child: _wrong
              ? Padding(
                  padding: const EdgeInsets.only(top: Gap.x2),
                  child: Text(
                    _pass.text.length < 6
                        ? 'Six characters at least — it guards everything.'
                        : 'They do not match yet.',
                    style: LedgerType.bodyText
                        .copyWith(fontSize: 12, color: c.seal),
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
    return ListView(
      key: const ValueKey('locked'),
      padding: const EdgeInsets.fromLTRB(Gap.page, Gap.x12, Gap.page, Gap.x6),
      children: [
        Center(
          child: Seal(
            size: 56,
            child: Icon(Icons.lock_outline, size: 22, color: c.seal),
          ),
        ),
        const SizedBox(height: Gap.x6),
        _shakeWrap(
            _passField(c, _pass, 'the passphrase', _unlock)),
        SizedBox(
          height: 24,
          child: _wrong
              ? Padding(
                  padding: const EdgeInsets.only(top: Gap.x2),
                  child: Text('Not it.',
                      style: LedgerType.bodyText
                          .copyWith(fontSize: 12, color: c.seal)),
                )
              : null,
        ),
        const SizedBox(height: Gap.x4),
        FilledButton(
          onPressed: _unlock,
          child: Text(_busy ? 'opening…' : 'Open the vault'),
        ),
      ],
    );
  }

  Widget _openView(LedgerColors c) {
    return ListView(
      key: const ValueKey('open'),
      padding:
          const EdgeInsets.fromLTRB(Gap.page, Gap.x4, Gap.page, Gap.x6),
      children: [
        if (_items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Gap.x8),
            child: Text(
              'Open, and empty. Whatever you seal in here stays between '
              'you and the passphrase.',
              style: LedgerType.bodyText
                  .copyWith(fontSize: 13, color: c.inkFaint),
            ),
          )
        else ...[
          Text('unsealed, for now',
              style: LedgerType.label.copyWith(color: c.inkFaint)),
          const SizedBox(height: Gap.x2),
          for (final (i, item) in _items.indexed)
            LedgerLine(
              title: item.title.isEmpty ? '(untitled)' : item.title,
              detail:
                  '${item.updatedAt.day}/${item.updatedAt.month}',
              amount: '',
              last: i == _items.length - 1,
              onTap: () => _edit(item),
            ),
        ],
      ],
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
    setState(() => _busy = true);
    final repo = ref.read(vaultRepoProvider);
    if (widget.item == null) {
      await repo.addItem(widget.vaultKey,
          title: _title.text.trim(), body: _body.text);
    } else {
      await repo.updateItem(widget.vaultKey, widget.item!.id,
          title: _title.text.trim(), body: _body.text);
    }
    if (!mounted) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final item = widget.item;
    if (item == null) return;
    final c = LedgerColors.of(context);
    final sure = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Gap.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Burn this page?',
                  style:
                      LedgerType.title.copyWith(fontSize: 22, color: c.ink)),
              const SizedBox(height: Gap.x2),
              Text('There is no undo inside the vault.',
                  style: LedgerType.bodyText
                      .copyWith(fontSize: 13, color: c.inkFaint)),
              const SizedBox(height: Gap.x4),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: c.seal),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Burn it'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep it'),
              ),
            ],
          ),
        ),
      ),
    );
    if (sure == true) {
      await ref.read(vaultRepoProvider).deleteItem(item.id);
      if (mounted) Navigator.of(context).pop();
    }
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
              padding:
                  const EdgeInsets.fromLTRB(Gap.page, Gap.x2, Gap.page, 0),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child:
                        Icon(Icons.arrow_back, size: 18, color: c.inkFaint),
                  ),
                  const Spacer(),
                  if (widget.item != null)
                    InkWell(
                      onTap: _delete,
                      child: Icon(Icons.delete_outline,
                          size: 18, color: c.inkFaint),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: Gap.page),
                children: [
                  TextField(
                    controller: _title,
                    style: LedgerType.title
                        .copyWith(fontSize: 24, color: c.ink),
                    decoration: InputDecoration(
                      hintText: 'Untitled',
                      hintStyle: LedgerType.title
                          .copyWith(fontSize: 24, color: c.inkFaint),
                      border: InputBorder.none,
                    ),
                  ),
                  TextField(
                    controller: _body,
                    maxLines: null,
                    style: LedgerType.bodyText
                        .copyWith(fontSize: 15, height: 1.55, color: c.ink),
                    decoration: InputDecoration(
                      hintText: 'What stays sealed…',
                      hintStyle: LedgerType.bodyText.copyWith(
                          fontSize: 15, height: 1.55, color: c.inkFaint),
                      border: InputBorder.none,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.page),
              child: FilledButton(
                onPressed: _save,
                child: Text(_busy ? 'sealing…' : 'Seal it in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
