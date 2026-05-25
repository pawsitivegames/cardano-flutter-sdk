import 'package:flutter/material.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';

/// Phase 2 example: Send testnet ADA and native assets.
class SendScreen extends StatefulWidget {
  final BlockfrostProvider provider;
  final String myAddress;
  final String paymentKey;
  final String stakeKey;

  const SendScreen({
    Key? key,
    required this.provider,
    required this.myAddress,
    required this.paymentKey,
    required this.stakeKey,
  }) : super(key: key);

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
  String? _successMessage;
  String? _txHash;
  String? _blockExplorerUrl;

  void _clearMessages() {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
      _txHash = null;
      _blockExplorerUrl = null;
    });
  }

  Future<void> _previewFee() async {
    _clearMessages();
    if (_recipientController.text.isEmpty || _amountController.text.isEmpty) {
      setState(() => _errorMessage = 'Please enter recipient and amount');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Fetch UTXOs
      final utxos = await widget.provider.fetchUtxos(widget.myAddress);
      if (utxos.isEmpty) {
        setState(() {
          _errorMessage = 'No UTXOs available. Send some ADA to your address.';
          _isLoading = false;
        });
        return;
      }

      // Fetch protocol parameters
      final params = await widget.provider.fetchProtocolParameters();

      // Convert amount from ADA to lovelace
      final amountAda = double.parse(_amountController.text);
      final amountLovelace = BigInt.from((amountAda * 1000000).toInt());

      // Create target outputs
      final targetOutputs = [
        TxOutput(
          address: _recipientController.text,
          value: Value(coin: amountLovelace, assets: []),
        ),
      ];

      // Convert protocol parameters
      final protocolParams = ProtocolParams(
        minFeeA: BigInt.from(params.minFeeA),
        minFeeB: BigInt.from(params.minFeeB),
        coinsPerUtxoByte: BigInt.from(params.coinsPerUtxoByte),
        maxTxSize: params.maxTxSize,
        poolDeposit: BigInt.from(params.poolDeposit),
        keyDeposit: BigInt.from(params.keyDeposit),
        maxValSize: params.maxValueSize,
      );

      // Convert Blockfrost UTXOs to TxInputs
      final txInputs = utxos
          .map((u) => TxInput(
                txHash: u.txHash,
                outputIndex: u.outputIndex,
                address: widget.myAddress,
                value: Value(coin: u.coin, assets: []),
              ))
          .toList();

      // Perform coin selection
      final coinSelection = await selectCoinsForTransaction(
        availableUtxos: txInputs,
        targetOutputs: targetOutputs,
        changeAddress: widget.myAddress,
        protocolParams: protocolParams,
      );

      // Build transaction
      final allOutputs = [
        ...targetOutputs,
        ...coinSelection.changeOutputs,
      ];

      final builtTx = await buildTransaction(
        inputs: coinSelection.selectedInputs,
        outputs: allOutputs,
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
        _errorMessage = 'Error calculating fee: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _sendTransaction() async {
    _clearMessages();
    if (_recipientController.text.isEmpty ||
        _amountController.text.isEmpty ||
        _feeEstimate == null) {
      setState(() => _errorMessage = 'Please preview fee first');
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
            Text('Recipient: ${_recipientController.text}'),
            const SizedBox(height: 8),
            Text('Amount: ${_amountController.text} ADA'),
            const SizedBox(height: 8),
            Text('Fee: $_feeEstimate'),
            const SizedBox(height: 16),
            const Text(
              'This is a TESTNET transaction only. Never use real funds!',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
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
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      // Fetch UTXOs again (fresh)
      final utxos = await widget.provider.fetchUtxos(widget.myAddress);
      if (utxos.isEmpty) {
        setState(() {
          _errorMessage = 'No UTXOs available';
          _isLoading = false;
        });
        return;
      }

      // Fetch protocol parameters
      final params = await widget.provider.fetchProtocolParameters();

      // Convert amount from ADA to lovelace
      final amountAda = double.parse(_amountController.text);
      final amountLovelace = BigInt.from((amountAda * 1000000).toInt());

      // Create target outputs
      final targetOutputs = [
        TxOutput(
          address: _recipientController.text,
          value: Value(coin: amountLovelace, assets: []),
        ),
      ];

      // Convert protocol parameters
      final protocolParams = ProtocolParams(
        minFeeA: BigInt.from(params.minFeeA),
        minFeeB: BigInt.from(params.minFeeB),
        coinsPerUtxoByte: BigInt.from(params.coinsPerUtxoByte),
        maxTxSize: params.maxTxSize,
        poolDeposit: BigInt.from(params.poolDeposit),
        keyDeposit: BigInt.from(params.keyDeposit),
        maxValSize: params.maxValueSize,
      );

      // Convert Blockfrost UTXOs to TxInputs
      final txInputs = utxos
          .map((u) => TxInput(
                txHash: u.txHash,
                outputIndex: u.outputIndex,
                address: widget.myAddress,
                value: Value(coin: u.coin, assets: []),
              ))
          .toList();

      // Perform coin selection
      final coinSelection = await selectCoinsForTransaction(
        availableUtxos: txInputs,
        targetOutputs: targetOutputs,
        changeAddress: widget.myAddress,
        protocolParams: protocolParams,
      );

      // Build transaction
      final allOutputs = [
        ...targetOutputs,
        ...coinSelection.changeOutputs,
      ];

      final builtTx = await buildTransaction(
        inputs: coinSelection.selectedInputs,
        outputs: allOutputs,
        changeAddress: widget.myAddress,
        ttl: null,
        protocolParams: protocolParams,
      );

      // Sign transaction
      final signedTx = await signTransaction(
        txBodyCborHex: builtTx.txBodyCborHex,
        paymentKeys: [widget.paymentKey],
      );

      // Submit transaction
      final txBytes = signedTxToBytes(signedTx);
      final submittedHash = await widget.provider.submitTransaction(txBytes);

      setState(() {
        _txHash = submittedHash;
        _blockExplorerUrl =
            'https://preview.cexplorer.io/tx/$submittedHash';
        _successMessage = 'Transaction submitted successfully!';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error submitting transaction: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Testnet ADA - Phase 2'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Warning banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.red),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'TESTNET ONLY\n'
                      'Do not use with real funds',
                      style: TextStyle(
                        color: Colors.red,
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
                hintText: 'addr_test1q...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                errorText: _errorMessage,
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffix: const Text('ADA'),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 24),

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
            const SizedBox(height: 24),

            // Error message
            if (_errorMessage != null)
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

            // Success message
            if (_successMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 12),
                        Text(
                          _successMessage!,
                          style: const TextStyle(color: Colors.green),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_txHash != null)
                      SelectableText(
                        'TX Hash: $_txHash',
                        style: const TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (_blockExplorerUrl != null)
                      GestureDetector(
                        onTap: () {
                          // In a real app, use url_launcher package
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Open in block explorer: $_blockExplorerUrl',
                              ),
                            ),
                          );
                        },
                        child: Text(
                          'View on cexplorer',
                          style: TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            if (_successMessage == null) ...[
              const SizedBox(height: 24),
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _previewFee,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
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
                        backgroundColor: Colors.green,
                      ),
                      child: const Text(
                        'Send',
                        style: TextStyle(color: Colors.white),
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
