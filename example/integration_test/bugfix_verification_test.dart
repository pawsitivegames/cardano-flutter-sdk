import 'dart:convert';
import 'dart:io';

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// On-device verification for the bug fixes in branch
/// `fix/hash-cip25-coinselect-mint`. Runs the REAL device framework (the
/// rebuilt arm64 dylib) on a physical iPhone and exercises every affected
/// code path deterministically — no network, no funded wallet, no submission.
///
/// Affected areas covered:
///   #1 tx.rs    — `buildTransaction` tx hash is canonical Blake2b-256
///                 (must equal `signTransaction`'s hash; pre-fix they differed)
///   #2 metadata — `buildCip25Metadata` chunks a >64-byte image URI (pre-fix:
///                 threw "Max metadata string too long")
///   #4 minting  — `buildMintTx` rejects an i64::MIN quantity cleanly (pre-fix:
///                 panicked inside CSL's CBOR writer)
///   #3 coinsel  — `selectCoinsForTransaction` conserves native assets
///
/// Run on the iPhone 13:
///   cd example && flutter test integration_test/bugfix_verification_test.dart \
///       -d 00008110-00014D2C0A22801E
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const mnemonic =
      'test walk nut penalty hip pave soap entry language right filter choice';

  String hexOf(String s) =>
      utf8.encode(s).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  ProtocolParams params() => ProtocolParams(
        minFeeA: BigInt.from(44),
        minFeeB: BigInt.from(155381),
        coinsPerUtxoByte: BigInt.from(4310),
        maxTxSize: 16384,
        poolDeposit: BigInt.from(500000000),
        keyDeposit: BigInt.from(2000000),
        maxValSize: 5000,
      );

  setUpAll(() async {
    // Match the example app's iOS init: load the embedded framework binary.
    if (Platform.isIOS) {
      final bundleDir = File(Platform.resolvedExecutable).parent.path;
      final libPath =
          '$bundleDir/Frameworks/cardano_flutter_rs.framework/cardano_flutter_rs';
      await RustLib.init(externalLibrary: ExternalLibrary.open(libPath));
    } else {
      await RustLib.init();
    }
  });

  testWidgets('#1 build_tx hash is canonical Blake2b-256 (== sign hash)',
      (tester) async {
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

    final input = TxInput(
      txHash: '00' * 32,
      outputIndex: 0,
      address: addr,
      value: Value(coin: BigInt.from(5000000), assets: const []),
    );
    final output = TxOutput(
      address: addr,
      value: Value(coin: BigInt.from(1000000), assets: const []),
    );

    final built = await buildTransaction(
      inputs: [input],
      outputs: [output],
      changeAddress: addr,
      ttl: null,
      protocolParams: params(),
    );

    expect(built.txHash.length, 64, reason: '32-byte hash → 64 hex chars');

    final signed = await signTransaction(
      txBodyCborHex: built.txBodyCborHex,
      paymentKeys: [keys.paymentSigningKey], // xprv — paymentKey is a display xpub
    );

    // The crux: the build-side hash (tx.rs) must equal the sign-side hash
    // (sign.rs, the verified-correct Blake2b-256). Pre-fix tx.rs returned a
    // truncated Blake2b-512, so these did NOT match.
    expect(built.txHash, signed.txHash,
        reason: 'build_tx hash must equal sign_tx hash (both Blake2b-256)');
  });

  testWidgets('#2 CIP-25 long image URI is chunked, not rejected',
      (tester) async {
    final longImage = 'ipfs://${'Q' * 90}'; // 97 bytes > 64
    expect(longImage.length, greaterThan(64));

    // Pre-fix this threw because CSL rejects text metadata > 64 bytes.
    final hex = buildCip25Metadata(policies: [
      Cip25Policy(
        policyIdHex: 'a0' * 28,
        assets: [
          Cip25Asset(
            assetNameHex: hexOf('LongNFT'),
            name: 'Long NFT',
            image: longImage,
            mediaType: 'image/png',
          ),
        ],
      ),
    ]);
    expect(hex, isNotEmpty);
    expect(() => buildCip25Metadata(policies: [
          Cip25Policy(policyIdHex: 'a0' * 28, assets: [
            Cip25Asset(
                assetNameHex: hexOf('LongNFT'),
                name: 'Long NFT',
                image: longImage),
          ])
        ]), returnsNormally);
  });

  testWidgets('#4 mint quantity i64::MIN is rejected cleanly (no crash)',
      (tester) async {
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
    final script = makePubkeyScript(keyHashHex: keys.paymentKeyHash);

    const i64Min = -9223372036854775807 - 1; // i64::MIN, no literal overflow

    // Reaching the matcher at all means the FFI returned instead of crashing
    // the isolate (pre-fix it panicked inside CSL's CBOR negative-int writer).
    expect(
      () => buildMintTx(
        inputs: [
          TxInput(
            txHash: '00' * 32,
            outputIndex: 0,
            address: addr,
            value: Value(coin: BigInt.from(10000000), assets: const []),
          )
        ],
        outputs: const [],
        changeAddress: addr,
        mintSpecs: [
          MintSpec(
            policyScriptCborHex: script,
            assets: [MintAsset(assetNameHex: hexOf('TestNFT'), quantity: i64Min)],
          )
        ],
        params: params(),
      ),
      throwsA(anything),
    );
  });

  testWidgets('#3 coin selection conserves native assets', (tester) async {
    const policy = '29d222ce763455e3a6ce516f5a56f76349c3ecbf3c60d7751c4f6418';
    const name = 'MYTKN';

    final utxo = TxInput(
      txHash: 'aa' * 32,
      outputIndex: 0,
      address: 'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz',
      value: Value(coin: BigInt.from(5000000), assets: [
        NativeAsset(
            policyId: policy, assetName: name, quantity: BigInt.from(200)),
      ]),
    );
    final target = TxOutput(
      address: 'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz',
      value: Value(coin: BigInt.from(1500000), assets: [
        NativeAsset(
            policyId: policy, assetName: name, quantity: BigInt.from(100)),
      ]),
    );

    final result = await selectCoinsForTransaction(
      availableUtxos: [utxo],
      targetOutputs: [target],
      changeAddress:
          'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz',
      protocolParams: params(),
    );

    final changeQty = result.changeOutputs
        .expand((o) => o.value.assets)
        .where((a) => a.policyId == policy && a.assetName == name)
        .fold<BigInt>(BigInt.zero, (sum, a) => sum + a.quantity);
    // 200 held − 100 sent = 100 returned as change. No assets lost.
    expect(changeQty, BigInt.from(100));
  });
}
