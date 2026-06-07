import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';

/// Phase 2 / 2.5 example: Send testnet ADA and native assets.
///
/// Phase 2.5 additions:
/// - Correct multi-asset UTXO conversion (uses [utxoToTxInput])
/// - TX confirmation polling after submit
/// - Network mismatch warning (testnet address vs mainnet provider)
class SendScreen extends StatefulWidget {
  final BlockfrostProvider provider;
  final String myAddress;
  /// Payment signing key (xprv bech32) — used for signing only, not displayed.
  final String paymentSigningKey;
  final String stakeKey;

  const SendScreen({
    super.key,
    required this.provider,
    required this.myAddress,
    required this.paymentSigningKey,
    required this.stakeKey,
  });

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final TextEditingController _recipientController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _policyIdController = TextEditingController();
  final TextEditingController _assetNameController = TextEditingController();
  final TextEditingController _assetQuantityController = TextEditingController();

  String? _feeEstimate;
  bool _isLoading = false;
  String? _errorMessage;
  String? _statusMessage;
  String? _txHash;
  String? _blockExplorerUrl;
  bool _confirmed = false;

  bool get _isMainnet => widget.provider.network == Network.mainnet;

  void _clearMessages() {
    setState(() {
      _errorMessage = null;
      _statusMessage = null;
      _txHash = null;
      _blockExplorerUrl = null;
      _confirmed = false;
    });
  }

  /// Build target outputs from the form fields.
  List<TxOutput> _buildTargetOutputs(String recipient, BigInt amountLovelace) {
    final assets = <NativeAsset>[];
    final policyId = _policyIdController.text.trim();
    final assetName = _assetNameController.text.trim();
    final assetQtyText = _assetQuantityController.text.trim();

    if (policyId.isNotEmpty && assetName.isNotEmpty && assetQtyText.isNotEmpty) {
      final qty = BigInt.tryParse(assetQtyText);
      if (qty != null && qty > BigInt.zero) {
        assets.add(NativeAsset(
          policyId: policyId,
          assetName: assetName,
          quantity: qty,
        ));
      }
    }

    return [
      TxOutput(
        address: recipient,
        value: Value(coin: amountLovelace, assets: assets),
      ),
    ];
  }

