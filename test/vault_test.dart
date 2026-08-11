import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/data/repos/vault_repo.dart';
import 'package:budgetbox/features/vault/vault_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LedgerDb db;
  late VaultRepo vault;

  setUp(() {
    db = LedgerDb.forTesting(NativeDatabase.memory());
    // Low iterations: tests exercise correctness, not key-stretching cost.
    vault = VaultRepo(db, iterations: 100);
  });

  tearDown(() => db.close());

  test('starts un-set-up; setUp seals it', () async {
    expect(await vault.isSetUp(), isFalse);
    await vault.setUp('correct horse battery');
    expect(await vault.isSetUp(), isTrue);
  });

  test('right passphrase opens, wrong one does not', () async {
    await vault.setUp('correct horse battery');
    expect(await vault.unlock('correct horse battery'), isNotNull);
    expect(await vault.unlock('wrong horse'), isNull);
    expect(await vault.unlock(''), isNull);
  });

  test('round-trips items, ciphertext only at rest', () async {
    final key = await vault.setUp('correct horse battery');
    await vault.addItem(key, title: 'Aadhaar', body: '1234 5678 9012');
    await vault.addItem(key, title: 'Wifi', body: 'chai-at-ganeshs');

    final items = await vault.readAll(key);
    expect(items.map((i) => i.title), containsAll(['Aadhaar', 'Wifi']));
    expect(items.firstWhere((i) => i.title == 'Aadhaar').body,
        '1234 5678 9012');

    // Nothing legible in the database rows themselves.
    final rows = await db.select(db.vaultItems).get();
    for (final row in rows) {
      expect(row.cipher.contains('Aadhaar'), isFalse);
      expect(row.cipher.contains('1234'), isFalse);
      expect(row.nonce.contains('Wifi'), isFalse);
    }
  });

  test('update re-encrypts under a fresh nonce', () async {
    final key = await vault.setUp('correct horse battery');
    final id = await vault.addItem(key, title: 'card pin', body: '0000');
    final before = (await db.select(db.vaultItems).get()).single;

    await vault.updateItem(key, id, title: 'card pin', body: '9999');
    final after = (await db.select(db.vaultItems).get()).single;
    expect(after.nonce, isNot(before.nonce));
    expect(after.cipher, isNot(before.cipher));

    final items = await vault.readAll(key);
    expect(items.single.body, '9999');
  });

  test('delete burns the page', () async {
    final key = await vault.setUp('correct horse battery');
    final id = await vault.addItem(key, title: 'gone', body: 'soon');
    await vault.deleteItem(id);
    expect(await vault.readAll(key), isEmpty);
    expect(await db.select(db.vaultItems).get(), isEmpty);
  });

  test('a second repo instance with the same passphrase can read it all',
      () async {
    final key = await vault.setUp('correct horse battery');
    await vault.addItem(key, title: 'persists', body: 'across sessions');

    final again = VaultRepo(db, iterations: 100);
    final key2 = await again.unlock('correct horse battery');
    expect(key2, isNotNull);
    final items = await again.readAll(key2!);
    expect(items.single.title, 'persists');
  });

  // ————— the page itself: opening, closing, and walking away —————

  Widget host() => ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          vaultRepoProvider.overrideWithValue(vault),
        ],
        child: MaterialApp(
          theme: ledgerDayTheme(),
          home: const Scaffold(body: VaultPage()),
        ),
      );

  /// Seals a book with one page in it, then opens the vault on screen.
  Future<void> openOnScreen(WidgetTester tester) async {
    final key = await vault.setUp('correct horse battery');
    await vault.addItem(key, title: 'Aadhaar', body: '1234 5678 9012');
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Open the vault'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'correct horse battery');
    await tester.tap(find.text('Open the vault'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aadhaar', findRichText: true), findsOneWidget);
  }

  /// Let the page's own delayed work run out before the test ends.
  Future<void> quiesce(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('the right passphrase stamps the vault open', (tester) async {
    await openOnScreen(tester);
    await quiesce(tester);
  });

  testWidgets('sealing runs its beat and puts the cover back', (tester) async {
    await openOnScreen(tester);

    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aadhaar', findRichText: true), findsNothing);
    expect(find.text('Open the vault'), findsOneWidget);
    await quiesce(tester);
  });

  testWidgets('backgrounding past the grace seals it and says so',
      (tester) async {
    await openOnScreen(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // Away long enough for the vault to shut itself, then back to the app.
    await tester.pump(const Duration(seconds: 21));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.textContaining('Aadhaar', findRichText: true), findsNothing);
    expect(find.text('Open the vault'), findsOneWidget);
    expect(
      find.textContaining('Sealed itself while you were away'),
      findsOneWidget,
    );
    await quiesce(tester);
  });

  testWidgets('a glance away leaves the vault open', (tester) async {
    await openOnScreen(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.textContaining('Aadhaar', findRichText: true), findsOneWidget);
    await quiesce(tester);
  });

  testWidgets('burning from the list asks first, then takes the page',
      (tester) async {
    await openOnScreen(tester);

    await tester.longPress(find.textContaining('Aadhaar', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Burn it'));
    await tester.pumpAndSettle();

    // The confirm sheet stands between the tap and the loss.
    expect(find.text('Burn this page?'), findsOneWidget);
    await tester.tap(find.text('Burn it'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Aadhaar', findRichText: true), findsNothing);
    expect(find.text('Open, and empty.'), findsOneWidget);
    await quiesce(tester);
  });

  testWidgets('long-press copies the secret without opening the page',
      (tester) async {
    await openOnScreen(tester);

    final clipped = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<Object?, Object?>;
          clipped.add(args['text'] as String);
        }
        return null;
      },
    );

    await tester.longPress(find.textContaining('Aadhaar', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('Copy the secret'), findsOneWidget);

    await tester.tap(find.text('Copy the secret'));
    await tester.pumpAndSettle();

    expect(clipped, ['1234 5678 9012']);
    expect(find.text('On the clipboard'), findsOneWidget);
    // The editor never opened — the body stayed off screen.
    expect(find.text('What stays sealed…'), findsNothing);

    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await quiesce(tester);
  });
}
