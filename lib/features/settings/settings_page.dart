import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tokens.dart';
import '../../core/typography.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../../data/providers.dart';
import '../setup/setup_flow.dart';
import 'account_manager.dart';
import 'category_manager.dart';
import 'pinned_manager.dart';

/// Day / night / follow-the-sun — persisted in the settings table, loaded on
/// first read so the book keeps its light across launches.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    ref.read(settingsRepoProvider).themeMode().then((saved) {
      final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
      if (mode != null && mode != state) state = mode;
    });
    return ThemeMode.system;
  }

  void set(ThemeMode mode) {
    state = mode;
    ref.read(settingsRepoProvider).setThemeMode(mode.name);
  }
}

/// The box — settings by intent, never an A–Z toggle dump.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, _, _) => page,
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
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = LedgerColors.of(context);
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: Gap.page),
          children: [
            Padding(
              padding: const EdgeInsets.only(top: Gap.x2),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.arrow_back, size: 18, color: c.inkFaint),
                  ),
                  const SizedBox(width: Gap.x3),
                  Text(
                    'the box',
                    style: LedgerType.wordmark.copyWith(color: c.ink),
                  ),
                ],
              ),
            ),
            const RuleHeader('appearance'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.x2),
              child: Row(
                children: [
                  for (final (m, icon, label) in const [
                    (ThemeMode.light, Icons.light_mode_outlined, 'day'),
                    (ThemeMode.dark, Icons.dark_mode_outlined, 'night'),
                    (
                      ThemeMode.system,
                      Icons.brightness_auto_outlined,
                      'follow the sun',
                    ),
                  ]) ...[
                    LedgerChip(
                      label,
                      icon: icon,
                      selected: mode == m,
                      onTap: () => ref.read(themeModeProvider.notifier).set(m),
                    ),
                    const SizedBox(width: Gap.x2),
                  ],
                ],
              ),
            ),
            const RuleHeader('my book'),
            _Row('Categories', 'your words, your marks',
                onTap: () => _push(context, const CategoryManagerPage())),
            _Row('Accounts', 'banks, cash, cards',
                onTap: () => _push(context, const AccountManagerPage())),
            _Row('Pinned entries', 'the one-tap repeats',
                onTap: () => _push(context, const PinnedManagerPage())),
            const RuleHeader('rhythm'),
            const _Row('Salary day', '1st of the month'),
            const _Row('Year', 'FY April–March'),
            const RuleHeader('lock'),
            const _PinRow(),
            const _Row('Face ID', 'tries first when a PIN is set'),
            const RuleHeader('the data'),
            const _Row('Export', 'CSV, any time'),
            const _Row('Backup', 'one file, yours'),
            const _Row('Activity log', 'every stroke, undoable'),
            const RuleHeader('the ritual'),
            _Row(
              'Run the setup ritual',
              'preview the first-launch flow',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SetupFlow()),
              ),
            ),
            const SizedBox(height: Gap.x8),
            Center(
              child: Text(
                'home-cooked, for one · since July 2026',
                style: LedgerType.bodyText.copyWith(
                  fontSize: 12,
                  color: c.inkFaint,
                ),
              ),
            ),
            const SizedBox(height: Gap.x6),
          ],
        ),
      ),
    );
  }
}

/// Set, change, or remove the 4-digit PIN that closes the book.
class _PinRow extends ConsumerStatefulWidget {
  const _PinRow();

  @override
  ConsumerState<_PinRow> createState() => _PinRowState();
}

class _PinRowState extends ConsumerState<_PinRow> {
  bool? _hasPin;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final has = await ref.read(settingsRepoProvider).hasPin();
    if (mounted) setState(() => _hasPin = has);
  }

  Future<void> _setPin() async {
    final c = LedgerColors.of(context);
    final controller = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: Gap.page,
          right: Gap.page,
          top: Gap.x4,
          bottom: MediaQuery.of(context).viewInsets.bottom + Gap.x4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Four digits. Only your book, only you.',
              style: LedgerType.bodyStrong.copyWith(color: c.ink),
            ),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              style: LedgerType.heroAmount.copyWith(
                fontSize: 32,
                color: c.ink,
                letterSpacing: 12,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                counterText: '',
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Lock it down'),
            ),
            if (_hasPin == true)
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Remove the PIN instead'),
              ),
          ],
        ),
      ),
    );
    final settings = ref.read(settingsRepoProvider);
    if (saved == true) {
      final pin = controller.text.trim();
      if (pin.length == 4 && int.tryParse(pin) != null) {
        await settings.setPin(pin);
      }
    } else if (saved == false && _hasPin == true) {
      await settings.clearPin();
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return _Row('PIN', switch (_hasPin) {
      null => '…',
      true => 'set — tap to change',
      false => 'not set — tap to add',
    }, onTap: _setPin);
  }
}

class _Row extends StatelessWidget {
  const _Row(this.title, this.sub, {this.onTap});

  final String title;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = LedgerColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: Gap.x3),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.rule)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: LedgerType.bodyText.copyWith(color: c.ink),
              ),
            ),
            Text(
              sub,
              style: LedgerType.bodyText.copyWith(
                fontSize: 12,
                color: c.inkFaint,
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: Gap.x2),
              Icon(Icons.chevron_right, size: 16, color: c.inkFaint),
            ],
          ],
        ),
      ),
    );
  }
}
