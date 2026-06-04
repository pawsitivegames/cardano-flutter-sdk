import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';

/// Phase 3 example: Mint an NFT on Cardano testnet using CIP-25 metadata.
class MintScreen extends StatefulWidget {
  final BlockfrostProvider provider;
  final String myAddress;
  /// Payment signing key (xprv bech32) — used for signing only, not displayed.
  final String paymentSigningKey;
  final String paymentKeyHash;

  const MintScreen({
    super.key,
    required this.provider,
    required this.myAddress,
    required this.paymentSigningKey,
    required this.paymentKeyHash,
  });

  @override
  State<MintScreen> createState() => _MintScreenState();
}

class _MintScreenState extends State<MintScreen> {
  final _nftNameController = TextEditingController(text: 'TestNFT');
  // Default is intentionally >64 bytes so it exercises CIP-25 string chunking
  // (a single metadata text string is capped at 64 bytes; longer values must be
  // encoded as an array of ≤64-byte chunks).
  final _nftImageController = TextEditingController(
      text:
          'https://gateway.pinata.cloud/ipfs/QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG');
  final _nftDescriptionController =
      TextEditingController(text: 'A test NFT minted from the Cardano Flutter SDK');

  bool _isLoading = false;
  String? _status;
  String? _policyId;
  String? _policyScript;
  String? _txHash;
  String? _error;

  @override
  void initState() {
    super.initState();
    _computePolicy();
  }

  @override
  void dispose() {
    _nftNameController.dispose();
    _nftImageController.dispose();
    _nftDescriptionController.dispose();
    super.dispose();
  }

  void _computePolicy() {
    try {
      final script = makePubkeyScript(keyHashHex: widget.paymentKeyHash);
      final policyId = computePolicyId(nativeScriptCborHex: script);
      setState(() {
        _policyScript = script;
        _policyId = policyId;
      });
    } catch (e) {
      setState(() => _error = 'Failed to compute policy: $e');
    }
  }

