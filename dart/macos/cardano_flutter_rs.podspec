Pod::Spec.new do |s|
  s.name             = 'cardano_flutter_rs'
  s.version          = '0.9.0'
  s.summary          = 'Cardano Flutter SDK - Rust FFI binding (macOS)'
  s.description      = 'Production-grade Cardano SDK for Flutter, powered by Rust + FFI'
  s.homepage         = 'https://github.com/pawsitivegames/cardano-flutter-sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Cardano Flutter SDK' => 'dev@pawsitivegames.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{h,m}'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'

  # Same rationale as iOS: with use_frameworks! every pod would otherwise become
  # its own dynamic framework, and the ObjC stub's cardano_flutter_rs.framework
  # would collide with the Rust framework below. static_framework links the stub
  # into the host binary so the vendored Rust framework is the sole
  # cardano_flutter_rs.framework embedded in <App>.app/Contents/Frameworks.
  s.static_framework = true

  # Universal (arm64 + x86_64) Rust framework. Built by build_macos_framework.sh
  # (run it after any Rust change). Unlike iOS there is no device/simulator split,
  # so a single vendored framework suffices — no copy-dylib script phase.
  s.vendored_frameworks = 'Libs/cardano_flutter_rs.framework'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
