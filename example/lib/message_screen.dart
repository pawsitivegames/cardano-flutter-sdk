import 'package:flutter/material.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';

/// Phase 4.2 example: CIP-8 message signing and verification.
///
/// Provides UI for:
/// - Signing messages with payment or stake keys
/// - Verifying signed messages
/// - Demonstrating CIP-8 COSE Sign1 structure
/// - Testing dApp authentication flows
class MessageScreen extends StatefulWidget {
  final String myAddress;
  final String paymentSigningKey;
  final String stakeSigningKey;

  const MessageScreen({
    Key? key,
    required this.myAddress,
    required this.paymentSigningKey,
    required this.stakeSigningKey,
  }) : super(key: key);

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();

  bool _isLoading = false;
  String? _statusMessage;
  String? _errorMessage;

  SignedMessage? _currentSignedMessage;
  bool? _verificationResult;
  String? _verificationError;

  @override
  void initState() {
    super.initState();
    _messageController.text = 'Login to dApp';
    _displayNameController.text = 'My dApp Auth';
  }

  @override
  void dispose() {
    _messageController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _clearMessages() {
    setState(() {
      _statusMessage = null;
      _errorMessage = null;
      _verificationResult = null;
      _verificationError = null;
    });
  }

  Future<void> _signMessageWithKey({
    required String signingKey,
    required String keyType,
  }) async {
    _clearMessages();

    if (_messageController.text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a message to sign';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Signing message with $keyType...';
    });

    try {
      // Convert message to hex for signing
      final messageHex = _stringToHex(_messageController.text);

      final signed = await signMessage(
        message: messageHex,
        signingKey: signingKey,
        address: widget.myAddress,
      );

      if (!mounted) return;

      setState(() {
        _currentSignedMessage = signed;
        _statusMessage = 'Message signed successfully with $keyType!';
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Signed with $keyType'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Signing failed: $e';
        _isLoading = false;
        _statusMessage = null;
      });
    }
  }

  Future<void> _verifySignature() async {
    if (_currentSignedMessage == null) {
      setState(() {
        _verificationError = 'No signed message to verify';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Verifying signature...';
      _verificationError = null;
      _verificationResult = null;
    });

    try {
      final isValid = await verifyMessage(
        signedMessage: _currentSignedMessage!,
        expectedAddress: widget.myAddress,
      );

      setState(() {
        _verificationResult = isValid;
        _statusMessage = isValid
            ? 'Signature is VALID ✓'
            : 'Signature is INVALID ✗';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _verificationError = 'Verification failed: $e';
        _isLoading = false;
        _statusMessage = null;
      });
    }
  }

  void _clearSignature() {
    setState(() {
      _currentSignedMessage = null;
      _verificationResult = null;
      _verificationError = null;
      _statusMessage = null;
      _errorMessage = null;
    });
  }

  String _stringToHex(String str) {
    return str.codeUnits
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String _truncateHex(String hex, {int maxLength = 32}) {
    if (hex.length <= maxLength) return hex;
    return '${hex.substring(0, maxLength ~/ 2)}...${hex.substring(hex.length - maxLength ~/ 2)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Signing (CIP-8)'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Card(
                color: Colors.indigo.shade50,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.indigo.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.security, size: 16, color: Colors.indigo),
                          const SizedBox(width: 8),
                          const Text(
                            'CIP-8 Message Signing',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.indigo,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sign and verify messages with payment or stake keys for dApp authentication',
                        style: TextStyle(fontSize: 12, color: Colors.indigo.shade700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Message input
              const Text(
                'Message to Sign',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  hintText: 'Enter message to sign',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                maxLines: 3,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),

              // Display name (optional context)
              const Text(
                'Display Name (for context)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _displayNameController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  hintText: 'e.g., "My dApp Auth"',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                enabled: !_isLoading,
              ),
              const SizedBox(height: 24),

              // Address info
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Signing Address:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.myAddress,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Sign buttons
              const Text(
                'Sign With:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _signMessageWithKey(
                              signingKey: widget.paymentSigningKey,
                              keyType: 'Payment Key',
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    icon: const Icon(Icons.vpn_key, size: 16, color: Colors.white),
                    label: const Text(
                      'Payment Key',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _signMessageWithKey(
                              signingKey: widget.stakeSigningKey,
                              keyType: 'Stake Key',
                            ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                    ),
                    icon: const Icon(Icons.account_balance, size: 16, color: Colors.white),
                    label: const Text(
                      'Stake Key',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Status messages
              if (_isLoading)
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.blue.shade700),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _statusMessage ?? 'Processing...',
                          style: TextStyle(color: Colors.blue.shade700),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_errorMessage != null)
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_statusMessage != null && !_isLoading)
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: TextStyle(color: Colors.green.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // Signed message display
              if (_currentSignedMessage != null) ...[
                const Text(
                  'Signed Message Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DetailRow(
                          label: 'COSE Sign1 (hex):',
                          value: _truncateHex(_currentSignedMessage!.coseSign1Hex),
                          fullValue: _currentSignedMessage!.coseSign1Hex,
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: 'Public Key (hex):',
                          value: _truncateHex(_currentSignedMessage!.publicKeyHex),
                          fullValue: _currentSignedMessage!.publicKeyHex,
                        ),
                        if (_currentSignedMessage!.address != null) ...[
                          const SizedBox(height: 8),
                          _DetailRow(
                            label: 'Address:',
                            value: _currentSignedMessage!.address!,
                            fullValue: _currentSignedMessage!.address!,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Verify button
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _verifySignature,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                    icon: const Icon(Icons.verified_user, size: 16, color: Colors.white),
                    label: const Text(
                      'Verify Signature',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Verification result
                if (_verificationResult != null)
                  Card(
                    color: _verificationResult! ? Colors.green.shade50 : Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          Icon(
                            _verificationResult! ? Icons.check_circle : Icons.cancel,
                            color: _verificationResult! ? Colors.green.shade700 : Colors.red.shade700,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _verificationResult!
                                  ? 'Signature verified successfully!'
                                  : 'Signature verification failed!',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _verificationResult! ? Colors.green.shade700 : Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_verificationError != null)
                  Card(
                    color: Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _verificationError!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // Clear button
                Center(
                  child: ElevatedButton.icon(
                    onPressed: _clearSignature,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                    ),
                    icon: const Icon(Icons.clear, size: 16, color: Colors.white),
                    label: const Text(
                      'Clear Signature',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final String fullValue;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.fullValue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Full Value'),
                content: SingleChildScrollView(
                  child: SelectableText(
                    fullValue,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
