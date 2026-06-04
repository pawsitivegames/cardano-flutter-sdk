// Tests for the Phase 4.5 hardware-wallet layer: xpub→account derivation, raw
// vkey-witness assemble/extract, and the HardwareCip30Wallet orchestration
// (read surface + device-signing assembly), all without a physical device.
//
// The signing round-trip uses a MockHardwareWallet whose witnesses are produced
// by the SOFTWARE signing path (cip30SignTx) and pulled out as raw pairs via
// extractVkeyWitnesses — so the assembled transaction is exercised with real
// Ed25519 signatures, and is asserted byte-identical to the software-signed tx.

import 'dart:convert';

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const testMnemonic =
    'test walk nut penalty hip pave soap entry language right filter choice';

// Account-level xpub for `testMnemonic` at m/1852'/1815'/0' (64-byte BIP-32
// public key: 32-byte raw key + 32-byte chain code). Reproducible from the
// mnemonic via Bip32PrivateKey → account → to_public().
const testAccountXpub =
    'cf779aa32f35083707808532471cb64ee41426c9bbd46134dac2ac5b2a0ec0e9'
    '8fa5fcd46abd9d46d4d8a97a8f3465e2c4e8f3c9dad9ff66823a161ecadca604';

/// A fake [HardwareWallet] that returns a fixed xpub and a fixed witness list.
class MockHardwareWallet implements HardwareWallet {
  final String xpub;
  List<HardwareVkeyWitness> witnesses;
  HardwareSignRequest? lastRequest;

  MockHardwareWallet({required this.xpub, this.witnesses = const []});

  @override
  String get deviceName => 'MockLedger';

  @override
  Future<String> getAccountXpub({int accountIndex = 0}) async => xpub;

