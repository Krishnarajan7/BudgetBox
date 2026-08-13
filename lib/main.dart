import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/sync/sync_driver.dart';
import 'features/settings/settings_page.dart';
import 'features/splash/splash_screen.dart';

void main() {
  runApp(const ProviderScope(child: BudgetBoxApp()));
}

class BudgetBoxApp extends ConsumerWidget {
  const BudgetBoxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Krish Space',
      debugShowCheckedModeBanner: false,
      theme: ledgerDayTheme(),
      darkTheme: ledgerNightTheme(),
      themeMode: ref.watch(themeModeProvider),
      // Day turns to lamplight, it doesn't snap: the whole palette lerps.
      themeAnimationDuration: const Duration(milliseconds: 350),
      themeAnimationCurve: Curves.easeOutCubic,
      // Draws nothing; decides when the queue drains. See SyncDriver.
      home: const SyncDriver(child: SplashScreen()),
    );
  }
}
