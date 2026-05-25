import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';
import 'send_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _sdkVersion = 'Ready to test';
  String _addressValidation = 'Not tested yet';
  String _keyDerivation = 'Not tested yet';
  bool _isTesting = false;
  bool _libInitialized = false;
  String _initError = '';
  String? _blockfrostProjectId;
  String? _myAddress;
  KeyDerivationResult? _derivedKeys;

  @override
  void initState() {
    super.initState();
    // Pre-initialize the Rust library in the background
    _preInitializeLib();
    // Get Blockfrost project ID from dart-define
    _blockfrostProjectId = const String.fromEnvironment('BLOCKFROST_PROJECT_ID');
  }

  Future<void> _preInitializeLib() async {
    try {
      debugPrint('[Cardano SDK] Starting pre-initialization...');
      if (!kIsWeb) {
        await RustLib.init();
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
        await RustLib.init();
        setState(() => _libInitialized = true);
        debugPrint('[Cardano SDK] RustLib.init() completed successfully');
      }

      // Test 1: Get SDK version
      debugPrint('[Cardano SDK] Testing getSdkVersion()...');
      final version = await getSdkVersion();
      debugPrint('[Cardano SDK] SDK Version: $version');

      // Test 2: Validate a Bech32 address
      final testAddr =
          'addr1qw2f2cjnal96nuzl0pn5xysqf24kxyxnxvjd7yq6khvn2wl2uld';
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

    // For this demo, we'll use a known testnet address
    // In production, derive from payment key hash
    const testnetAddress =
        'addr_test1qzx9hu8j4zh3k1sugsscq69ek5ee2nrw6rasydg4gwyydewjjxtwq2ytjqd8';

    final provider = BlockfrostProvider(
      projectId: _blockfrostProjectId!,
      network: Network.testnetPreview,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => SendScreen(
          provider: provider,
          myAddress: testnetAddress,
          paymentKey: _derivedKeys!.paymentKey,
          stakeKey: _derivedKeys!.stakeKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cardano Flutter RS Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Cardano Flutter RS - Phase 1 & 2'),
        ),
        body: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Phase 1 & 2: SDK + Transaction Building',
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
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _derivedKeys != null
                            ? _navigateToSendScreen
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        child: const Text(
                          'Send Testnet ADA',
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
