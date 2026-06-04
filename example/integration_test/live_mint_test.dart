import 'dart:convert';
import 'dart:io';

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// LIVE on-chain verification of the CIP-25 chunking fix (#2).
///
/// Mints a real NFT on Cardano **preview testnet** whose `image` is a >64-byte
/// `ipfs://` URI — the exact case that threw "Max metadata string too long"
/// before the fix. A successful Blockfrost submit proves a real node ACCEPTS the
/// chunked CIP-25 metadata (submit validates structure and only returns a hash
/// if the tx is well-formed), and the confirmation poll proves it landed on-chain.
///
/// Requires a funded preview wallet. Run:
///   cd example && flutter test integration_test/live_mint_test.dart \
///       --dart-define=BLOCKFROST_PROJECT_ID=preview...
/// (or set BLOCKFROST_PROJECT_ID in the host environment for a host run).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Accept the key from --dart-define (device) or the host environment.
  const defineId = String.fromEnvironment('BLOCKFROST_PROJECT_ID');
  final envId = Platform.environment['BLOCKFROST_PROJECT_ID'];
  final projectId = defineId.isNotEmpty ? defineId : (envId ?? '');

  const mnemonic =
      'test walk nut penalty hip pave soap entry language right filter choice';

  String hexOf(String s) =>
      utf8.encode(s).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  setUpAll(() async {
    if (Platform.isIOS) {
      final bundleDir = File(Platform.resolvedExecutable).parent.path;
      final libPath =
          '$bundleDir/Frameworks/cardano_flutter_rs.framework/cardano_flutter_rs';
      await RustLib.init(externalLibrary: ExternalLibrary.open(libPath));
    } else {
      await RustLib.init();
    }
  });

  testWidgets('live: mint NFT with >64-byte image URI on preview testnet',
      (tester) async {
    if (projectId.isEmpty) {
      // ignore: avoid_print
      print('[LIVE_MINT] BLOCKFROST_PROJECT_ID not provided — skipping.');
      return;
    }

    final keys = await deriveKeysFromMnemonic(
      mnemonic: mnemonic,
      passphrase: '',
      accountIndex: 0,
      isTestnet: true,
    );
    final addr = computeBaseAddress(
      paymentKeyHashHex: keys.paymentKeyHash,
      stakeKeyHashHex: keys.stakeKeyHash,
      networkId: 0,
    );
    // ignore: avoid_print
    print('[LIVE_MINT] funded address: $addr');

    final provider =
        BlockfrostProvider(projectId: projectId, network: Network.testnetPreview);

    final utxos = await provider.fetchUtxos(addr);
    // ignore: avoid_print
    print('[LIVE_MINT] UTxOs at address: ${utxos.length}');
    expect(utxos, isNotEmpty,
        reason: 'wallet must be funded on preview testnet (fund 0/0 of the test mnemonic)');

    // Use a single pure-ADA UTxO so the mint isn't entangled with the wallet's
    // existing native tokens (this test verifies the mint witness + CIP-25
    // chunking, not multi-asset change balancing).
    final pureAda = utxos.where((u) => u.assets.isEmpty).toList()
      ..sort((a, b) => b.coin.compareTo(a.coin));
    expect(pureAda, isNotEmpty,
        reason: 'need at least one pure-ADA UTxO (≥ ~3 ADA) to fund the mint');
    final fundingUtxos = [pureAda.first];
    // ignore: avoid_print
    print('[LIVE_MINT] funding from pure-ADA UTxO ${pureAda.first.txHash}#'
        '${pureAda.first.outputIndex} = ${pureAda.first.coin} lovelace');

    final params = (await provider.fetchProtocolParameters()).toProtocolParams();

    // Single-sig policy controlled by the payment key.
    final policyScript = makePubkeyScript(keyHashHex: keys.paymentKeyHash);
    final policyId = computePolicyId(nativeScriptCborHex: policyScript);

    // Unique asset name per run so repeated runs don't collide.
    final suffix = DateTime.now().millisecondsSinceEpoch.toString();
    final assetName = 'CFSDK$suffix';
    final assetNameHex = hexOf(assetName);

    // THE THING UNDER TEST: an image URI longer than 64 bytes.
    final longImage = 'ipfs://${'Q' * 90}'; // 97 bytes
    expect(longImage.length, greaterThan(64));

    final auxDataHex = buildCip25Metadata(policies: [
      Cip25Policy(
        policyIdHex: policyId,
        assets: [
          Cip25Asset(
            assetNameHex: assetNameHex,
            name: assetName,
            image: longImage,
            mediaType: 'image/png',
            description:
                'cardano_flutter_rs CIP-25 chunking live test ($suffix) — '
                'this description is also deliberately longer than sixty-four '
                'bytes to exercise multi-field chunking.',
          ),
        ],
      ),
    ]);

    final builtMintTx = buildMintTx(
      inputs: utxosToTxInputs(fundingUtxos),
      outputs: const [],
      changeAddress: addr,
      mintSpecs: [
        MintSpec(
          policyScriptCborHex: policyScript,
          assets: [MintAsset(assetNameHex: assetNameHex, quantity: 1)],
        ),
      ],
      auxDataCborHex: auxDataHex,
      ttl: null,
      params: params,
    );
    // ignore: avoid_print
    print('[LIVE_MINT] built mint tx, fee ${builtMintTx.fee} lovelace');

    final signedTx = await signMintTransaction(
      builtMintTx: builtMintTx,
      paymentKeys: [keys.paymentSigningKey],
    );

    // Submit. Blockfrost rejects malformed txs here, so a returned hash == the
    // node accepted the chunked CIP-25 metadata.
    final txHash = await provider.submitTransaction(signedTxToBytes(signedTx));
    expect(txHash, isNotEmpty);
    // ignore: avoid_print
    print('[LIVE_MINT] SUBMITTED tx: $txHash');
    // ignore: avoid_print
    print('[LIVE_MINT] explorer: https://preview.cexplorer.io/tx/$txHash');

    // Best-effort confirmation poll (does not fail the test on timeout).
    var confirmed = false;
    for (var i = 0; i < 20 && !confirmed; i++) {
      await Future.delayed(const Duration(seconds: 5));
      try {
        final status = await provider.pollTransactionConfirmation(
          txHash,
          pollInterval: const Duration(seconds: 5),
          timeout: const Duration(seconds: 6),
        );
        confirmed = status.confirmed;
      } catch (_) {
        // keep waiting
      }
      // ignore: avoid_print
      print('[LIVE_MINT] confirmation poll ${i + 1}: confirmed=$confirmed');
    }
    // ignore: avoid_print
    print('[LIVE_MINT] final: confirmed=$confirmed (submission already proves '
        'node acceptance of the chunked metadata)');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
