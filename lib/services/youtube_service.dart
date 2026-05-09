import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/song_model.dart';

/// Represents a YouTube search result before audio extraction
class YouTubeResult {
  final String videoId;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;

  const YouTubeResult({
    required this.videoId,
    required this.title,
    required this.author,
    this.duration,
    required this.thumbnailUrl,
  });

  /// Format duration as mm:ss or h:mm:ss
  String get durationText {
    if (duration == null) return '';
    final hours = duration!.inHours;
    final mins = duration!.inMinutes % 60;
    final secs = duration!.inSeconds % 60;
    if (hours > 0) {
      return '$hours:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}

class YouTubeService {
  static YoutubeExplode? _yt;
  // Prevents concurrent downloads of the same video
  static final Map<String, Future<String>> _activeDownloads = {};
  // Cache trending results to avoid re-fetching and rate limiting
  static List<YouTubeResult>? _trendingCache;
  static DateTime? _trendingCacheTime;
  static const _trendingCacheDuration = Duration(minutes: 5);
  // Rate limit cooldown — don't make requests while rate limited
  static DateTime? _rateLimitedUntil;

  static YoutubeExplode get _client {
    _yt ??= YoutubeExplode();
    return _yt!;
  }

  /// Create a fresh client WITHOUT closing the old one.
  /// Closing the old one kills pending requests → HttpClientClosedException.
  static void _freshClient() {
    _yt = YoutubeExplode(); // Old client is GC'd naturally
  }

  /// Check if we're currently rate limited
  static bool get _isRateLimited {
    if (_rateLimitedUntil == null) return false;
    if (DateTime.now().isAfter(_rateLimitedUntil!)) {
      _rateLimitedUntil = null;
      return false;
    }
    return true;
  }

  /// Mark rate limited for a duration
  static void _markRateLimited({int seconds = 30}) {
    _rateLimitedUntil = DateTime.now().add(Duration(seconds: seconds));
    debugPrint('[YouTubeService] ⚠ Rate limited. Cooldown for ${seconds}s');
  }

  /// Search YouTube for videos matching the query.
  static Future<List<YouTubeResult>> search(
    String query, {
    int maxResults = 20,
  }) async {
    // Don't search for very short queries — reduces unnecessary API calls
    if (query.trim().length < 3) {
      return [];
    }

    // Respect rate limit cooldown
    if (_isRateLimited) {
      debugPrint('[YouTubeService] Skipping search — rate limited');
      throw Exception(
        'YouTube is temporarily rate limited. Please wait a moment and try again.',
      );
    }

    try {
      debugPrint('[YouTubeService] Searching: "$query"');
      final searchResults = await _client.search.search(query);

      final results = <YouTubeResult>[];
      for (final video in searchResults) {
        if (results.length >= maxResults) break;
        results.add(
          YouTubeResult(
            videoId: video.id.value,
            title: video.title,
            author: video.author,
            duration: video.duration,
            thumbnailUrl: video.thumbnails.highResUrl,
          ),
        );
      }
      debugPrint('[YouTubeService] Found ${results.length} results');
      return results;
    } catch (e) {
      debugPrint('[YouTubeService] Search error: $e');
      if (e.toString().contains('RequestLimitExceeded')) {
        _markRateLimited();
        _freshClient();
      }
      rethrow;
    }
  }

  /// Fetch trending / popular music videos. Results are cached for 5 minutes.
  static Future<List<YouTubeResult>> fetchTrending({
    bool forceRefresh = false,
  }) async {
    // Return cache if still valid
    if (!forceRefresh &&
        _trendingCache != null &&
        _trendingCacheTime != null &&
        DateTime.now().difference(_trendingCacheTime!) <
            _trendingCacheDuration) {
      debugPrint(
        '[YouTubeService] Using cached trending (${_trendingCache!.length} songs)',
      );
      return _trendingCache!;
    }

    try {
      final results = <YouTubeResult>[];
      final seenIds = <String>{};

      // Use ONE query to reduce API calls and avoid rate limiting
      try {
        final searchResults = await _client.search.search(
          'new tamil songs 2025',
        );
        for (final video in searchResults) {
          if (video.duration != null && video.duration!.inMinutes > 15) {
            continue;
          }
          if (!seenIds.contains(video.id.value)) {
            seenIds.add(video.id.value);
            results.add(
              YouTubeResult(
                videoId: video.id.value,
                title: video.title,
                author: video.author,
                duration: video.duration,
                thumbnailUrl: video.thumbnails.highResUrl,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('[YouTubeService] Trending query failed: $e');
        if (e.toString().contains('RequestLimitExceeded')) {
          _markRateLimited();
          _freshClient();
          if (_trendingCache != null) return _trendingCache!;
        }
      }

      debugPrint('[YouTubeService] Loaded ${results.length} trending songs');

      // Cache the results
      if (results.isNotEmpty) {
        _trendingCache = results;
        _trendingCacheTime = DateTime.now();
      }

      return results;
    } catch (e) {
      debugPrint('[YouTubeService] Trending error: $e');
      return _trendingCache ?? [];
    }
  }

  /// Get the cache directory for downloaded YouTube audio.
  static Future<Directory> _getCacheDir() async {
    final appDir = await getApplicationSupportDirectory();
    final cacheDir = Directory(
      '${appDir.path}${Platform.pathSeparator}yt_cache',
    );
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Get the downloads directory for permanently saved songs.
  static Future<Directory> getDownloadsDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dlDir = Directory(
      '${appDir.path}${Platform.pathSeparator}yt_downloads',
    );
    if (!await dlDir.exists()) {
      await dlDir.create(recursive: true);
    }
    return dlDir;
  }

  /// Check if a video is already cached/downloaded. Returns file path or null.
  static Future<String?> getCachedPath(String videoId) async {
    final cacheDir = await _getCacheDir();
    final dlDir = await getDownloadsDir();

    // Check downloads first (with both extensions)
    for (final ext in ['m4a', 'webm']) {
      final dlFile = File(
        '${dlDir.path}${Platform.pathSeparator}$videoId.$ext',
      );
      if (await dlFile.exists() && await dlFile.length() > 1000) {
        return dlFile.path;
      }
    }

    // Then check cache
    for (final ext in ['m4a', 'webm']) {
      final cacheFile = File(
        '${cacheDir.path}${Platform.pathSeparator}$videoId.$ext',
      );
      if (await cacheFile.exists() && await cacheFile.length() > 1000) {
        return cacheFile.path;
      }
    }

    return null;
  }

  /// Select the best audio stream for playback.
  /// Prefers AAC/MP4 (mp4a.40.2) for maximum compatibility with MPV on Windows.
  /// Falls back to Opus/WebM if no AAC is available.
  static AudioOnlyStreamInfo _selectBestStream(
    List<AudioOnlyStreamInfo> streams,
  ) {
    // Separate into AAC (MP4) and Opus (WebM) streams
    final aacStreams = streams
        .where(
          (s) => s.container.name == 'mp4' || s.audioCodec.startsWith('mp4a'),
        )
        .toList();
    final opusStreams = streams
        .where((s) => s.container.name == 'webm' || s.audioCodec == 'opus')
        .toList();

    debugPrint(
      '[YouTubeService] AAC streams: ${aacStreams.length}, Opus streams: ${opusStreams.length}',
    );

    // Prefer AAC for best Windows/MPV compatibility
    if (aacStreams.isNotEmpty) {
      aacStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
      final best = aacStreams.first;
      debugPrint(
        '[YouTubeService] ✓ Selected AAC: ${best.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps, '
        'codec: ${best.audioCodec}, container: ${best.container.name}',
      );
      return best;
    }

    // Fallback to Opus
    if (opusStreams.isNotEmpty) {
      opusStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
      final best = opusStreams.first;
      debugPrint(
        '[YouTubeService] ✓ Selected Opus: ${best.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps, '
        'codec: ${best.audioCodec}, container: ${best.container.name}',
      );
      return best;
    }

    // Last resort: just pick highest bitrate regardless
    streams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
    return streams.first;
  }

  /// Get the direct audio stream URL for a video — for INSTANT streaming playback.
  /// The player (just_audio + media_kit) handles buffering/streaming natively.
  /// Includes retry with backoff for rate limiting.
  static Future<String> getStreamUrl(String videoId) async {
    if (_isRateLimited) {
      throw Exception(
        'YouTube is temporarily rate limited. Please wait a moment and try again.',
      );
    }

    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        if (attempt > 0) {
          final delay = Duration(seconds: 10 * attempt);
          debugPrint(
            '[YouTubeService] Retry $attempt after ${delay.inSeconds}s...',
          );
          await Future.delayed(delay);
          _freshClient();
        }

        debugPrint('[YouTubeService] Getting stream URL for $videoId...');
        final manifest = await _client.videos.streams.getManifest(videoId);
        final audioStreams = manifest.audioOnly.toList();

        if (audioStreams.isEmpty) {
          throw Exception('No audio streams found for video $videoId');
        }

        final bestAudio = _selectBestStream(audioStreams);
        final url = bestAudio.url.toString();
        debugPrint(
          '[YouTubeService] ✓ Stream URL ready '
          '(${bestAudio.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps)',
        );

        final isWebm = bestAudio.container.name == 'webm';
        final proxyUrl = await YouTubeProxyServer.startProxy(
          url,
          contentType: isWebm ? 'audio/webm' : 'audio/mp4',
          extension: isWebm ? 'webm' : 'm4a',
        );
        return proxyUrl;
      } catch (e) {
        if (e.toString().contains('RequestLimitExceeded') && attempt < 2) {
          debugPrint('[YouTubeService] Rate limited, will retry...');
          _markRateLimited(seconds: 15);
          continue;
        }
        if (e.toString().contains('RequestLimitExceeded')) {
          _markRateLimited();
          _freshClient();
        }
        rethrow;
      }
    }
    throw Exception('Failed to get stream URL after retries');
  }

  /// Extract audio for INSTANT playback — returns SongModel with stream URL.
  /// If already cached locally, uses the cached file instead.
  /// This does NOT download the file — the player streams it directly.
  static Future<SongModel> extractAudio(YouTubeResult result) async {
    try {
      // Check if already cached locally
      final existing = await getCachedPath(result.videoId);
      if (existing != null) {
        debugPrint('[YouTubeService] Using cached file: $existing');
        return SongModel.fromYouTube(
          videoId: result.videoId,
          title: result.title,
          artist: result.author,
          streamUrl: existing,
          thumbnailUrl: result.thumbnailUrl,
          duration: result.duration,
        );
      }

      // Get the stream URL for instant playback (no download needed!)
      final streamUrl = await getStreamUrl(result.videoId);

      return SongModel.fromYouTube(
        videoId: result.videoId,
        title: result.title,
        artist: result.author,
        streamUrl: streamUrl,
        thumbnailUrl: result.thumbnailUrl,
        duration: result.duration,
      );
    } catch (e) {
      debugPrint('[YouTubeService] extractAudio error: $e');
      rethrow;
    }
  }

  /// Download audio to a file using HTTP (not youtube_explode streams).
  /// This is more reliable on Windows than the stream-based approach.
  static Future<String> _downloadAudio({
    required String videoId,
    required String targetDir,
  }) async {
    debugPrint(
      '[YouTubeService] Getting stream manifest for download: $videoId',
    );

    final manifest = await _client.videos.streams.getManifest(videoId);
    final audioStreams = manifest.audioOnly.toList();

    if (audioStreams.isEmpty) {
      throw Exception('No audio streams found for video $videoId');
    }

    final bestAudio = _selectBestStream(audioStreams);
    final ext = bestAudio.container.name == 'webm' ? 'webm' : 'm4a';
    final targetPath = '$targetDir${Platform.pathSeparator}$videoId.$ext';

    // Check if already fully downloaded
    final existingTarget = File(targetPath);
    if (await existingTarget.exists() && await existingTarget.length() > 1000) {
      debugPrint('[YouTubeService] Already downloaded: $targetPath');
      return targetPath;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempPath = '$targetPath.$timestamp.tmp';
    final totalBytes = bestAudio.size.totalBytes;
    final downloadUrl = bestAudio.url.toString();

    debugPrint(
      '[YouTubeService] Downloading ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB via HTTP → $targetPath',
    );

    try {
      // Use HTTP client for reliable downloading on Windows
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final file = File(tempPath);
      final sink = file.openWrite();
      int downloadedBytes = 0;
      int lastLogPercent = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        // Log progress every 10%
        if (totalBytes > 0) {
          final percent = (downloadedBytes * 100 ~/ totalBytes);
          if (percent >= lastLogPercent + 10) {
            lastLogPercent = percent;
            debugPrint(
              '[YouTubeService] Download progress: $percent% '
              '(${(downloadedBytes / 1024 / 1024).toStringAsFixed(1)} MB)',
            );
          }
        }
      }

      await sink.flush();
      await sink.close();

      // Verify file size
      final fileSize = await File(tempPath).length();
      debugPrint(
        '[YouTubeService] Downloaded: ${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB',
      );

      if (fileSize < 1000) {
        throw Exception('Downloaded file too small: $fileSize bytes');
      }

      // Rename temp → final
      try {
        if (await existingTarget.exists()) {
          await existingTarget.delete();
        }
      } catch (_) {}
      await File(tempPath).rename(targetPath);

      debugPrint('[YouTubeService] ✅ Download complete: $targetPath');
      return targetPath;
    } catch (e) {
      debugPrint('[YouTubeService] ❌ Download failed: $e');
      try {
        final tf = File(tempPath);
        if (await tf.exists()) await tf.delete();
      } catch (_) {}
      rethrow;
    }
  }

  /// Download a song permanently (not just cache). With deduplication.
  static Future<String> downloadPermanently(YouTubeResult result) async {
    // Check if already downloaded
    final existing = await getCachedPath(result.videoId);
    if (existing != null && existing.contains('yt_downloads')) {
      debugPrint('[YouTubeService] Already downloaded: $existing');
      return existing;
    }

    final dlDir = await getDownloadsDir();
    final downloadKey = result.videoId;

    // If a download is already in progress for this video, wait for it
    if (_activeDownloads.containsKey(downloadKey)) {
      debugPrint(
        '[YouTubeService] Waiting for in-progress download: $downloadKey',
      );
      return _activeDownloads[downloadKey]!;
    }

    final downloadFuture = _downloadAudio(
      videoId: result.videoId,
      targetDir: dlDir.path,
    );
    _activeDownloads[downloadKey] = downloadFuture;

    try {
      return await downloadFuture;
    } finally {
      _activeDownloads.remove(downloadKey);
    }
  }

  /// Extract audio from a YouTube URL directly (paste URL → play)
  static Future<SongModel> extractFromUrl(String url) async {
    try {
      final videoId = VideoId.parseVideoId(url);
      if (videoId == null) {
        throw Exception('Invalid YouTube URL');
      }

      final video = await _client.videos.get(videoId);
      final result = YouTubeResult(
        videoId: video.id.value,
        title: video.title,
        author: video.author,
        duration: video.duration,
        thumbnailUrl: video.thumbnails.highResUrl,
      );

      return extractAudio(result);
    } catch (e) {
      debugPrint('[YouTubeService] URL extraction error: $e');
      rethrow;
    }
  }

  /// Clean up all cached audio files (keeps permanent downloads)
  static Future<void> clearCache() async {
    try {
      final cacheDir = await _getCacheDir();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        debugPrint('[YouTubeService] Cache cleared');
      }
    } catch (e) {
      debugPrint('[YouTubeService] Error clearing cache: $e');
    }
  }

  /// Clean up resources
  static void dispose() {
    _yt?.close();
    _yt = null;
  }
}

class YouTubeProxyServer {
  static HttpServer? _server;
  static final Map<String, _ProxyTarget> _streams = {};
  static int _streamCounter = 0;

  static Future<String> startProxy(
    String sourceUrl, {
    String contentType = 'audio/mp4',
    String extension = 'm4a',
  }) async {
    if (_server == null) {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: true,
      );

      debugPrint('[YouTubeProxy] Started on port ${_server!.port}');

      _server!.listen((HttpRequest request) async {
        HttpClient? client;
        try {
          final pathSegment = request.uri.pathSegments.isEmpty
              ? ''
              : request.uri.pathSegments.first;
          final streamId = pathSegment.split('.').first;
          final target = _streams[streamId];

          if (target == null) {
            request.response.statusCode = 404;
            await request.response.close();
            return;
          }

          client = HttpClient();
          client.userAgent =
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36';

          final ytRequest = await client.getUrl(Uri.parse(target.sourceUrl));
          ytRequest.followRedirects = true;

          // Crucial: Forward the Range header from MPV to YouTube so it can seek the moov atom!
          final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
          if (rangeHeader != null) {
            ytRequest.headers.set(HttpHeaders.rangeHeader, rangeHeader);
          } else {
            ytRequest.headers.set(HttpHeaders.acceptHeader, '*/*');
          }

          final ytResponse = await ytRequest.close();

          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            target.contentType,
          );
          request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
          request.response.headers.set(
            HttpHeaders.connectionHeader,
            'keep-alive',
          );
          request.response.headers.set(
            HttpHeaders.cacheControlHeader,
            'no-cache',
          );

          // Pass through the exact status code (200 OK or 206 Partial Content)
          request.response.statusCode = ytResponse.statusCode;

          // Forward crucial length and range response headers back to MPV
          final contentLength = ytResponse.headers.value(
            HttpHeaders.contentLengthHeader,
          );
          if (contentLength != null) {
            request.response.headers.set(
              HttpHeaders.contentLengthHeader,
              contentLength,
            );
          }
          final contentRange = ytResponse.headers.value(
            HttpHeaders.contentRangeHeader,
          );
          if (contentRange != null) {
            request.response.headers.set(
              HttpHeaders.contentRangeHeader,
              contentRange,
            );
          }

          await ytResponse.pipe(request.response);
        } catch (e) {
          debugPrint('[YouTubeProxy] ERROR: $e');
          try {
            request.response.statusCode = 500;
            await request.response.close();
          } catch (_) {}
        } finally {
          client?.close(force: true);
        }
      });
    }

    final streamId =
        '${DateTime.now().millisecondsSinceEpoch}-${_streamCounter++}';
    _streams[streamId] = _ProxyTarget(
      sourceUrl: sourceUrl,
      contentType: contentType,
    );
    _trimOldStreams();

    return 'http://127.0.0.1:${_server!.port}/$streamId.$extension';
  }

  static void _trimOldStreams() {
    while (_streams.length > 8) {
      _streams.remove(_streams.keys.first);
    }
  }
}

class _ProxyTarget {
  final String sourceUrl;
  final String contentType;

  const _ProxyTarget({required this.sourceUrl, required this.contentType});
}