  @override
  Future<List<HardwareVkeyWitness>> signTransaction(
      HardwareSignRequest request) async {
    lastRequest = request;
    return witnesses;
  }
}

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  group('xpubToAccount', () {
    test('matches the mnemonic-derived key hashes and addresses', () async {
      final keys = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: '',
        accountIndex: 0,
        isTestnet: true,
      );
      final account = xpubToAccount(
        accountXpubHex: testAccountXpub,
        networkId: 0,
      );

      // Public soft-derivation lands on the identical credentials as the
      // private mnemonic path.
      expect(account.paymentKeyHash, keys.paymentKeyHash);
      expect(account.stakeKeyHash, keys.stakeKeyHash);

      // And therefore the identical addresses.
      final base = computeBaseAddress(
        paymentKeyHashHex: keys.paymentKeyHash,
        stakeKeyHashHex: keys.stakeKeyHash,
        networkId: 0,
      );
      expect(account.baseAddress, base);
      expect(account.baseAddress.startsWith('addr_test1'), isTrue);
      expect(account.rewardAddress.startsWith('stake_test1'), isTrue);
    });

    test('mainnet network id yields mainnet prefixes', () {
      final account = xpubToAccount(
        accountXpubHex: testAccountXpub,
        networkId: 1,
      );
      expect(account.baseAddress.startsWith('addr1'), isTrue);
      expect(account.rewardAddress.startsWith('stake1'), isTrue);
    });

    test('rejects a malformed xpub', () {
      expect(
        () => xpubToAccount(accountXpubHex: 'deadbeef', networkId: 0),
        throwsA(anything),
      );
    });
  });

  group('vkey witness assemble/extract', () {
    test('extract is the inverse of assemble', () async {
      // Produce a real witness set via the software signing path.
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
      final built = _buildSampleTx(base);
      final signed = await signTransaction(
        txBodyCborHex: built.txBodyCborHex,
        paymentKeys: [keys.paymentSigningKey],
      );
      final softwareWitnessSet = cip30SignTx(
        txCborHex: signed.txCborHex,
        signingKeysBech32: [keys.paymentSigningKey],
      );

      final pairs = extractVkeyWitnesses(witnessSetCborHex: softwareWitnessSet);
      expect(pairs, hasLength(1));
      expect(pairs.first.vkeyHex.length, 64); // 32-byte pubkey
      expect(pairs.first.signatureHex.length, 128); // 64-byte signature

      final reassembled = assembleVkeyWitnessSet(witnesses: pairs);
      final reExtracted =
          extractVkeyWitnesses(witnessSetCborHex: reassembled);
      expect(reExtracted.first.vkeyHex, pairs.first.vkeyHex);
      expect(reExtracted.first.signatureHex, pairs.first.signatureHex);
    });
  });

  group('HardwareCip30Wallet', () {
    BlockfrostProvider providerWithUtxos(List<Map<String, dynamic>> utxos) {
      final client = MockClient((request) async {
        if (request.url.path.contains('/utxos')) {
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

    Map<String, dynamic> lovelaceUtxo(String address, int lovelace, int idx) =>
        {
          'address': address,
          'tx_hash':
              '00000000000000000000000000000000000000000000000000000000000000$idx$idx',
          'output_index': idx,
          'amount': [
            {'unit': 'lovelace', 'quantity': '$lovelace'},
          ],
        };

    test('fromDevice derives addresses from the device xpub', () async {
      final device = MockHardwareWallet(xpub: testAccountXpub);
      final wallet = await HardwareCip30Wallet.fromDevice(
        device: device,
        provider: providerWithUtxos([]),
      );
      expect(wallet.baseAddress.startsWith('addr_test1'), isTrue);
      expect(wallet.rewardAddress.startsWith('stake_test1'), isTrue);
      expect(await wallet.getNetworkId(), 0);
      expect(wallet.paymentPath, [
        1852 | 0x80000000,
        1815 | 0x80000000,
        0 | 0x80000000,
        0,
        0,
      ]);
      expect(wallet.stakePath.last, 0);
      expect(wallet.stakePath[3], 2);
    });

    test('read surface returns CBOR hex backed by the provider', () async {
      final device = MockHardwareWallet(xpub: testAccountXpub);
      // Derive the address first so the provider can be primed for it.
      final addr = xpubToAccount(accountXpubHex: testAccountXpub, networkId: 0)
          .baseAddress;
      final wallet = await HardwareCip30Wallet.fromDevice(
        device: device,
        provider: providerWithUtxos([
          lovelaceUtxo(addr, 3000000, 0),
          lovelaceUtxo(addr, 7000000, 1),
        ]),
      );

      final utxos = await wallet.getUtxos();
      expect(utxos, hasLength(2));
      expect(utxos.every((u) => u.isNotEmpty && u.length.isEven), isTrue);

      final balance = await wallet.getBalance();
      expect(balance, isNotEmpty);

      final used = await wallet.getUsedAddresses();
      expect(used, hasLength(1));
      expect(used.first, addressToHex(addressBech32: wallet.baseAddress));

      final change = await wallet.getChangeAddress();
      expect(change, addressToHex(addressBech32: wallet.baseAddress));

      final rewards = await wallet.getRewardAddresses();
      expect(rewards.first, addressToHex(addressBech32: wallet.rewardAddress));
    });

    test('signTransaction assembles a tx byte-identical to software signing',
        () async {
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
      final built = _buildSampleTx(base);

      // Software-sign to get the reference witnesses + reference signed tx.
      final signed = await signTransaction(
        txBodyCborHex: built.txBodyCborHex,
        paymentKeys: [keys.paymentSigningKey],
      );
      final softwareWitnessSet = cip30SignTx(
        txCborHex: signed.txCborHex,
        signingKeysBech32: [keys.paymentSigningKey],
      );
      final referenceTx = cip30AssembleTx(
        txBodyCborHex: built.txBodyCborHex,
        witnessSetCborHex: softwareWitnessSet,
      );

      // Feed those real witnesses to the device and let the hardware wallet
      // assemble — the result must be byte-identical.
      final device = MockHardwareWallet(
        xpub: testAccountXpub,
        witnesses:
            extractVkeyWitnesses(witnessSetCborHex: softwareWitnessSet),
      );
      final wallet = await HardwareCip30Wallet.fromDevice(
        device: device,
        provider: providerWithUtxos([]),
      );
      final hardwareTx = await wallet.signTransaction(HardwareSignRequest(
        txBodyCborHex: built.txBodyCborHex,
        signerPaths: [wallet.paymentPath],
      ));

      expect(hardwareTx, referenceTx);
      // The device received the request it was meant to sign.
      expect(device.lastRequest?.txBodyCborHex, built.txBodyCborHex);
      expect(device.lastRequest?.signerPaths, [wallet.paymentPath]);
    });

    test('signTx returns just the witness set', () async {
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
      final built = _buildSampleTx(base);
      final signed = await signTransaction(
        txBodyCborHex: built.txBodyCborHex,
        paymentKeys: [keys.paymentSigningKey],
      );
      final softwareWitnessSet = cip30SignTx(
        txCborHex: signed.txCborHex,
        signingKeysBech32: [keys.paymentSigningKey],
      );
      final device = MockHardwareWallet(
        xpub: testAccountXpub,
        witnesses:
            extractVkeyWitnesses(witnessSetCborHex: softwareWitnessSet),
      );
      final wallet = await HardwareCip30Wallet.fromDevice(
        device: device,
        provider: providerWithUtxos([]),
      );
      final witnessSet = await wallet.signTx(built.txBodyCborHex);
      // Round-trips back to the same witnesses.
      final pairs = extractVkeyWitnesses(witnessSetCborHex: witnessSet);
      expect(pairs, hasLength(1));
    });
  });

  group('xpubDerivePublicKey', () {
    test('role-0 pubkey matches the software payment witness pubkey', () async {
      // Software-sign a tx, extract the payment vkey it used, and confirm the
      // public soft-derivation at role 0/index 0 reproduces exactly that key.
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
      final built = _buildSampleTx(base);
      final signed = await signTransaction(
        txBodyCborHex: built.txBodyCborHex,
        paymentKeys: [keys.paymentSigningKey],
      );
      final softwarePubkey = extractVkeyWitnesses(
        witnessSetCborHex: cip30SignTx(
          txCborHex: signed.txCborHex,
          signingKeysBech32: [keys.paymentSigningKey],
        ),
      ).first.vkeyHex;

      final payPub = xpubDerivePublicKey(
          accountXpubHex: testAccountXpub, role: 0, index: 0);
      final stakePub = xpubDerivePublicKey(
          accountXpubHex: testAccountXpub, role: 2, index: 0);
      expect(payPub.length, 64); // 32-byte raw Ed25519 public key
      expect(payPub, softwarePubkey);
      // Stake key is a distinct soft-derivation.
      expect(stakePub, isNot(payPub));
    });

    test('rejects a malformed xpub', () {
      expect(
        () => xpubDerivePublicKey(
            accountXpubHex: 'deadbeef', role: 0, index: 0),
        throwsA(anything),
      );
    });
  });

  group('decomposeTxBody', () {
    test('breaks a payment body into device-signable parts', () async {
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
      final built = _buildSampleTx(base);
      final parts = decomposeTxBody(txBodyCborHex: built.txBodyCborHex);

      expect(parts.inputs, hasLength(1));
      expect(parts.inputs.first.txHashHex,
          '0000000000000000000000000000000000000000000000000000000000000000');
      expect(parts.inputs.first.outputIndex, 0);
      expect(parts.outputs, isNotEmpty);
      // Every output amount and the fee parse as integers.
      expect(BigInt.parse(parts.outputs.first.coin), greaterThan(BigInt.zero));
      expect(BigInt.parse(parts.fee), greaterThan(BigInt.zero));
      // Plain payment carries no certs/withdrawals/mint/etc.
      expect(parts.hasUnsupportedFeatures, isFalse);
    });

    test('rejects malformed CBOR', () {
      expect(
        () => decomposeTxBody(txBodyCborHex: '00'),
        throwsA(anything),
      );
    });
  });

  // Simulates exactly what the Ledger adapter does on-device: the "device"
  // returns each signature paired only with a derivation path, and the adapter
  // re-derives the public key from the account xpub (xpubDerivePublicKey) to
  // rebuild a full vkey witness. Using a real software signature, the assembled
  // transaction must be byte-identical to the software-signed reference — so the
  // adapter's witness-reconstruction logic is proven without a physical device.
  group('device witness reconstruction (no device)', () {
    test('path + re-derived pubkey + real signature → identical tx', () async {
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
      final built = _buildSampleTx(base);
      final signed = await signTransaction(
        txBodyCborHex: built.txBodyCborHex,
        paymentKeys: [keys.paymentSigningKey],
      );
      final softwareWitnessSet = cip30SignTx(
        txCborHex: signed.txCborHex,
        signingKeysBech32: [keys.paymentSigningKey],
      );
      final referenceTx = cip30AssembleTx(
        txBodyCborHex: built.txBodyCborHex,
        witnessSetCborHex: softwareWitnessSet,
      );

      // The device gives us only (path, signature) — discard the pubkey.
      final deviceSig =
          extractVkeyWitnesses(witnessSetCborHex: softwareWitnessSet)
              .first
              .signatureHex;
      // Re-derive the payment pubkey from the xpub (path role 0, index 0).
      final reconstructed = HardwareVkeyWitness(
        vkeyHex: xpubDerivePublicKey(
            accountXpubHex: testAccountXpub, role: 0, index: 0),
        signatureHex: deviceSig,
      );

      final witnessSet = assembleVkeyWitnessSet(witnesses: [reconstructed]);
      final assembled = cip30AssembleTx(
        txBodyCborHex: built.txBodyCborHex,
        witnessSetCborHex: witnessSet,
      );
      expect(assembled, referenceTx);
    });
  });
}

ProtocolParams _params() => ProtocolParams(
      minFeeA: BigInt.from(44),
      minFeeB: BigInt.from(155381),
      coinsPerUtxoByte: BigInt.from(4310),
      maxTxSize: 16384,
      poolDeposit: BigInt.from(500000000),
      keyDeposit: BigInt.from(2000000),
      maxValSize: 5000,
    );

BuiltTx _buildSampleTx(String address) => buildTx(
      inputs: [
        TxInput(
          txHash:
              '0000000000000000000000000000000000000000000000000000000000000000',
          outputIndex: 0,
          address: address,
          value: Value(coin: BigInt.from(10000000), assets: []),
        ),
      ],
      outputs: [
        TxOutput(
          address: address,
          value: Value(coin: BigInt.from(2000000), assets: []),
        ),
      ],
      changeAddress: address,
      ttl: null,
      params: _params(),
    );
