Pod::Spec.new do |s|
  s.name             = 'cardano_flutter_rs'
  s.version          = '0.1.0'
  s.summary          = 'Cardano Flutter SDK - Rust FFI binding'
  s.description      = 'Production-grade Cardano SDK for Flutter, powered by Rust + FFI'
  s.homepage         = 'https://github.com/YOUR_HANDLE/cardano-flutter-sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Cardano' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'

  s.platform = :ios, '12.0'

  # iOS Rust static library built by flutter_rust_bridge
  s.vendored_libraries = 'Libs/libcardano_flutter_rs.a'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
  }

  s.swift_version = '5.0'
end