  Future<void> _previewFee() async {
    _clearMessages();
    final recipient = _recipientController.text.trim();
    final amountText = _amountController.text.trim();

    if (recipient.isEmpty || amountText.isEmpty) {
      setState(() => _errorMessage = 'Please enter recipient and amount');
      return;
    }

    // Network mismatch check — fast path, no UTXO fetch needed
    final bool recipientIsTestnet = recipient.startsWith('addr_test') ||
        recipient.startsWith('stake_test');
    final bool mismatch = _isMainnet == recipientIsTestnet;
    if (mismatch) {
      final providerNet = _isMainnet ? 'mainnet' : 'testnet';
      final addrNet = recipientIsTestnet ? 'testnet' : 'mainnet';
      setState(() => _errorMessage =
          'Network mismatch: provider is $providerNet but recipient address is $addrNet.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final utxos = await widget.provider.fetchUtxos(widget.myAddress);
      if (utxos.isEmpty) {
        setState(() {
          _errorMessage = 'No UTXOs available. Send some ADA to your address first.';
          _isLoading = false;
        });
        return;
      }

      final params = await widget.provider.fetchProtocolParameters();
      final amountAda = double.parse(amountText);
      final amountLovelace = BigInt.from((amountAda * 1000000).toInt());
      final targetOutputs = _buildTargetOutputs(recipient, amountLovelace);
      final protocolParams = params.toProtocolParams();

      // Phase 2.5: use utxosToTxInputs to preserve multi-asset holdings
      final txInputs = utxosToTxInputs(utxos);

      final coinSelection = await selectCoinsForTransaction(
        availableUtxos: txInputs,
        targetOutputs: targetOutputs,
        changeAddress: widget.myAddress,
        protocolParams: protocolParams,
      );

      // TX-1: pass ONLY the target outputs and let build_tx's add_change_if_needed
      // create the single change output. Passing coinSelection.changeOutputs here
      // too would stack two change/fee engines (double-change → dust burned to fee
      // / redundant change). selectCoinsForTransaction is used for input selection
      // + fee preview; CSL is the single source of truth for change.
      final builtTx = await buildTransaction(
        inputs: coinSelection.selectedInputs,
        outputs: targetOutputs,
        changeAddress: widget.myAddress,
        ttl: null,
        protocolParams: protocolParams,
      );

      setState(() {
        _feeEstimate = '${(builtTx.fee.toInt() / 1000000).toStringAsFixed(6)} ADA';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = _friendlyError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _sendTransaction() async {
    _clearMessages();
    final recipient = _recipientController.text.trim();
    final amountText = _amountController.text.trim();

    if (recipient.isEmpty || amountText.isEmpty || _feeEstimate == null) {
      setState(() => _errorMessage = 'Please preview the fee first');
      return;
    }

    // Phase 2.5: network mismatch safety gate
    final bool recipientIsTestnet = recipient.startsWith('addr_test') ||
        recipient.startsWith('stake_test');
    final bool mismatch = _isMainnet == recipientIsTestnet;
    if (mismatch) {
      final providerNet = _isMainnet ? 'mainnet' : 'testnet';
      final addrNet = recipientIsTestnet ? 'testnet' : 'mainnet';
      setState(() {
        _errorMessage =
            'Network mismatch: provider is $providerNet but recipient address is $addrNet.';
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Transaction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recipient: $recipient'),
            const SizedBox(height: 8),
            Text('Amount: $amountText ADA'),
            const SizedBox(height: 8),
            Text('Fee: $_feeEstimate'),
            if (_policyIdController.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Asset: ${_assetQuantityController.text} × ${_assetNameController.text}'),
            ],
            const SizedBox(height: 16),
            Text(
              _isMainnet
                  ? '⚠️ MAINNET — real funds will be spent!'
                  : 'TESTNET ONLY — no real funds at risk.',
              style: TextStyle(
                color: _isMainnet ? Colors.red : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: _isMainnet
                ? ElevatedButton.styleFrom(backgroundColor: Colors.red)
                : null,
            child: Text(
              _isMainnet ? 'Send (MAINNET)' : 'Confirm',
              style: _isMainnet ? const TextStyle(color: Colors.white) : null,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Building transaction…';
    });

    try {
      final utxos = await widget.provider.fetchUtxos(widget.myAddress);
      if (utxos.isEmpty) {
        setState(() {
          _errorMessage = 'No UTXOs available';
          _isLoading = false;
          _statusMessage = null;
        });
        return;
      }

      final params = await widget.provider.fetchProtocolParameters();
      final amountAda = double.parse(amountText);
      final amountLovelace = BigInt.from((amountAda * 1000000).toInt());
      final targetOutputs = _buildTargetOutputs(recipient, amountLovelace);
      final protocolParams = params.toProtocolParams();

      // Phase 2.5: preserve multi-asset holdings in UTXO conversion
      final txInputs = utxosToTxInputs(utxos);

      final coinSelection = await selectCoinsForTransaction(
        availableUtxos: txInputs,
        targetOutputs: targetOutputs,
        changeAddress: widget.myAddress,
        protocolParams: protocolParams,
      );

      // TX-3: set a TTL (~2h) so a delayed/stuck tx expires instead of remaining
      // submittable forever. ~20 slots/s on mainnet+preview → 7200 slots ≈ 2h.
      final tipSlot = await widget.provider.fetchTipSlot();
      final ttl = BigInt.from(tipSlot + 7200);

      // TX-1: pass ONLY the target outputs and let build_tx's add_change_if_needed
      // create the single change output. Passing coinSelection.changeOutputs here
      // too would stack two change/fee engines (double-change → dust burned to fee
      // / redundant change). selectCoinsForTransaction is used for input selection
      // + fee preview; CSL is the single source of truth for change.
      final builtTx = await buildTransaction(
        inputs: coinSelection.selectedInputs,
        outputs: targetOutputs,
        changeAddress: widget.myAddress,
        ttl: ttl,
        protocolParams: protocolParams,
      );

      final signedTx = await signTransaction(
        txBodyCborHex: builtTx.txBodyCborHex,
        paymentKeys: [widget.paymentSigningKey],
      );

      setState(() => _statusMessage = 'Submitting transaction…');
      final txBytes = signedTxToBytes(signedTx);
      final submittedHash = await widget.provider.submitTransaction(txBytes);

      final explorerBase = _isMainnet
          ? 'https://cexplorer.io/tx'
          : 'https://preview.cexplorer.io/tx';

      setState(() {
        _txHash = submittedHash;
        _blockExplorerUrl = '$explorerBase/$submittedHash';
        _statusMessage = 'Submitted! Waiting for confirmation…';
      });

      // Phase 2.5: poll for confirmation
      try {
        final status = await widget.provider.pollTransactionConfirmation(
          submittedHash,
          pollInterval: const Duration(seconds: 10),
          timeout: const Duration(minutes: 5),
        );
        setState(() {
          _statusMessage = status.blockHeight != null
              ? 'Confirmed in block ${status.blockHeight}!'
              : 'Confirmed!';
          _confirmed = true;
          _isLoading = false;
        });
      } on TimeoutException {
        setState(() {
          _statusMessage =
              'Transaction submitted. Confirmation pending — check the explorer.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = _friendlyError(e);
        _isLoading = false;
        _statusMessage = null;
      });
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('InsufficientFunds')) {
      return 'Insufficient funds. Check your wallet balance.';
    }
    if (s.contains('DustChange')) {
      return 'Coin selection failed: change amount is below the minimum ADA '
          'required for a UTXO. Try sending a different amount or consolidate UTXOs.';
    }
    if (s.contains('InsufficientAsset')) {
      return 'Insufficient token balance for the requested transfer.';
    }
    return 'Error: $s';
  }

  @override
  Widget build(BuildContext context) {
    final networkLabel = _isMainnet ? 'MAINNET' : 'TESTNET';
    final networkColor = _isMainnet ? Colors.red : Colors.orange;

    return Scaffold(
      appBar: AppBar(
        title: Text('Send ADA — Phase 2.5 ($networkLabel)'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Network banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: networkColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: networkColor),
              ),
              child: Row(
                children: [
                  Icon(
                    _isMainnet ? Icons.warning : Icons.science,
                    color: networkColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isMainnet
                          ? 'MAINNET — real funds\nDouble-check all addresses'
                          : 'TESTNET ONLY\nDo not use with real funds',
                      style: TextStyle(
                        color: networkColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Recipient address field
            TextField(
              controller: _recipientController,
              decoration: InputDecoration(
                labelText: 'Recipient Address (bech32)',
                hintText: _isMainnet ? 'addr1q…' : 'addr_test1q…',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              minLines: 2,
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Amount field
            TextField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Amount (ADA)',
                hintText: '1.5',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                suffix: const Text('ADA'),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),

            // Optional native asset
            ExpansionTile(
              title: const Text('Send native token (optional)'),
              children: [
                TextField(
                  controller: _policyIdController,
                  decoration: InputDecoration(
                    labelText: 'Policy ID (hex, 56 chars)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _assetNameController,
                  decoration: InputDecoration(
                    labelText: 'Asset name (hex)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _assetQuantityController,
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
              ],
            ),
            const SizedBox(height: 16),

            // Fee preview
            if (_feeEstimate != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  border: Border.all(color: Colors.blue),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue),
                    const SizedBox(width: 12),
                    Text('Estimated fee: $_feeEstimate'),
                  ],
                ),
              ),

            // Error message
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Status / success message
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _confirmed ? Colors.green.shade50 : Colors.blue.shade50,
                  border: Border.all(
                    color: _confirmed ? Colors.green : Colors.blue,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _confirmed
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: TextStyle(
                              color: _confirmed ? Colors.green.shade800 : Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_txHash != null) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        'TX: $_txHash',
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                    if (_blockExplorerUrl != null) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Open in explorer: $_blockExplorerUrl'),
                            ),
                          );
                        },
                        child: const Text(
                          'View on cexplorer',
                          style: TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (_statusMessage == null || _errorMessage != null) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _previewFee,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Preview Fee'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isLoading || _feeEstimate == null)
                          ? null
                          : _sendTransaction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isMainnet ? Colors.red : Colors.green,
                      ),
                      child: Text(
                        _isMainnet ? 'Send (MAINNET)' : 'Send',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _amountController.dispose();
    _policyIdController.dispose();
    _assetNameController.dispose();
    _assetQuantityController.dispose();
    super.dispose();
  }
}
