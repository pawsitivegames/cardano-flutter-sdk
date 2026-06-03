import 'dart:async';
import 'dart:convert';

import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Reference CIP-45 transport: hosts the bugout library (WebTorrent discovery +
/// WebRTC data channel) inside a headless WebView and bridges RPC frames to a
/// [Cip45WalletHandler].
///
/// This lives in the example app (not the core package) so the SDK stays free of
/// WebView/WebRTC dependencies. It is a faithful implementation of the CIP-45
/// proof-of-concept, which uses bugout for peer-to-peer transport.
///
/// Usage:
/// ```dart
/// final transport = BugoutCip45Transport(
///   identifier: dAppIdentifier,           // from the scanned/pasted URI
///   name: handler.name,
///   version: handler.version,
///   methods: handler.supportedMethods,
///   onStatus: (s) => setState(() => _status = s),
///   onLog: (lvl, msg) => debugPrint('[$lvl] $msg'),
/// );
/// transport.onRequest(handler.handleRequest);
/// await transport.start();
/// ```
class BugoutCip45Transport implements Cip45Transport {
  /// The dApp's bugout identifier (its public key) to connect to.
  final String identifier;

  /// Wallet name announced to the dApp.
  final String name;

  /// API version announced to the dApp.
  final String version;

  /// CIP-30 method names this wallet exposes.
  final List<String> methods;

  /// Called with transport state changes: ready / announcing / connected / error.
  final void Function(String status)? onStatus;

  /// Called with diagnostic log lines from the bridge.
  final void Function(String level, String message)? onLog;

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  Future<Object?> Function(String method, List<dynamic> params)? _handler;
  final Completer<void> _ready = Completer<void>();

  BugoutCip45Transport({
    required this.identifier,
    required this.name,
    required this.version,
    required this.methods,
    this.onStatus,
    this.onLog,
  });

  @override
  void onRequest(
    Future<Object?> Function(String method, List<dynamic> params) handler,
  ) {
    _handler = handler;
  }

  @override
  Future<void> start() async {
    _webView = HeadlessInAppWebView(
      initialFile: 'assets/cip45/cip45_bridge.html',
      initialSettings: InAppWebViewSettings(
        isInspectable: false,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptEnabled: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;

        controller.addJavaScriptHandler(
          handlerName: 'rpc',
          callback: (args) async {
            final method = args.isNotEmpty ? args[0] as String : '';
            final params = (args.length > 1 && args[1] is List)
                ? List<dynamic>.from(args[1] as List)
                : <dynamic>[];
            final handler = _handler;
            if (handler == null) {
              return {'ok': false, 'error': 'no handler registered'};
            }
            try {
              // Envelope the result so primitive returns (e.g. getNetworkId's
              // int 0) survive the Dart->JS round-trip; the bridge unwraps it.
              return {'ok': true, 'result': await handler(method, params)};
            } catch (e) {
              return {'ok': false, 'error': '$e'};
            }
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'log',
          callback: (args) {
            final level = args.isNotEmpty ? '${args[0]}' : 'info';
            final msg = args.length > 1 ? '${args[1]}' : '';
            onLog?.call(level, msg);
            return null;
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'status',
          callback: (args) {
            final s = args.isNotEmpty ? '${args[0]}' : '';
            onStatus?.call(s);
            if (s == 'ready' && !_ready.isCompleted) _ready.complete();
            return null;
          },
        );
      },
      onConsoleMessage: (controller, msg) {
        onLog?.call('console', msg.message);
      },
    );

    await _webView!.run();

    // Wait for the page to load bugout and signal 'ready', then start it.
    await _ready.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => onLog?.call('warn', 'bridge did not signal ready in 20s'),
    );

    await _controller!.evaluateJavascript(
      source: 'startBugout('
          '${jsonEncode(identifier)},'
          '${jsonEncode(name)},'
          '${jsonEncode(version)},'
          '${jsonEncode(methods)});',
    );
  }

  @override
  Future<void> close() async {
    await _webView?.dispose();
    _webView = null;
    _controller = null;
  }
}
