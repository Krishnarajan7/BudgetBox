import 'dart:convert';

import 'package:budgetbox/core/theme.dart';
import 'package:budgetbox/core/weather.dart';
import 'package:budgetbox/data/db.dart';
import 'package:budgetbox/data/providers.dart';
import 'package:budgetbox/features/weather/weather_page.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the sky page shows the reading and the week ahead',
      (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sky = Weather(
      nowC: 31.6,
      highC: 35,
      lowC: 26,
      code: 2,
      at: now, // fresh, so the page never reaches for the network
      days: [
        for (var i = 0; i < 8; i++)
          DayForecast(
            date: today.add(Duration(days: i)),
            code: i.isEven ? 2 : 61,
            highC: 30 + i.toDouble(),
            lowC: 24,
          ),
      ],
    );
    await db.into(db.settings).insertOnConflictUpdate(
          SettingsCompanion(
            key: const Value('weather'),
            value: Value(jsonEncode(sky.toJson())),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [dbProvider.overrideWithValue(db)],
        child: MaterialApp(theme: ledgerDayTheme(), home: const WeatherPage()),
      ),
    );
    // Let the cached reading land, then walk through the entry motion:
    // the count-up and the staggered ink-ins. pumpAndSettle would never
    // return — the sky itself breathes forever.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 2));

    // The chiselled numeral is layered, so the figure appears many times.
    expect(find.text('32'), findsWidgets);
    expect(find.text('part cloud'), findsOneWidget);
    expect(find.textContaining('high 35°'), findsOneWidget);
    // The week row leads with to-day and carries all eight brackets.
    expect(find.text('today'), findsOneWidget);
    expect(find.text('30°'), findsOneWidget);
    expect(find.text('37°'), findsOneWidget);

    // Tear the page down so the sky's endless breath releases its ticker.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unread sky says so instead of pretending', (tester) async {
    final db = LedgerDb.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(db),
          // A book with no reading and no way to take one.
          weatherRepoProvider.overrideWithValue(
            WeatherRepo(db, locate: () async => null),
          ),
        ],
        child: MaterialApp(theme: ledgerDayTheme(), home: const WeatherPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('the sky is unread'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
