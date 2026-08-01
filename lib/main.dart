import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
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
      title: 'BudgetBox',
      debugShowCheckedModeBanner: false,
      theme: ledgerDayTheme(),
      darkTheme: ledgerNightTheme(),
      themeMode: ref.watch(themeModeProvider),
      home: const SplashScreen(),
    );
  }
}
