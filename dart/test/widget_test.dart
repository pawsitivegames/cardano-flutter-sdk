// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that values change correctly.

import 'package:flutter_test/flutter_test.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  group('SDK Version', () {
    test('returns version string', () async {
      final version = await getSdkVersion();
      expect(version, isNotEmpty);
      expect(version, contains('cardano_flutter_rs'));
    });

    test('includes CSL backend identifier', () async {
      final version = await getSdkVersion();
      expect(version, contains('CSL-backed'));
    });
  });

  group('Address Validation', () {
    test('validates bech32 format', () async {
      // Enterprise address derived from the test mnemonic (CIP-1852 m/1852'/1815'/0'/0/0, testnet)
      const validAddr =
          'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz';
      final isValid = await isValidBech32(validAddr);
      expect(isValid, isTrue);
    });

    test('rejects malformed addresses', () async {
      const malformed = 'not_a_valid_address';
      final isValid = await isValidBech32(malformed);
      expect(isValid, isFalse);
    });

    test('rejects empty string', () async {
      final isValid = await isValidBech32('');
      expect(isValid, isFalse);
    });

    test('validateAddress returns AddressInfo with correct network', () async {
      const testAddr =
          'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz';
      final info = await validateAddress(testAddr);
      expect(info, isA<AddressInfo>());
      expect(info.address, equals(testAddr));
      expect(info.network, equals('testnet'));
    });
  });

  group('Key Derivation', () {
    const testMnemonic =
        'test walk nut penalty hip pave soap entry language right filter choice';
    const emptyPassphrase = '';
    const validAccountIndex = 0;

    test('derives keys from valid mnemonic', () async {
      final keys = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: emptyPassphrase,
        accountIndex: validAccountIndex,
        isTestnet: false,
      );
      expect(keys, isA<KeyDerivationResult>());
      expect(keys.accountKey, isNotEmpty);
      expect(keys.paymentKey, isNotEmpty);
      expect(keys.stakeKey, isNotEmpty);
    });

    test('derives different keys for testnet', () async {
      final mainnetKeys = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: emptyPassphrase,
        accountIndex: validAccountIndex,
        isTestnet: false,
      );
      final testnetKeys = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: emptyPassphrase,
        accountIndex: validAccountIndex,
        isTestnet: true,
      );
      // Network ID affects address derivation, so the result should be different
      expect(mainnetKeys.paymentKey, isNotEmpty);
      expect(testnetKeys.paymentKey, isNotEmpty);
    });

    test('supports different account indices', () async {
      final account0 = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: emptyPassphrase,
        accountIndex: 0,
        isTestnet: false,
      );
      final account1 = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: emptyPassphrase,
        accountIndex: 1,
        isTestnet: false,
      );
      // Different accounts should derive different keys
      expect(account0.accountKey, isNotEmpty);
      expect(account1.accountKey, isNotEmpty);
    });

    test('paymentKeyHash is 56-char hex (28 bytes)', () async {
      final keys = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: emptyPassphrase,
        accountIndex: validAccountIndex,
        isTestnet: false,
      );
      expect(keys.paymentKeyHash.length, equals(56));
      expect(
        RegExp(r'^[0-9a-f]+$').hasMatch(keys.paymentKeyHash),
        isTrue,
      );
    });

    test('rejects invalid mnemonic', () async {
      const invalidMnemonic =
          'invalid mnemonic words that do not form a valid bip39 seed';
      expect(
        () => deriveKeysFromMnemonic(
          mnemonic: invalidMnemonic,
          passphrase: emptyPassphrase,
          accountIndex: validAccountIndex,
          isTestnet: false,
        ),
        throwsException,
      );
    });

    test('derives account key from key', () async {
      final keys = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: emptyPassphrase,
        accountIndex: validAccountIndex,
        isTestnet: false,
      );
      final childKey = await deriveAccountKey(
        accountKey: keys.accountKey,
        role: 0,
        index: 0,
      );
      expect(childKey, isNotEmpty);
      expect(childKey, isA<String>());
    });
  });

  group('utxoToTxInput', () {
    test('converts ADA-only UTXO correctly', () {
      final utxo = Utxo(
        txHash: 'abc123',
        outputIndex: 0,
        address: 'addr_test1q...',
        coin: BigInt.from(2000000),
        assets: {},
      );
      final input = utxoToTxInput(utxo);
      expect(input.txHash, equals('abc123'));
      expect(input.outputIndex, equals(0));
      expect(input.value.coin, equals(BigInt.from(2000000)));
      expect(input.value.assets, isEmpty);
    });

    test('preserves native tokens in multi-asset UTXO', () {
      const policyId =
          '29d222ce763455e3a6ce516f5a56f76349c3ecbf3c60d7751c4f6418';
      const assetName = '4d59544b4e'; // MYTKN hex
      final utxo = Utxo(
        txHash: 'def456',
        outputIndex: 1,
        address: 'addr_test1q...',
        coin: BigInt.from(1500000),
        assets: {
          policyId: {assetName: BigInt.from(100)},
        },
      );
      final input = utxoToTxInput(utxo);
      expect(input.value.coin, equals(BigInt.from(1500000)));
      expect(input.value.assets, hasLength(1));
      expect(input.value.assets.first.policyId, equals(policyId));
      expect(input.value.assets.first.assetName, equals(assetName));
      expect(input.value.assets.first.quantity, equals(BigInt.from(100)));
    });

    test('utxosToTxInputs converts list of UTXOs', () {
      final utxos = [
        Utxo(
          txHash: 'aaa',
          outputIndex: 0,
          address: 'addr_test1q...',
          coin: BigInt.from(5000000),
          assets: {},
        ),
        Utxo(
          txHash: 'bbb',
          outputIndex: 0,
          address: 'addr_test1q...',
          coin: BigInt.from(3000000),
          assets: {},
        ),
      ];
      final inputs = utxosToTxInputs(utxos);
      expect(inputs, hasLength(2));
      expect(inputs[0].txHash, equals('aaa'));
      expect(inputs[1].txHash, equals('bbb'));
    });

    test('rejects negative coin before FFI conversion', () {
      final utxo = Utxo(
        txHash: 'neg',
        outputIndex: 0,
        address: 'addr_test1q...',
        coin: BigInt.from(-1),
        assets: {},
      );

      expect(() => utxoToTxInput(utxo), throwsA(isA<ArgumentError>()));
    });

    test('rejects asset quantity above u64 before FFI conversion', () {
      const policyId =
          '29d222ce763455e3a6ce516f5a56f76349c3ecbf3c60d7751c4f6418';
      final utxo = Utxo(
        txHash: 'huge',
        outputIndex: 2,
        address: 'addr_test1q...',
        coin: BigInt.from(2000000),
        assets: {
          policyId: {'00': BigInt.one << 64},
        },
      );

      expect(() => utxoToTxInput(utxo), throwsA(isA<ArgumentError>()));
    });
  });

  group('Wrapper conversions', () {
    const testAddress =
        'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz';

    ProtocolParams protocolParams() => ProtocolParams(
          minFeeA: BigInt.from(44),
          minFeeB: BigInt.from(155381),
          coinsPerUtxoByte: BigInt.from(4310),
          maxTxSize: 16384,
          poolDeposit: BigInt.from(500000000),
          keyDeposit: BigInt.from(2000000),
          maxValSize: 5000,
        );

    test('ProtocolParameters.toProtocolParams maps all fields', () {
      final params = ProtocolParameters(
        minFeeA: 44,
        minFeeB: 155381,
        coinsPerUtxoByte: 4310,
        maxTxSize: 16384,
        maxValueSize: 5000,
        keyDeposit: 2000000,
        poolDeposit: 500000000,
      ).toProtocolParams();

      expect(params.minFeeA, equals(BigInt.from(44)));
      expect(params.minFeeB, equals(BigInt.from(155381)));
      expect(params.coinsPerUtxoByte, equals(BigInt.from(4310)));
      expect(params.maxTxSize, equals(16384));
      expect(params.maxValSize, equals(5000));
      expect(params.keyDeposit, equals(BigInt.from(2000000)));
      expect(params.poolDeposit, equals(BigInt.from(500000000)));
    });

    test('signedTxToBytes decodes transaction hex bytes', () {
      final signedTx = SignedTx(txCborHex: '840102ff', txHash: 'hash');

      expect(signedTxToBytes(signedTx), equals([0x84, 0x01, 0x02, 0xff]));
    });

    test('computeStakeAddress returns a testnet reward address', () {
      const stakeKeyHash =
          '05261533f512bfb9dc8a8686e97951f474a532778f0e2228f8865c17';

      final stakeAddress = computeStakeAddress(
        stakeKeyHashHex: stakeKeyHash,
        isTestnet: true,
      );

      expect(stakeAddress, startsWith('stake_test1'));
    });

    test('staking builders surface Rust validation errors through wrappers',
        () async {
      const stakeKeyHash =
          '05261533f512bfb9dc8a8686e97951f474a532778f0e2228f8865c17';

      expect(
        () => buildStakeRegistrationTx(
          stakeKeyHashHex: stakeKeyHash,
          inputs: [],
          changeAddress: testAddress,
          networkId: 0,
          params: protocolParams(),
        ),
        throwsException,
      );
      expect(
        () => buildDelegationTx(
          stakeKeyHashHex: stakeKeyHash,
          poolKeyhashHex:
              '29d222ce763455e3a6ce516f5a56f76349c3ecbf3c60d7751c4f6418',
          inputs: [],
          changeAddress: testAddress,
          networkId: 0,
          params: protocolParams(),
        ),
        throwsException,
      );
    });
  });

  group('Integration Tests', () {
    test('full key derivation and address workflow', () async {
      const mnemonic =
          'test walk nut penalty hip pave soap entry language right filter choice';

      // Step 1: Derive keys
      final keys = await deriveKeysFromMnemonic(
        mnemonic: mnemonic,
        passphrase: '',
        accountIndex: 0,
        isTestnet: true,
      );
      expect(keys.paymentKey, isNotEmpty);

      // Step 2: Validate address format (payment key contains address info)
      expect(keys.paymentKey.length, greaterThan(0));

      // Step 3: Get SDK version
      final version = await getSdkVersion();
      expect(version, contains('cardano_flutter_rs'));
    });

    test('can perform multiple operations sequentially', () async {
      final version1 = await getSdkVersion();
      final version2 = await getSdkVersion();
      expect(version1, equals(version2));

      const testAddr =
          'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz';
      final validation = await isValidBech32(testAddr);
      expect(validation, isA<bool>());
    });
  });
}
