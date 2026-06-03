// Tests for the Phase 4.4 CIP-45 protocol core: the CIP-13 connection URI and
// the wallet-side RPC request handler bridging to Cip30Wallet.

import 'dart:convert';

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const testMnemonic =
    'test walk nut penalty hip pave soap entry language right filter choice';

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  group('Cip45ConnectionUri', () {
    const id =
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';

    test('builds a CIP-13 web+cardano URI', () {
      final uri = Cip45ConnectionUri(identifier: id);
      expect(
        uri.toUriString(),
        'web+cardano://connect/v1?identifier=$id',
      );
    });

    test('round-trips build → parse', () {
      final uri = Cip45ConnectionUri(identifier: id);
      final parsed = Cip45ConnectionUri.parse(uri.toUriString());
      expect(parsed.identifier, id);
      expect(parsed.version, 'v1');
      expect(parsed, uri);
    });

    test('parses a scanned URI with surrounding whitespace', () {
      final parsed = Cip45ConnectionUri.parse(
        '  web+cardano://connect/v1?identifier=$id  ',
      );
      expect(parsed.identifier, id);
    });

    test('rejects wrong scheme', () {
      expect(
        () => Cip45ConnectionUri.parse('https://connect/v1?identifier=$id'),
        throwsFormatException,
      );
    });

    test('rejects wrong authority', () {
      expect(
        () => Cip45ConnectionUri.parse('web+cardano://pair/v1?identifier=$id'),
        throwsFormatException,
      );
    });

    test('rejects missing identifier', () {
      expect(
        () => Cip45ConnectionUri.parse('web+cardano://connect/v1'),
        throwsFormatException,
      );
    });
  });

  group('Cip45WalletHandler', () {
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

    Future<Cip45WalletHandler> handler(
        [List<Map<String, dynamic>> utxos = const []]) async {
      final wallet = await Cip30Wallet.fromMnemonic(
        mnemonic: testMnemonic,
        provider: providerWithUtxos(utxos),
      );
      return Cip45WalletHandler(wallet: wallet, name: 'TestWallet');
    }

    test('apiAnnouncement has CIP-45 shape', () async {
      final h = await handler();
      final ann = h.apiAnnouncement();
      expect(ann['api'], isA<Map>());
      final api = ann['api'] as Map;
      expect(api['name'], 'TestWallet');
      expect(api['version'], '1.0.0');
      expect(api['methods'], contains('signData'));
      expect(api['methods'], contains('getRewardAddresses'));
    });

    test('supportedMethods covers the CIP-30 surface', () async {
      final h = await handler();
      expect(
        h.supportedMethods,
        containsAll(<String>[
          'getNetworkId',
          'getUtxos',
          'getBalance',
          'getUsedAddresses',
          'getUnusedAddresses',
          'getChangeAddress',
          'getRewardAddresses',
          'signTx',
          'signData',
          'submitTx',
        ]),
      );
    });

    test('dispatches getNetworkId', () async {
      final h = await handler();
      expect(await h.handleRequest('getNetworkId'), 0);
    });

    test('dispatches getRewardAddresses', () async {
      final h = await handler();
      final res = await h.handleRequest('getRewardAddresses');
      expect(res, isA<List>());
      expect((res as List).length, 1);
    });

    test('dispatches getChangeAddress as hex', () async {
      final h = await handler();
      final res = await h.handleRequest('getChangeAddress');
      expect(res, isA<String>());
      expect((res as String).isNotEmpty, isTrue);
    });

    test('dispatches signData and returns {signature, key}', () async {
      final h = await handler();
      final payloadHex = utf8
          .encode('CIP-45 login')
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final addrHex = await h.wallet.getChangeAddress();

      final res = await h.handleRequest('signData', [addrHex, payloadHex]);
      expect(res, isA<Map>());
      final map = res as Map;
      expect(map['signature'], isA<String>());
      expect(map['key'], isA<String>());

      // The returned DataSignature verifies.
      final sig = DataSignature(
        signature: map['signature'] as String,
        key: map['key'] as String,
      );
      expect(
        cip30VerifyData(dataSignature: sig, expectedPayloadHex: payloadHex),
        isTrue,
      );
    });

    test('throws Cip45UnsupportedMethod for unknown method', () async {
      final h = await handler();
      expect(
        () => h.handleRequest('cardano_doMagic'),
        throwsA(isA<Cip45UnsupportedMethod>()),
      );
    });

    test('throws Cip45InvalidParams when signData missing params', () async {
      final h = await handler();
      expect(
        () => h.handleRequest('signData', ['only-one-arg']),
        throwsA(isA<Cip45InvalidParams>()),
      );
    });

    test('supports() reflects the method table', () async {
      final h = await handler();
      expect(h.supports('signTx'), isTrue);
      expect(h.supports('nope'), isFalse);
    });
  });
}
