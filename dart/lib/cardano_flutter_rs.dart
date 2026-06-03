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

// Phase 4: Staking operations
// Only export BuiltStakingTx type; the functions are wrapped in wrappers.dart
// to avoid ambiguous exports and provide friendlier async signatures.
export 'src/staking.dart' show BuiltStakingTx;

// Phase 4.2: Message signing (CIP-8)
// Only export SignedMessage type; the functions are wrapped in wrappers.dart
export 'src/message.dart' show SignedMessage;

// Providers
export 'src/providers/blockfrost.dart';
export 'src/providers/blockfrost_errors.dart';
