import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'windows_qr_scanner_dialog.dart';

/// A full-screen dialog that opens the device camera and scans a QR code.
/// Returns the decoded QR string, or null if the user cancels.
///
/// Automatically routes to the platform-appropriate scanner:
/// - **Windows / Linux** → periodic capture via [camera] + [zxing2] decoder
/// - **Android / iOS / macOS / Web** → real-time via [mobile_scanner]
Future<String?> showQrScannerDialog(BuildContext context) {
  // Windows and Linux use camera + zxing2 instead of mobile_scanner
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    return showWindowsQrScannerDialog(context);
  }
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _QrScannerDialog(),
  );
}

class _QrScannerDialog extends StatefulWidget {
  const _QrScannerDialog();

  @override
  State<_QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<_QrScannerDialog> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _hasScanned = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SizedBox(
        width: 400,
        height: 500,
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.qr_code_scanner, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Scan QR Code',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Camera viewfinder ──
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 48,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Camera error',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () {
                                setState(() => _error = null);
                                _controller.start();
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(20),
                      ),
                      child: Stack(
                        children: [
                          MobileScanner(
                            controller: _controller,
                            onDetect: _onDetect,
                            errorBuilder: (context, error, child) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(
                                    () => _error =
                                        error.errorDetails?.message ??
                                        error.errorCode.name,
                                  );
                                }
                              });
                              return child ?? const SizedBox.shrink();
                            },
                          ),
                          // ── Scan overlay ──
                          Center(
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          // ── Torch toggle ──
                          Positioned(
                            bottom: 16,
                            right: 16,
                            child: ValueListenableBuilder(
                              valueListenable: _controller,
                              builder: (context, value, child) {
                                final torchState = value.torchState;
                                return IconButton(
                                  icon: Icon(
                                    torchState == TorchState.on
                                        ? Icons.flash_on
                                        : Icons.flash_off,
                                    color: Colors.white,
                                  ),
                                  onPressed: () => _controller.toggleTorch(),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            // ── Footer hint ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Point the camera at a QR code',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
