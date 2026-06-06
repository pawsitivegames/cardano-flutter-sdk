// Web entry point for the example app.
//
// The native `main.dart` pulls in the Rust FFI barrel (`dart:ffi`), which does
// not compile under dart2js. This separate target imports ONLY the web library
// (`cardano_flutter_rs_web.dart`) and renders the scoped CIP-30 demo. Build/run
// with:
//
//   flutter run   -d chrome -t lib/main_web.dart
//   flutter build web        -t lib/main_web.dart
//
// The host page (web/index.html) instantiates the CML + message-signing WASM and
// installs the BIP-39 bridge before Flutter boots — see that file.
import 'package:flutter/material.dart';

import 'web_cip30_screen.dart';

void main() {
  runApp(const WebDemoApp());
}

class WebDemoApp extends StatelessWidget {
  const WebDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cardano Flutter RS — Web',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: const WebCip30Screen(),
    );
  }
}
