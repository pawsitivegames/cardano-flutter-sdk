import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';

/// Phase 4.3 example: CIP-30 dApp connector.
///
/// Builds a [Cip30Wallet] from the test mnemonic + a Blockfrost provider and
/// exercises the CIP-30 method surface: getNetworkId, getUtxos, getBalance,
/// getChangeAddress, getRewardAddresses, getUsed/UnusedAddresses, and signData
/// (with an in-app verify round-trip).
class Cip30Screen extends StatefulWidget {
  final BlockfrostProvider provider;
  final String mnemonic;

  const Cip30Screen({
    Key? key,
    required this.provider,
    required this.mnemonic,
  }) : super(key: key);

  @override
  State<Cip30Screen> createState() => _Cip30ScreenState();
}

class _Cip30ScreenState extends State<Cip30Screen> {
  Cip30Wallet? _wallet;
  Cip45WalletHandler? _cip45;
  bool _loading = true;
  String? _error;

  // Demo peer-discovery identifier. A real CIP-45 transport generates an
  // ephemeral Ed25519 keypair and uses its public key here.
  static const _demoIdentifier =
      'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';

  final List<_LogEntry> _log = [];

  @override
  void initState() {
    super.initState();
    _initWallet();
  }

  Future<void> _initWallet() async {
    try {
      final wallet = await Cip30Wallet.fromMnemonic(
        mnemonic: widget.mnemonic,
        provider: widget.provider,
      );
      setState(() {
        _wallet = wallet;
        _cip45 = Cip45WalletHandler(wallet: wallet, name: 'cardano_flutter_rs');
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to build wallet: $e';
        _loading = false;
      });
    }
  }

  void _add(String title, String value, {bool ok = true}) {
    setState(() {
      _log.insert(0, _LogEntry(title: title, value: value, ok: ok));
    });
  }

  Future<void> _run(String title, Future<String> Function() action) async {
    try {
      final result = await action();
      _add(title, result);
    } catch (e) {
      _add(title, '$e', ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _wallet;
    return Scaffold(
      appBar: AppBar(title: const Text('CIP-30 dApp Connector')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: TextStyle(color: Colors.red.shade700)),
                  ),
                )
              : SingleChildScrollView(
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
                              Row(
                                children: const [
                                  Icon(Icons.hub,
                                      size: 16, color: Colors.indigo),
                                  SizedBox(width: 8),
                                  Text('CIP-30 Wallet API',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                'Base: ${w!.baseAddress}',
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 10),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                'Reward: ${w.rewardAddress}',
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _btn('getNetworkId', () async {
                            final id = await w.getNetworkId();
                            _add('getNetworkId',
                                '$id  (${id == 1 ? "mainnet" : "testnet"})');
                          }),
                          _btn('getChangeAddress', () =>
                              _run('getChangeAddress', w.getChangeAddress)),
                          _btn('getRewardAddresses', () async {
                            final r = await w.getRewardAddresses();
                            _add('getRewardAddresses', r.join('\n'));
                          }),
                          _btn('getUtxos', () async {
                            final u = await w.getUtxos();
                            _add('getUtxos',
                                '${u.length} UTxO(s)\n${u.join('\n\n')}');
                          }),
                          _btn('getBalance', () => _run('getBalance',
                              w.getBalance)),
                          _btn('getUsedAddresses', () async {
                            final a = await w.getUsedAddresses();
                            _add('getUsedAddresses',
                                a.isEmpty ? '(none)' : a.join('\n'));
                          }),
                          _btn('getUnusedAddresses', () async {
                            final a = await w.getUnusedAddresses();
                            _add('getUnusedAddresses',
                                a.isEmpty ? '(none)' : a.join('\n'));
                          }),
                          _btn('signData + verify', _signDataDemo,
                              color: Colors.green),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _cip45Card(),
                      const SizedBox(height: 20),
                      const Text('Results',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 8),
                      if (_log.isEmpty)
                        const Text('Tap a method above to call it.',
                            style: TextStyle(color: Colors.grey)),
                      ..._log.map((e) => _logCard(e)),
                    ],
                  ),
                ),
    );
  }

  Widget _cip45Card() {
    final uri =
        const Cip45ConnectionUri(identifier: _demoIdentifier).toUriString();
    return Card(
      color: Colors.deepPurple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.cable, size: 16, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text('CIP-45 (mobile dApp connect)',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.deepPurple)),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Connection URI (CIP-13), shareable as a QR/link:',
                style: TextStyle(fontSize: 11)),
            const SizedBox(height: 4),
            SelectableText(uri,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _btn('CIP-45 announce', () async {
                  _add('CIP-45 apiAnnouncement',
                      const JsonEncoder.withIndent('  ')
                          .convert(_cip45!.apiAnnouncement()));
                }, color: Colors.deepPurple),
                _btn('CIP-45 dApp→getRewardAddresses', () async {
                  final res =
                      await _cip45!.handleRequest('getRewardAddresses');
                  _add('CIP-45 RPC getRewardAddresses', '$res',
                      ok: true);
                }, color: Colors.deepPurple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _signDataDemo() async {
    final w = _wallet!;
    try {
      const message = 'Sign in to ExampleDApp';
      final payloadHex = utf8
          .encode(message)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final sig = await w.signData(payloadHex);
      final valid = cip30VerifyData(
        dataSignature: sig,
        expectedPayloadHex: payloadHex,
      );
      _add(
        'signData("$message")',
        'verified: $valid\n\nsignature (COSE_Sign1):\n${sig.signature}\n\nkey (COSE_Key):\n${sig.key}',
        ok: valid,
      );
    } catch (e) {
      _add('signData', '$e', ok: false);
    }
  }

  Widget _btn(String label, Future<void> Function() onTap, {Color? color}) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color ?? Colors.indigo,
        foregroundColor: Colors.white,
      ),
      child: Text(label),
    );
  }

  Widget _logCard(_LogEntry e) {
    return Card(
      color: e.ok ? Colors.grey.shade50 : Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(e.ok ? Icons.check_circle : Icons.error_outline,
                    size: 16,
                    color:
                        e.ok ? Colors.green.shade700 : Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(e.title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              e.value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogEntry {
  final String title;
  final String value;
  final bool ok;
  _LogEntry({required this.title, required this.value, required this.ok});
}
