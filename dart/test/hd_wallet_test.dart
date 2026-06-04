import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const testMnemonic =
      'test walk nut penalty hip pave soap entry language right filter choice';

  setUpAll(() async {
    await RustLib.init();
  });

  /// Derives the bech32 address for a given account/role/index (testnet), so a
  /// fake [AddressUsedLookup] can mark specific real addresses as used.
  Future<String> addrAt(int accountIndex, int role, int index) async {
    final keys = await deriveKeysFromMnemonic(
      mnemonic: testMnemonic,
      passphrase: '',
      accountIndex: accountIndex,
      isTestnet: true,
    );
    final d = await deriveAddress(
      accountKey: keys.accountKey,
      role: role,
      index: index,
      networkId: 0,
    );
    return d.address;
  }

  group('deriveAddress', () {
    test('account 0 external index 0 matches the canonical payment key hash',
        () async {
      final keys = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: '',
        accountIndex: 0,
        isTestnet: true,
      );
      final d = await deriveAddress(
        accountKey: keys.accountKey,
        role: 0,
        index: 0,
        networkId: 0,
      );
      expect(d.paymentKeyHash,
          '9493315cd92eb5d8c4304e67b7e16ae36d61d34502694657811a2c8e');
      expect(d.address, startsWith('addr_test1'));
    });

    test('distinct addresses per index/role/account', () async {
      final a = await addrAt(0, 0, 0);
      final b = await addrAt(0, 0, 1);
      final c = await addrAt(0, 1, 0);
      final d = await addrAt(1, 0, 0);
      expect({a, b, c, d}.length, 4);
    });
  });

  group('HdWalletDiscovery.scanChain', () {
    test('stops after gapLimit consecutive unused; records used slots',
        () async {
      final keys = await deriveKeysFromMnemonic(
        mnemonic: testMnemonic,
        passphrase: '',
        accountIndex: 0,
        isTestnet: true,
      );
      // Mark external indices 0 and 3 as used.
      final used = <String>{
        await addrAt(0, 0, 0),
        await addrAt(0, 0, 3),
      };
      final discovery = HdWalletDiscovery(
        isAddressUsed: (a) async => used.contains(a),
        networkId: 0,
        gapLimit: 3,
      );
      final chain =
          await discovery.scanChain(accountKey: keys.accountKey, role: 0);

      // gap=3, used at 0 and 3 → scans indices 0..6 (3 trailing unused).
      expect(chain.length, 7);
      expect(
        chain.where((a) => a.isUsed).map((a) => a.index).toList(),
        [0, 3],
      );
    });
  });

  group('HdWalletDiscovery.scanAccount', () {
    test('nextReceiveAddress is the first unused external slot', () async {
      // external index 0 used → next receive should be index 1.
      final used = <String>{await addrAt(0, 0, 0)};
      final discovery = HdWalletDiscovery(
        isAddressUsed: (a) async => used.contains(a),
        networkId: 0,
        gapLimit: 2,
      );
      final account = await discovery.scanAccount(
        mnemonic: testMnemonic,
        accountIndex: 0,
      );
      expect(account.isActive, isTrue);
      expect(account.nextReceiveAddress.index, 1);
      expect(account.nextReceiveAddress.isUsed, isFalse);
      expect(account.usedAddresses.length, 1);
    });
  });

  group('HdWalletDiscovery.discoverAccounts', () {
    test('fresh wallet returns only account 0 (empty)', () async {
      final discovery = HdWalletDiscovery(
        isAddressUsed: (a) async => false, // nothing used anywhere
        networkId: 0,
        gapLimit: 2,
      );
      final accounts =
          await discovery.discoverAccounts(mnemonic: testMnemonic);
      expect(accounts.length, 1);
      expect(accounts.single.accountIndex, 0);
      expect(accounts.single.isActive, isFalse);
    });

    test('stops at the first empty account (account gap = 1)', () async {
      // Accounts 0 and 1 active; account 2 empty → discovery returns [0, 1].
      final used = <String>{
        await addrAt(0, 0, 0),
        await addrAt(1, 0, 0),
      };
      final discovery = HdWalletDiscovery(
        isAddressUsed: (a) async => used.contains(a),
        networkId: 0,
        gapLimit: 2,
      );
      final accounts =
          await discovery.discoverAccounts(mnemonic: testMnemonic);
      expect(accounts.map((a) => a.accountIndex).toList(), [0, 1]);
      expect(accounts.every((a) => a.isActive), isTrue);
    });
  });
}
