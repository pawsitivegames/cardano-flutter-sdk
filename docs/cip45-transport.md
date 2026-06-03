# CIP-45 transport integration (deferred)

Phase 4.4 ships the **transport-agnostic CIP-45 protocol core** (tested):

- `Cip45ConnectionUri` — build/parse the CIP-13 `web+cardano://connect/v1?identifier=<pubkey>` URI.
- `Cip45WalletHandler` — bridge inbound RPC calls (CIP-30 method names) to a `Cip30Wallet`, and produce the API-announcement payload.
- `Cip45Transport` — the interface a peer-to-peer backend implements.

What remains to make CIP-45 usable end-to-end on devices (needs a real transport + platform config + two-device testing):

## 1. Transport (WebTorrent discovery + WebRTC)

Per [CIP-45](https://cips.cardano.org/cip/CIP-45), discovery uses WebTorrent
trackers and the data channel uses WebRTC — the reference PoC uses
[`bugout`](https://github.com/chr15m/bugout). For Flutter, the realistic options:

- A Dart/native WebRTC stack (`flutter_webrtc`) plus a tracker client, or
- A thin platform channel wrapping `bugout` in a WebView, or
- A community Dart port if/when one exists.

Implement `Cip45Transport`:

```dart
class BugoutTransport implements Cip45Transport {
  // generate/persist an Ed25519 peer-discovery keypair → its pubkey is the
  // Cip45ConnectionUri identifier the dApp scans
  @override Future<void> start() { /* announce on trackers, open WebRTC */ }
  @override void onRequest(handler) { /* on inbound RPC frame: handler(method, params) → reply */ }
  @override Future<void> close() { /* ... */ }
}
```

Wire it to the handler:

```dart
final handler = Cip45WalletHandler(wallet: cip30Wallet, name: 'MyWallet');
final transport = BugoutTransport(/* seed, trackers */);
transport.onRequest(handler.handleRequest);
await transport.start();
// send handler.apiAnnouncement() to the dApp on connect
```

## 2. Deep linking for `web+cardano://`

So a dApp link/QR opens the wallet:

- **iOS:** register the `web+cardano` URL scheme (or a universal link) in
  `Info.plist`; handle inbound URLs (e.g. via `app_links`) → `Cip45ConnectionUri.parse`.
- **Android:** add an `<intent-filter>` for the `web+cardano` scheme in
  `AndroidManifest.xml`; handle the inbound intent → `Cip45ConnectionUri.parse`.

## 3. Verification (requires two devices / a peer dApp)

- dApp generates identifier → renders QR → wallet scans → `Cip45ConnectionUri.parse`.
- Transport connects; wallet announces `apiAnnouncement()`.
- dApp calls `getRewardAddresses`, `getUtxos`, `signTx`, `signData`, `submitTx`;
  each routes through `Cip45WalletHandler.handleRequest` to the `Cip30Wallet`.
- Confirm a `signTx` round-trip submits on testnet.

> Note: the roadmap originally labeled 4.4 "WalletConnect v2". CIP-45 proper is
> WebTorrent/WebRTC; WalletConnect is a separate (non-CIP-45) option. The core
> here (URI + RPC handler) is reusable under either transport.

## 4. Vendored `bugout.min.js` patch (falsy RPC responses)

⚠️ **`example/assets/cip45/bugout.min.js` is patched — do not blindly re-download it.**

Upstream bugout silently **drops any falsy RPC response value** (`0`, `false`,
`""`). Its response handler guards on truthiness:

```js
bugout.callbacks[nonce] && responsestringstruct ? (…callback(responsestringstruct)…) : debug("dropped")
```

`getNetworkId` returns `0` for testnet, which JSON-parses to `0` → `cb && 0` is
falsy → the caller's callback never fires. Discovered during live testing: the
wallet logged `← getNetworkId done` (it replied) but the dApp never received it.

**The patch** changes the truthiness guard to a null check so legitimate falsy
values pass (only `null`/`undefined`, e.g. malformed JSON, are dropped):

```diff
- bugout.callbacks[nonce]&&responsestringstruct?(
+ bugout.callbacks[nonce]&&null!=responsestringstruct?(
```

The dropping side is the **caller** (the peer holding the pending callback), so
the dApp's copy must be patched; the wallet bridge loads the same file. If you
ever refresh `bugout.min.js` from upstream, re-apply with:

```bash
cd example/assets/cip45
python3 - <<'PY'
p='bugout.min.js'; s=open(p,encoding='utf-8',errors='surrogateescape').read()
old='bugout.callbacks[nonce]&&responsestringstruct?('
new='bugout.callbacks[nonce]&&null!=responsestringstruct?('
assert s.count(old)==1, s.count(old)
open(p,'w',encoding='utf-8',errors='surrogateescape').write(s.replace(old,new))
print('patched')
PY
```

Also note: the wallet-side bridge wraps each handler result in an envelope
(`{ok, result}` in `cip45_transport.dart`, unwrapped in `cip45_bridge.html`) so
primitive results survive the Dart↔WebView (`flutter_inappwebview`) hop, which
also mangles bare primitives. Both fixes are needed for `getNetworkId` to work.
