#import <Foundation/Foundation.h>

/// Flutter plugin registration stub for cardano_flutter_rs.
/// The primary purpose of this class is to hold hard references to the Rust
/// FFI symbols so the linker does not dead-strip them from the static library
/// before Dart's ExternalLibrary.process() can find them via dlsym().
@interface CardanoFlutterRsPlugin : NSObject
+ (void)registerWithRegistrar:(NSObject *)registrar;
@end
