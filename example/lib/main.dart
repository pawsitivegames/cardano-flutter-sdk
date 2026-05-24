import 'package:flutter/material.dart';
import 'package:cardano_flutter_rs/cardano_flutter_rs.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _sdkVersion = 'Loading...';
  String _addressValidation = 'Not tested yet';
  String _keyDerivation = 'Not tested yet';

  @override
  void initState() {
    super.initState();
    _testSDK();
  }

  Future<void> _testSDK() async {
    try {
      // Initialize the FFI bridge
      await RustLib.init();

      // Test 1: Get SDK version
      final version = await getSdkVersion();

      // Test 2: Validate a Bech32 address
      final testAddr =
          'addr1qw2f2cjnal96nuzl0pn5xysqf24kxyxnxvjd7yq6khvn2wl2uld';
      final isValid = await isValidBech32(testAddr);

      // Test 3: Derive keys from mnemonic
      const testMnemonic =
          'test walk nut penalty hip pave soap entry language right filter choice';
      String keyDerived = 'Failed';
      try {
        final keys = await deriveKeysFromMnemonic(
          mnemonic: testMnemonic,
          passphrase: '',
          accountIndex: 0,
          isTestnet: false,
        );
        keyDerived =
            'Payment Key: ${keys.paymentKey.substring(0, 20)}...\nStake Key: ${keys.stakeKey.substring(0, 20)}...';
      } catch (e) {
        keyDerived = 'Error: $e';
      }

      setState(() {
        _sdkVersion = version;
        _addressValidation =
            'Valid: $isValid\nNetwork: Cardano Testnet';
        _keyDerivation = keyDerived;
      });
    } catch (e) {
      setState(() {
        _sdkVersion = 'Error: $e';
        _addressValidation = 'Error: $e';
        _keyDerivation = 'Error: $e';
      });
    }
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
          title: const Text('Cardano Flutter RS - Phase 1'),
        ),
        body: SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Phase 1: CSL-Backed SDK Test',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
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
                  ElevatedButton(
                    onPressed: _testSDK,
                    child: const Text('Re-Run Tests'),
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
