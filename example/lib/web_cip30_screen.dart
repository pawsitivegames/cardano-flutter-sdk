import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs_web.dart';

import 'dev_config.dart';

/// Scoped CIP-30 demo for the **web** build.
///
/// Drives [WebCip30Wallet] (CML-JS backend + Blockfrost REST) through the RC's
/// scoped CIP-30 surface — getNetworkId / getChangeAddress / getRewardAddresses
/// / getUsed/UnusedAddresses / getUtxos / getBalance / signData — and verifies
/// the produced signature in-browser via [CmlWebBackend.verifyData], closing the
/// sign↔verify loop entirely on web.
class WebCip30Screen extends StatefulWidget {
  const WebCip30Screen({super.key});

  @override
  State<WebCip30Screen> createState() => _WebCip30ScreenState();
}

class _WebCip30ScreenState extends State<WebCip30Screen> {
  // Canonical test mnemonic (CIP-1852 m/1852'/1815'/0'/0/0, testnet). The web
  // host's BIP-39 bridge (index.html) is pinned to this mnemonic for the demo.
  static const String _mnemonic =
      'test walk nut penalty hip pave soap entry language right filter choice';

  WebCip30Wallet? _wallet;
  String _status = 'Not connected';
  final List<_LogEntry> _log = [];

  // SEC-1: env first; debug-only dev-key fallback; empty in release builds.
  String get _projectId => resolveBlockfrostProjectId();

  void _add(String op, String result, {bool ok = true}) {
    setState(() => _log.insert(0, _LogEntry(op, result, ok)));
  }

  Future<void> _connect() async {
    setState(() => _status = 'Connecting…');
    try {
      final provider = BlockfrostProvider(
        projectId: _projectId,
        network: Network.testnetPreview,
      );
      final wallet = await WebCip30Wallet.fromMnemonic(
        mnemonic: _mnemonic,
        provider: provider,
        isTestnet: true,
      );
      setState(() {
        _wallet = wallet;
        _status = 'Connected (CML-JS web backend)';
      });
      _add('connect',
          'base: ${wallet.baseAddressBech32}\nreward: ${wallet.rewardAddressBech32}');
    } catch (e) {
      setState(() => _status = 'Connect failed');
      _add('connect', '$e', ok: false);
    }
  }

  Future<void> _run(String op, Future<dynamic> Function() fn) async {
    try {
      final r = await fn();
      _add(op, '$r');
    } catch (e) {
      _add(op, '$e', ok: false);
    }
  }

  Future<void> _signAndVerify() async {
    final w = _wallet;
    if (w == null) return;
    try {
      const message = 'Hello from cardano_flutter_rs web!';
      final payloadHex = _utf8Hex(message);
      final sig = w.signData(payloadHex);
      // Close the loop: verify the signature in-browser via the same backend.
      final addrHex = const CmlWebBackend()
          .addressToHex(addressBech32: w.baseAddressBech32);
      final ok = const CmlWebBackend().verifyData(
        signature: sig.signature,
        key: sig.key,
        expectedPayloadHex: payloadHex,
        expectedAddressHex: addrHex,
      );
      _add(
        'signData + verifyData',
        'message: "$message"\n'
            'COSE_Sign1: ${_ellipsize(sig.signature)}\n'
            'COSE_Key:   ${_ellipsize(sig.key)}\n'
            'verifyData: $ok',
        ok: ok,
      );
    } catch (e) {
      _add('signData + verifyData', '$e', ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _wallet;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web CIP-30 (scoped)'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              color: Colors.indigo.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status: $_status',
                        style:
                            const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text(
                      'CML compiled to JS/WASM via Dart JS interop. No Rust FFI on web.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _connect,
                  child: const Text('Connect'),
                ),
                _btn('getNetworkId', w, () async {
                  final id = await w!.getNetworkId();
                  _add('getNetworkId', '$id (0=testnet, 1=mainnet)');
                }),
                _btn('getChangeAddress', w,
                    () => _run('getChangeAddress', w!.getChangeAddress)),
                _btn('getUsedAddresses', w, () async {
                  _add('getUsedAddresses', (await w!.getUsedAddresses()).join('\n'));
                }),
                _btn('getUnusedAddresses', w, () async {
                  final a = await w!.getUnusedAddresses();
                  _add('getUnusedAddresses', a.isEmpty ? '(none)' : a.join('\n'));
                }),
                _btn('getRewardAddresses', w, () async {
                  _add('getRewardAddresses',
                      (await w!.getRewardAddresses()).join('\n'));
                }),
                _btn('getUtxos', w, () async {
                  final u = await w!.getUtxos();
                  _add('getUtxos',
                      '${u.length} UTxO(s)\n${u.take(5).map((e) => e.toString()).join('\n')}');
                }),
                _btn('getBalance', w,
                    () => _run('getBalance (Value CBOR)', w!.getBalance)),
                _btn('signData + verify', w, _signAndVerify),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            Expanded(
              child: ListView.separated(
                itemCount: _log.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final e = _log[i];
                  return ListTile(
                    leading: Icon(
                      e.ok ? Icons.check_circle : Icons.error,
                      color: e.ok ? Colors.green : Colors.red,
                    ),
                    title: Text(e.op,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: SelectableText(
                      e.result,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(String label, WebCip30Wallet? w, VoidCallback onTap) =>
      ElevatedButton(
        onPressed: w == null ? null : onTap,
        child: Text(label),
      );

  static String _utf8Hex(String s) {
    final bytes = utf8.encode(s);
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static String _ellipsize(String s, [int head = 24]) =>
      s.length <= head * 2 ? s : '${s.substring(0, head)}…${s.substring(s.length - head)}';
}

class _LogEntry {
  final String op;
  final String result;
  final bool ok;
  _LogEntry(this.op, this.result, this.ok);
}
