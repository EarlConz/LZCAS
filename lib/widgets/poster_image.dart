// lib/widgets/poster_image.dart
//
// Displaying the image half of an announcement or a birthday greeting.
//
// The bucket is private (v44), so nothing here can point Image.network at a
// stored path directly — the path has to be signed first, and the signature
// expires. That round trip is what this widget exists to hide: every caller
// gets a path in and a picture out.

import 'package:flutter/material.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';

/// A stored poster, resolved and drawn.
///
/// Renders nothing at all — a zero-size box — when [path] is null or the URL
/// cannot be signed. A poster that fails to load must never leave a hole
/// where the announcement's text should be; the text is the fallback.
class PosterImage extends StatefulWidget {
  final String? path;

  /// Null lets the poster take its natural aspect ratio, which is what the
  /// detail view and the unseen popup want. The list passes a fixed size for
  /// the thumbnail.
  final double? width;
  final double? height;

  final BoxFit fit;
  final double borderRadius;
  final bool isDark;

  /// Caps how tall a natural-ratio poster may get. Without it a portrait
  /// poster on a phone pushes the title and the Save button off-screen.
  final double? maxHeight;

  /// Tapping opens the full-screen zoomable viewer. Off for thumbnails,
  /// whose row already has its own tap target.
  final bool openOnTap;

  const PosterImage({
    super.key,
    required this.path,
    required this.isDark,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 10,
    this.maxHeight,
    this.openOnTap = false,
  });

  @override
  State<PosterImage> createState() => _PosterImageState();
}

class _PosterImageState extends State<PosterImage> {
  Future<String?>? _url;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(PosterImage old) {
    super.didUpdateWidget(old);
    // Re-sign only when the poster actually changed. Rebuilds are frequent
    // (every star toggle rebuilds the list) and re-resolving on each one
    // would restart the image load and flash the placeholder.
    if (old.path != widget.path) _resolve();
  }

  void _resolve() {
    final path = widget.path;
    _url = (path == null || path.trim().isEmpty)
        ? Future.value(null)
        : repository.posterUrl(path);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.path == null || widget.path!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return _frame(_Placeholder(isDark: widget.isDark, spinning: true));
        }
        final url = snap.data;
        if (url == null) return const SizedBox.shrink();

        Widget image = Image.network(
          url,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : _Placeholder(isDark: widget.isDark, spinning: true),
          // A signed URL that has expired, or a file removed from the
          // bucket. Same rule as a failed signature: show nothing.
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );

        if (widget.openOnTap) {
          image = Semantics(
            button: true,
            label: 'View poster full screen',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => showPosterViewer(context, widget.path),
                child: image,
              ),
            ),
          );
        }

        return _frame(image);
      },
    );
  }

  Widget _frame(Widget child) {
    final constrained = widget.maxHeight == null
        ? child
        : ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight!),
            child: child,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: constrained,
    );
  }
}

/// The grey box shown while a poster resolves and downloads.
class _Placeholder extends StatelessWidget {
  final bool isDark;
  final bool spinning;

  const _Placeholder({required this.isDark, this.spinning = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      // 3:2 keeps the list from jumping when the real poster lands; most
      // posters are close enough that the settle is not visible.
      constraints: const BoxConstraints(minHeight: 90),
      color: isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
      alignment: Alignment.center,
      child: spinning
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark
                    ? StockpileColors.darkTextMuted
                    : StockpileColors.mutedText,
              ),
            )
          : null,
    );
  }
}

/// Full-screen, pinch-zoomable view of one poster.
///
/// Posters carry small print — dates, prices, terms — that a 300px-wide card
/// cannot render legibly, so every full-size poster in the app is tappable
/// through to this.
Future<void> showPosterViewer(BuildContext context, String? path) async {
  if (path == null || path.trim().isEmpty) return;
  final url = await repository.posterUrl(path);
  if (url == null || !context.mounted) return;

  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, _, _) => _PosterViewer(url: url),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 180),
    ),
  );
}

class _PosterViewer extends StatelessWidget {
  final String url;
  const _PosterViewer({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tapping the backdrop closes. The image sits above this, so a tap
          // on the poster itself does not dismiss mid-pinch.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
            ),
          ),
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Text(
                    'That poster could not be loaded.',
                    style: StockpileFonts.satoshi(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
