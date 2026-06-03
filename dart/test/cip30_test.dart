// Tests for the Phase 4.3 CIP-30 dApp connector: serialization/signing
// primitives and the high-level Cip30Wallet orchestration class.

import 'dart:convert';

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const testMnemonic =
    'test walk nut penalty hip pave soap entry language right filter choice';

String utf8Hex(String s) => utf8
    .encode(s)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  group('CIP-30 address primitives', () {
    late KeyDerivationResult keys;

    setUp(() async {
      keys = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: '',
        accountIndex: 0,
        isTestnet: true,
      );
    });

    test('computeBaseAddress produces a valid testnet base address', () async {
      final addr = computeBaseAddress(
        paymentKeyHashHex: keys.paymentKeyHash,
        stakeKeyHashHex: keys.stakeKeyHash,
        networkId: 0,
      );
      expect(addr.startsWith('addr_test1'), isTrue);
      expect(await isValidBech32(addr), isTrue);
    });

    test('computeBaseAddress produces a valid mainnet base address', () async {
      final addr = computeBaseAddress(
        paymentKeyHashHex: keys.paymentKeyHash,
        stakeKeyHashHex: keys.stakeKeyHash,
        networkId: 1,
      );
      expect(addr.startsWith('addr1'), isTrue);
      expect(await isValidBech32(addr), isTrue);
    });

    test('addressToHex returns non-empty hex', () {
      final addr = computeBaseAddress(
        paymentKeyHashHex: keys.paymentKeyHash,
        stakeKeyHashHex: keys.stakeKeyHash,
        networkId: 0,
      );
      final hex = addressToHex(addressBech32: addr);
      expect(hex, isNotEmpty);
      expect(hex.length.isEven, isTrue);
    });
  });

  group('CIP-30 value / utxo serialization', () {
    test('valueToCborHex encodes pure ADA', () {
      final hex = valueToCborHex(
        value: Value(coin: BigInt.from(2000000), assets: []),
      );
      expect(hex, isNotEmpty);
    });

    test('utxoToCborHex encodes a TransactionUnspentOutput', () {
      final input = TxInput(
        txHash:
            '0000000000000000000000000000000000000000000000000000000000000000',
        outputIndex: 0,
        address:
            'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz',
        value: Value(coin: BigInt.from(5000000), assets: []),
      );
      final hex = utxoToCborHex(input: input);
      expect(hex, isNotEmpty);
    });

    test('sumValues adds ADA across UTxOs', () {
      final total = sumValues(values: [
        Value(coin: BigInt.from(1000000), assets: []),
        Value(coin: BigInt.from(2500000), assets: []),
      ]);
      expect(total.coin, BigInt.from(3500000));
      expect(total.assets, isEmpty);
    });

    test('sumValues aggregates native assets', () {
      const policy = 'a0028f350aaabe0545fdcb56b039bfb08e4bb4d8c4d7c3c7d481c235';
      final name = utf8Hex('TOKEN');
      final total = sumValues(values: [
        Value(coin: BigInt.from(1000000), assets: [
          NativeAsset(policyId: policy, assetName: name, quantity: BigInt.from(10)),
        ]),
        Value(coin: BigInt.from(2000000), assets: [
          NativeAsset(policyId: policy, assetName: name, quantity: BigInt.from(5)),
        ]),
      ]);
      expect(total.coin, BigInt.from(3000000));
      expect(total.assets.length, 1);
      expect(total.assets.first.quantity, BigInt.from(15));
    });
  });

  group('CIP-30 signData / verifyData', () {
    test('round-trips: sign then verify', () async {
      final keys = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: '',
        accountIndex: 0,
        isTestnet: true,
      );
      final addr = computeBaseAddress(
        paymentKeyHashHex: keys.paymentKeyHash,
        stakeKeyHashHex: keys.stakeKeyHash,
        networkId: 0,
      );
      final addrHex = addressToHex(addressBech32: addr);
      final payload = utf8Hex('Login at 2026-06-02');

      final sig = cip30SignData(
        addressHex: addrHex,
        payloadHex: payload,
        signingKeyBech32: keys.paymentSigningKey,
      );
      expect(sig.signature, isNotEmpty);
      expect(sig.key, isNotEmpty);

      expect(
        cip30VerifyData(dataSignature: sig, expectedPayloadHex: payload),
        isTrue,
      );
      expect(cip30VerifyData(dataSignature: sig), isTrue);
    });

    test('verify fails for a different payload', () async {
      final keys = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: '',
        accountIndex: 0,
        isTestnet: true,
      );
      final addrHex = addressToHex(
        addressBech32: computeBaseAddress(
          paymentKeyHashHex: keys.paymentKeyHash,
          stakeKeyHashHex: keys.stakeKeyHash,
          networkId: 0,
        ),
      );
      final sig = cip30SignData(
        addressHex: addrHex,
        payloadHex: utf8Hex('original'),
        signingKeyBech32: keys.paymentSigningKey,
      );
      expect(
        cip30VerifyData(
            dataSignature: sig, expectedPayloadHex: utf8Hex('tampered')),
        isFalse,
      );
    });
  });

  group('Cip30Wallet', () {
    // A MockClient that returns canned Blockfrost responses.
    BlockfrostProvider providerWithUtxos(List<Map<String, dynamic>> utxos) {
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.contains('/utxos')) {
          return http.Response(jsonEncode(utxos), 200);
        }
        return http.Response('Not found', 404);
      });
      return BlockfrostProvider(
        projectId: 'test',
        network: Network.testnetPreview,
        client: client,
      );
    }

    Map<String, dynamic> lovelaceUtxo(String address, int lovelace, int idx) => {
          'address': address,
          'tx_hash':
              '00000000000000000000000000000000000000000000000000000000000000$idx$idx',
          'output_index': idx,
          'amount': [
            {'unit': 'lovelace', 'quantity': '$lovelace'},
          ],
        };

    test('fromMnemonic derives base + reward addresses', () async {
      final wallet = await Cip30Wallet.fromMnemonic(
        mnemonic: testMnemonic,
        provider: providerWithUtxos([]),
      );
      expect(wallet.baseAddress.startsWith('addr_test1'), isTrue);
      expect(wallet.rewardAddress.startsWith('stake_test1'), isTrue);
      expect(await wallet.getNetworkId(), 0);
    });

    test('getChangeAddress / getRewardAddresses return hex', () async {
      final wallet = await Cip30Wallet.fromMnemonic(
        mnemonic: testMnemonic,
        provider: providerWithUtxos([]),
      );
      final change = await wallet.getChangeAddress();
      expect(change, isNotEmpty);
      expect(change, addressToHex(addressBech32: wallet.baseAddress));

      final rewards = await wallet.getRewardAddresses();
      expect(rewards, hasLength(1));
      expect(rewards.first, addressToHex(addressBech32: wallet.rewardAddress));
    });

    test('getUtxos returns CBOR hex per UTxO', () async {
      late Cip30Wallet wallet;
      wallet = await Cip30Wallet.fromMnemonic(
        mnemonic: testMnemonic,
        provider: providerWithUtxos(const []),
      );
      // Rebuild provider now that we know the address.
      final provider = providerWithUtxos([
        lovelaceUtxo(wallet.baseAddress, 3000000, 0),
        lovelaceUtxo(wallet.baseAddress, 7000000, 1),
      ]);
      wallet = await Cip30Wallet.fromMnemonic(
        mnemonic: testMnemonic,
        provider: provider,
      );
      final utxos = await wallet.getUtxos();
      expect(utxos, hasLength(2));
      for (final u in utxos) {
        expect(u, isNotEmpty);
      }
    });

    test('getBalance sums UTxOs into a CBOR Value', () async {
      var wallet = await Cip30Wallet.fromMnemonic(
        mnemonic: testMnemonic,
        provider: providerWithUtxos(const []),
      );
      final provider = providerWithUtxos([
        lovelaceUtxo(wallet.baseAddress, 3000000, 0),
        lovelaceUtxo(wallet.baseAddress, 7000000, 1),
      ]);
      wallet = await Cip30Wallet.fromMnemonic(
        mnemonic: testMnemonic,
        provider: provider,
      );
      final balance = await wallet.getBalance();
      expect(balance, isNotEmpty);
      // 10 ADA total encoded; cross-check via sumValues primitive.
      final expected = valueToCborHex(
        value: Value(coin: BigInt.from(10000000), assets: []),
      );
      expect(balance, expected);
    });

    test('getBalance returns zero Value for empty wallet', () async {
      final wallet = await Cip30Wallet.fromMnemonic(
        mnemonic: testMnemonic,
        provider: providerWithUtxos(const []),
      );
      final balance = await wallet.getBalance();
      expect(
        balance,
        valueToCborHex(value: Value(coin: BigInt.zero, assets: [])),
      );
    });

    test('used/unused address lists flip on UTxO presence', () async {
      // Empty wallet: base address is unused.
      final empty = await Cip30Wallet.fromMnemonic(
        mnemonic: testMnemonic,
        provider: providerWithUtxos(const []),
      );
      expect(await empty.getUsedAddresses(), isEmpty);
      expect(await empty.getUnusedAddresses(), hasLength(1));

      // Funded wallet: base address is used.
      var funded = await Cip30Wallet.fromMnemonic(
        mnemonic: testMnemonic,
        provider: providerWithUtxos(const []),
      );
      funded = await Cip30Wallet.fromMnemonic(
        mnemonic: testMnemonic,
        provider: providerWithUtxos([
          lovelaceUtxo(funded.baseAddress, 5000000, 0),
        ]),
      );
      expect(await funded.getUsedAddresses(), hasLength(1));
      expect(await funded.getUnusedAddresses(), isEmpty);
    });

    test('signData via wallet round-trips with verify', () async {
      final wallet = await Cip30Wallet.fromMnemonic(
        mnemonic: testMnemonic,
        provider: providerWithUtxos(const []),
      );
      final payload = utf8Hex('dApp login');
      final sig = await wallet.signData(payload);
      expect(cip30VerifyData(dataSignature: sig, expectedPayloadHex: payload),
          isTrue);
    });
  });

  group('CIP-30 signTx', () {
    test('returns a witness set for a real transaction', () async {
      final keys = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: '',
        accountIndex: 0,
        isTestnet: true,
      );
      final base = computeBaseAddress(
        paymentKeyHashHex: keys.paymentKeyHash,
        stakeKeyHashHex: keys.stakeKeyHash,
        networkId: 0,
      );
      final params = ProtocolParams(
        minFeeA: BigInt.from(44),
        minFeeB: BigInt.from(155381),
        coinsPerUtxoByte: BigInt.from(4310),
        maxTxSize: 16384,
        poolDeposit: BigInt.from(500000000),
        keyDeposit: BigInt.from(2000000),
        maxValSize: 5000,
      );
      final built = buildTx(
        inputs: [
          TxInput(
            txHash:
                '0000000000000000000000000000000000000000000000000000000000000000',
            outputIndex: 0,
            address: base,
            value: Value(coin: BigInt.from(10000000), assets: []),
          ),
        ],
        outputs: [
          TxOutput(
            address: base,
            value: Value(coin: BigInt.from(2000000), assets: []),
          ),
        ],
        changeAddress: base,
        ttl: null,
        params: params,
      );

      // Wrap the body into a full transaction by signing once.
      final signed = await signTransaction(
        txBodyCborHex: built.txBodyCborHex,
        paymentKeys: [keys.paymentSigningKey],
      );

      final witnessSetHex = cip30SignTx(
        txCborHex: signed.txCborHex,
        signingKeysBech32: [keys.paymentSigningKey],
      );
      expect(witnessSetHex, isNotEmpty);
      expect(witnessSetHex.length.isEven, isTrue);
    });
  });
}
