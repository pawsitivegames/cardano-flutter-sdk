#import <Foundation/Foundation.h>

/// Flutter (macOS) plugin registration stub for cardano_flutter_rs.
/// Its only purpose is to hold hard references to the Rust FFI symbols so the
/// linker does not dead-strip them and the vendored framework is loaded into the
/// process, letting Dart's ExternalLibrary resolve them at runtime.
@interface CardanoFlutterRsPlugin : NSObject
+ (void)registerWithRegistrar:(NSObject *)registrar;
@end
