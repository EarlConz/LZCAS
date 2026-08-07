// lib/services/updater_service.dart
// In-app GitHub Auto-Updater — checks GitHub Releases for newer versions,
// downloads the platform-appropriate binary with progress tracking, and
// opens the installer on completion.
//
// Triggered automatically after login and manually from Settings.

import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show Platform, File, HttpClient, HttpClientResponse, HttpException;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

// ── Types ───────────────────────────────────────────────────────────────────

enum UpdateStatus { idle, checking, updateAvailable, downloading, ready, error }

class UpdateInfo {
  final String version;
  final String changelog;
  final String downloadUrl;
  final String fileName;
  final int fileSize;

  const UpdateInfo({
    required this.version,
    required this.changelog,
    required this.downloadUrl,
    required this.fileName,
    required this.fileSize,
  });
}

// ── Service ─────────────────────────────────────────────────────────────────

class UpdaterService extends ChangeNotifier {
  static const _repoOwner = 'EarlConz';
  static const _repoName = 'LZCAS';
  static const _apiBase = 'https://api.github.com';

  final Dio _dio;

  UpdateStatus _status = UpdateStatus.idle;
  UpdateInfo? _updateInfo;
  double _downloadProgress = 0.0;
  String? _errorMessage;
  String? _downloadedFilePath;

  UpdateStatus get status => _status;
  UpdateInfo? get updateInfo => _updateInfo;
  double get downloadProgress => _downloadProgress;
  String? get errorMessage => _errorMessage;
  String? get downloadedFilePath => _downloadedFilePath;

  UpdaterService({Dio? dio}) : _dio = dio ?? Dio();

  // ── Public API ──────────────────────────────────────────────────────────

  /// Check GitHub for a newer release.
  ///
  /// When [silent] is true (auto-check after login), listeners are NOT
  /// notified unless an update IS available — the user never sees a
  /// "no update found" toast after login.
  Future<UpdateInfo?> checkForUpdate({bool silent = true}) async {
    _status = UpdateStatus.checking;
    _errorMessage = null;
    _updateInfo = null;
    notifyListeners();

    try {
      // 1) Current app version from package_info_plus.
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"

      // 2) Latest GitHub release.
      final latest = await _fetchLatestRelease();
      if (latest == null) {
        _status = UpdateStatus.idle;
        _errorMessage = 'Could not reach GitHub. Check your connection.';
        if (!silent) notifyListeners();
        return null;
      }

      final latestVersion = _stripV(latest['tag_name'] as String? ?? '');
      final changelog =
          (latest['body'] as String?)?.trim() ?? 'No release notes.';

      // 3) Compare — only continue if the remote version is newer.
      if (_compareVersions(latestVersion, currentVersion) <= 0) {
        _status = UpdateStatus.idle;
        if (!silent) notifyListeners();
        return null;
      }

      // 4) Find platform-matching asset.
      final assets = latest['assets'] as List<dynamic>? ?? [];
      final asset = _findMatchingAsset(assets);
      if (asset == null) {
        _status = UpdateStatus.idle;
        _errorMessage = 'No binary found for your platform.';
        if (!silent) notifyListeners();
        return null;
      }

      _updateInfo = UpdateInfo(
        version: latestVersion,
        changelog: changelog,
        downloadUrl: asset['browser_download_url'] as String,
        fileName: asset['name'] as String,
        fileSize: (asset['size'] as num?)?.toInt() ?? 0,
      );

      _status = UpdateStatus.updateAvailable;
      notifyListeners();
      return _updateInfo;
    } catch (e) {
      _status = UpdateStatus.idle;
      _errorMessage = 'Update check failed: $e';
      if (!silent) notifyListeners();
      return null;
    }
  }

