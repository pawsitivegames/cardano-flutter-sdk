/// cardano_flutter_rs — production-grade Cardano SDK for Flutter, powered by Rust + FFI.
///
/// See README.md and docs/PLAN.md for usage and architecture.
library cardano_flutter_rs;

// FFI bridge and generated bindings
export 'src/frb_generated.dart';
export 'src/error.dart';
export 'src/wrappers.dart';

// Wallet and key derivation types (not functions, to avoid duplicate exports)
export 'src/wallet.dart' show KeyDerivationResult, DerivedAddress;
export 'src/address.dart' show AddressInfo;

// Phase 5a: HD multi-account discovery + BIP-44 gap-limit address scanning.
export 'src/hd/hd_wallet.dart';

// Phase 5b: at-rest seed encryption (Argon2id KDF + XChaCha20-Poly1305 AEAD).
// Password-based primitives; the platform secure-storage (Keychain/Keystore)
// wrapping-key composition is demonstrated in the example app.
export 'src/seed.dart';

// Transaction building, signing, and coin selection
export 'src/tx.dart';
export 'src/coin_selection.dart';
export 'src/sign.dart';

// Phase 3: Native minting, Plutus data, CIP-25/68 metadata
export 'src/minting.dart';
export 'src/plutus.dart';
export 'src/metadata.dart';

// Phase 4: Staking operations
// Only export BuiltStakingTx type; the functions are wrapped in wrappers.dart
// to avoid ambiguous exports and provide friendlier async signatures.
export 'src/staking.dart' show BuiltStakingTx;

// Phase 4.2: Message signing (CIP-8)
// Only export SignedMessage type; the functions are wrapped in wrappers.dart
export 'src/message.dart' show SignedMessage;

// Phase 4.3: CIP-30 dApp connector
// Raw serialization/signing primitives + the high-level Cip30Wallet class.
export 'src/cip30.dart';
export 'src/cip30/cip30_wallet.dart';

// Phase 4.4: CIP-45 mobile dApp connector (transport-agnostic protocol core).
export 'src/cip45/cip45.dart';

// Phase 6: CSL↔CML cross-backend conformance harness. The deterministic
// serialization/derivation contract both the native (CSL/FFI) and web (CML-JS)
// backends must satisfy byte-for-byte. Golden vectors freeze the contract.
export 'src/conformance/conformance.dart';

// Phase 4.5: Hardware wallets (Ledger/Trezor).
// Pure xpub-derivation + witness-assembly primitives, a device-agnostic
// HardwareWallet interface, and a CIP-30-shaped HardwareCip30Wallet. The device
// transport (BLE/USB) is implemented by adapters outside the core package.
export 'src/hardware.dart'
    show
        HardwareAccount,
        HardwareVkeyWitness,
        HardwareTxBody,
        HardwareTxInput,
        HardwareTxOutput,
        HardwareTxAsset,
        xpubToAccount,
        xpubDerivePublicKey,
        assembleVkeyWitnessSet,
        extractVkeyWitnesses,
        decomposeTxBody;
export 'src/hardware/hardware_cip30_wallet.dart';

// Providers
export 'src/providers/blockfrost.dart';
export 'src/providers/blockfrost_errors.dart';
