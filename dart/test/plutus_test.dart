import 'package:flutter_test/flutter_test.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  const testAddr =
      'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz';
  const fakeTxHash =
      '0000000000000000000000000000000000000000000000000000000000000000';

  final params = ProtocolParams(
    minFeeA: BigInt.from(44),
    minFeeB: BigInt.from(155381),
    coinsPerUtxoByte: BigInt.from(4310),
    maxTxSize: 16384,
    poolDeposit: BigInt.from(500000000),
    keyDeposit: BigInt.from(2000000),
    maxValSize: 5000,
  );

  TxInput makeInput({BigInt? coin}) => TxInput(
        txHash: fakeTxHash,
        outputIndex: 0,
        address: testAddr,
        value: Value(coin: coin ?? BigInt.from(10000000), assets: []),
      );

  group('plutusDataInt', () {
    test('encodes zero', () {
      final result = plutusDataInt(n: 0);
      expect(result, isNotEmpty);
      expect(result.length % 2, equals(0));
    });

    test('encodes positive integer', () {
      final result = plutusDataInt(n: 42);
      expect(result, isNotEmpty);
    });

    test('encodes negative integer', () {
      final result = plutusDataInt(n: -1);
      expect(result, isNotEmpty);
    });

    test('different values produce different CBOR', () {
      final a = plutusDataInt(n: 1);
      final b = plutusDataInt(n: 2);
      expect(a, isNot(equals(b)));
    });

    test('is deterministic', () {
      expect(plutusDataInt(n: 42), equals(plutusDataInt(n: 42)));
    });

    test('validates as PlutusData', () {
      final cbor = plutusDataInt(n: 100);
      expect(validatePlutusData(cborHex: cbor), equals(cbor));
    });
  });

  group('plutusDataBytes', () {
    test('encodes bytes from hex', () {
      final result = plutusDataBytes(hexData: 'deadbeef');
      expect(result, isNotEmpty);
      expect(result.length % 2, equals(0));
    });

    test('encodes empty bytes', () {
      final result = plutusDataBytes(hexData: '');
      expect(result, isNotEmpty);
    });

    test('different hex values produce different CBOR', () {
      final a = plutusDataBytes(hexData: 'aabb');
      final b = plutusDataBytes(hexData: 'ccdd');
      expect(a, isNot(equals(b)));
    });

    test('validates as PlutusData', () {
      final cbor = plutusDataBytes(hexData: 'cafebabe');
      expect(validatePlutusData(cborHex: cbor), equals(cbor));
    });

    test('throws on invalid hex input', () {
      expect(
        () => plutusDataBytes(hexData: 'not_hex!!'),
        throwsA(isA<CardanoError>()),
      );
    });
  });

  group('plutusDataConstr', () {
    test('encodes empty constructor', () {
      final result = plutusDataConstr(
        constructor: BigInt.zero,
        fieldsCborHex: [],
      );
      expect(result, isNotEmpty);
    });

    test('encodes constructor with fields', () {
      final intField = plutusDataInt(n: 42);
      final bytesField = plutusDataBytes(hexData: 'deadbeef');
      final result = plutusDataConstr(
        constructor: BigInt.zero,
        fieldsCborHex: [intField, bytesField],
      );
      expect(result, isNotEmpty);
    });

    test('different constructor indices produce different CBOR', () {
      final c0 = plutusDataConstr(
        constructor: BigInt.zero,
        fieldsCborHex: [],
      );
      final c1 = plutusDataConstr(
        constructor: BigInt.one,
        fieldsCborHex: [],
      );
      expect(c0, isNot(equals(c1)));
    });

    test('validates as PlutusData', () {
      final cbor = plutusDataConstr(
        constructor: BigInt.zero,
        fieldsCborHex: [plutusDataInt(n: 1)],
      );
      expect(validatePlutusData(cborHex: cbor), equals(cbor));
    });

    test('nested constructors work', () {
      final inner = plutusDataConstr(
        constructor: BigInt.zero,
        fieldsCborHex: [plutusDataInt(n: 99)],
      );
      final outer = plutusDataConstr(
        constructor: BigInt.one,
        fieldsCborHex: [inner],
      );
      expect(outer, isNotEmpty);
      expect(validatePlutusData(cborHex: outer), equals(outer));
    });
  });

  group('plutusDataList', () {
    test('encodes empty list', () {
      final result = plutusDataList(itemsCborHex: []);
      expect(result, isNotEmpty);
    });

    test('encodes list with items', () {
      final items = [
        plutusDataInt(n: 1),
        plutusDataInt(n: 2),
        plutusDataBytes(hexData: 'aabb'),
      ];
      final result = plutusDataList(itemsCborHex: items);
      expect(result, isNotEmpty);
    });

    test('validates as PlutusData', () {
      final items = [plutusDataInt(n: 10), plutusDataInt(n: 20)];
      final cbor = plutusDataList(itemsCborHex: items);
      expect(validatePlutusData(cborHex: cbor), equals(cbor));
    });

    test('list with one item differs from list with two', () {
      final single = plutusDataList(itemsCborHex: [plutusDataInt(n: 1)]);
      final double_ = plutusDataList(itemsCborHex: [
        plutusDataInt(n: 1),
        plutusDataInt(n: 1),
      ]);
      expect(single, isNot(equals(double_)));
    });
  });

  group('validatePlutusData', () {
    test('accepts valid integer datum', () {
      final cbor = plutusDataInt(n: 42);
      expect(validatePlutusData(cborHex: cbor), equals(cbor));
    });

    test('accepts valid bytes datum', () {
      final cbor = plutusDataBytes(hexData: '0102030405');
      expect(validatePlutusData(cborHex: cbor), equals(cbor));
    });

    test('accepts valid constr datum', () {
      final cbor = plutusDataConstr(constructor: BigInt.zero, fieldsCborHex: []);
      expect(validatePlutusData(cborHex: cbor), equals(cbor));
    });

    test('throws on empty string', () {
      expect(
        () => validatePlutusData(cborHex: ''),
        throwsA(isA<CardanoError>()),
      );
    });

    test('throws on non-hex string', () {
      expect(
        () => validatePlutusData(cborHex: 'not_hex'),
        throwsA(isA<CardanoError>()),
      );
    });

    test('throws on random bytes that are not valid PlutusData', () {
      // 'ff' alone is an invalid CBOR break code
      expect(
        () => validatePlutusData(cborHex: 'ff'),
        throwsA(isA<CardanoError>()),
      );
    });
  });

  group('buildScriptTx', () {
    test('throws InvalidParameter on empty scriptInputs', () {
      expect(
        () => buildScriptTx(
          scriptInputs: [],
          regularInputs: [makeInput()],
          outputs: [],
          changeAddress: testAddr,
          collateralInputs: [makeInput()],
          referenceInputs: [],
          ttl: null,
          params: params,
        ),
        throwsA(
          isA<CardanoError>().having(
            (e) => e,
            'invalidParameter',
            isA<CardanoError_InvalidParameter>(),
          ),
        ),
      );
    });

    test('throws InvalidParameter on empty collateralInputs', () {
      // Need a dummy PlutusInput — redeemer/datum are dummy CBOR (int 0)
      final dummyCbor = plutusDataInt(n: 0);
      final dummyScript = '01'; // minimal v2 script bytes (will likely fail CBOR parse)

      expect(
        () => buildScriptTx(
          scriptInputs: [
            PlutusInput(
              txInput: makeInput(),
              scriptCborHex: dummyScript,
              scriptVersion: PlutusScriptVersion.v2,
              datumCborHex: dummyCbor,
              redeemerCborHex: dummyCbor,
              exUnitsMem: BigInt.from(1000000),
              exUnitsSteps: BigInt.from(1000000),
            ),
          ],
          regularInputs: [makeInput()],
          outputs: [],
          changeAddress: testAddr,
          collateralInputs: [], // empty → should throw
          referenceInputs: [],
          ttl: null,
          params: params,
        ),
        throwsA(isA<CardanoError>()),
      );
    });
  });
}
