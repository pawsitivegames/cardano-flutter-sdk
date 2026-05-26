import 'package:flutter_test/flutter_test.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  // Known 56-char policy ID hex (28 bytes)
  const policyIdHex = 'b16b56f5ec64be6ac3cabfb9f246679b08a4e426e4c80dc7f3e2a460';
  const policyIdHex2 = 'c27c67d4fd75cf7b4d1befca0357788c19b5e537f5d91ed8e4f3b571';

  // 'MyNFT' in hex
  const assetNameHex = '4d794e4654';
  // 'TestToken' in hex
  const assetNameHex2 = '54657374546f6b656e';

  group('buildCip25Metadata', () {
    test('returns non-empty CBOR hex', () {
      final result = buildCip25Metadata(
        policies: [
          Cip25Policy(
            policyIdHex: policyIdHex,
            assets: [
              Cip25Asset(
                assetNameHex: assetNameHex,
                name: 'My NFT',
                image: 'ipfs://QmTestImageHash',
              ),
            ],
          ),
        ],
      );
      expect(result, isNotEmpty);
      expect(result.length % 2, equals(0)); // valid hex
    });

    test('is deterministic', () {
      final policy = Cip25Policy(
        policyIdHex: policyIdHex,
        assets: [
          Cip25Asset(
            assetNameHex: assetNameHex,
            name: 'My NFT',
            image: 'ipfs://QmTest',
          ),
        ],
      );
      final r1 = buildCip25Metadata(policies: [policy]);
      final r2 = buildCip25Metadata(policies: [policy]);
      expect(r1, equals(r2));
    });

    test('includes all optional fields', () {
      final result = buildCip25Metadata(
        policies: [
          Cip25Policy(
            policyIdHex: policyIdHex,
            assets: [
              Cip25Asset(
                assetNameHex: assetNameHex,
                name: 'My NFT',
                image: 'ipfs://QmTest',
                mediaType: 'image/png',
                description: 'A test NFT',
              ),
            ],
          ),
        ],
      );
      expect(result, isNotEmpty);
    });

    test('handles multiple policies', () {
      final result = buildCip25Metadata(
        policies: [
          Cip25Policy(
            policyIdHex: policyIdHex,
            assets: [
              Cip25Asset(
                assetNameHex: assetNameHex,
                name: 'NFT One',
                image: 'ipfs://QmOne',
              ),
            ],
          ),
          Cip25Policy(
            policyIdHex: policyIdHex2,
            assets: [
              Cip25Asset(
                assetNameHex: assetNameHex2,
                name: 'NFT Two',
                image: 'ipfs://QmTwo',
              ),
            ],
          ),
        ],
      );
      expect(result, isNotEmpty);
      // Multi-policy result should be longer than single
      final singlePolicy = buildCip25Metadata(
        policies: [
          Cip25Policy(
            policyIdHex: policyIdHex,
            assets: [
              Cip25Asset(
                assetNameHex: assetNameHex,
                name: 'NFT One',
                image: 'ipfs://QmOne',
              ),
            ],
          ),
        ],
      );
      expect(result.length, greaterThan(singlePolicy.length));
    });

    test('handles multiple assets under one policy', () {
      final result = buildCip25Metadata(
        policies: [
          Cip25Policy(
            policyIdHex: policyIdHex,
            assets: [
              Cip25Asset(
                assetNameHex: assetNameHex,
                name: 'NFT One',
                image: 'ipfs://QmOne',
              ),
              Cip25Asset(
                assetNameHex: assetNameHex2,
                name: 'NFT Two',
                image: 'ipfs://QmTwo',
              ),
            ],
          ),
        ],
      );
      expect(result, isNotEmpty);
    });
  });

  group('buildCip68Datum', () {
    test('returns non-empty CBOR hex', () {
      final result = buildCip68Datum(
        name: 'My NFT',
        image: 'ipfs://QmTestImageHash',
        version: BigInt.one,
      );
      expect(result, isNotEmpty);
      expect(result.length % 2, equals(0));
    });

    test('is deterministic', () {
      final r1 = buildCip68Datum(
        name: 'My NFT',
        image: 'ipfs://QmTest',
        version: BigInt.one,
      );
      final r2 = buildCip68Datum(
        name: 'My NFT',
        image: 'ipfs://QmTest',
        version: BigInt.one,
      );
      expect(r1, equals(r2));
    });

    test('includes optional fields', () {
      final withOptional = buildCip68Datum(
        name: 'My NFT',
        image: 'ipfs://QmTest',
        mediaType: 'image/png',
        description: 'A test NFT',
        version: BigInt.one,
      );
      final withoutOptional = buildCip68Datum(
        name: 'My NFT',
        image: 'ipfs://QmTest',
        version: BigInt.one,
      );
      // With optional fields should produce different (usually larger) CBOR
      expect(withOptional, isNotEmpty);
      expect(withOptional, isNot(equals(withoutOptional)));
    });

    test('different names produce different datums', () {
      final d1 = buildCip68Datum(
        name: 'NFT Alpha',
        image: 'ipfs://QmTest',
        version: BigInt.one,
      );
      final d2 = buildCip68Datum(
        name: 'NFT Beta',
        image: 'ipfs://QmTest',
        version: BigInt.one,
      );
      expect(d1, isNot(equals(d2)));
    });

    test('different versions produce different datums', () {
      final v1 = buildCip68Datum(
        name: 'My NFT',
        image: 'ipfs://QmTest',
        version: BigInt.one,
      );
      final v2 = buildCip68Datum(
        name: 'My NFT',
        image: 'ipfs://QmTest',
        version: BigInt.two,
      );
      expect(v1, isNot(equals(v2)));
    });

    test('valid CIP-68 datum validates as PlutusData', () {
      final datum = buildCip68Datum(
        name: 'My NFT',
        image: 'ipfs://QmTest',
        version: BigInt.one,
      );
      // CIP-68 datum is PlutusData CBOR — validatePlutusData should accept it
      final validated = validatePlutusData(cborHex: datum);
      expect(validated, equals(datum));
    });
  });
}
