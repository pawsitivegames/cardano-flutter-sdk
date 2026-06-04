import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';

/// Phase 5a example: HD multi-account discovery + BIP-44 gap-limit scanning.
///
/// Runs [HdWalletDiscovery] over the test mnemonic against Blockfrost, listing
/// each discovered account with its used-address count, next receive address,
/// and an aggregated ADA balance. Discovery stops at the first empty account
/// (account gap = 1); account 0 always shows even when empty.
class AccountsScreen extends StatefulWidget {
  final BlockfrostProvider provider;
  final String mnemonic;

  const AccountsScreen({
    Key? key,
    required this.provider,
    required this.mnemonic,
  }) : super(key: key);

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool _running = false;
  String? _error;
  String _status = '';
  final List<_AccountView> _accounts = [];

  int get _networkId =>
      widget.provider.network == Network.mainnet ? 1 : 0;

  Future<void> _discover() async {
    setState(() {
      _running = true;
      _error = null;
      _accounts.clear();
      _status = 'Deriving and scanning addresses…';
    });

    try {
      final discovery = HdWalletDiscovery(
        isAddressUsed: widget.provider.isAddressUsed,
        networkId: _networkId,
        // Demo gap limit kept small so discovery is snappy on the free tier.
        // Production should use the BIP-44 standard of 20.
        gapLimit: 5,
      );

      final accounts =
          await discovery.discoverAccounts(mnemonic: widget.mnemonic);

      for (final account in accounts) {
        setState(() => _status =
            'Fetching balance for account #${account.accountIndex}…');
        final balance = await _accountBalance(account);
        _accounts.add(_AccountView(account: account, lovelace: balance));
      }

      setState(() => _status =
          'Discovered ${accounts.length} account(s). '
          'Gap limit 5 (demo); BIP-44 standard is 20.');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _running = false);
    }
  }

  /// Aggregate lovelace across an account's used addresses plus its next
  /// receive address (so a funded-but-unscanned next slot still shows).
  Future<BigInt> _accountBalance(HdAccount account) async {
    final targets = <String>{
      ...account.usedAddresses.map((a) => a.address),
      account.nextReceiveAddress.address,
    };
    var total = BigInt.zero;
    for (final address in targets) {
      final utxos = await widget.provider.fetchUtxos(address);
      for (final u in utxos) {
        total += u.coin;
      }
    }
    return total;
  }

  String _ada(BigInt lovelace) {
    final ada = lovelace / BigInt.from(1000000);
    return '${ada.toStringAsFixed(6)} ₳';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HD Accounts (Phase 5a)'),
        backgroundColor: Colors.cyan,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _running ? null : _discover,
              icon: const Icon(Icons.travel_explore),
              label: Text(_running ? 'Discovering…' : 'Discover accounts'),
            ),
            const SizedBox(height: 12),
            if (_running) const LinearProgressIndicator(),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_status,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(10),
                color: Colors.red.shade50,
                child: Text(_error!,
                    style: TextStyle(color: Colors.red.shade900, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _accounts.isEmpty
                  ? const Center(
                      child: Text(
                        'Tap "Discover accounts" to scan this seed.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _accounts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _accountCard(_accounts[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountCard(_AccountView view) {
    final account = view.account;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor:
                      account.isActive ? Colors.cyan : Colors.grey.shade400,
                  child: Text('${account.accountIndex}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                const SizedBox(width: 10),
                Text(
                  account.isActive ? 'Active' : 'Empty',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color:
                        account.isActive ? Colors.cyan.shade700 : Colors.grey,
                  ),
                ),
                const Spacer(),
                Text(_ada(view.lovelace),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${account.usedAddresses.length} used address(es) · '
              'external ${account.external.length} scanned · '
              'change ${account.change.length} scanned',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            _addressRow('Next receive', account.nextReceiveAddress.address),
          ],
        ),
      ),
    );
  }

  Widget _addressRow(String label, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        Expanded(
          child: Text(address,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
        ),
        InkWell(
          onTap: () {
            Clipboard.setData(ClipboardData(text: address));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Address copied'),
                  duration: Duration(seconds: 1)),
            );
          },
          child: const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.copy, size: 16, color: Colors.cyan),
          ),
        ),
      ],
    );
  }
}

class _AccountView {
  final HdAccount account;
  final BigInt lovelace;
  const _AccountView({required this.account, required this.lovelace});
}
