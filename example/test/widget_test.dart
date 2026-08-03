import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:cardano_flutter_rs_example/main.dart';

void main() {
  test('CIP-45 deep-link subscription stops forwarding after cancellation',
      () async {
    final links = StreamController<Uri>();
    addTearDown(links.close);
    final received = <String>[];
    final subscription = subscribeToCip45Links(
      links: links.stream,
      onConnection: received.add,
    );

    links.add(Uri.parse('web+cardano://connect/first'));
    await Future<void>.delayed(Duration.zero);
    expect(received, ['web+cardano://connect/first']);

    await subscription.cancel();
    links.add(Uri.parse('web+cardano://connect/second'));
    await Future<void>.delayed(Duration.zero);
    expect(received, ['web+cardano://connect/first']);
  });

  test('provider-backed demos require both keys and a project id', () {
    expect(providerDemoReady(projectId: null, hasKeys: true), isFalse);
    expect(providerDemoReady(projectId: '', hasKeys: true), isFalse);
    expect(
        providerDemoReady(projectId: 'preview-key', hasKeys: false), isFalse);
    expect(providerDemoReady(projectId: 'preview-key', hasKeys: true), isTrue);
  });

  testWidgets('home screen exposes its real first-run actions', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('SDK playground'), findsOneWidget);
    expect(find.text('Re-run diagnostics'), findsOneWidget);
    expect(find.text('Open Send ADA demo'), findsOneWidget);
    expect(find.text('Network demos are not configured'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Open Send ADA demo'),
          )
          .onPressed,
      isNull,
    );

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('home screen survives the compact and expanded viewport matrix',
      (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpWidget(
      MyApp(diagnosticsRunner: () async {}),
    );
    await tester.pump();

    for (final size in const [
      Size(320, 568),
      Size(375, 667),
      Size(430, 932),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();

      expect(find.text('SDK playground'), findsOneWidget,
          reason: 'home title missing at ${size.width}x${size.height}');
      expect(find.text('Open Send ADA demo'), findsOneWidget,
          reason: 'primary action missing at ${size.width}x${size.height}');
      expect(tester.takeException(), isNull,
          reason: 'home rendered an exception at ${size.width}x${size.height}');
    }
  });

  testWidgets('diagnostics failure can recover through retry', (tester) async {
    var shouldFail = true;
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MyApp(
        diagnosticsRunner: () async {
          if (shouldFail) {
            throw StateError('diagnostics failed');
          }
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Diagnostics could not start'), findsOneWidget);
    expect(find.text('Retry diagnostics'), findsOneWidget);
    expect(
      find.text(
        'Diagnostics could not start. Check the native library and try again.',
      ),
      findsOneWidget,
    );

    shouldFail = false;
    await tester.ensureVisible(find.text('Retry diagnostics'));
    await tester.tap(find.text('Retry diagnostics'));
    await tester.pumpAndSettle();

    expect(find.text('Diagnostics could not start'), findsNothing);
    expect(find.text('Re-run diagnostics'), findsOneWidget);
  });
}
