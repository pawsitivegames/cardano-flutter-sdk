// In-browser harness for [WebCip30Wallet] (Phase 6 scoped web CIP-30).
//
// Compiled with `dart compile js` and run in a real browser (headless Chromium
// in CI). It drives the scoped wallet's OFFLINE ops — derivation + signData —
// against the frozen native golden values, and round-trips signData↔verifyData.
// Network ops (getUtxos/getBalance) are intentionally excluded here so the gate
// stays deterministic and key-free; those are exercised manually in the example.
//
// The host page must have instantiated CML + message-signing WASM on
// globalThis.CML / globalThis.MS and installed globalThis.CFL_mnemonicToEntropy
// (see wallet_index.html / data.js). Publishes globalThis.WALLET_RESULT and sets
// globalThis.WALLET_DONE = true when finished.
import 'dart:convert';
import 'dart:js_interop';

import 'package:cardano_flutter_rs/cardano_flutter_rs_web.dart';

@JS('WALLET_RESULT')
external set _walletResult(String v);

@JS('WALLET_DONE')
external set _walletDone(bool v);

const _mnemonic =
    'test walk nut penalty hip pave soap entry language right filter choice';

// Frozen native golden values (CSL) for the test mnemonic, account 0, testnet.
// See dart/test/conformance/golden_cbor.json (deriveAddress / keyDerivation).
const _expPaymentHash = '9493315cd92eb5d8c4304e67b7e16ae36d61d34502694657811a2c8e';
const _expStakeHash = '32c728d3861e164cab28cb8f006448139c8f1740ffb8e7aa9e5232dc';
const _expBaseAddr =
    'addr_test1qz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3jcu5d8ps7zex2k2xt3uqxgjqnnj83ws8lhrn648jjxtwq2ytjqp';
const _expRewardAddr =
    'stake_test1uqevw2xnsc0pvn9t9r9c7qryfqfeerchgrlm3ea2nefr9hqp8n5xl';

Future<void> main() async {
  final checks = <String, bool>{};
  final notes = <String>[];

  void check(String name, bool ok, [String? note]) {
    checks[name] = ok;
    if (note != null) notes.add('$name: $note');
  }

  try {
    // A provider is required by the factory but never called by offline ops.
    final provider = BlockfrostProvider(
      projectId: 'offline-harness',
      network: Network.testnetPreview,
    );
    final wallet = await WebCip30Wallet.fromMnemonic(
      mnemonic: _mnemonic,
      provider: provider,
      isTestnet: true,
    );

    check('getNetworkId==0', await wallet.getNetworkId() == 0);
    check('paymentKeyHash', wallet.paymentKeyHashHex == _expPaymentHash,
        wallet.paymentKeyHashHex);
    check('stakeKeyHash', wallet.stakeKeyHashHex == _expStakeHash,
        wallet.stakeKeyHashHex);

    final change = await wallet.getChangeAddress();
    check('getChangeAddress==goldenBase', change == _expBaseAddr, change);
    check('baseAddress==goldenBase', wallet.baseAddressBech32 == _expBaseAddr);

    final used = await wallet.getUsedAddresses();
    check('getUsedAddresses==[base]',
        used.length == 1 && used.first == _expBaseAddr);
    check('getUnusedAddresses==[]', (await wallet.getUnusedAddresses()).isEmpty);

    final reward = await wallet.getRewardAddresses();
    check('getRewardAddresses==goldenReward',
        reward.length == 1 && reward.first == _expRewardAddr,
        reward.isEmpty ? '(none)' : reward.first);

    // signData → verifyData round-trip + tamper rejection (all in-browser).
    final payloadHex = _utf8Hex('hello web cip-30');
    final sig = wallet.signData(payloadHex);
    final addrHex =
        const CmlWebBackend().addressToHex(addressBech32: _expBaseAddr);
    const cml = CmlWebBackend();
    check(
      'signData→verifyData(accept)',
      cml.verifyData(
        signature: sig.signature,
        key: sig.key,
        expectedPayloadHex: payloadHex,
        expectedAddressHex: addrHex,
      ),
    );
    check(
      'verifyData(wrong payload)→reject',
      !cml.verifyData(
        signature: sig.signature,
        key: sig.key,
        expectedPayloadHex: _utf8Hex('tampered'),
        expectedAddressHex: addrHex,
      ),
    );
  } catch (e, st) {
    check('harness-threw', false, '$e\n$st');
  }

  final pass = checks.values.where((v) => v).length;
  final fail = checks.length - pass;
  final failed =
      checks.entries.where((e) => !e.value).map((e) => e.key).toList();
  final summary = StringBuffer('PASS $pass  FAIL $fail  / ${checks.length}');
  if (failed.isNotEmpty) summary.write('\nFAILED: ${failed.join(', ')}');
  if (notes.isNotEmpty) summary.write('\n${notes.join('\n')}');

  _walletResult = summary.toString();
  _walletDone = true;
}

String _utf8Hex(String s) {
  final sb = StringBuffer();
  for (final b in utf8.encode(s)) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
