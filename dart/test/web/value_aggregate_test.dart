// Unit tests for the web wallet's UTxO → Value aggregation (getBalance core).
//
// Pure Dart — no FFI, no js_interop, no browser — so it runs on the VM test
// runner. Covers the one piece of new web-wallet logic the in-browser harness
// deliberately skips (it excludes network ops). `valueToCborHex` itself is
// conformance-gated; this pins the summing/dedup glue that feeds it.
import 'package:cardano_flutter_rs/src/providers/blockfrost.dart';
import 'package:cardano_flutter_rs/src/web/value_aggregate.dart';
import 'package:flutter_test/flutter_test.dart';

Utxo _utxo({
  required BigInt coin,
  Map<String, Map<String, BigInt>> assets = const {},
  String txHash = '00',
  int index = 0,
}) =>
    Utxo(
      txHash: txHash,
      outputIndex: index,
      address: 'addr_test1xxx',
      coin: coin,
      assets: assets,
    );

void main() {
  const policyA = 'aa11111111111111111111111111111111111111111111111111aaaa';
  const policyB = 'bb22222222222222222222222222222222222222222222222222bbbb';
  const nameX = '58'; // "X"
  const nameY = '59'; // "Y"

  test('empty UTxO set → zero coin, no assets', () {
    final agg = aggregateUtxos(const []);
    expect(agg.coin, BigInt.zero);
    expect(agg.assets, isEmpty);
  });

  test('ADA-only across multiple UTxOs sums coin, no assets', () {
    final agg = aggregateUtxos([
      _utxo(coin: BigInt.from(1000000), index: 0),
      _utxo(coin: BigInt.from(2500000), index: 1),
    ]);
    expect(agg.coin, BigInt.from(3500000));
    expect(agg.assets, isEmpty);
  });

  test('same (policy, asset) across UTxOs is summed, not duplicated', () {
    final agg = aggregateUtxos([
      _utxo(coin: BigInt.from(1000000), index: 0, assets: {
        policyA: {nameX: BigInt.from(5)},
      }),
      _utxo(coin: BigInt.from(1000000), index: 1, assets: {
        policyA: {nameX: BigInt.from(7)},
      }),
    ]);
    expect(agg.coin, BigInt.from(2000000));
    expect(agg.assets, hasLength(1));
    expect(agg.assets.single,
        (policyId: policyA, assetName: nameX, quantity: BigInt.from(12)));
  });

  test('multiple policies/assets aggregate with deterministic order', () {
    final agg = aggregateUtxos([
      _utxo(coin: BigInt.zero, index: 0, assets: {
        policyB: {nameX: BigInt.from(1)},
        policyA: {
          nameY: BigInt.from(2),
          nameX: BigInt.from(3),
        },
      }),
    ]);
    // Sorted by policy id, then asset name: A/X, A/Y, B/X.
    expect(agg.assets, [
      (policyId: policyA, assetName: nameX, quantity: BigInt.from(3)),
      (policyId: policyA, assetName: nameY, quantity: BigInt.from(2)),
      (policyId: policyB, assetName: nameX, quantity: BigInt.from(1)),
    ]);
  });

  test('large quantities use BigInt without overflow', () {
    final big = BigInt.parse('9000000000000000000'); // > 2^63
    final agg = aggregateUtxos([
      _utxo(coin: BigInt.zero, assets: {
        policyA: {nameX: big},
      }),
      _utxo(coin: BigInt.zero, index: 1, assets: {
        policyA: {nameX: big},
      }),
    ]);
    expect(agg.assets.single.quantity, big * BigInt.two);
  });

  test('net-zero asset quantity is dropped', () {
    final agg = aggregateUtxos([
      _utxo(coin: BigInt.from(1000000), assets: {
        policyA: {nameX: BigInt.zero},
      }),
    ]);
    expect(agg.coin, BigInt.from(1000000));
    expect(agg.assets, isEmpty);
  });
}