  /// Download the update binary to the platform temp directory,
  /// reporting progress via [downloadProgress].
  ///
  /// GitHub release asset URLs issue a 302 redirect to AWS S3
  /// (objects.githubusercontent.com). We configure Dio to follow
  /// redirects and strip custom headers that S3 would reject.
  /// If Dio still fails, a native [HttpClient] fallback runs.
  Future<bool> downloadUpdate() async {
    if (_updateInfo == null) return false;

    _status = UpdateStatus.downloading;
    _downloadProgress = 0.0;
    _errorMessage = null;
    notifyListeners();

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/${_updateInfo!.fileName}';
    final file = File(filePath);

    // Remove stale partial download.
    if (await file.exists()) await file.delete();

    // ── Attempt 1: Dio with redirect-safe configuration ──────────────
    try {
      final redirected = await _downloadWithDio(filePath);
      if (redirected) {
        _downloadedFilePath = filePath;
        _status = UpdateStatus.ready;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('[Updater] Dio download failed, trying HttpClient: $e');
    }

    // ── Attempt 2: Native HttpClient fallback ────────────────────────
    try {
      await _downloadWithHttpClient(filePath);
      _downloadedFilePath = filePath;
      _status = UpdateStatus.ready;
      notifyListeners();
      return true;
    } catch (e) {
      _status = UpdateStatus.error;
      _errorMessage = 'Download failed: $e';
      notifyListeners();
      return false;
    }
  }

  /// Dio-based download configured to handle GitHub → S3 redirects.
  /// Returns true on success, or throws on failure.
  Future<bool> _downloadWithDio(String filePath) async {
    final downloadDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 10),
        // ── Critical for GitHub → S3 redirect chain ──────────────────
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (status) => status != null && status < 500,
        // Do NOT set any Authorization or custom headers — S3 rejects
        // forwarded auth headers after the 302 redirect.
        headers: {'User-Agent': 'LZCAS-Updater/1.0'},
      ),
    );

    await downloadDio.download(
      _updateInfo!.downloadUrl,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          _downloadProgress = received / total;
          notifyListeners();
        }
      },
    );
    return true;
  }

  /// Native dart:io HttpClient fallback. Handles the 302 → S3 redirect
  /// chain with full control over header forwarding.
  Future<void> _downloadWithHttpClient(String filePath) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(_updateInfo!.downloadUrl));
      // Follow GitHub → S3 redirects (default limit: 5 hops).
      request.followRedirects = true;
      // Only set a User-Agent — no Authorization headers.
      request.headers.set('User-Agent', 'LZCAS-Updater/1.0');
      request.headers.set('Accept', 'application/octet-stream');

      final response = await request.close();

      if (response.statusCode >= 400) {
        throw HttpException(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }

      final total = response.contentLength;
      var received = 0;

      final sink = File(filePath).openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          _downloadProgress = received.toDouble() / total.toDouble();
          notifyListeners();
        }
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
  }

  /// Launch the downloaded installer package.
  Future<bool> openDownloadedFile() async {
    if (_downloadedFilePath == null) return false;
    try {
      final result = await OpenFilex.open(_downloadedFilePath!);
      return result.type == ResultType.done;
    } catch (e) {
      _errorMessage = 'Could not open installer: $e';
      notifyListeners();
      return false;
    }
  }

  /// Reset state (called after dialog dismissal).
  void reset() {
    _status = UpdateStatus.idle;
    _updateInfo = null;
    _downloadProgress = 0.0;
    _errorMessage = null;
    _downloadedFilePath = null;
    notifyListeners();
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _fetchLatestRelease() async {
    try {
      final uri = Uri.parse(
        '$_apiBase/repos/$_repoOwner/$_repoName/releases/latest',
      );
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'LZCAS-Updater/1.0',
        },
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
      }
      return null;
    } catch (e) {
      debugPrint('[Updater] GitHub fetch failed: $e');
      return null;
    }
  }

  /// Strip leading 'v' from semver tag: "v1.2.3" → "1.2.3".
  String _stripV(String tag) => tag.startsWith('v') ? tag.substring(1) : tag;

  /// Compare two semantic versions.
  /// Returns >0 if [a] > [b], <0 if [a] < [b], 0 if equal.
  int _compareVersions(String a, String b) {
    final aParts = _parseVersion(a);
    final bParts = _parseVersion(b);
    for (int i = 0; i < 3; i++) {
      final cmp = aParts[i].compareTo(bParts[i]);
      if (cmp != 0) return cmp;
    }
    return 0;
  }

  List<int> _parseVersion(String version) {
    final parts = version.split('.');
    return [
      int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0,
      int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
      int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0,
    ];
  }

  /// Match a release asset to the current OS.
  Map<String, dynamic>? _findMatchingAsset(List<dynamic> assets) {
    for (final a in assets) {
      if (a is! Map<String, dynamic>) continue;
      final name = (a['name'] as String?)?.toLowerCase() ?? '';
      if (_isMatchForCurrentPlatform(name)) return a;
    }
    return null;
  }

  bool _isMatchForCurrentPlatform(String assetName) {
    if (Platform.isAndroid) return assetName.endsWith('.apk');
    if (Platform.isWindows) {
      return assetName.endsWith('.exe') || assetName.endsWith('.msi');
    }
    if (Platform.isMacOS) {
      return assetName.endsWith('.dmg') || assetName.endsWith('.pkg');
    }
    if (Platform.isLinux) {
      return assetName.endsWith('.appimage') ||
          assetName.endsWith('.deb') ||
          assetName.endsWith('.tar.gz');
    }
    return false;
  }
}
