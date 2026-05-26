Pod::Spec.new do |s|
  s.name             = 'cardano_flutter_rs'
  s.version          = '0.1.0'
  s.summary          = 'Cardano Flutter SDK - Rust FFI binding'
  s.description      = 'Production-grade Cardano SDK for Flutter, powered by Rust + FFI'
  s.homepage         = 'https://github.com/YOUR_HANDLE/cardano-flutter-sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Cardano' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{h,m}'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # IMPORTANT: Prevents the ObjC plugin code from producing a competing
  # cardano_flutter_rs.framework. With use_frameworks! in the Podfile,
  # every pod normally becomes a dynamic framework — which would create a
  # cardano_flutter_rs.framework from Classes/*.m that then overwrites
  # (or is overwritten by) the Rust framework below, leaving the device
  # with only the 87 KB ObjC shell and no Rust symbols.
  #
  # static_framework = true makes CocoaPods link the ObjC code statically
  # into the host binary instead. The Rust vendored_frameworks below becomes
  # the sole cardano_flutter_rs.framework embedded in Runner.app/Frameworks/.
  s.static_framework = true

  # Rust dynamic framework — embedded in Runner.app/Frameworks/ at build time.
  # The script phase below swaps in the correct device / simulator binary
  # before Xcode processes the embed step.
  s.vendored_frameworks = 'Libs/cardano_flutter_rs.framework'

  # Select the right Rust binary (device vs. simulator) before Xcode embeds
  # the framework. Without this, whatever binary was last written into
  # Libs/cardano_flutter_rs.framework gets deployed, regardless of target.
  s.script_phases = [
    {
      :name              => '[Cardano SDK] Copy Rust Dylib',
      :script            => 'bash "${PODS_TARGET_SRCROOT}/copy_dylib.sh"',
      :execution_position => :before_compile,
      :output_files      => [
        '$(PODS_TARGET_SRCROOT)/Libs/cardano_flutter_rs.framework/cardano_flutter_rs',
      ],
      :always_out_of_date => '1',
    }
  ]

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
