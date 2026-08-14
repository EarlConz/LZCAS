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
import '../config/build_flavor.dart';
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

  /// True when the running app is below the release's declared
  /// `min-supported-version` floor — the update must be installed (the dialog
  /// hides "Later" and blocks dismissal). Used to force clients up when a
  /// release is backend-breaking (e.g. ships DB migrations).
  final bool mandatory;

  const UpdateInfo({
    required this.version,
    required this.changelog,
    required this.downloadUrl,
    required this.fileName,
    required this.fileSize,
    this.mandatory = false,
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
    // Skip automatic (silent) checks in debug builds so development isn't
    // interrupted by the update prompt. A manual check from Settings
    // (silent: false) still runs so the flow remains testable.
    if (kDebugMode && silent) {
      _status = UpdateStatus.idle;
      return null;
    }

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
      final rawBody = (latest['body'] as String?)?.trim() ?? '';

      // Declared minimum supported version (floor). When the running app is
      // below it, the update is mandatory. Marker is stripped from the notes.
      final minSupported = _parseMinSupported(rawBody);
      final mandatory = minSupported != null &&
          _compareVersions(currentVersion, minSupported) < 0 &&
          _compareVersions(latestVersion, minSupported) >= 0;
      final changelog = () {
        final c = _stripMinMarker(rawBody);
        return c.isEmpty ? 'No release notes.' : c;
      }();

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
        mandatory: mandatory,
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

  /// Fetch the newest release for THIS build's channel.
  ///
  /// The two flavors read disjoint sets of releases, so a staging build can
  /// never update itself into production (or vice-versa):
  ///
  ///   • production → `/releases/latest`, which GitHub defines as the newest
  ///     release that is NOT a pre-release and NOT a draft.
  ///   • staging    → `/releases` (newest first), taking the first entry
  ///     flagged `prerelease` and skipping drafts.
  Future<Map<String, dynamic>?> _fetchLatestRelease() async {
    final path = BuildConfig.isStaging
        ? '/repos/$_repoOwner/$_repoName/releases?per_page=30'
        : '/repos/$_repoOwner/$_repoName/releases/latest';
    try {
      final response = await http.get(
        Uri.parse('$_apiBase$path'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'LZCAS-Updater/1.0',
        },
      );
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);

      // Production: the endpoint already returns exactly one release.
      if (!BuildConfig.isStaging) {
        return decoded is Map<String, dynamic> ? decoded : null;
      }

      // Staging: pick the newest pre-release from the list.
      if (decoded is! List) return null;
      for (final r in decoded) {
        if (r is! Map<String, dynamic>) continue;
        if (r['draft'] == true) continue;
        if (r['prerelease'] == true) return r;
      }
      return null;
    } catch (e) {
      debugPrint('[Updater] GitHub fetch failed: $e');
      return null;
    }
  }

  /// Strip leading 'v' from semver tag: "v1.2.3" → "1.2.3".
  String _stripV(String tag) => tag.startsWith('v') ? tag.substring(1) : tag;

  /// Read the declared minimum supported version from a release body.
  /// Recognises `min-supported-version: 1.5.0` (any of -/_/space, `:` or `=`)
  /// and the shorthand `[min:1.5.0]`. Returns null if none present.
  String? _parseMinSupported(String body) {
    final patterns = [
      RegExp(
          r'min[-_ ]?supported[-_ ]?version\s*[:=]\s*v?(\d+\.\d+(?:\.\d+)?)',
          caseSensitive: false),
      RegExp(r'\[\s*min\s*:\s*v?(\d+\.\d+(?:\.\d+)?)\s*\]',
          caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(body);
      if (m != null) return m.group(1);
    }
    return null;
  }

  /// Remove the min-version marker so it doesn't show in the changelog.
  String _stripMinMarker(String body) => body
      .replaceAll(
          RegExp(r'^.*min[-_ ]?supported[-_ ]?version\s*[:=].*$',
              multiLine: true, caseSensitive: false),
          '')
      .replaceAll(
          RegExp(r'\[\s*min\s*:\s*v?\d+\.\d+(?:\.\d+)?\s*\]',
              caseSensitive: false),
          '')
      .trim();

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

  /// Parse "1.2.3" into [1, 2, 3], tolerating a pre-release/build suffix on
  /// any segment.
  ///
  /// Only the LEADING digits of each segment are read, so "1.1.2-rc1" yields
  /// [1, 1, 2] rather than [1, 1, 0]. The naive `int.tryParse` used to fail on
  /// "2-rc1" and fall back to 0, silently discarding the patch number and
  /// making a real update look identical to an older one.
  ///
  /// Note this still ignores the suffix itself: "1.2.3-rc1" and "1.2.3-rc2"
  /// compare EQUAL. Tag releases with plain incrementing numbers.
  List<int> _parseVersion(String version) {
    final parts = version.trim().split('.');
    int segment(int i) {
      if (i >= parts.length) return 0;
      final match = RegExp(r'^\d+').firstMatch(parts[i].trim());
      return match == null ? 0 : (int.tryParse(match.group(0)!) ?? 0);
    }

    return [segment(0), segment(1), segment(2)];
  }

  /// Match a release asset to the current OS.
  /// Pick the asset for this platform AND this build flavor.
  ///
  /// Flavor safety: a staging build only accepts an asset whose filename
  /// contains "staging", and a production build only accepts one that does
  /// NOT. If the wrong binary is attached to a release, the update fails
  /// loudly ("No binary found for your platform") instead of silently
  /// converting a client's staging install into production, or vice-versa.
  Map<String, dynamic>? _findMatchingAsset(List<dynamic> assets) {
    for (final a in assets) {
      if (a is! Map<String, dynamic>) continue;
      final name = (a['name'] as String?)?.toLowerCase() ?? '';
      if (!_isMatchForCurrentPlatform(name)) continue;
      if (name.contains('staging') != BuildConfig.isStaging) continue;
      return a;
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
