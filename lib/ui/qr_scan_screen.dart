import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Returns the first `gshare://` code it sees.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.startsWith('gshare://')) {
        _done = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan gshare code')),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          const Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Point the camera at the code on the other device\'s Receive tab.'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
