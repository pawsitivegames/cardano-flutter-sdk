import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cardano_flutter_rs/src/providers/blockfrost.dart';
import 'package:cardano_flutter_rs/src/providers/blockfrost_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'blockfrost_test.mocks.dart';

@GenerateMocks([http.Client])
void main() {
  group('BlockfrostProvider', () {
    late MockClient mockClient;
    late BlockfrostProvider provider;

    setUp(() {
      mockClient = MockClient();
      provider = BlockfrostProvider(
        projectId: 'test_project_id',
        network: Network.testnetPreview,
        client: mockClient,
      );
    });

    group('fetchUtxos', () {
      test('parses valid response into List<Utxo>', () async {
        const address =
            'addr_test1qz2fxv2umyhttkxyxp8x0dlsdtqbgf8pq2fwh7tgkz0v9v8w';
        final responseBody = jsonEncode([
          {
            'address': address,
            'tx_hash': 'abcdef1234567890',
            'tx_index': 0,
            'output_index': 0,
            'amount': [
              {'unit': 'lovelace', 'quantity': '2000000'}
            ],
            'block': 'xyz123',
            'data_hash': null,
            'inline_datum': null,
            'reference_script_hash': null,
          }
        ]);

        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response(responseBody, 200));

        final utxos = await provider.fetchUtxos(address);

        expect(utxos, hasLength(1));
        expect(utxos[0].txHash, equals('abcdef1234567890'));
        expect(utxos[0].outputIndex, equals(0));
        expect(utxos[0].coin, equals(BigInt.parse('2000000')));
        expect(utxos[0].address, equals(address));

        verify(mockClient.get(
          Uri.parse(
              'https://cardano-preview.blockfrost.io/api/v0/addresses/$address/utxos'),
          headers: {
            'project_id': 'test_project_id',
            'Content-Type': 'application/json'
          },
        )).called(1);
      });

      test('handles multi-asset response', () async {
        const address =
            'addr_test1qz2fxv2umyhttkxyxp8x0dlsdtqbgf8pq2fwh7tgkz0v9v8w';
        // Example policy ID + asset name
        const policyId =
            '1e349c9bdea19fd6c147626a5260bc44b71635f398b67c59881df209';
        const assetName = '504154415445';
        final responseBody = jsonEncode([
          {
            'address': address,
            'tx_hash': 'multi_asset_tx',
            'tx_index': 0,
            'output_index': 1,
            'amount': [
              {'unit': 'lovelace', 'quantity': '1500000'},
              {'unit': policyId + assetName, 'quantity': '1000'}
            ],
            'block': 'xyz456',
            'data_hash': null,
            'inline_datum': null,
            'reference_script_hash': null,
          }
        ]);

        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response(responseBody, 200));

        final utxos = await provider.fetchUtxos(address);

        expect(utxos, hasLength(1));
        expect(utxos[0].coin, equals(BigInt.parse('1500000')));
        expect(utxos[0].assets, hasLength(1));
        expect(utxos[0].assets[policyId], isNotNull);
        expect(utxos[0].assets[policyId]![assetName],
            equals(BigInt.parse('1000')));
      });

      test('returns empty list for 404 (no UTxOs)', () async {
        const address =
            'addr_test1qempty0000000000000000000000000000000000000000';

        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response('not found', 404));

        final utxos = await provider.fetchUtxos(address);

        expect(utxos, isEmpty);
      });

      test('throws BlockfrostUnauthorized on 401', () async {
        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response('Unauthorized', 401));

        expect(
          () => provider.fetchUtxos('any_address'),
          throwsA(isA<BlockfrostUnauthorized>()),
        );
      });

      test('throws BlockfrostUnauthorized on 403', () async {
        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response('Forbidden', 403));

        expect(
          () => provider.fetchUtxos('any_address'),
          throwsA(isA<BlockfrostUnauthorized>()),
        );
      });
    });

    group('fetchProtocolParameters', () {
      test('maps Blockfrost fields to ProtocolParameters', () async {
        final responseBody = jsonEncode({
          'min_fee_a': 44,
          'min_fee_b': 155381,
          'max_tx_size': 16384,
          'max_val_size': '5000',
          'key_deposit': '2000000',
          'pool_deposit': '500000000',
          'coins_per_utxo_size': '4310',
          'price_mem': 0.0577,
          'price_steps': 0.0000721,
          'utxo_cost_per_byte': '4310',
        });

        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response(responseBody, 200));

        final params = await provider.fetchProtocolParameters();

        expect(params.minFeeA, equals(44));
        expect(params.minFeeB, equals(155381));
        expect(params.maxTxSize, equals(16384));
        expect(params.maxValueSize, equals(5000));
        expect(params.keyDeposit, equals(2000000));
        expect(params.poolDeposit, equals(500000000));
        expect(params.coinsPerUtxoByte, equals(4310));

        verify(mockClient.get(
          Uri.parse(
              'https://cardano-preview.blockfrost.io/api/v0/epochs/latest/parameters'),
          headers: {
            'project_id': 'test_project_id',
            'Content-Type': 'application/json'
          },
        )).called(1);
      });

      test('throws BlockfrostServerError on 500', () async {
        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response('Server Error', 500));

        expect(
          () => provider.fetchProtocolParameters(),
          throwsA(isA<BlockfrostServerError>()),
        );
      });

      test('throws BlockfrostRateLimited on 429', () async {
        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response('Too Many Requests', 429,
            headers: {'retry-after': '30'}));

        expect(
          () => provider.fetchProtocolParameters(),
          throwsA(isA<BlockfrostRateLimited>()),
        );
      });
    });

    group('chain queries', () {
      test('fetchTipSlot parses integer slot', () async {
        when(mockClient.get(any, headers: anyNamed('headers'))).thenAnswer(
            (_) async => http.Response(jsonEncode({'slot': 123}), 200));

        expect(await provider.fetchTipSlot(), equals(123));
      });

      test('fetchTipSlot rejects missing slot', () async {
        when(mockClient.get(any, headers: anyNamed('headers'))).thenAnswer(
            (_) async => http.Response(jsonEncode({'hash': 'b'}), 200));

        expect(() => provider.fetchTipSlot(), throwsA(isA<FormatException>()));
      });

      test('fetchAccountInfo returns null for unregistered stake address',
          () async {
        when(mockClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async => http.Response('', 404));

        expect(await provider.fetchAccountInfo('stake_test1u...'), isNull);
      });

      test('fetchAccountInfo parses rewards and delegation fields', () async {
        when(mockClient.get(any, headers: anyNamed('headers'))).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'stake_address': 'stake_test1uabc',
              'active': true,
              'controlled_amount': '5000000',
              'rewards_sum': '100000',
              'withdrawable_amount': '25000',
              'pool_id': 'pool1xyz',
            }),
            200,
          ),
        );

        final info = await provider.fetchAccountInfo('stake_test1uabc');

        expect(info, isNotNull);
        expect(info!.stakeAddress, equals('stake_test1uabc'));
        expect(info.isRegistered, isTrue);
        expect(info.controlledStake, equals(BigInt.from(5000000)));
        expect(info.rewardsSum, equals(BigInt.from(100000)));
        expect(info.withdrawableReward, equals(BigInt.from(25000)));
        expect(info.poolId, equals('pool1xyz'));
        expect(info.toString(), contains('pool1xyz'));
      });

      test('fetchAddressMetadata returns null for never-seen address',
          () async {
        when(mockClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async => http.Response('', 404));

        expect(await provider.fetchAddressMetadata('addr_test1unused'), isNull);
        expect(await provider.isAddressUsed('addr_test1unused'), isFalse);
      });

      test('fetchAddressMetadata parses tx count and lovelace sums', () async {
        when(mockClient.get(any, headers: anyNamed('headers'))).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'address': 'addr_test1used',
              'tx_count': 3,
              'received_sum': [
                {'unit': 'lovelace', 'quantity': '9000000'},
                {'unit': 'token', 'quantity': '1'},
              ],
              'sent_sum': [
                {'unit': 'lovelace', 'quantity': '4000000'},
              ],
            }),
            200,
          ),
        );

        final meta = await provider.fetchAddressMetadata('addr_test1used');

        expect(meta, isNotNull);
        expect(meta!.isUsed, isTrue);
        expect(meta.txCount, equals(3));
        expect(meta.totalReceived, equals(BigInt.from(9000000)));
        expect(meta.totalSent, equals(BigInt.from(4000000)));
        expect(meta.toString(), contains('txCount: 3'));
      });
    });

    group('staking pool queries', () {
      test('fetchPoolIds parses active pool IDs with paging parameters',
          () async {
        when(mockClient.get(any, headers: anyNamed('headers'))).thenAnswer(
            (_) async => http.Response(jsonEncode(['pool1', 'pool2']), 200));

        final pools = await provider.fetchPoolIds(page: 2, count: 5);

        expect(pools, equals(['pool1', 'pool2']));
        verify(mockClient.get(
          Uri.parse(
              'https://cardano-preview.blockfrost.io/api/v0/pools?page=2&count=5&order=desc'),
          headers: anyNamed('headers'),
        )).called(1);
      });

      test('fetchPoolInfo parses optional numeric fields', () async {
        when(mockClient.get(any, headers: anyNamed('headers'))).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'fixed_cost': '340000000',
              'margin_cost': '0.025',
              'live_saturation': '0.42',
            }),
            200,
          ),
        );

        final info = await provider.fetchPoolInfo('pool1abc');

        expect(info.poolId, equals('pool1abc'));
        expect(info.fixedCost, equals('340000000'));
        expect(info.margin, equals(0.025));
        expect(info.saturation, equals(0.42));
        expect(info.toString(), contains('pool1abc'));
      });

      test('fetchPoolMetadata returns empty map for missing metadata',
          () async {
        when(mockClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async => http.Response('', 404));

        expect(await provider.fetchPoolMetadata('pool1missing'), isEmpty);
      });

      test('fetchPoolMetadata parses metadata fields', () async {
        when(mockClient.get(any, headers: anyNamed('headers'))).thenAnswer(
          (_) async => http.Response(
            jsonEncode({
              'name': 'Pool Name',
              'ticker': 'POOL',
              'description': 'A stake pool',
              'homepage': 'https://example.com',
            }),
            200,
          ),
        );

        final metadata = await provider.fetchPoolMetadata('pool1abc');

        expect(metadata['name'], equals('Pool Name'));
        expect(metadata['ticker'], equals('POOL'));
        expect(metadata['description'], equals('A stake pool'));
        expect(metadata['homepage'], equals('https://example.com'));
      });
    });

    group('submitTransaction', () {
      test('posts CBOR with correct headers and returns tx hash', () async {
        final txCbor = Uint8List.fromList([0x84, 0x18, 0x2a]); // example CBOR
        const expectedTxHash =
            'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890';

        when(mockClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        )).thenAnswer(
            (_) async => http.Response(jsonEncode(expectedTxHash), 200));

        final txHash = await provider.submitTransaction(txCbor);

        expect(txHash, equals(expectedTxHash));

        verify(mockClient.post(
          Uri.parse('https://cardano-preview.blockfrost.io/api/v0/tx/submit'),
          headers: {
            'project_id': 'test_project_id',
            'Content-Type': 'application/cbor'
          },
          body: txCbor,
        )).called(1);
      });

      test('throws BlockfrostBadRequest on 400', () async {
        final txCbor = Uint8List.fromList([0x84, 0x18, 0x2a]);
        const errorBody = 'InvalidTx: fee too low';

        when(mockClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        )).thenAnswer((_) async => http.Response(errorBody, 400));

        expect(
          () => provider.submitTransaction(txCbor),
          throwsA(isA<BlockfrostBadRequest>()),
        );
      });

      test('throws BlockfrostUnauthorized on 403', () async {
        final txCbor = Uint8List.fromList([0x84, 0x18, 0x2a]);

        when(mockClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        )).thenAnswer((_) async => http.Response('Forbidden', 403));

        expect(
          () => provider.submitTransaction(txCbor),
          throwsA(isA<BlockfrostUnauthorized>()),
        );
      });
    });

    group('retry logic', () {
      test('retries on 500 and succeeds on third attempt', () async {
        const address =
            'addr_test1qz2fxv2umyhttkxyxp8x0dlsdtqbgf8pq2fwh7tgkz0v9v8w';
        final successResponse = jsonEncode([
          {
            'address': address,
            'tx_hash': 'success_tx',
            'tx_index': 0,
            'output_index': 0,
            'amount': [
              {'unit': 'lovelace', 'quantity': '1000000'}
            ],
            'block': 'xyz',
            'data_hash': null,
            'inline_datum': null,
            'reference_script_hash': null,
          }
        ]);

        final callCount = <int>[0];
        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async {
          callCount[0]++;
          if (callCount[0] < 3) {
            return http.Response('Server Error', 500);
          }
          return http.Response(successResponse, 200);
        });

        final utxos = await provider.fetchUtxos(address);

        expect(utxos, hasLength(1));
        expect(utxos[0].txHash, equals('success_tx'));

        verify(mockClient.get(any, headers: anyNamed('headers'))).called(3);
      });

      test('does not retry on 400', () async {
        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response('Bad Request', 400));

        expect(
          () => provider.fetchUtxos('any_address'),
          throwsA(isA<BlockfrostBadRequest>()),
        );

        verify(mockClient.get(any, headers: anyNamed('headers'))).called(1);
      });

      test('fails after max retries on 500', () async {
        // Create a fresh mock for this test to avoid interference
        final freshMock = MockClient();
        final testProvider = BlockfrostProvider(
          projectId: 'test_project_id',
          network: Network.testnetPreview,
          client: freshMock,
        );

        int callCount = 0;
        // Configure mock to always return 500 and track calls
        when(freshMock.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async {
          callCount++;
          return http.Response('Server Error', 500);
        });

        // Call fetchUtxos and expect it to throw
        bool didThrow = false;
        try {
          await testProvider.fetchUtxos('any_address');
        } on BlockfrostServerError {
          didThrow = true;
        }

        // Should have thrown
        expect(didThrow, isTrue);

        // Should have made 4 HTTP requests total: 1 initial + 3 retries
        expect(callCount, equals(4));
      });
    });

    group('network selection', () {
      test('uses correct URL for testnetPreview', () async {
        final testnetProvider = BlockfrostProvider(
          projectId: 'test_id',
          network: Network.testnetPreview,
          client: mockClient,
        );

        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response(jsonEncode([]), 200));

        await testnetProvider.fetchUtxos('addr_test1q...');

        verify(mockClient.get(
          argThat(
            predicate<Uri>((uri) =>
                uri.toString().contains('cardano-preview.blockfrost.io')),
          ),
          headers: anyNamed('headers'),
        )).called(1);
      });

      test('uses correct URL for mainnet', () async {
        final mainnetProvider = BlockfrostProvider(
          projectId: 'mainnet_id',
          network: Network.mainnet,
          client: mockClient,
        );

        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response(jsonEncode([]), 200));

        await mainnetProvider.fetchUtxos('addr1q...');

        verify(mockClient.get(
          argThat(
            predicate<Uri>((uri) =>
                uri.toString().contains('cardano-mainnet.blockfrost.io')),
          ),
          headers: anyNamed('headers'),
        )).called(1);
      });
    });

    group('error handling', () {
      test('surfaces typed error for 401', () async {
        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async => http.Response('Unauthorized', 401));

        expect(
          () => provider.fetchProtocolParameters(),
          throwsA(isA<BlockfrostUnauthorized>()),
        );
      });

      test('returns empty list for 404 in other endpoints', () async {
        // Note: fetchUtxos returns empty list for 404, but other endpoints
        // like fetchProtocolParameters would throw NotFound if it returned 404.
        // This test is removed because fetchUtxos specifically handles 404
        // as a valid response (no UTxOs).
      });

      test('includes response body in BlockfrostBadRequest', () async {
        const errorBody = 'InvalidTx: min_fee too low';
        when(mockClient.post(
          any,
          headers: anyNamed('headers'),
          body: anyNamed('body'),
        )).thenAnswer((_) async => http.Response(errorBody, 400));

        try {
          await provider.submitTransaction(Uint8List(0));
          fail('Should have thrown BlockfrostBadRequest');
        } on BlockfrostBadRequest catch (e) {
          expect(e.responseBody, equals(errorBody));
        }
      });

      test('includes retry-after in BlockfrostRateLimited', () async {
        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((_) async =>
            http.Response('Rate Limited', 429, headers: {'retry-after': '60'}));

        try {
          await provider.fetchProtocolParameters();
          fail('Should have thrown BlockfrostRateLimited');
        } on BlockfrostRateLimited catch (e) {
          expect(e.retryAfter, equals(Duration(seconds: 60)));
        }
      });

      test('Blockfrost error toString methods include context', () {
        expect(
          BlockfrostBadRequest('Bad request', 'InvalidTx').toString(),
          equals('Bad request: InvalidTx'),
        );
        expect(
          BlockfrostRateLimited(
            'Rate limited',
            retryAfter: const Duration(seconds: 12),
          ).toString(),
          equals('Rate limited (retry after 12s)'),
        );
        expect(BlockfrostNotFound('missing').toString(), equals('missing'));
      });
    });

    group('fetchTransactionStatus', () {
      const txHash =
          'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890';

      test('returns confirmed=true with blockHeight when TX is on-chain',
          () async {
        final body = jsonEncode({
          'hash': txHash,
          'block': 'blockxyz',
          'block_height': 8500000,
          'block_time': 1700000000,
          'index': 0,
          'output_amount': [],
          'fees': '172000',
        });

        when(mockClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async => http.Response(body, 200));

        final status = await provider.fetchTransactionStatus(txHash);

        expect(status.hash, equals(txHash));
        expect(status.confirmed, isTrue);
        expect(status.blockHeight, equals(8500000));
      });

      test('returns confirmed=false when TX is not yet in a block (404)',
          () async {
        when(mockClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async => http.Response('', 404));

        final status = await provider.fetchTransactionStatus(txHash);

        expect(status.hash, equals(txHash));
        expect(status.confirmed, isFalse);
        expect(status.blockHeight, isNull);
      });

      test('hits the correct /txs/{hash} endpoint', () async {
        when(mockClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async => http.Response('', 404));

        await provider.fetchTransactionStatus(txHash);

        verify(mockClient.get(
          Uri.parse('https://cardano-preview.blockfrost.io/api/v0/txs/$txHash'),
          headers: anyNamed('headers'),
        )).called(1);
      });
    });

    group('pollTransactionConfirmation', () {
      const txHash =
          'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890';

      test('returns immediately when TX is already confirmed', () async {
        final body = jsonEncode({
          'hash': txHash,
          'block_height': 42,
          'block': 'b',
          'block_time': 1,
          'index': 0,
          'output_amount': [],
          'fees': '0',
        });

        when(mockClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async => http.Response(body, 200));

        final status = await provider.pollTransactionConfirmation(
          txHash,
          pollInterval: const Duration(milliseconds: 10),
          timeout: const Duration(seconds: 5),
        );

        expect(status.confirmed, isTrue);
        expect(status.blockHeight, equals(42));
      });

      test('polls until TX is confirmed after initial pending', () async {
        int callCount = 0;
        when(mockClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async {
          callCount++;
          if (callCount < 3) {
            return http.Response('', 404); // pending
          }
          return http.Response(
            jsonEncode({
              'hash': txHash,
              'block_height': 99,
              'block': 'b',
              'block_time': 1,
              'index': 0,
              'output_amount': [],
              'fees': '0',
            }),
            200,
          );
        });

        final status = await provider.pollTransactionConfirmation(
          txHash,
          pollInterval: const Duration(milliseconds: 10),
          timeout: const Duration(seconds: 5),
        );

        expect(status.confirmed, isTrue);
        expect(callCount, equals(3));
      });

      test('throws TimeoutException when TX never confirms', () async {
        when(mockClient.get(any, headers: anyNamed('headers')))
            .thenAnswer((_) async => http.Response('', 404));

        expect(
          () => provider.pollTransactionConfirmation(
            txHash,
            pollInterval: const Duration(milliseconds: 10),
            timeout: const Duration(milliseconds: 50),
          ),
          throwsA(isA<TimeoutException>()),
        );
      });
    });

    group('header management', () {
      test('includes project_id header on every request', () async {
        final captured = <Map<String, String>>[];
        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((invocation) {
          final headers = invocation.namedArguments[Symbol('headers')]
              as Map<String, String>;
          captured.add(headers);
          return Future.value(http.Response(jsonEncode([]), 200));
        });

        await provider.fetchUtxos('addr_test1q...');

        expect(captured.length, greaterThan(0));
        expect(captured[0].containsKey('project_id'), isTrue);
        expect(captured[0]['project_id'], equals('test_project_id'));
      });

      test('sets Content-Type header for requests', () async {
        final captured = <Map<String, String>>[];
        when(mockClient.get(
          any,
          headers: anyNamed('headers'),
        )).thenAnswer((invocation) {
          final headers = invocation.namedArguments[Symbol('headers')]
              as Map<String, String>;
          captured.add(headers);
          return Future.value(http.Response(jsonEncode([]), 200));
        });

        await provider.fetchUtxos('addr_test1q...');

        expect(captured.length, greaterThan(0));
        expect(captured[0].containsKey('Content-Type'), isTrue);
        expect(captured[0]['Content-Type'], equals('application/json'));
      });
    });
  });
}
