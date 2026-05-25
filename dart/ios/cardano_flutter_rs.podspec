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

  # iOS Rust dynamic framework built by cargo (cdylib)
  s.vendored_frameworks = 'Libs/cardano_flutter_rs.framework'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) $(PODS_ROOT)/cardano_flutter_rs',
  }

  s.user_target_xcconfig = {
    'RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/Frameworks @loader_path/Frameworks',
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) @executable_path/Frameworks @loader_path/Frameworks',
  }

  s.swift_version = '5.0'
end
