/// cardano_flutter_rs — production-grade Cardano SDK for Flutter, powered by Rust + FFI.
///
/// See README.md and docs/PLAN.md for usage and architecture.
library cardano_flutter_rs;

// FFI bridge and generated bindings
export 'src/frb_generated.dart';
export 'src/error.dart';
export 'src/wrappers.dart';

// Wallet and key derivation types (not functions, to avoid duplicate exports)
export 'src/wallet.dart' show KeyDerivationResult;
export 'src/address.dart' show AddressInfo;

// Transaction building, signing, and coin selection
export 'src/tx.dart';
export 'src/coin_selection.dart';
export 'src/sign.dart';

// Phase 3: Native minting, Plutus data, CIP-25/68 metadata
export 'src/minting.dart';
export 'src/plutus.dart';
export 'src/metadata.dart';

// Providers
export 'src/providers/blockfrost.dart';
export 'src/providers/blockfrost_errors.dart';
