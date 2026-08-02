import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:cardano_flutter_rs_example/main.dart';

void main() {
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

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });
}
