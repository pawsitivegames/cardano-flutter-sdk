// Pure (no FFI / no js_interop) UTxO → Value aggregation for the web wallet.
//
// Split out of `web_cip30_wallet.dart` precisely so it can be unit-tested on the
// Dart VM: that file imports `dart:js_interop` (web-only) and can't run under the
// VM test runner, but the balance-summing logic here is plain Dart over the
// already-VM-safe `Utxo` / `ConformanceAsset` types. `getBalance` calls this, then
// serializes the result via the conformance-frozen `valueToCborHex`.
import '../conformance/conformance_contract.dart';
import '../providers/blockfrost.dart';

/// A summed balance: total lovelace [coin] plus per-(policy, asset) [assets].
typedef AggregatedValue = ({BigInt coin, List<ConformanceAsset> assets});

/// Sums a UTxO set into a single [AggregatedValue].
///
/// Adds every UTxO's lovelace into [AggregatedValue.coin] and folds native
/// tokens together by `(policyId, assetName)`, summing quantities across UTxOs.
/// Zero-quantity entries are dropped (a token fully spent in net terms carries no
/// balance). The returned [AggregatedValue.assets] order is deterministic:
/// policy id, then asset name (both ascending). Canonical CBOR ordering is applied
/// downstream by `valueToCborHex`, so this order is purely for test stability.
AggregatedValue aggregateUtxos(List<Utxo> utxos) {
  var coin = BigInt.zero;
  final byPolicy = <String, Map<String, BigInt>>{};
  for (final u in utxos) {
    coin += u.coin;
    u.assets.forEach((policyId, names) {
      final inner = byPolicy.putIfAbsent(policyId, () => <String, BigInt>{});
      names.forEach((assetName, qty) {
        inner[assetName] = (inner[assetName] ?? BigInt.zero) + qty;
      });
    });
  }

  final assets = <ConformanceAsset>[];
  final policyIds = byPolicy.keys.toList()..sort();
  for (final policyId in policyIds) {
    final names = byPolicy[policyId]!;
    final assetNames = names.keys.toList()..sort();
    for (final assetName in assetNames) {
      final qty = names[assetName]!;
      if (qty == BigInt.zero) continue;
      assets.add((policyId: policyId, assetName: assetName, quantity: qty));
    }
  }

  return (coin: coin, assets: assets);
}
