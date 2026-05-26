import 'package:flutter_test/flutter_test.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  // 28-byte (56-char) key hash for testing
  const keyHashHex = 'b16b56f5ec64be6ac3cabfb9f246679b08a4e426e4c80dc7f3e2a460';
  const keyHashHex2 = 'c27c67d4fd75cf7b4d1befca0357788c19b5e537f5d91ed8e4f3b571';

  // Standard testnet address derived from the canonical test mnemonic
  const testAddr =
      'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz';
  const fakeTxHash =
      '0000000000000000000000000000000000000000000000000000000000000000';

  // 'MyNFT' in hex
  const assetNameHex = '4d794e4654';

  final params = ProtocolParams(
    minFeeA: BigInt.from(44),
    minFeeB: BigInt.from(155381),
    coinsPerUtxoByte: BigInt.from(4310),
    maxTxSize: 16384,
    poolDeposit: BigInt.from(500000000),
    keyDeposit: BigInt.from(2000000),
    maxValSize: 5000,
  );

  group('makePubkeyScript', () {
    test('returns non-empty CBOR hex', () {
      final script = makePubkeyScript(keyHashHex: keyHashHex);
      expect(script, isNotEmpty);
      expect(script.length % 2, equals(0)); // valid hex
    });

    test('is deterministic', () {
      final s1 = makePubkeyScript(keyHashHex: keyHashHex);
      final s2 = makePubkeyScript(keyHashHex: keyHashHex);
      expect(s1, equals(s2));
    });

    test('different key hashes produce different scripts', () {
      final s1 = makePubkeyScript(keyHashHex: keyHashHex);
      final s2 = makePubkeyScript(keyHashHex: keyHashHex2);
      expect(s1, isNot(equals(s2)));
    });

    test('throws on invalid key hash', () {
      expect(
        () => makePubkeyScript(keyHashHex: 'not_valid_hex'),
        throwsA(isA<CardanoError>()),
      );
    });

    test('throws on wrong-length key hash', () {
      expect(
        () => makePubkeyScript(keyHashHex: 'deadbeef'), // too short
        throwsA(isA<CardanoError>()),
      );
    });
  });

  group('makeTimelockExpiryScript', () {
    test('returns non-empty CBOR hex', () {
      final script = makeTimelockExpiryScript(
        keyHashHex: keyHashHex,
        expirySlot: BigInt.from(100000),
      );
      expect(script, isNotEmpty);
      expect(script.length % 2, equals(0));
    });

    test('different expiry slots produce different scripts', () {
      final s1 = makeTimelockExpiryScript(
        keyHashHex: keyHashHex,
        expirySlot: BigInt.from(100000),
      );
      final s2 = makeTimelockExpiryScript(
        keyHashHex: keyHashHex,
        expirySlot: BigInt.from(200000),
      );
      expect(s1, isNot(equals(s2)));
    });

    test('different key hashes produce different timelocks', () {
      final s1 = makeTimelockExpiryScript(
        keyHashHex: keyHashHex,
        expirySlot: BigInt.from(100000),
      );
      final s2 = makeTimelockExpiryScript(
        keyHashHex: keyHashHex2,
        expirySlot: BigInt.from(100000),
      );
      expect(s1, isNot(equals(s2)));
    });
  });

  group('computePolicyId', () {
    test('returns 56-character hex (28 bytes)', () {
      final script = makePubkeyScript(keyHashHex: keyHashHex);
      final policyId = computePolicyId(nativeScriptCborHex: script);
      expect(policyId.length, equals(56));
    });

    test('is deterministic', () {
      final script = makePubkeyScript(keyHashHex: keyHashHex);
      final p1 = computePolicyId(nativeScriptCborHex: script);
      final p2 = computePolicyId(nativeScriptCborHex: script);
      expect(p1, equals(p2));
    });

    test('different scripts give different policy IDs', () {
      final s1 = makePubkeyScript(keyHashHex: keyHashHex);
      final s2 = makePubkeyScript(keyHashHex: keyHashHex2);
      expect(
        computePolicyId(nativeScriptCborHex: s1),
        isNot(equals(computePolicyId(nativeScriptCborHex: s2))),
      );
    });

    test('pubkey and timelock scripts for same key produce different IDs', () {
      final pubkey = makePubkeyScript(keyHashHex: keyHashHex);
      final timelock = makeTimelockExpiryScript(
        keyHashHex: keyHashHex,
        expirySlot: BigInt.from(100000),
      );
      expect(
        computePolicyId(nativeScriptCborHex: pubkey),
        isNot(equals(computePolicyId(nativeScriptCborHex: timelock))),
      );
    });

    test('throws on invalid CBOR hex', () {
      expect(
        () => computePolicyId(nativeScriptCborHex: 'not_hex'),
        throwsA(isA<CardanoError>()),
      );
    });
  });

  group('buildMintTx', () {
    late String policyScript;
    late String policyIdHex;

    setUp(() {
      policyScript = makePubkeyScript(keyHashHex: keyHashHex);
      policyIdHex = computePolicyId(nativeScriptCborHex: policyScript);
    });

    test('builds a valid minting transaction', () {
      final input = TxInput(
        txHash: fakeTxHash,
        outputIndex: 0,
        address: testAddr,
        value: Value(coin: BigInt.from(10000000), assets: []),
      );
      final output = TxOutput(
        address: testAddr,
        value: Value(
          coin: BigInt.from(2000000),
          assets: [
            NativeAsset(
              policyId: policyIdHex,
              assetName: assetNameHex,
              quantity: BigInt.one,
            ),
          ],
        ),
      );

      final result = buildMintTx(
        inputs: [input],
        outputs: [output],
        changeAddress: testAddr,
        mintSpecs: [
          MintSpec(
            policyScriptCborHex: policyScript,
            assets: [MintAsset(assetNameHex: assetNameHex, quantity: 1)],
          ),
        ],
        auxDataCborHex: null,
        ttl: null,
        params: params,
      );

      expect(result.txBodyCborHex, isNotEmpty);
      expect(result.txHash.length, equals(64));
      expect(result.fee, greaterThan(BigInt.zero));
    });

    test('includes aux data when provided', () {
      final auxData = buildCip25Metadata(
        policies: [
          Cip25Policy(
            policyIdHex: policyIdHex,
            assets: [
              Cip25Asset(
                assetNameHex: assetNameHex,
                name: 'My NFT',
                image: 'ipfs://QmTest',
              ),
            ],
          ),
        ],
      );

      final input = TxInput(
        txHash: fakeTxHash,
        outputIndex: 0,
        address: testAddr,
        value: Value(coin: BigInt.from(10000000), assets: []),
      );

      final result = buildMintTx(
        inputs: [input],
        outputs: [],
        changeAddress: testAddr,
        mintSpecs: [
          MintSpec(
            policyScriptCborHex: policyScript,
            assets: [MintAsset(assetNameHex: assetNameHex, quantity: 1)],
          ),
        ],
        auxDataCborHex: auxData,
        ttl: BigInt.from(999999),
        params: params,
      );

      expect(result.auxDataCborHex, isNotNull);
      expect(result.txBodyCborHex, isNotEmpty);
    });

    test('throws on empty inputs', () {
      expect(
        () => buildMintTx(
          inputs: [],
          outputs: [],
          changeAddress: testAddr,
          mintSpecs: [
            MintSpec(
              policyScriptCborHex: policyScript,
              assets: [MintAsset(assetNameHex: assetNameHex, quantity: 1)],
            ),
          ],
          auxDataCborHex: null,
          ttl: null,
          params: params,
        ),
        throwsA(isA<CardanoError>()),
      );
    });

    test('throws on empty mint specs', () {
      final input = TxInput(
        txHash: fakeTxHash,
        outputIndex: 0,
        address: testAddr,
        value: Value(coin: BigInt.from(10000000), assets: []),
      );
      expect(
        () => buildMintTx(
          inputs: [input],
          outputs: [],
          changeAddress: testAddr,
          mintSpecs: [],
          auxDataCborHex: null,
          ttl: null,
          params: params,
        ),
        throwsA(isA<CardanoError>()),
      );
    });

    test('burn produces negative quantity', () {
      final burnAsset = MintAsset(assetNameHex: assetNameHex, quantity: -1);
      expect(burnAsset.quantity, equals(-1));
    });
  });
}
