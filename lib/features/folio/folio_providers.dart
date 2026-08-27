import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_client.dart';
import '../../data/api/endpoints/endpoints.dart';
import '../../data/providers.dart';
import '../../data/repos/settings_repo.dart';

Future<T> _ask<T>(
  SettingsRepo settings,
  Future<T> Function(FolioApi api) question,
) async {
  final config = await settings.serverConfig();
  if (!config.wired) throw const BbxOffline('not wired');
  final client = BbxClient(config);
  try {
    return await question(FolioApi(client));
  } finally {
    client.close();
  }
}

sealed class FolioGate {
  const FolioGate();
}

class FolioUnwired extends FolioGate {
  const FolioUnwired();
}

class FolioAway extends FolioGate {
  const FolioAway(this.detail);

  final String detail;
}

class FolioOpen extends FolioGate {
  const FolioOpen(this.overview, this.funds);

  final FolioOverview overview;
  final List<Fund> funds;
}

final folioGateProvider = FutureProvider.autoDispose<FolioGate>((ref) async {
  final settings = ref.read(settingsRepoProvider);
  final config = await settings.serverConfig();
  if (!config.wired) return const FolioUnwired();
  try {
    final result = await _ask(
      settings,
      (api) async => (await api.overview(), await api.funds()),
    );
    return FolioOpen(result.$1, result.$2);
  } on BbxOffline catch (e) {
    return FolioAway(e.detail);
  } on BbxProblem catch (e) {
    return FolioAway(e.detail);
  }
});

final folioSeriesProvider = FutureProvider.autoDispose<List<FolioPoint>>(
  (ref) => _ask(ref.read(settingsRepoProvider), (api) => api.series()),
);

final fundProvider = FutureProvider.autoDispose
    .family<(Fund, List<FolioEntry>), String>((ref, id) async {
      final settings = ref.read(settingsRepoProvider);
      return _ask(settings, (api) async => (await api.fund(id), await api.entries(id)));
    });

/// Live search over AMFI's file. Debounced by the field, not here.
final schemeSearchProvider = FutureProvider.autoDispose
    .family<List<Scheme>, String>((ref, query) async {
      if (query.trim().length < 3) return const [];
      try {
        return await _ask(
          ref.read(settingsRepoProvider),
          (api) => api.schemes(query),
        );
      } on BbxProblem {
        return const [];
      }
    });

/// The compact figures the Worth page shows without opening the folio.
final folioSummaryProvider = FutureProvider.autoDispose<FolioOverview?>((
  ref,
) async {
  final gate = await ref.watch(folioGateProvider.future);
  return gate is FolioOpen ? gate.overview : null;
});

class FolioWriter {
  const FolioWriter(this._settings);

  final SettingsRepo _settings;

  Future<Fund> addFund(String id, FundIn body) =>
      _ask(_settings, (api) => api.addFund(id, body));

  Future<void> stamp(String id, FolioMoveIn body) =>
      _ask(_settings, (api) => api.contribute(id, body));

  Future<void> redeem(String id, FolioMoveIn body) =>
      _ask(_settings, (api) => api.redeem(id, body));

  Future<void> setValue(String id, int paise) =>
      _ask(_settings, (api) => api.setValue(id, paise));

  Future<void> refresh() => _ask(_settings, (api) => api.refresh());

  Future<void> archive(String id) =>
      _ask(_settings, (api) => api.patchFund(id, const FundPatch(archived: true)));
}

final folioWriterProvider = Provider<FolioWriter>(
  (ref) => FolioWriter(ref.watch(settingsRepoProvider)),
);
