import 'package:flutter/material.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';

import 'cip45_transport.dart';
import 'qr_scanner_page.dart';

/// Phase 4.4 example: CIP-45 wallet endpoint.
///
/// Connects to a dApp's CIP-13 connection URI over the bugout transport
/// (WebTorrent + WebRTC) and serves CIP-30 RPC calls from the dApp via a
/// [Cip45WalletHandler] bridged to a [Cip30Wallet].
class Cip45Screen extends StatefulWidget {
  final BlockfrostProvider provider;
  final String mnemonic;

  /// Optional connection URI delivered via a `web+cardano://` deep link.
  final String? initialUri;

  const Cip45Screen({
    super.key,
    required this.provider,
    required this.mnemonic,
    this.initialUri,
  });

  @override
  State<Cip45Screen> createState() => _Cip45ScreenState();
}

class _Cip45ScreenState extends State<Cip45Screen> {
  final TextEditingController _uriController = TextEditingController();

  Cip30Wallet? _wallet;
  Cip45WalletHandler? _handler;
  BugoutCip45Transport? _transport;

  bool _initializing = true;
  bool _connecting = false;
  String _status = 'idle';
  String? _error;
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialUri != null) {
      _uriController.text = widget.initialUri!;
    }
    _init();
  }

  Future<void> _init() async {
    try {
      final wallet = await Cip30Wallet.fromMnemonic(
        mnemonic: widget.mnemonic,
        provider: widget.provider,
      );
      setState(() {
        _wallet = wallet;
        _handler = Cip45WalletHandler(wallet: wallet, name: 'cardano_flutter_rs');
        _initializing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to build wallet: $e';
        _initializing = false;
      });
    }
  }

  void _addLog(String line) {
    setState(() => _log.insert(0, line));
  }

  Future<void> _connect() async {
    final raw = _uriController.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Paste a web+cardano:// connection URI first');
      return;
    }
    Cip45ConnectionUri uri;
    try {
      uri = Cip45ConnectionUri.parse(raw);
    } on FormatException catch (e) {
      setState(() => _error = 'Invalid connection URI: ${e.message}');
      return;
    }

    setState(() {
      _error = null;
      _connecting = true;
      _status = 'connecting';
      _log.clear();
    });

    await _transport?.close();

    final handler = _handler!;
    final transport = BugoutCip45Transport(
      identifier: uri.identifier,
      name: handler.name,
      version: handler.version,
      methods: handler.supportedMethods,
      onStatus: (s) => setState(() => _status = s),
      onLog: (lvl, msg) => _addLog('[$lvl] $msg'),
    );
    transport.onRequest((method, params) async {
      _addLog('→ handling $method');
      final result = await handler.handleRequest(method, params);
      _addLog('← $method done');
      return result;
    });

    try {
      await transport.start();
      setState(() {
        _transport = transport;
        _connecting = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Transport error: $e';
        _connecting = false;
        _status = 'error';
      });
    }
  }

  /// Open the camera, scan a `web+cardano://` QR code into the URI field, and
  /// connect immediately on a successful scan.
  Future<void> _scanQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QrScannerPage(
          title: 'Scan CIP-45 QR',
          validate: (v) => v.trim().startsWith('web+cardano://'),
        ),
      ),
    );
    if (scanned == null || !mounted) return;
    _uriController.text = scanned.trim();
    setState(() => _error = null);
    await _connect();
  }

  Future<void> _disconnect() async {
    await _transport?.close();
    setState(() {
      _transport = null;
      _status = 'idle';
    });
  }

  @override
  void dispose() {
    _transport?.close();
    _uriController.dispose();
    super.dispose();
  }

  Color _statusColor() {
    switch (_status) {
      case 'connected':
        return Colors.green;
      case 'announcing':
      case 'connecting':
        return Colors.orange;
      case 'idle':
        return Colors.grey;
      default:
        return _status.startsWith('error') ? Colors.red : Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CIP-45 Wallet (bugout)')),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    color: Colors.deepPurple.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.cable,
                                  size: 16, color: Colors.deepPurple),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Connect to a dApp via CIP-45 (WebTorrent + WebRTC)',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepPurple),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Open the reference dApp page in a browser, then paste '
                            'its web+cardano:// connection URI below (or open it '
                            'as a deep link).',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.deepPurple.shade700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _uriController,
                    decoration: InputDecoration(
                      labelText: 'web+cardano://connect/v1?identifier=…',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      filled: true,
                    ),
                    maxLines: 2,
                    enabled: !_connecting,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                                color: _statusColor(),
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          Text(_status,
                              style: TextStyle(
                                  color: _statusColor(),
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const Spacer(),
                      if (_transport == null) ...[
                        OutlinedButton.icon(
                          onPressed: _connecting ? null : _scanQr,
                          icon: const Icon(Icons.qr_code_scanner, size: 16),
                          label: const Text('Scan QR'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.deepPurple),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _connecting ? null : _connect,
                          icon: _connecting
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.link, size: 16),
                          label: const Text('Connect'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white),
                        ),
                      ]
                      else
                        ElevatedButton.icon(
                          onPressed: _disconnect,
                          icon: const Icon(Icons.link_off, size: 16),
                          label: const Text('Disconnect'),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white),
                        ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_error!,
                            style: TextStyle(color: Colors.red.shade700)),
                      ),
                    ),
                  ],
                  if (_wallet != null) ...[
                    const SizedBox(height: 16),
                    Text('Serving from: ${_wallet!.baseAddress}',
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 10)),
                  ],
                  const SizedBox(height: 20),
                  const Text('Transport log',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  if (_log.isEmpty)
                    const Text('Connect to see peer-discovery + RPC activity.',
                        style: TextStyle(color: Colors.grey)),
                  ..._log.map(
                    (l) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(l,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 10)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
