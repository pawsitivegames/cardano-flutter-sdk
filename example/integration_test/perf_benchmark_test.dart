// Integration-test harness logs timings to stdout; print is appropriate here.
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Phase 6 performance pass.
///
/// Measures the latency budget the PLAN sets for the SDK's hot paths, against
/// live testnet-preview Blockfrost + the real Rust FFI build (run on macOS):
///   • UTxO fetch (REST)            target < 2000 ms
///   • coin selection + tx build    target <  500 ms  (the FFI hot path)
///
/// Also re-runs the build path N times to surface any gross per-call leak /
/// growth (a smoke check, not a profiler).
///
/// Live-only: needs BLOCKFROST_PROJECT_ID. Run on macOS so the timings reflect
/// the packaged framework, not the host test dylib:
///   cd example && BLOCKFROST_PROJECT_ID=KEY \
///     flutter test integration_test/perf_benchmark_test.dart -d macos
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final projectId = Platform.environment['BLOCKFROST_PROJECT_ID'];
  final isLive = projectId != null && projectId.isNotEmpty;
  // testWidgets.skip is bool-only; the reason lives in the doc comment above.

  // A funded testnet-preview address — the enterprise address the example app
  // itself sends from (see example/lib/main.dart).
  const fundedAddress =
      'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz';

  // Budgets from docs/PLAN.md Phase 6.
  const fetchBudgetMs = 2000;
  const buildBudgetMs = 500;

  testWidgets('hot-path latency within Phase 6 budgets', skip: !isLive,
      (tester) async {
    await RustLib.init();

    final provider = BlockfrostProvider(
      projectId: projectId!,
      network: Network.testnetPreview,
    );

    // --- protocol params (warms the REST client) ---
    final pSw = Stopwatch()..start();
    final params = await provider.fetchProtocolParameters();
    pSw.stop();

    // --- UTxO fetch ---
    final fSw = Stopwatch()..start();
    final utxos = await provider.fetchUtxos(fundedAddress);
    fSw.stop();
    expect(utxos, isNotEmpty, reason: 'fund $fundedAddress via the faucet');

    final rustParams = ProtocolParams(
      minFeeA: BigInt.from(params.minFeeA),
      minFeeB: BigInt.from(params.minFeeB),
      coinsPerUtxoByte: BigInt.from(params.coinsPerUtxoByte),
      maxTxSize: params.maxTxSize,
      poolDeposit: BigInt.from(params.poolDeposit),
      keyDeposit: BigInt.from(params.keyDeposit),
      maxValSize: params.maxValueSize,
    );

    final txInputs = utxos
        .map((u) => TxInput(
              txHash: u.txHash,
              outputIndex: u.outputIndex,
              address: u.address,
              value: Value(coin: u.coin, assets: const []),
            ))
        .toList();
    final targetOutputs = [
      TxOutput(
        address: fundedAddress,
        value: Value(coin: BigInt.from(1000000), assets: const []),
      ),
    ];

    // --- coin selection + build (the FFI hot path), measured over N runs ---
    const runs = 20;
    final buildTimings = <int>[];
    for (var i = 0; i < runs; i++) {
      final bSw = Stopwatch()..start();
      final sel = await selectCoinsForTransaction(
        availableUtxos: txInputs,
        targetOutputs: targetOutputs,
        changeAddress: fundedAddress,
        protocolParams: rustParams,
      );
      final built = await buildTransaction(
        inputs: sel.selectedInputs,
        outputs: [...sel.changeOutputs, ...targetOutputs],
        changeAddress: fundedAddress,
        ttl: null,
        protocolParams: rustParams,
      );
      bSw.stop();
      expect(built.txBodyCborHex, isNotEmpty);
      buildTimings.add(bSw.elapsedMilliseconds);
    }

    buildTimings.sort();
    final buildMin = buildTimings.first;
    final buildMax = buildTimings.last;
    final buildMedian = buildTimings[buildTimings.length ~/ 2];
    final buildAvg =
        (buildTimings.reduce((a, b) => a + b) / buildTimings.length).round();

    final summary = 'PERF utxo_fetch=${fSw.elapsedMilliseconds}ms '
        '(budget ${fetchBudgetMs}ms) | protocol_params=${pSw.elapsedMilliseconds}ms | '
        'select+build x$runs: min=${buildMin}ms median=${buildMedian}ms '
        'avg=${buildAvg}ms max=${buildMax}ms (budget ${buildBudgetMs}ms)';
    print(summary);

    binding.reportData = <String, dynamic>{
      'perf': summary,
      'utxo_fetch_ms': fSw.elapsedMilliseconds,
      'protocol_params_ms': pSw.elapsedMilliseconds,
      'build_min_ms': buildMin,
      'build_median_ms': buildMedian,
      'build_avg_ms': buildAvg,
      'build_max_ms': buildMax,
      'runs': runs,
      'utxo_count': utxos.length,
    };

    // Budgets. Build uses median to ignore one-off GC/JIT outliers; the leak
    // smoke check is that max stays within a small multiple of the median.
    expect(fSw.elapsedMilliseconds, lessThan(fetchBudgetMs),
        reason: 'UTxO fetch over budget');
    expect(buildMedian, lessThan(buildBudgetMs),
        reason: 'coin-selection+build over budget');
    expect(buildMax, lessThan(buildMedian * 6 + 50),
        reason: 'build latency grows across runs — possible leak/retention');
  });
}
