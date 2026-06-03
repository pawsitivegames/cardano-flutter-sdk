import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';

/// Phase 4.1 example: Staking operations on Cardano.
///
/// Provides UI for:
/// - Viewing stake account info (registration status, pool, rewards)
/// - Registering a stake key
/// - Delegating to a pool
/// - Withdrawing rewards
/// - Deregistering a stake key
class StakeScreen extends StatefulWidget {
  final BlockfrostProvider provider;
  final String myAddress;
  final String stakeAddress;
  final String paymentSigningKey;
  final String stakeSigningKey;
  final String stakeKeyHashHex;

  const StakeScreen({
    Key? key,
    required this.provider,
    required this.myAddress,
    required this.stakeAddress,
    required this.paymentSigningKey,
    required this.stakeSigningKey,
    required this.stakeKeyHashHex,
  }) : super(key: key);

  @override
  State<StakeScreen> createState() => _StakeScreenState();
}

class _StakeScreenState extends State<StakeScreen> {
  final TextEditingController _poolIdController = TextEditingController();

  AccountInfo? _accountInfo;
  bool _loadingAccount = true;
  String? _accountError;

  bool _isLoading = false;
  String? _statusMessage;
  String? _errorMessage;
  String? _txHash;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _loadAccountInfo();
  }

  @override
  void dispose() {
    _poolIdController.dispose();
    super.dispose();
  }


  Future<void> _loadAccountInfo() async {
    setState(() {
      _loadingAccount = true;
      _accountError = null;
    });
    try {
      final info = await widget.provider.fetchAccountInfo(widget.stakeAddress);
      setState(() {
        _accountInfo = info;
        _loadingAccount = false;
      });
    } catch (e) {
      setState(() {
        _accountError = e.toString();
        _loadingAccount = false;
      });
    }
  }

  void _clearMessages() {
    setState(() {
      _errorMessage = null;
      _statusMessage = null;
      _txHash = null;
      _confirmed = false;
    });
  }

  Future<void> _executeStakingTx({
    required String actionLabel,
    required Future<BuiltStakingTx> Function(
            List<TxInput> inputs, ProtocolParams params)
        buildFn,
  }) async {
    _clearMessages();
    setState(() {
      _isLoading = true;
      _statusMessage = 'Fetching UTxOs...';
    });

    try {
      final utxos = await widget.provider.fetchUtxos(widget.myAddress);
      if (utxos.isEmpty) {
        setState(() {
          _errorMessage =
              'No UTxOs found at ${widget.myAddress}. Fund this address first.';
          _isLoading = false;
          _statusMessage = null;
        });
        return;
      }

      setState(() => _statusMessage = 'Fetching protocol parameters...');
      final rawParams = await widget.provider.fetchProtocolParameters();
      final params = rawParams.toProtocolParams();
      final inputs = utxosToTxInputs(utxos);

      setState(() => _statusMessage = 'Building $actionLabel transaction...');
      final builtTx = await buildFn(inputs, params);

      setState(() => _statusMessage = 'Signing transaction...');
      final signedTx = await signStakingTransaction(
        txBodyCborHex: builtTx.txBodyCborHex,
        paymentSigningKey: widget.paymentSigningKey,
        stakeSigningKey: widget.stakeSigningKey,
      );

      setState(() => _statusMessage = 'Submitting to Cardano...');
      final txHash =
          await widget.provider.submitTransaction(signedTxToBytes(signedTx));

      setState(() {
        _txHash = txHash;
        _statusMessage = 'Submitted! Waiting for confirmation...';
      });

      try {
        await widget.provider.pollTransactionConfirmation(
          txHash,
          pollInterval: const Duration(seconds: 10),
          timeout: const Duration(minutes: 5),
        );
        setState(() {
          _statusMessage = '$actionLabel confirmed!';
          _confirmed = true;
          _isLoading = false;
        });
        // Refresh account info after confirmation
        await _loadAccountInfo();
      } on TimeoutException {
        setState(() {
          _statusMessage =
              'Transaction submitted. Confirmation pending — check the explorer.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
        _statusMessage = null;
      });
    }
  }

  Future<void> _register() async {
    await _executeStakingTx(
      actionLabel: 'Register',
      buildFn: (inputs, params) => buildStakeRegistrationTx(
        stakeKeyHashHex: widget.stakeKeyHashHex,
        inputs: inputs,
        changeAddress: widget.myAddress,
        networkId: 0, // testnet
        params: params,
      ),
    );
  }

  Future<void> _delegate() async {
    final poolId = _poolIdController.text.trim();
    if (poolId.isEmpty) {
      setState(() => _errorMessage = 'Please enter a pool ID (bech32 or hex)');
      return;
    }
    // Convert bech32 pool ID to hex key hash if needed
    // For simplicity, we expect a hex pool keyhash (56 chars)
    if (poolId.length != 56) {
      setState(() => _errorMessage =
          'Pool ID must be 56 hex chars (the pool keyhash, not the bech32 pool ID).\n'
          'Use a tool like cardanoscan.io to find the hex pool keyhash.');
      return;
    }

    await _executeStakingTx(
      actionLabel: 'Delegate',
      buildFn: (inputs, params) => buildDelegationTx(
        stakeKeyHashHex: widget.stakeKeyHashHex,
        poolKeyhashHex: poolId,
        inputs: inputs,
        changeAddress: widget.myAddress,
        networkId: 0,
        params: params,
      ),
    );
  }

  Future<void> _withdrawRewards() async {
    final info = _accountInfo;
    if (info == null || info.withdrawableReward == BigInt.zero) {
      setState(
          () => _errorMessage = 'No rewards available to withdraw.');
      return;
    }

    await _executeStakingTx(
      actionLabel: 'Withdraw rewards',
      buildFn: (inputs, params) => buildRewardWithdrawalTx(
        stakeKeyHashHex: widget.stakeKeyHashHex,
        rewardAmount: info.withdrawableReward,
        inputs: inputs,
        changeAddress: widget.myAddress,
        networkId: 0,
        params: params,
      ),
    );
  }

  Future<void> _deregister() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deregister Stake Key?'),
        content: const Text(
          'This will deregister your stake key and return the 2 ADA deposit.\n\n'
          'You will stop earning staking rewards until you re-register.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deregister',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _executeStakingTx(
      actionLabel: 'Deregister',
      buildFn: (inputs, params) => buildStakeDeregistrationTx(
        stakeKeyHashHex: widget.stakeKeyHashHex,
        inputs: inputs,
        changeAddress: widget.myAddress,
        networkId: 0,
        params: params,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stake ADA — Phase 4.1'),
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadAccountInfo,
            tooltip: 'Refresh account info',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Account info card
            _buildAccountInfoCard(),
            const SizedBox(height: 16),

            // Actions card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Staking Actions',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),

                    // Register / Deregister
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ||
                                    (_accountInfo?.isRegistered ?? false)
                                ? null
                                : _register,
                            icon: const Icon(Icons.how_to_reg, size: 16),
                            label: const Text('Register'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ||
                                    !(_accountInfo?.isRegistered ?? false)
                                ? null
                                : _deregister,
                            icon:
                                const Icon(Icons.remove_circle_outline, size: 16),
                            label: const Text('Deregister'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Pool delegation
                    TextField(
                      controller: _poolIdController,
                      decoration: InputDecoration(
                        labelText: 'Pool keyhash (56 hex chars)',
                        hintText: 'e.g. 8e4d2a343f3dcf...',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        suffixIcon: Tooltip(
                          message:
                              'The pool\'s Ed25519 key hash (not the bech32 pool ID).\n'
                              'Find it on cardanoscan.io or pooltool.io',
                          child: const Icon(Icons.info_outline),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ||
                                !(_accountInfo?.isRegistered ?? false)
                            ? null
                            : _delegate,
                        icon: const Icon(Icons.send, size: 16),
                        label: const Text('Delegate to Pool'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Withdraw rewards
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ||
                                !(_accountInfo?.isRegistered ?? false) ||
                                (_accountInfo?.withdrawableReward ??
                                        BigInt.zero) ==
                                    BigInt.zero
                            ? null
                            : _withdrawRewards,
                        icon: const Icon(Icons.savings, size: 16),
                        label: Text(
                          _accountInfo != null &&
                                  _accountInfo!.withdrawableReward >
                                      BigInt.zero
                              ? 'Withdraw ${(_accountInfo!.withdrawableReward.toDouble() / 1e6).toStringAsFixed(6)} ADA'
                              : 'Withdraw Rewards',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Error
            if (_errorMessage != null)
              _buildStatusCard(
                color: Colors.red,
                icon: Icons.error_outline,
                message: _errorMessage!,
              ),

            // Status / success
            if (_statusMessage != null) ...[
              _buildStatusCard(
                color: _confirmed ? Colors.green : Colors.blue,
                icon: _confirmed ? Icons.check_circle : null,
                message: _statusMessage!,
                showSpinner: !_confirmed,
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
                GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Open: https://preview.cexplorer.io/tx/$_txHash',
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'View on cexplorer (testnet preview)',
                    style: TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 24),
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountInfoCard() {
    return Card(
      color: Colors.teal.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.account_balance, color: Colors.teal.shade700, size: 16),
              const SizedBox(width: 6),
              Text(
                'Stake Account',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade800,
                ),
              ),
              const Spacer(),
              if (_loadingAccount)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ]),
            const SizedBox(height: 8),
            _LabelValue(
              label: 'Stake Address',
              value: widget.stakeAddress,
              monospace: true,
            ),
            if (_accountError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Error: $_accountError',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              )
            else if (_accountInfo == null && !_loadingAccount)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Not registered on-chain yet.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              )
            else if (_accountInfo != null) ...[
              _LabelValue(
                label: 'Registered',
                value: _accountInfo!.isRegistered ? 'Yes' : 'No',
              ),
              if (_accountInfo!.poolId != null)
                _LabelValue(
                  label: 'Pool',
                  value: _accountInfo!.poolId!,
                  monospace: true,
                ),
              _LabelValue(
                label: 'Controlled',
                value:
                    '${(_accountInfo!.controlledStake.toDouble() / 1e6).toStringAsFixed(6)} ADA',
              ),
              _LabelValue(
                label: 'Withdrawable',
                value:
                    '${(_accountInfo!.withdrawableReward.toDouble() / 1e6).toStringAsFixed(6)} ADA',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard({
    required Color color,
    IconData? icon,
    required String message,
    bool showSpinner = false,
  }) {
    return Card(
      color: color.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (showSpinner)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (icon != null)
              Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: color.withOpacity(0.9), fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 16),
              const SizedBox(width: 6),
              Text(
                'How it works',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const Text(
              '1. Register your stake key (costs 2 ADA deposit)\n'
              '2. Delegate to a pool using its keyhash\n'
              '3. Earn rewards each epoch (~5 days)\n'
              '4. Withdraw rewards any time\n'
              '5. Deregister to reclaim the 2 ADA deposit\n\n'
              'Both payment and stake key witnesses are required '
              'for staking transactions (Phase 4.1).',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelValue extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;

  const _LabelValue({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.teal.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
