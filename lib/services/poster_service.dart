// lib/services/poster_service.dart
//
// Picking and preparing the image half of an announcement or a birthday
// greeting.
//
// Two jobs, both deliberately kept out of the repository: choosing a file
// from the machine, and getting it down to something reasonable to upload.
// The repository does the uploading and the signing; it does not know what a
// JPEG is.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// The longest edge we keep. A poster is displayed at most a few hundred
/// logical pixels wide, so 1600 leaves room for a high-DPI phone screen and
/// for pinch-zoom in the detail view without shipping a 12-megapixel camera
/// original to every member on mobile data.
const int _maxEdge = 1600;

/// JPEG quality for photographic posters. 85 is the usual point where
/// artefacts stop being visible on a screen; below ~75 flat brand colours
/// start to band.
const int _jpegQuality = 85;

/// Anything larger than this is refused before we even decode it. A 60 MB
/// RAW file is not a poster, and decoding it just to find out costs memory
/// on a phone.
const int _maxSourceBytes = 25 * 1024 * 1024;

/// What the picker hands back: bytes ready to upload, and the extension they
/// should be stored under.
class PreparedPoster {
  final Uint8List bytes;

  /// 'jpg' or 'png' — decided by whether the image needs transparency,
  /// not by what the user happened to pick.
  final String extension;

  final int width;
  final int height;

  const PreparedPoster({
    required this.bytes,
    required this.extension,
    required this.width,
    required this.height,
  });

  String get contentType => extension == 'png' ? 'image/png' : 'image/jpeg';

  /// For the "Poster · 1240×1754 · 412 KB" line under the preview.
  String get sizeLabel {
    final kb = bytes.lengthInBytes / 1024;
    return kb < 1024
        ? '${kb.round()} KB'
        : '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

/// Raised when a chosen file cannot be used. The message is written to be
/// shown to an admin as-is.
class PosterException implements Exception {
  final String message;
  const PosterException(this.message);
  @override
  String toString() => message;
}

/// Open the system file picker and prepare whatever was chosen.
///
/// Returns null when the picker was dismissed — that is a cancel, not an
/// error, and callers should do nothing.
///
/// Throws [PosterException] with a displayable message when the file is too
/// large or is not an image we can decode.
Future<PreparedPoster?> pickPoster() async {
  const typeGroup = XTypeGroup(
    label: 'Images',
    extensions: <String>['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
    // Needed on Android/iOS, which match on MIME rather than extension.
    mimeTypes: <String>[
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
      'image/bmp',
    ],
  );

  final file = await openFile(acceptedTypeGroups: const [typeGroup]);
  if (file == null) return null;

  final source = await file.readAsBytes();

  if (source.lengthInBytes > _maxSourceBytes) {
    final mb = (source.lengthInBytes / (1024 * 1024)).toStringAsFixed(1);
    throw PosterException(
      'That image is $mb MB. Pick one under 25 MB, or export it smaller first.',
    );
  }
  if (source.isEmpty) {
    throw const PosterException('That file is empty.');
  }

  // Decode, resize and re-encode off the UI thread: a 4000px source takes
  // long enough that doing it inline drops frames on a phone, and the admin
  // form animates while this runs.
  return compute(_prepare, source);
}

/// Runs in a background isolate — must not touch anything Flutter.
PreparedPoster _prepare(Uint8List source) {
  final decoded = img.decodeImage(source);
  if (decoded == null) {
    throw const PosterException(
      'That file could not be read as an image. JPG, PNG and WebP all work.',
    );
  }

  final longest = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;

  // Only ever shrink. Upscaling a small poster would inflate the upload
  // without adding a single pixel of detail.
  final resized = longest <= _maxEdge
      ? decoded
      : img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? _maxEdge : null,
          height: decoded.height > decoded.width ? _maxEdge : null,
          interpolation: img.Interpolation.average,
        );

  // Keep PNG only when transparency is actually in use. Brand posters are
  // often exported as PNG out of habit, and re-encoding those as JPEG is
  // typically a 5-10x saving; but a logo with a transparent background
  // would grow an ugly black box if we flattened it.
  if (_hasTransparency(resized)) {
    return PreparedPoster(
      bytes: Uint8List.fromList(img.encodePng(resized)),
      extension: 'png',
      width: resized.width,
      height: resized.height,
    );
  }

  return PreparedPoster(
    bytes: Uint8List.fromList(img.encodeJpg(resized, quality: _jpegQuality)),
    extension: 'jpg',
    width: resized.width,
    height: resized.height,
  );
}

/// Whether any pixel is not fully opaque.
///
/// Checks the channel count first so a JPEG — which cannot carry alpha —
/// costs nothing, and bails on the first transparent pixel rather than
/// scanning an entire large image.
bool _hasTransparency(img.Image image) {
  if (image.numChannels < 4) return false;
  for (final pixel in image) {
    if (pixel.a < pixel.maxChannelValue) return true;
  }
  return false;
}
