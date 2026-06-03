# CIP-45 end-to-end testing guide (iOS)

This walks through a live two-peer CIP-45 test: the **reference dApp** (a web page)
and the **wallet** (the example Flutter app), connected peer-to-peer over bugout
(WebTorrent discovery + WebRTC), with no central server.

> ✅ **Verified 2026-06-02** — iPhone 13 (iOS 26.5) ↔ desktop Chrome dApp on
> Cardano **preview**. Full handshake (`wallet connected: cardano_flutter_rs`)
> plus live CIP-30 RPC: `getNetworkId` (`0`), `getBalance` (real multi-asset
> value), `getUtxos` (real UTXOs), and `signData` (valid `COSE_Sign1` +
> `COSE_Key`) all round-tripped over WebTorrent/WebRTC. Fixes landed during the
> run:
> - example home-screen button rows → `Wrap` (CIP-30/45 buttons were clipped
>   off-screen in a `Row`);
> - `signData` handler accepts `[payload]` or `[address, payload]` (blank address
>   → wallet's own base address), matching how real CIP-30 dApps call it;
> - **`getNetworkId` falsy-response bug:** bugout silently drops falsy RPC results
>   (`0`/`false`/`""`) and `flutter_inappwebview` mangles bare primitives. Fixed
>   by an envelope around the bridge result + a one-line patch to `bugout.min.js`.
>   See `docs/cip45-transport.md` §4.

## What's implemented

- **Core (package, tested):** `Cip45ConnectionUri`, `Cip45WalletHandler`, `Cip45Transport`.
- **Transport (example):** `BugoutCip45Transport` — hosts `bugout.min.js` in a
  headless WebView and bridges RPC to the wallet.
- **Wallet UI (example):** the **CIP-45** screen — paste/deep-link a connection
  URI, connect, and serve CIP-30 calls.
- **dApp (example asset):** `assets/cip45/dapp.html` — shows the connection
  URI + QR and calls wallet methods.
- **Deep link:** iOS registers `web+cardano://` (Info.plist) → opens the CIP-45 screen.

## Steps

### 1. Serve the reference dApp

```bash
cd example/assets/cip45
python3 -m http.server 8000
```

Open <http://localhost:8000/dapp.html> in a desktop browser (Chrome/Safari).
It generates a bugout identifier and shows a `web+cardano://connect/v1?identifier=…`
URI plus a QR code. Status starts as "waiting for wallet…".

### 2. Run the wallet app on an iOS device

```bash
cd example
flutter run -d <your-iphone>          # or run from Xcode
```

In the app, tap **CIP-45**.

### 3. Connect

Copy the `web+cardano://…` URI from the dApp page and paste it into the wallet's
CIP-45 screen, then tap **Connect**. (Peer discovery + WebRTC can take ~10–60 s.)

When connected:
- the wallet status pill turns green ("connected"),
- the dApp page shows "wallet connected" and renders a button per method.

### 4. Exercise the API from the dApp

Click the method buttons on the dApp page; results appear in its log:

- `getNetworkId` → `0`
- `getRewardAddresses`, `getUsedAddresses`, `getUnusedAddresses`, `getChangeAddress`
- `getUtxos`, `getBalance` (CBOR hex)
- `signData` → accept the default payload → `{ signature, key }`
- `signTx` / `submitTx` → paste a tx CBOR hex (advanced)

### Deep-link variant (optional)

Instead of pasting, open the URI as a link on the device (e.g. Notes →
`web+cardano://connect/v1?identifier=…`). iOS should launch the wallet straight
to the CIP-45 screen with the URI pre-filled.

> Note: iOS custom URL schemes containing `+` can be finicky; if the link does
> not launch the app, the paste flow always works.

## Troubleshooting

- **Never connects:** bugout relies on public WebTorrent trackers + WebRTC NAT
  traversal. Ensure both peers have internet; try a different network (some
  corporate/cellular NATs block WebRTC). Tracker availability varies — the
  transport announces on several.
- **Watch the wallet log** on the CIP-45 screen for peer counts and RPC lines.
- **Inspect the dApp** with the browser console for bugout diagnostics.

## Report back

If you hit issues, capture: the wallet CIP-45 log, the dApp browser console, the
network you're on, and which step failed — and I'll iterate on the transport.
