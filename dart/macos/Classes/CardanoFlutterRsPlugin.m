#import "CardanoFlutterRsPlugin.h"

// Declare the Rust FFI symbols that Dart will locate at runtime. Referencing
// them here creates a hard linker dependency that prevents the linker from
// dead-stripping them and keeps the vendored framework loaded in the process.
extern uint32_t frb_get_rust_content_hash(void);
extern void frb_pde_ffi_dispatcher_primary(void);
extern void frb_pde_ffi_dispatcher_sync(void);
extern void frb_dart_api_dl(void);
extern void frb_dart_fn_deliver_output(void);
extern void frb_rust_vec_u8_new(void);
extern void frb_rust_vec_u8_free(void);
extern void frb_create_shutdown_callback(void);

/// Dummy function — never called at runtime. Its sole job is to appear in the
/// object file so the linker pulls in all the declarations above.
__attribute__((used))
static void cardano_flutter_rs_force_link_rust_symbols(void) {
    (void)frb_get_rust_content_hash;
    (void)frb_pde_ffi_dispatcher_primary;
    (void)frb_pde_ffi_dispatcher_sync;
    (void)frb_dart_api_dl;
    (void)frb_dart_fn_deliver_output;
    (void)frb_rust_vec_u8_new;
    (void)frb_rust_vec_u8_free;
    (void)frb_create_shutdown_callback;
}

@implementation CardanoFlutterRsPlugin
+ (void)registerWithRegistrar:(NSObject *)registrar {}
@end
