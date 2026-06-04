// HD multi-account discovery + BIP-44 gap-limit address scanning (Phase 5a).
//
// CIP-1852 derives a tree of accounts from one seed:
//   m/1852'/1815'/account'/role/index
// where role 0 = external (receive), 1 = internal (change), 2 = stake. This
// module discovers which accounts and addresses of a seed have on-chain history,
// using only public derivation ([deriveAddress]) plus an address-usage lookup
// (e.g. `BlockfrostProvider.isAddressUsed`). No crypto is reimplemented in Dart.

import '../wallet.dart' show DerivedAddress;
import '../wrappers.dart' show deriveAddress, deriveKeysFromMnemonic;

/// Reports whether an address has ever been used on-chain (any transaction
/// history, even if its current balance is zero).
///
/// `BlockfrostProvider.isAddressUsed` satisfies this signature directly.
typedef AddressUsedLookup = Future<bool> Function(String address);

/// A single derived address slot within an account, with its discovered usage.
class HdAddress {
  /// Chain role: 0 = external/receive, 1 = internal/change.
  final int role;

  /// Address index on the chain.
  final int index;

  /// bech32 base address (`addr…` / `addr_test…`).
  final String address;

  /// Blake2b-224 hash (56 hex chars) of this slot's payment public key.
  final String paymentKeyHash;

  /// Whether this address has on-chain history.
  final bool isUsed;

  const HdAddress({
    required this.role,
    required this.index,
    required this.address,
    required this.paymentKeyHash,
    required this.isUsed,
  });

  @override
  String toString() =>
      'HdAddress(role: $role, index: $index, used: $isUsed, $address)';
}

/// A discovered CIP-1852 account: its derivation key plus the scanned external
/// and change chains.
///
/// > **Security:** [accountKey] is the account-level extended *private* key
/// > (xprv). Treat it as secret — Phase 5b adds encrypted-at-rest storage.
class HdAccount {
  /// Account index (the `account'` segment, 0-based).
  final int accountIndex;

  /// Account-level extended private key (bech32 xprv). **Sensitive.**
  final String accountKey;

  /// Blake2b-224 hash of the account's stake key (one reward address per account).
  final String stakeKeyHash;

  /// External/receive chain (role 0), scanned to the gap limit.
  final List<HdAddress> external;

  /// Internal/change chain (role 1), scanned to the gap limit.
  final List<HdAddress> change;

  const HdAccount({
    required this.accountIndex,
    required this.accountKey,
    required this.stakeKeyHash,
    required this.external,
    required this.change,
  });

  /// Whether any address on either chain has on-chain history.
  bool get isActive =>
      external.any((a) => a.isUsed) || change.any((a) => a.isUsed);

  /// All used addresses across both chains.
  List<HdAddress> get usedAddresses =>
      [...external, ...change].where((a) => a.isUsed).toList();

  /// The first unused external address — the next address to hand out for
  /// receiving. Falls back to external index 0 for a brand-new account.
  HdAddress get nextReceiveAddress => external.firstWhere(
        (a) => !a.isUsed,
        orElse: () => external.first,
      );

  @override
  String toString() => 'HdAccount(#$accountIndex, active: $isActive, '
      'used: ${usedAddresses.length})';
}

/// Discovers HD accounts and addresses for a mnemonic by gap-limit scanning.
///
/// ```dart
/// final discovery = HdWalletDiscovery(
///   isAddressUsed: provider.isAddressUsed,
///   networkId: 0, // testnet
/// );
/// final accounts = await discovery.discoverAccounts(mnemonic: mnemonic);
/// for (final a in accounts) {
///   print('account ${a.accountIndex}: ${a.usedAddresses.length} used, '
///       'next receive ${a.nextReceiveAddress.address}');
/// }
/// ```
class HdWalletDiscovery {
  /// On-chain usage lookup (e.g. `provider.isAddressUsed`).
  final AddressUsedLookup isAddressUsed;

  /// Target network: 0 = testnet, 1 = mainnet.
  final int networkId;

  /// BIP-44 gap limit: stop scanning a chain after this many consecutive unused
  /// addresses. Standard is 20.
  final int gapLimit;

  /// Largest number of accounts to probe in [discoverAccounts] (safety cap).
  final int maxAccounts;

  const HdWalletDiscovery({
    required this.isAddressUsed,
    required this.networkId,
    this.gapLimit = 20,
    this.maxAccounts = 20,
  })  : assert(gapLimit > 0),
        assert(networkId == 0 || networkId == 1);

  /// Gap-limit scans one chain ([role] 0 = external, 1 = change) of an account.
  ///
  /// Derives addresses sequentially and queries usage, stopping after
  /// [gapLimit] consecutive unused addresses. The returned list includes the
  /// trailing gap (so the next unused slot is discoverable).
  Future<List<HdAddress>> scanChain({
    required String accountKey,
    required int role,
  }) async {
    final addresses = <HdAddress>[];
    var consecutiveUnused = 0;
    var index = 0;

    while (consecutiveUnused < gapLimit) {
      final DerivedAddress d = await deriveAddress(
        accountKey: accountKey,
        role: role,
        index: index,
        networkId: networkId,
      );
      final used = await isAddressUsed(d.address);
      addresses.add(HdAddress(
        role: role,
        index: index,
        address: d.address,
        paymentKeyHash: d.paymentKeyHash,
        isUsed: used,
      ));
      consecutiveUnused = used ? 0 : consecutiveUnused + 1;
      index++;
    }
    return addresses;
  }

  /// Scans a single account (both external and change chains).
  Future<HdAccount> scanAccount({
    required String mnemonic,
    required int accountIndex,
    String passphrase = '',
  }) async {
    final keys = await deriveKeysFromMnemonic(
      mnemonic: mnemonic,
      passphrase: passphrase,
      accountIndex: accountIndex,
      isTestnet: networkId == 0,
    );
    final external = await scanChain(accountKey: keys.accountKey, role: 0);
    final change = await scanChain(accountKey: keys.accountKey, role: 1);
    return HdAccount(
      accountIndex: accountIndex,
      accountKey: keys.accountKey,
      stakeKeyHash: keys.stakeKeyHash,
      external: external,
      change: change,
    );
  }

  /// Discovers accounts for [mnemonic], stopping at the first **empty** account
  /// (BIP-44 account gap = 1).
  ///
  /// Account 0 is always returned even when empty (a fresh wallet still has an
  /// account 0 to receive into). Scanning then continues 1, 2, … while each is
  /// active, and stops as soon as an account has no on-chain history.
  Future<List<HdAccount>> discoverAccounts({
    required String mnemonic,
    String passphrase = '',
  }) async {
    final accounts = <HdAccount>[];
    for (var i = 0; i < maxAccounts; i++) {
      final account = await scanAccount(
        mnemonic: mnemonic,
        accountIndex: i,
        passphrase: passphrase,
      );
      final active = account.isActive;
      // Always include account 0; include later accounts only if active.
      if (i == 0 || active) accounts.add(account);
      // Stop at the first empty account (gap = 1).
      if (!active) break;
    }
    return accounts;
  }
}
