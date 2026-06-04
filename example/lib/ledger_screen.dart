// Phase 4.5 example: Hardware wallet (Ledger over BLE).
//
// Demonstrates the working read path: scan → connect → read the account xpub →
// derive the wallet's addresses locally and query balance/UTxOs through a
// [HardwareCip30Wallet]. On-device signing is surfaced but gated behind the
// pending verification described in docs/hardware-wallets.md.

import 'package:flutter/material.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:ledger_cardano_plus/ledger_cardano_plus.dart' show LedgerDevice;
import 'package:permission_handler/permission_handler.dart';

import 'ledger_hardware_wallet.dart';

class LedgerScreen extends StatefulWidget {
  final BlockfrostProvider provider;

  const LedgerScreen({super.key, required this.provider});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  LedgerHardwareWallet? _ledger;
  HardwareCip30Wallet? _wallet;
  final List<LedgerDevice> _devices = [];
  final List<String> _log = [];
  bool _scanning = false;
  bool _busy = false;

  void _logLine(String s) => setState(() => _log.insert(0, s));

  Future<bool> _onPermissionRequest({required bool unsupported}) async {
    final statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _devices.clear();
    });
    _logLine('Scanning for Ledger devices…');
    try {
      _ledger ??= LedgerHardwareWallet.ble(
        onPermissionRequest: _onPermissionRequest,
      );
      _ledger!.scanForDevices().listen(
        (d) {
          if (_devices.every((e) => e.id != d.id)) {
            setState(() => _devices.add(d));
            _logLine('Found: ${d.name} (${d.id})');
          }
        },
        onError: (e) => _logLine('Scan error: $e'),
      );
    } catch (e) {
      _logLine('Scan failed: $e');
    }
  }

  Future<void> _connect(LedgerDevice device) async {
    setState(() => _busy = true);
    _logLine('Connecting to ${device.name}…');
    try {
      final ledger = _ledger!;
      final version = await ledger.connect(device);
      _logLine('Connected. Cardano app v${version.versionName}');

      final wallet = await HardwareCip30Wallet.fromDevice(
        device: ledger,
        provider: widget.provider,
      );
      setState(() => _wallet = wallet);
      _logLine('Account xpub read; base address derived locally:');
      _logLine(wallet.baseAddress);
    } catch (e) {
      _logLine('Connect failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _fetchBalance() async {
    final wallet = _wallet;
    if (wallet == null) return;
    setState(() => _busy = true);
    try {
      final balance = await wallet.getBalance();
      _logLine('getBalance (CBOR hex): $balance');
      final utxos = await wallet.getUtxos();
      _logLine('getUtxos: ${utxos.length} UTxO(s)');
    } catch (e) {
      _logLine('Query failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  /// On-device signing round-trip (the v1.0 gate): build a minimal self-payment
  /// from the wallet's own UTxOs, have the Ledger sign it, assemble, and submit.
  ///
  /// Until this has succeeded against a physical Ledger it is unverified — see
  /// docs/hardware-wallets.md.
  Future<void> _signAndSubmit() async {
    final wallet = _wallet;
    if (wallet == null) return;
    setState(() => _busy = true);
    try {
      final utxos = await widget.provider.fetchUtxos(wallet.baseAddress);
      if (utxos.isEmpty) {
        _logLine('No UTxOs — fund ${wallet.baseAddress} on preview first.');
        return;
      }

      // Send 1 ADA back to ourselves; change returns to the same address.
      final params = (await widget.provider.fetchProtocolParameters())
          .toProtocolParams();
      final txInputs = utxosToTxInputs(utxos);
      final target = TxOutput(
        address: wallet.baseAddress,
        value: Value(coin: BigInt.from(1000000), assets: []),
      );
      final selection = await selectCoinsForTransaction(
        availableUtxos: txInputs,
        targetOutputs: [target],
        changeAddress: wallet.baseAddress,
        protocolParams: params,
      );
      final built = await buildTransaction(
        inputs: selection.selectedInputs,
        outputs: [target, ...selection.changeOutputs],
        changeAddress: wallet.baseAddress,
        ttl: null,
        protocolParams: params,
      );

      _logLine('Built tx ${built.txHash} (fee ${built.fee} lovelace).');
      _logLine('Confirm on the Ledger…');

      final signedTx = await wallet.signTransaction(HardwareSignRequest(
        txBodyCborHex: built.txBodyCborHex,
        signerPaths: [wallet.paymentPath],
      ));
      _logLine('Device signed; submitting…');
      final txId = await wallet.submitTx(signedTx);
      _logLine('Submitted! tx: $txId');
    } catch (e) {
      _logLine('Sign/submit failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _ledger?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    return Scaffold(
      appBar: AppBar(title: const Text('Hardware Wallet (Ledger)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Connect a Ledger (Nano X / Stax / Flex) over Bluetooth, open the '
              'Cardano app, then scan. Address & balance work today; on-device '
              'signing is pending hardware verification.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _scanning && _busy ? null : _scan,
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Scan'),
                ),
                ElevatedButton.icon(
                  onPressed: wallet == null || _busy ? null : _fetchBalance,
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('Balance / UTxOs'),
                ),
                ElevatedButton.icon(
                  onPressed: wallet == null || _busy ? null : _signAndSubmit,
                  icon: const Icon(Icons.edit_document),
                  label: const Text('Sign 1 ₳ → self'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_devices.isNotEmpty && wallet == null)
              SizedBox(
                height: 120,
                child: ListView(
                  children: _devices
                      .map((d) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.usb),
                            title: Text(d.name),
                            subtitle: Text(d.id),
                            onTap: _busy ? null : () => _connect(d),
                          ))
                      .toList(),
                ),
              ),
            if (wallet != null) ...[
              const Divider(),
              Text('Device: ${_ledger?.deviceName ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              SelectableText('Base:   ${wallet.baseAddress}',
                  style: const TextStyle(fontSize: 11)),
              SelectableText('Reward: ${wallet.rewardAddress}',
                  style: const TextStyle(fontSize: 11)),
            ],
            const Divider(),
            const Text('Log', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: _log.length,
                itemBuilder: (ctx, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(_log[i], style: const TextStyle(fontSize: 11)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
