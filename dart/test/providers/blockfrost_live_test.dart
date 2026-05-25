import 'dart:io';

import 'package:cardano_flutter_rs/src/providers/blockfrost.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Only run live tests if BLOCKFROST_PROJECT_ID is set
  final projectId = Platform.environment['BLOCKFROST_PROJECT_ID'];
  final isLiveTest = projectId != null && projectId.isNotEmpty;

  group('BlockfrostProvider live tests', () {
    if (!isLiveTest) {
      test(
        'fetchProtocolParameters_live_testnet_preview',
        skip:
            'BLOCKFROST_PROJECT_ID env var not set, skipping live test',
        () async {},
      );
    } else {
      test('fetchProtocolParameters_live_testnet_preview', () async {
        final provider = BlockfrostProvider(
          projectId: projectId!,
          network: Network.testnetPreview,
        );

        // Should succeed without throwing
        final params = await provider.fetchProtocolParameters();

        // Verify response shape
        expect(params.minFeeA, greaterThan(0));
        expect(params.minFeeB, greaterThan(0));
        expect(params.coinsPerUtxoByte, greaterThan(0));
        expect(params.maxTxSize, greaterThan(0));
        expect(params.maxValueSize, greaterThan(0));
        expect(params.keyDeposit, greaterThan(0));
        expect(params.poolDeposit, greaterThan(0));

        // Verify they're reasonable values for testnet preview
        expect(params.minFeeA, lessThan(1000));
        expect(params.minFeeB, lessThan(1000000));
        expect(params.coinsPerUtxoByte, inInclusiveRange(4000, 5000));
      });
    }
  });
}
