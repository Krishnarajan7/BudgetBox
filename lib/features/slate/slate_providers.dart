import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/api/endpoints/endpoints.dart';
import '../../data/providers.dart';
import '../../data/repos/settings_repo.dart';

/// The slate lives on the server, like the music book: the arithmetic that
/// keeps lending out of spending belongs next to the ledger it moves, not in
/// two implementations that can drift.

Future<T> _ask<T>(
  SettingsRepo settings,
  Future<T> Function(SlateApi api) question,
) async {
  final config = await settings.serverConfig();
  if (!config.wired) throw const BbxOffline('not wired');
  final client = BbxClient(config);
  try {
    return await question(SlateApi(client));
  } finally {
    client.close();
  }
}

/// What the door finds.
sealed class SlateGate {
  const SlateGate();
}

class SlateUnwired extends SlateGate {
  const SlateUnwired();
}

class SlateAway extends SlateGate {
  const SlateAway(this.detail);

  final String detail;
}

class SlateOpen extends SlateGate {
  const SlateOpen(this.overview, this.people);

  final SlateOverview overview;
  final List<SlatePerson> people;
}

final slateGateProvider = FutureProvider.autoDispose<SlateGate>((ref) async {
  final settings = ref.read(settingsRepoProvider);
  final config = await settings.serverConfig();
  if (!config.wired) return const SlateUnwired();
  try {
    final result = await _ask(
      settings,
      (api) async => (await api.overview(), await api.people()),
    );
    final (overview, people) = result;
    // The shelf's spine line, cached so the shelf never makes a call of
    // its own.
    await settings.setSlateLine(_spineLine(overview));
    return SlateOpen(overview, people);
  } on BbxOffline catch (e) {
    return SlateAway(e.detail);
  } on BbxProblem catch (e) {
    return SlateAway(e.detail);
  }
});

String _spineLine(SlateOverview o) {
  if (o.netPaise == 0 && o.owedToYouPaise == 0 && o.youOwePaise == 0) {
    return 'clean';
  }
  final parts = <String>[];
  if (o.owedToYouPaise > 0) {
    parts.add('₹${(o.owedToYouPaise / 100).round()} out');
  }
  if (o.youOwePaise > 0) {
    parts.add('₹${(o.youOwePaise / 100).round()} owed');
  }
  return parts.join(' · ');
}

final slatePersonProvider = FutureProvider.autoDispose
    .family<(SlatePerson, List<SlateEntry>), String>((ref, id) async {
      final settings = ref.read(settingsRepoProvider);
      return _ask(
        settings,
        (api) async => (await api.person(id), await api.entries(id)),
      );
    });

final adoptableProvider = FutureProvider.autoDispose<List<Adoptable>>(
  (ref) => _ask(ref.read(settingsRepoProvider), (api) => api.adoptable()),
);

/// Everything that writes. Each returns nothing and throws on refusal — the
/// caller decides what the screen says.
class SlateWriter {
  const SlateWriter(this._settings);

  final SettingsRepo _settings;

  Future<SlatePerson> addPerson(String id, PersonIn body) =>
      _ask(_settings, (api) => api.upsertPerson(id, body));

  Future<void> lend(String id, MoveIn body) =>
      _ask(_settings, (api) => api.lend(id, body));

  Future<void> borrow(String id, MoveIn body) =>
      _ask(_settings, (api) => api.borrow(id, body));

  Future<void> repay(String id, MoveIn body) =>
      _ask(_settings, (api) => api.repay(id, body));

  Future<void> close(String id, {int? amountPaise}) =>
      _ask(_settings, (api) => api.close(id, amountPaise: amountPaise));

  Future<void> adopt(String id, String txnId) =>
      _ask(_settings, (api) => api.adopt(id, txnId));

  Future<void> archive(String id, {required bool archived}) => _ask(
    _settings,
    (api) => api.patchPerson(id, PersonPatch(archived: archived)),
  );
}

final slateWriterProvider = Provider<SlateWriter>(
  (ref) => SlateWriter(ref.watch(settingsRepoProvider)),
);
