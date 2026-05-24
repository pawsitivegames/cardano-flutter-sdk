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

  @override
  void initState() {
    super.initState();
    _testFFIBridge();
  }

  Future<void> _testFFIBridge() async {
    try {
      // Test 1: Get SDK version
      final version = await getSdkVersion();

      // Test 2: Validate a Bech32 address
      const testAddr =
          'addr1q8f6mxhg5nglpy54nngfwx4nwydqy545y9nxmpl8zex3eqtty2nqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc7ygug';
      final isValid = await isValidBech32(testAddr);

      setState(() {
        _sdkVersion = version;
        _addressValidation = isValid ? 'Valid address' : 'Invalid address';
      });
    } catch (e) {
      setState(() {
        _sdkVersion = 'Error: $e';
        _addressValidation = 'Error: $e';
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
          title: const Text('Cardano Flutter RS - Phase 0 Test'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'FFI Bridge Test Results:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              Card(
                margin: const EdgeInsets.all(16),
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _testFFIBridge,
                child: const Text('Retry Test'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