  Future<void> _mintNft() async {
    if (_policyScript == null || _policyId == null) {
      setState(() => _error = 'Policy not computed');
      return;
    }

    final nftName = _nftNameController.text.trim();
    if (nftName.isEmpty) {
      setState(() => _error = 'NFT name is required');
      return;
    }

    setState(() {
      _isLoading = true;
      _status = 'Fetching UTxOs...';
      _error = null;
      _txHash = null;
    });

    try {
      // 1. Fetch UTxOs and protocol params
      final utxos = await widget.provider.fetchUtxos(widget.myAddress);
      if (utxos.isEmpty) {
        setState(() {
          _error = 'No UTxOs found at ${widget.myAddress}\n'
              'Fund this address with testnet ADA from:\n'
              'https://docs.cardano.org/cardano-testnet/tools/faucet/';
          _isLoading = false;
          _status = null;
        });
        return;
      }

      setState(() => _status = 'Fetching protocol parameters...');
      final rawParams = await widget.provider.fetchProtocolParameters();
      final params = ProtocolParams(
        minFeeA: BigInt.from(rawParams.minFeeA),
        minFeeB: BigInt.from(rawParams.minFeeB),
        coinsPerUtxoByte: BigInt.from(rawParams.coinsPerUtxoByte),
        maxTxSize: rawParams.maxTxSize,
        poolDeposit: BigInt.from(rawParams.poolDeposit),
        keyDeposit: BigInt.from(rawParams.keyDeposit),
        maxValSize: rawParams.maxValueSize,
      );

      // 2. Encode asset name as hex
      final assetNameHex = utf8
          .encode(nftName)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

      // 3. Build CIP-25 metadata
      setState(() => _status = 'Building CIP-25 metadata...');
      final auxDataHex = buildCip25Metadata(
        policies: [
          Cip25Policy(
            policyIdHex: _policyId!,
            assets: [
              Cip25Asset(
                assetNameHex: assetNameHex,
                name: nftName,
                image: _nftImageController.text.trim(),
                mediaType: 'image/png',
                description: _nftDescriptionController.text.trim().isNotEmpty
                    ? _nftDescriptionController.text.trim()
                    : null,
              ),
            ],
          ),
        ],
      );

      // 4. Build inputs from UTxOs.
      //
      // Prefer a single pure-ADA UTxO: minting from UTxOs that already hold
      // native tokens requires returning every one of those tokens in the
      // change output, which the demo's simple build path does not handle and
      // which the ledger rejects with ValueNotConservedUTxO. A pure-ADA input
      // keeps the mint self-contained. If the wallet has only token-bearing
      // UTxOs we fall back to all of them WITH their assets preserved (via
      // utxoToTxInput) so the input values are at least correct.
      setState(() => _status = 'Building transaction...');
      final pureAda = utxos.where((u) => u.assets.isEmpty).toList()
        ..sort((a, b) => b.coin.compareTo(a.coin));
      final inputs = pureAda.isNotEmpty
          ? [utxoToTxInput(pureAda.first)]
          : utxosToTxInputs(utxos);

      // 5. Build minting transaction with CIP-25 metadata
      final builtMintTx = buildMintTx(
        inputs: inputs,
        outputs: [],
        changeAddress: widget.myAddress,
        mintSpecs: [
          MintSpec(
            policyScriptCborHex: _policyScript!,
            assets: [MintAsset(assetNameHex: assetNameHex, quantity: 1)],
          ),
        ],
        auxDataCborHex: auxDataHex,
        ttl: null,
        params: params,
      );

      // 6. Sign with payment signing key (using metadata-aware signer)
      setState(() => _status = 'Signing transaction...');
      final signedTx = await signMintTransaction(
        builtMintTx: builtMintTx,
        paymentKeys: [widget.paymentSigningKey],
      );

      // 7. Submit to Blockfrost
      setState(() => _status = 'Submitting to Cardano testnet...');
      final txHash = await widget.provider.submitTransaction(
        signedTxToBytes(signedTx),
      );

      setState(() {
        _txHash = txHash;
        _isLoading = false;
        _status = 'Minted successfully!';
      });
    } on CardanoError catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _status = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _status = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mint NFT (Phase 3)'),
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPolicyCard(),
            const SizedBox(height: 16),
            _buildNftForm(),
            const SizedBox(height: 16),
            if (_error != null) _buildErrorCard(),
            if (_status != null && !_isLoading) _buildSuccessCard(),
            if (_txHash != null) _buildTxHashCard(),
            const SizedBox(height: 16),
            _buildMintButton(),
            const SizedBox(height: 24),
            _buildInfoCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildPolicyCard() {
    return Card(
      color: Colors.purple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.policy, color: Colors.purple.shade700, size: 16),
              const SizedBox(width: 6),
              Text(
                'Minting Policy',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade800,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            _LabelValue(
              label: 'Type',
              value: 'ScriptPubkey (key-locked)',
            ),
            _LabelValue(
              label: 'Key Hash',
              value: widget.paymentKeyHash,
              monospace: true,
            ),
            if (_policyId != null)
              _LabelValue(
                label: 'Policy ID',
                value: _policyId!,
                monospace: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNftForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'NFT Metadata (CIP-25)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nftNameController,
              decoration: const InputDecoration(
                labelText: 'NFT Name *',
                hintText: 'e.g. TestNFT',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nftImageController,
              decoration: const InputDecoration(
                labelText: 'Image URI *',
                hintText: 'ipfs://Qm... or https://...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nftDescriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMintButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _mintNft,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple.shade700,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.token),
        label: Text(
          _isLoading ? (_status ?? 'Minting...') : 'Mint NFT on Testnet',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.error, color: Colors.red, size: 16),
              const SizedBox(width: 6),
              const Text(
                'Error',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 16),
          const SizedBox(width: 6),
          Text(
            _status!,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildTxHashCard() {
    return Card(
      color: Colors.green.shade100,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Transaction Hash',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _txHash!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tx hash copied to clipboard')),
                );
              },
              child: Text(
                _txHash!,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'View on Cardanoscan:\nhttps://preview.cardanoscan.io/transaction/$_txHash',
              style: const TextStyle(fontSize: 11, color: Colors.green),
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
              '1. Policy = ScriptPubkey tied to your payment key\n'
              '2. CIP-25 metadata (label 721) attached as AuxiliaryData\n'
              '3. Native token minted under that policy\n'
              '4. Transaction signed with your payment key\n'
              '5. Submitted to Cardano testnet preview via Blockfrost\n\n'
              'This is Phase 3 of the Cardano Flutter SDK.',
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
            width: 72,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.purple.shade700,
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
