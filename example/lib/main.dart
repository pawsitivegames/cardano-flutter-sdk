import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:app_links/app_links.dart';
import 'send_screen.dart';
import 'mint_screen.dart';
import 'stake_screen.dart';
import 'message_screen.dart';
import 'ledger_screen.dart';
import 'cip30_screen.dart';
import 'cip45_screen.dart';

// Compile-time Flutter version injected via --dart-define (optional).
// Falls back to a placeholder if not provided.
const String kFlutterVersion =
    String.fromEnvironment('FLUTTER_VERSION', defaultValue: 'unknown');

// Increment this every build so the running version is visible on screen.
const String kBuildLabel = 'build-008 · Phase 4.2';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  String _sdkVersion = 'Ready to test';
  String _addressValidation = 'Not tested yet';
  String _keyDerivation = 'Not tested yet';
  bool _isTesting = false;
  bool _libInitialized = false;
  String _initError = '';
  String? _blockfrostProjectId;
  String? _myAddress;
  KeyDerivationResult? _derivedKeys;

  final AppLinks _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    // Get Blockfrost project ID from dart-define, fall back to dev key
    const envKey = String.fromEnvironment('BLOCKFROST_PROJECT_ID');
    _blockfrostProjectId = envKey.isNotEmpty
        ? envKey
        : 'previewAmnr5VzpgWZkHMg8BibEiC4Vqkcq4G7e'; // TODO: remove before release
    // Auto-run tests on startup for verification
    debugPrint('[Cardano SDK] App initialized, running tests automatically...');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _testSDK();
    });
    _initDeepLinks();
  }

  /// Listen for `web+cardano://connect/...` deep links (CIP-45) and route them
  /// to the CIP-45 wallet screen.
  void _initDeepLinks() {
    if (kIsWeb) return;
    _appLinks.uriLinkStream.listen((uri) {
      final s = uri.toString();
      if (s.startsWith('${Cip45ConnectionUri.scheme}://')) {
        _navigateToCip45Screen(initialUri: s);
      }
    }, onError: (_) {});
  }

  Future<void> _preInitializeLib() async {
    try {
      debugPrint('[Cardano SDK] Starting pre-initialization...');
      if (!kIsWeb) {
        if (Platform.isIOS) {
          // Build absolute path: Runner.app/ is the parent of the executable.
          // CocoaPods embeds the framework at Runner.app/Frameworks/.
          final bundleDir = File(Platform.resolvedExecutable).parent.path;
          final libPath = '$bundleDir/Frameworks/cardano_flutter_rs.framework/cardano_flutter_rs';
          await RustLib.init(
            externalLibrary: ExternalLibrary.open(libPath),
          );
        } else {
          await RustLib.init();
        }
        debugPrint('[Cardano SDK] RustLib.init() completed successfully');
        setState(() => _libInitialized = true);
      }
    } catch (e) {
      debugPrint('[Cardano SDK] RustLib.init() failed: $e');
      setState(() {
        _initError = 'Init Error: $e';
        _libInitialized = false;
      });
    }
  }

  Future<void> _testSDK() async {
    setState(() => _isTesting = true);
    if (kIsWeb) {
      setState(() {
        _sdkVersion = 'Web Version (Demo Mode)';
        _addressValidation = 'Valid: true\nNetwork: Demo (No FFI on web)';
        _keyDerivation = 'Payment Key: demo_key_abcdef123456...\nStake Key: demo_stake_key_xyz789...';
        _isTesting = false;
      });
      return;
    }

    try {
      // Initialize the FFI bridge if not already done (native only, not web)
      if (!_libInitialized) {
        debugPrint('[Cardano SDK] Running RustLib.init() from test button...');
        if (Platform.isIOS) {
          final exe = Platform.resolvedExecutable;
          final bundleDir = File(exe).parent.path;
          final libPath = '$bundleDir/Frameworks/cardano_flutter_rs.framework/cardano_flutter_rs';
          final exists = File(libPath).existsSync();
          setState(() => _sdkVersion = 'DEBUG\nexe=$exe\nexists=$exists');
          await RustLib.init(
            externalLibrary: ExternalLibrary.open(libPath),
          );
        } else {
          await RustLib.init();
        }
        setState(() => _libInitialized = true);
        debugPrint('[Cardano SDK] RustLib.init() completed successfully');
      }

      // Test 1: Get SDK version
      debugPrint('[Cardano SDK] Testing getSdkVersion()...');
      final version = await getSdkVersion();
      debugPrint('[Cardano SDK] SDK Version: $version');

      // Test 2: Validate a Bech32 address
      // Enterprise address derived from the test mnemonic (CIP-1852 m/1852'/1815'/0'/0/0, testnet)
      const testAddr =
          'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz';
      debugPrint('[Cardano SDK] Testing isValidBech32()...');
      final isValid = await isValidBech32(testAddr);
      debugPrint('[Cardano SDK] Address valid: $isValid');

      // Test 3: Derive keys from mnemonic (testnet for Phase 2 Send demo)
      const testMnemonic =
          'test walk nut penalty hip pave soap entry language right filter choice';
      String keyDerived = 'Failed';
      KeyDerivationResult? keys;
      try {
        debugPrint('[Cardano SDK] Testing deriveKeysFromMnemonic()...');
        keys = await deriveKeysFromMnemonic(
          mnemonic: testMnemonic,
          passphrase: '',
          accountIndex: 0,
          isTestnet: true,
        );
        keyDerived =
            'Payment Key: ${keys?.paymentKey.substring(0, 20)}...\nStake Key: ${keys?.stakeKey.substring(0, 20)}...';
        debugPrint('[Cardano SDK] Key derivation successful');

        // Store keys for Send screen
        _derivedKeys = keys;
      } catch (e) {
        keyDerived = 'Error: $e';
        debugPrint('[Cardano SDK] Key derivation failed: $e');
      }

      setState(() {
        _sdkVersion = version;
        _addressValidation =
            'Valid: $isValid\nNetwork: Cardano Testnet Preview';
        _keyDerivation = keyDerived;
        _isTesting = false;
      });
    } catch (e) {
      debugPrint('[Cardano SDK] Test failed with error: $e');
      setState(() {
        _sdkVersion = 'Error: $e';
        _addressValidation = 'Error: $e';
        _keyDerivation = 'Error: $e';
        _isTesting = false;
      });
    }
  }

  void _navigateToMintScreen() {
    if (_blockfrostProjectId == null || _blockfrostProjectId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set BLOCKFROST_PROJECT_ID to use the Mint screen'),
        ),
      );
      return;
    }

    if (_derivedKeys == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please run tests first to derive keys')),
      );
      return;
    }

    const testnetAddress =
        'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz';

    final provider = BlockfrostProvider(
      projectId: _blockfrostProjectId!,
      network: Network.testnetPreview,
    );

    _navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (ctx) => MintScreen(
          provider: provider,
          myAddress: testnetAddress,
          paymentSigningKey: _derivedKeys!.paymentSigningKey,
          paymentKeyHash: _derivedKeys!.paymentKeyHash,
        ),
      ),
    );
  }

  void _navigateToStakeScreen() {
    if (_blockfrostProjectId == null || _blockfrostProjectId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please set BLOCKFROST_PROJECT_ID to use the Stake screen',
          ),
        ),
      );
      return;
    }

    if (_derivedKeys == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please run tests first to derive keys')),
      );
      return;
    }

    const testnetAddress =
        'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz';

    final provider = BlockfrostProvider(
      projectId: _blockfrostProjectId!,
      network: Network.testnetPreview,
    );

    // Compute the bech32 stake address from the stake key hash
    final stakeAddress = computeStakeAddress(
      stakeKeyHashHex: _derivedKeys!.stakeKeyHash,
      isTestnet: true,
    );

    _navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (ctx) => StakeScreen(
          provider: provider,
          myAddress: testnetAddress,
          stakeAddress: stakeAddress,
          paymentSigningKey: _derivedKeys!.paymentSigningKey,
          stakeSigningKey: _derivedKeys!.stakeSigningKey,
          stakeKeyHashHex: _derivedKeys!.stakeKeyHash,
        ),
      ),
    );
  }

  void _navigateToMessageScreen() {
    if (_derivedKeys == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please run tests first to derive keys')),
      );
      return;
    }

    const testnetAddress =
        'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz';

    _navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (ctx) => MessageScreen(
          myAddress: testnetAddress,
          paymentSigningKey: _derivedKeys!.paymentSigningKey,
          stakeSigningKey: _derivedKeys!.stakeSigningKey,
        ),
      ),
    );
  }

  void _navigateToCip30Screen() {
    if (_blockfrostProjectId == null || _blockfrostProjectId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please set BLOCKFROST_PROJECT_ID environment variable or run with --dart-define=BLOCKFROST_PROJECT_ID=your_id',
          ),
        ),
      );
      return;
    }

    const testMnemonic =
        'test walk nut penalty hip pave soap entry language right filter choice';

    final provider = BlockfrostProvider(
      projectId: _blockfrostProjectId!,
      network: Network.testnetPreview,
    );

    _navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (ctx) => Cip30Screen(
          provider: provider,
          mnemonic: testMnemonic,
        ),
      ),
    );
  }

  void _navigateToLedgerScreen() {
    if (_blockfrostProjectId == null || _blockfrostProjectId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please set BLOCKFROST_PROJECT_ID environment variable or run with --dart-define=BLOCKFROST_PROJECT_ID=your_id',
          ),
        ),
      );
      return;
    }

    final provider = BlockfrostProvider(
      projectId: _blockfrostProjectId!,
      network: Network.testnetPreview,
    );

    _navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (ctx) => LedgerScreen(provider: provider),
      ),
    );
  }

  void _navigateToCip45Screen({String? initialUri}) {
    final projectId = _blockfrostProjectId;
    if (projectId == null || projectId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please set BLOCKFROST_PROJECT_ID environment variable or run with --dart-define=BLOCKFROST_PROJECT_ID=your_id',
          ),
        ),
      );
      return;
    }

    const testMnemonic =
        'test walk nut penalty hip pave soap entry language right filter choice';

    final provider = BlockfrostProvider(
      projectId: projectId,
      network: Network.testnetPreview,
    );

    _navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (ctx) => Cip45Screen(
          provider: provider,
          mnemonic: testMnemonic,
          initialUri: initialUri,
        ),
      ),
    );
  }

  void _navigateToSendScreen() {
    if (_blockfrostProjectId == null || _blockfrostProjectId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please set BLOCKFROST_PROJECT_ID environment variable or run with --dart-define=BLOCKFROST_PROJECT_ID=your_id',
          ),
        ),
      );
      return;
    }

    if (_derivedKeys == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please run tests first to derive keys'),
        ),
      );
      return;
    }

    // Canonical test address: CIP-1852 m/1852'/1815'/0'/0/0 from test mnemonic, testnet
    const testnetAddress =
        'addr_test1vz2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzerspjrlsz';

    final provider = BlockfrostProvider(
      projectId: _blockfrostProjectId!,
      network: Network.testnetPreview,
    );

    _navigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (ctx) => SendScreen(
          provider: provider,
          myAddress: testnetAddress,
          paymentSigningKey: _derivedKeys!.paymentSigningKey,
          stakeKey: _derivedKeys!.stakeKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Cardano Flutter RS Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Cardano Flutter RS'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(20),
            child: Container(
              color: Colors.blue.shade800,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: const Text(
                kBuildLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        body: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _VersionBanner(sdkVersion: _sdkVersion),
                  const SizedBox(height: 12),
                  const Text(
                    'Phase 1–4: SDK + TX + Minting + Staking + Messages',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_blockfrostProjectId == null || _blockfrostProjectId!.isEmpty)
                    Card(
                      color: Colors.orange.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Warning: BLOCKFROST_PROJECT_ID not set',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Run with: flutter run --dart-define=BLOCKFROST_PROJECT_ID=your_project_id\n\n'
                              'Get a free testnet API key from https://blockfrost.io',
                              style: TextStyle(color: Colors.orange),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_initError.isNotEmpty)
                    Card(
                      color: Colors.red.shade100,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Initialization Error:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                            Text(
                              _initError,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_initError.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SDK Version:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(_sdkVersion),
                            const SizedBox(height: 16),
                            const Text(
                              'Address Validation:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(_addressValidation),
                            const SizedBox(height: 16),
                            const Text(
                              'Key Derivation:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(_keyDerivation),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _testSDK,
                        child: const Text('Re-Run Tests'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _derivedKeys != null
                            ? _navigateToSendScreen
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        icon: const Icon(Icons.send, color: Colors.white, size: 16),
                        label: const Text(
                          'Send ADA',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _derivedKeys != null
                            ? _navigateToMintScreen
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                        ),
                        icon: const Icon(Icons.token, color: Colors.white, size: 16),
                        label: const Text(
                          'Mint NFT',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _derivedKeys != null
                            ? _navigateToStakeScreen
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                        ),
                        icon: const Icon(Icons.account_balance,
                            color: Colors.white, size: 16),
                        label: const Text(
                          'Stake ADA',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _derivedKeys != null
                            ? _navigateToMessageScreen
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                        icon: const Icon(Icons.security,
                            color: Colors.white, size: 16),
                        label: const Text(
                          'Sign Message',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _libInitialized
                            ? _navigateToCip30Screen
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                        ),
                        icon: const Icon(Icons.hub,
                            color: Colors.white, size: 16),
                        label: const Text(
                          'CIP-30',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed:
                            _libInitialized ? () => _navigateToCip45Screen() : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                        ),
                        icon: const Icon(Icons.cable,
                            color: Colors.white, size: 16),
                        label: const Text(
                          'CIP-45',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed:
                            _libInitialized ? _navigateToLedgerScreen : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                        ),
                        icon: const Icon(Icons.memory,
                            color: Colors.white, size: 16),
                        label: const Text(
                          'Ledger',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionBanner extends StatelessWidget {
  final String sdkVersion;
  const _VersionBanner({required this.sdkVersion});

  @override
  Widget build(BuildContext context) {
    final dartVer = kIsWeb ? 'web' : Platform.version.split(' ').first;
    final osVer = kIsWeb ? 'web' : Platform.operatingSystemVersion;
    final mode = kReleaseMode
        ? 'RELEASE'
        : kProfileMode
            ? 'PROFILE'
            : 'DEBUG';

    final rows = <_InfoRow>[
      _InfoRow('Build', kBuildLabel),
      _InfoRow('Mode', mode),
      _InfoRow('Dart', dartVer),
      _InfoRow('OS', osVer),
      if (!sdkVersion.startsWith('Ready') &&
          !sdkVersion.startsWith('Error') &&
          !sdkVersion.startsWith('DEBUG'))
        _InfoRow('Rust SDK', sdkVersion),
    ];

    return Card(
      color: Colors.indigo.shade50,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.indigo.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.info_outline, size: 14, color: Colors.indigo.shade700),
              const SizedBox(width: 4),
              Text(
                'Build Info',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.indigo.shade800,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            ...rows.map((r) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          '${r.label}:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.indigo.shade600,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          r.value,
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _InfoRow {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
}
