// A small full-screen QR scanner that returns the first decoded value.
//
// Used by the CIP-45 screen to scan a dApp's `web+cardano://` connection URI
// instead of pasting it. Lives in the example app; the core SDK has no camera
// dependency.

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Push this and await a `String?` — the scanned QR payload, or `null` if the
/// user backed out.
///
/// [validate] is an optional filter: return `true` to accept a decoded value and
/// pop with it, `false` to keep scanning (e.g. ignore non-`web+cardano://`
/// codes). When omitted, the first decoded value is returned.
class QrScannerPage extends StatefulWidget {
  final String title;
  final bool Function(String value)? validate;

  const QrScannerPage({
    super.key,
    this.title = 'Scan QR code',
    this.validate,
  });

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      final ok = widget.validate?.call(value) ?? true;
      if (!ok) continue;
      _handled = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable: ${error.errorDetails?.message ?? error.errorCode.name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          // Simple reticle to aim the code.
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          const Positioned(
            bottom: 48,
            left: 24,
            right: 24,
            child: Text(
              'Point the camera at the dApp’s connection QR code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
