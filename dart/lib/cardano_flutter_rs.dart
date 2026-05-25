/// cardano_flutter_rs — production-grade Cardano SDK for Flutter, powered by Rust + FFI.
///
/// See README.md and docs/project-plan.md for usage and architecture.
library cardano_flutter_rs;

// FFI bridge and generated bindings
export 'src/frb_generated.dart';
export 'src/error.dart';
export 'src/wrappers.dart';

// Providers
export 'src/providers/blockfrost.dart';
export 'src/providers/blockfrost_errors.dart';
