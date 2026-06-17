import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:zxing2/qrcode.dart';

/// A Windows-compatible QR scanner that uses [camera] to show a live preview
/// and periodically captures frames to decode QR codes via [zxing2].
///
/// On platforms where [mobile_scanner] is unavailable (Windows, Linux), use
/// this dialog instead. The camera preview + periodic capture loop provides
/// a near-real-time scanning experience.
Future<String?> showWindowsQrScannerDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _WindowsQrScannerDialog(),
  );
}

class _WindowsQrScannerDialog extends StatefulWidget {
  const _WindowsQrScannerDialog();

  @override
  State<_WindowsQrScannerDialog> createState() =>
      _WindowsQrScannerDialogState();
}

class _WindowsQrScannerDialogState extends State<_WindowsQrScannerDialog> {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _hasScanned = false;
  String? _error;
  Timer? _captureTimer;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No camera found');
        return;
      }

      _controller = CameraController(cameras.first, ResolutionPreset.medium);

      await _controller!.initialize();
      if (!mounted) return;

      setState(() => _isInitialized = true);

      // Start periodic capture loop (~3 fps)
      _captureTimer = Timer.periodic(const Duration(milliseconds: 350), (_) {
        _captureAndScan();
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Camera error: ${e.toString().replaceAll(RegExp(r'^Exception: '), '')}',
        );
      }
    }
  }

  Future<void> _captureAndScan() async {
    if (_hasScanned || _isCapturing || _controller == null) return;
    _isCapturing = true;

    try {
      final xfile = await _controller!.takePicture();
      final scanned = await _decodeQrFromFile(xfile);

      if (scanned != null && scanned.isNotEmpty && !_hasScanned) {
        _hasScanned = true;
        _captureTimer?.cancel();
        if (mounted) {
          Navigator.of(context).pop(scanned);
        }
      }
    } catch (_) {
      // Swallow frame-level errors; continue scanning
    } finally {
      _isCapturing = false;
    }
  }

  /// Decode a QR code from a captured image by decoding JPEG via [dart:ui],
  /// converting to ARGB [Int32List], then running [zxing2]'s QR decoder.
  Future<String?> _decodeQrFromFile(XFile xfile) async {
    try {
      final bytes = await xfile.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 640,
        targetHeight: 480,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData();
      codec.dispose();

      if (byteData == null) return null;

      final width = image.width;
      final height = image.height;
      final rgba = byteData.buffer.asUint8List();

      // Convert RGBA (4 bytes/pixel) → ARGB Int32List (1 int = 0xAARRGGBB)
      final argb = Int32List(width * height);
      for (var i = 0; i < width * height; i++) {
        final offset = i * 4;
        final r = rgba[offset];
        final g = rgba[offset + 1];
        final b = rgba[offset + 2];
        final a = rgba[offset + 3];
        argb[i] = (a << 24) | (r << 16) | (g << 8) | b;
      }

      final source = RGBLuminanceSource(width, height, argb);
      final binarizer = HybridBinarizer(source);
      final bitmap = BinaryBitmap(binarizer);
      final reader = QRCodeReader();
      final result = reader.decode(bitmap);
      return result.text;
    } catch (_) {
      return null; // Decode failed for this frame
    }
  }

  @override
  void dispose() {
    _captureTimer?.cancel();
    _controller?.dispose();
    super.dispose();
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

            // ── Camera preview / error ──
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
                              'Camera unavailable',
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
                                _initCamera();
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _isInitialized && _controller != null
                  ? ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(20),
                      ),
                      child: Stack(
                        children: [
                          CameraPreview(_controller!),
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
                          // ── Scanning indicator ──
                          if (_isCapturing)
                            const Positioned(
                              top: 16,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),

            // ── Footer actions ──
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
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.paste, size: 18),
                    label: const Text('Paste'),
                    onPressed: () {
                      _captureTimer?.cancel();
                      _showPasteDialog(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPasteDialog(BuildContext context) async {
    final tc = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste QR code'),
        content: TextField(
          controller: tc,
          decoration: const InputDecoration(
            hintText: 'Paste QR code text here',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, tc.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (result != null) {
      if (mounted) Navigator.of(context).pop(result);
    } else {
      // User cancelled paste; resume scanning
      if (mounted) {
        setState(() {
          _captureTimer = Timer.periodic(const Duration(milliseconds: 350), (
            _,
          ) {
            _captureAndScan();
          });
        });
      }
    }
  }
}
