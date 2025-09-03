import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '/data/membersdata.dart'; // ✅ import members data

class QRScanButton extends StatefulWidget {
  const QRScanButton({super.key});

  @override
  State<QRScanButton> createState() => _QRScanButtonState();
}

class _QRScanButtonState extends State<QRScanButton> {
  String? scannedText;

  void _startQRScan(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (result != null && mounted) {
      setState(() => scannedText = result);

      // ✅ Look for the member in membersdata
      final member = membersdata.firstWhere(
        (m) => m["qr"] == scannedText,
        orElse: () => {},
      );

      if (member.isNotEmpty) {
        // ✅ Member found
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Member Found"),
            content: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Name: ${member["firstName"]} ${member["middleName"]} ${member["lastName"]}"),
                    Text("Role: ${member["role"]}"),
                    Text("Contact: ${member["contactNo"]}"),
                    Text("Birthday: ${member["birthday"]}"),
                    Text("Address: ${member["address"]}"),
                    Text("Referrer: ${member["referrer"]}"),
                    Text("Points: ${member["points"]}"),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          ),
        );
      } else {
        // ❌ Not found
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Not Found"),
            content: Text("No member matches QR: $scannedText"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.qr_code_scanner),
      label: const Text("Scan QR Code"),
      onPressed: () => _startQRScan(context),
    );
  }
}

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController controller = MobileScannerController();
  bool isScanned = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanArea = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 250,
      height: 250,
    );

    return Scaffold(
      body: Stack(
        children: [
          // ✅ Camera feed
          MobileScanner(
            controller: controller,
            scanWindow: scanArea,
            fit: BoxFit.cover,
            onDetect: (capture) async {
              if (isScanned) return; // prevent multiple triggers
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty) {
                isScanned = true;
                await controller.stop(); // ✅ stop scanning immediately
                if (mounted) {
                  Navigator.pop(context, barcodes.first.rawValue ?? "");
                }
              }
            },
          ),

          // ✅ Dark overlay with transparent scan area
          ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.6),
              BlendMode.srcOut,
            ),
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    backgroundBlendMode: BlendMode.dstOut,
                  ),
                ),
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ✅ Green scan box border (kept bright)
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.greenAccent,
                  width: 4,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // Close button
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Instruction text
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Text(
              "Align QR code inside the box",
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}