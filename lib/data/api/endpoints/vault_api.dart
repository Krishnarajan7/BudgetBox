import '../api_client.dart';
import 'wire.dart';

/// Zero-knowledge at rest. The server only ever sees a nonce and a ciphertext
/// blob; title and body exist decrypted in memory on the phone and nowhere
/// else. A forgotten passphrase is permanent loss — by design.
class VaultApi {
  const VaultApi(this._c);

  final BbxClient _c;

  Future<List<VaultItemOut>> list() async =>
      wireList(await _c.get('/v1/vault'), VaultItemOut.fromJson);

  Future<VaultItemOut> upsert(String id, VaultItemIn body) async =>
      VaultItemOut.fromJson(
        wireObject(await _c.put('/v1/vault/$id', body.toJson())),
      );

  Future<void> delete(String id) => _c.delete('/v1/vault/$id');
}

class VaultItemOut {
  const VaultItemOut({
    required this.id,
    required this.nonce,
    required this.cipher,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String nonce;
  final String cipher;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory VaultItemOut.fromJson(Map<String, dynamic> json) => VaultItemOut(
        id: json.text('id'),
        nonce: json.text('nonce'),
        cipher: json.text('cipher'),
        createdAt: json.instant('created_at'),
        updatedAt: json.instant('updated_at'),
      );
}

class VaultItemIn {
  const VaultItemIn({
    required this.nonce,
    required this.cipher,
    this.expectedUpdatedAt,
  });

  final String nonce;
  final String cipher;

  /// Optimistic concurrency: pass the `updated_at` the edit was based on and
  /// the server refuses the write if the row moved underneath it. The one
  /// place blind retry is wrong — a clobbered secret cannot be recovered from
  /// an activity log, because there isn't one.
  final DateTime? expectedUpdatedAt;

  Map<String, dynamic> toJson() => (WireBody()
        ..set('nonce', nonce)
        ..set('cipher', cipher)
        ..maybe('expected_updated_at', wireInstantOrNull(expectedUpdatedAt)))
      .build();
}
