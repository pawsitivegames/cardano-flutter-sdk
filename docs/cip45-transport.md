# CIP-45 transport integration

Phase 4.4 ships the **transport-agnostic CIP-45 protocol core** (tested):

- `Cip45ConnectionUri` — build/parse the CIP-13 `web+cardano://connect/v1?identifier=<pubkey>` URI.
- `Cip45WalletHandler` — bridge inbound RPC calls (CIP-30 method names) to a `Cip30Wallet`, and produce the API-announcement payload.
- `Cip45Transport` — the interface a peer-to-peer backend implements.

The example ships two transports + full deep-link wiring (see status table at the
end). Live-verified path: the bugout WebView transport. Native WebRTC transport:
scaffold with documented seams.

## 1. Transport (WebTorrent discovery + WebRTC)

Per [CIP-45](https://cips.cardano.org/cip/CIP-45), discovery uses WebTorrent
trackers and the data channel uses WebRTC — the reference PoC uses
[`bugout`](https://github.com/chr15m/bugout).

### 1a. `BugoutCip45Transport` — shipped & live-verified ✅

`example/lib/cip45_transport.dart` hosts the patched `bugout.min.js`
(WebTorrent+WebRTC) inside a headless `flutter_inappwebview` WebView and bridges
RPC frames to `Cip45WalletHandler`. This is the supported, live-verified path
(iPhone ↔ desktop dApp; `getBalance`/`getUtxos`/`signData` round-tripped). Because
it runs the real bugout.js, it is byte-compatible with bugout-based dApps.

### 1b. `WebrtcCip45Transport` — native scaffold (no WebView) 🟡

`example/lib/cip45_webrtc_transport.dart` runs the WebRTC half *natively* via
`flutter_webrtc`, with **no WebView**. The WebRTC data-channel negotiation
(offer/answer, trickled ICE, data-channel RPC serve loop) is fully implemented.
Two bugout-specific pieces are factored out behind interfaces so they are
explicit rather than faked:

- **`Cip45SignalingChannel`** — peer DISCOVERY + SDP/ICE relay. In real CIP-45
  this is bugout's WebTorrent layer (announce an infohash derived from the
  identifier to WSS trackers; the swarm relays offers/answers). A Dart WebTorrent
  WSS tracker client is the main remaining work — none exists on pub.dev today.
- **`Cip45RpcCodec`** — on-wire framing of RPC over the data channel. bugout uses
  bencode + NaCl (ed25519 sign / box encrypt) keyed by the address. The bundled
  `JsonCip45RpcCodec` is plain JSON (fine native↔native); a `BugoutCip45RpcCodec`
  is required to talk to a bugout.js dApp.

So the WebRTC plumbing is real and exercised; bugout compatibility is the
documented gap. Usage:

```dart
final handler = Cip45WalletHandler(wallet: cip30Wallet, name: 'MyWallet');
final transport = WebrtcCip45Transport(
  identifier: uri.identifier,
  signaling: myTrackerSignalingChannel,      // implement Cip45SignalingChannel
  announcement: handler.apiAnnouncement(),
  // codec: BugoutCip45RpcCodec(...),         // for bugout.js dApps
);
transport.onRequest(handler.handleRequest);
await transport.start();
```

## 2. Deep linking for `web+cardano://` — shipped ✅

Both platforms open the wallet from a dApp link/QR; inbound URIs route to the
CIP-45 screen via `app_links` → `Cip45ConnectionUri.parse`.

- **iOS:** the `web+cardano` URL scheme is registered in `Info.plist`
  (`CFBundleURLTypes`).
- **Android:** a `VIEW`/`BROWSABLE` `<intent-filter>` for the `web+cardano`
  scheme on the `singleTop` `MainActivity` in `AndroidManifest.xml`.

In-wallet QR scanning of the connection URI is wired on the CIP-45 screen via
`mobile_scanner` (`example/lib/qr_scanner_page.dart`); camera permission is
declared for both platforms.

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

## Status (2026-06-03)

| Item | Status |
|------|--------|
| Protocol core (`Cip45ConnectionUri` / `Cip45WalletHandler` / `Cip45Transport`) | ✅ shipped, unit-tested |
| `BugoutCip45Transport` (WebView) | ✅ shipped, **live-verified** (iOS ↔ desktop dApp) |
| iOS `web+cardano://` deep link | ✅ shipped |
| Android `web+cardano://` intent-filter | ✅ shipped (Android-device verify pending) |
| In-wallet QR scanning (`mobile_scanner`) | ✅ **verified on iPhone 13 (2026-06-03)** — scanned the dApp QR → parsed URI → CIP-45 connect → API handshake (`wallet connected: cardano_flutter_rs`) |
| `WebrtcCip45Transport` (native, no WebView) | 🟡 scaffold — WebRTC done; bugout `Cip45SignalingChannel` (WebTorrent tracker) + `Cip45RpcCodec` (NaCl/bencode) seams documented, not implemented |
| Two-device / Android-device live run | ⏳ pending hardware |

The native WebRTC transport is intentionally a documented scaffold: a faithful
bugout-compatible implementation needs a Dart WebTorrent WSS tracker client and
bugout's NaCl/bencode framing, neither of which can be verified without two live
peers. The bugout WebView transport remains the supported, verified path.
