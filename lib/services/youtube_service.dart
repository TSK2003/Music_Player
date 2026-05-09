import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
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
  final bool isPodcast;

  const YouTubeResult({
    required this.videoId,
    required this.title,
    required this.author,
    this.duration,
    required this.thumbnailUrl,
    this.isPodcast = false,
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

typedef PlaybackCancelCheck = bool Function();

class YouTubeService {
  static const _manifestTimeout = Duration(seconds: 20);
  static const _downloadStallTimeout = Duration(seconds: 90);
  static const _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36';
  static const _androidUserAgent =
      'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip';
  static const _androidMusicUserAgent =
      'com.google.android.youtube/19.29.1 (Linux; U; Android 11) gzip';
  static const _iosUserAgent =
      'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)';
  static const _safariUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15';
  static final List<_DownloadClientAttempt> _downloadClientFallbacks = [
    _DownloadClientAttempt('androidVr', [YoutubeApiClient.androidVr]),
    _DownloadClientAttempt('android', [YoutubeApiClient.android]),
    _DownloadClientAttempt('safari', [YoutubeApiClient.safari]),
    _DownloadClientAttempt('ios', [YoutubeApiClient.ios]),
    _DownloadClientAttempt('tv', [YoutubeApiClient.tv]),
  ];
  static final List<_DownloadClientAttempt> _playbackClientAttempts = [
    _DownloadClientAttempt('ios', [YoutubeApiClient.ios]),
    _DownloadClientAttempt('android', [YoutubeApiClient.android]),
    _DownloadClientAttempt('androidMusic', [YoutubeApiClient.androidMusic]),
    _DownloadClientAttempt('androidVr', [YoutubeApiClient.androidVr]),
    _DownloadClientAttempt('safari', [YoutubeApiClient.safari]),
    _DownloadClientAttempt('tv', [YoutubeApiClient.tv]),
  ];

  static YoutubeExplode? _yt;
  // Prevents concurrent downloads of the same video into the same directory.
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

  static bool _isRateLimitError(Object error) {
    final message = error.toString();
    return message.contains('RequestLimitExceeded') ||
        message.contains('rate limiting') ||
        message.contains('Too many requests');
  }

  static bool isPlaybackCancelled(Object error) =>
      error is YouTubePlaybackCancelledException;

  static void _throwIfCancelled(PlaybackCancelCheck? shouldCancel) {
    if (shouldCancel?.call() ?? false) {
      throw const YouTubePlaybackCancelledException();
    }
  }

  static String get _rateLimitMessage =>
      'YouTube temporarily blocked requests from this network. '
      'Please wait a few minutes and try again.';

  /// Mark rate limited for a duration
  static void _markRateLimited({int seconds = 120}) {
    _rateLimitedUntil = DateTime.now().add(Duration(seconds: seconds));
    debugPrint('[YouTubeService] ⚠ Rate limited. Cooldown for ${seconds}s');
  }

  /// Search YouTube for videos matching the query.
  static Future<List<YouTubeResult>> search(
    String query, {
    int maxResults = 60,
    bool includePodcasts = true,
  }) async {
    // Don't search for very short queries — reduces unnecessary API calls
    if (query.trim().length < 3) {
      return [];
    }

    // Respect rate limit cooldown
    if (_isRateLimited) {
      debugPrint('[YouTubeService] Skipping search — rate limited');
      throw Exception(_rateLimitMessage);
    }

    try {
      debugPrint('[YouTubeService] Searching: "$query"');
      final results = <YouTubeResult>[];

      final normalTarget = includePodcasts
          ? (maxResults * 3 / 4).round()
          : maxResults;
      await _collectSearchVideos(
        query: query,
        results: results,
        maxResults: normalTarget,
      );

      if (includePodcasts && results.length < maxResults) {
        await _collectSearchVideos(
          query: '$query podcast',
          results: results,
          maxResults: maxResults,
          isPodcast: true,
        );
      }

      debugPrint('[YouTubeService] Found ${results.length} results');
      return results;
    } catch (e) {
      debugPrint('[YouTubeService] Search error: $e');
      if (_isRateLimitError(e)) {
        _markRateLimited();
        _freshClient();
      }
      rethrow;
    }
  }

  static Future<void> _collectSearchVideos({
    required String query,
    required List<YouTubeResult> results,
    required int maxResults,
    bool isPodcast = false,
  }) async {
    final seenIds = results.map((r) => r.videoId).toSet();
    var page = await _client.search.search(query);
    var pageCount = 0;

    while (pageCount < 4 && results.length < maxResults) {
      pageCount++;
      for (final video in page) {
        if (results.length >= maxResults) break;
        if (seenIds.contains(video.id.value)) continue;

        seenIds.add(video.id.value);
        results.add(
          YouTubeResult(
            videoId: video.id.value,
            title: video.title,
            author: video.author,
            duration: video.duration,
            thumbnailUrl: video.thumbnails.highResUrl,
            isPodcast: isPodcast,
          ),
        );
      }

      if (results.length >= maxResults) break;
      final next = await page.nextPage();
      if (next == null) break;
      page = next;
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
        if (_isRateLimitError(e)) {
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
  static Future<String> getStreamUrl(String videoId) async {
    final resolved = await _resolvePlayableStream(videoId);
    if (!Platform.isWindows) return resolved.url;

    return YouTubeProxyServer.startProxy(
      resolved.url,
      contentType: resolved.contentType,
      extension: resolved.extension,
      headers: resolved.headers,
      totalBytes: resolved.totalBytes,
    );
  }

  /// Resolve a playable audio-only stream without downloading the track.
  static Future<_ResolvedYouTubeStream> _resolvePlayableStream(
    String videoId,
  ) async {
    if (_isRateLimited) {
      throw Exception(_rateLimitMessage);
    }

    Object? lastError;

    for (final attempt in _playbackClientAttempts) {
      try {
        debugPrint(
          '[YouTubeService] Getting stream manifest for playback: '
          '$videoId (${attempt.label})',
        );
        final manifest = await _client.videos.streams
            .getManifest(videoId, ytClients: attempt.clients)
            .timeout(_manifestTimeout);
        final audioStreams = manifest.audioOnly.toList();

        if (audioStreams.isEmpty) {
          throw Exception('No audio streams found for video $videoId');
        }

        final bestAudio = _selectBestStream(audioStreams);
        debugPrint(
          '[YouTubeService] Stream URL ready via ${attempt.label} '
          '(${bestAudio.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps)',
        );

        return _ResolvedYouTubeStream(
          url: bestAudio.url.toString(),
          contentType: _contentTypeFor(bestAudio),
          extension: bestAudio.container.name == 'webm' ? 'webm' : 'm4a',
          headers: _headersForStreamUri(bestAudio.url),
          totalBytes: bestAudio.size.totalBytes,
        );
      } catch (e) {
        lastError = e;
        debugPrint(
          '[YouTubeService] Playback manifest failed via '
          '${attempt.label}: $e',
        );
        if (_isRateLimitError(e)) {
          _markRateLimited();
          _freshClient();
          throw Exception(_rateLimitMessage);
        }
        _freshClient();
      }
    }

    final detail = lastError == null
        ? ''
        : ' Last error: ${lastError.toString().split('\n').first}';
    throw Exception('Unable to resolve this YouTube audio stream.$detail');
  }

  static String _contentTypeFor(AudioOnlyStreamInfo stream) {
    if (stream.container.name == 'webm') return 'audio/webm';
    if (stream.container.name == 'mp4') return 'audio/mp4';
    return 'application/octet-stream';
  }

  static Map<String, String> _headersForStreamUri(Uri uri) {
    final client = uri.queryParameters['c']?.toUpperCase();
    final userAgent = switch (client) {
      'ANDROID' => _androidUserAgent,
      'ANDROID_MUSIC' => _androidMusicUserAgent,
      'IOS' => _iosUserAgent,
      'WEB' => _safariUserAgent,
      _ => _desktopUserAgent,
    };

    return {
      HttpHeaders.userAgentHeader: userAgent,
      HttpHeaders.acceptHeader: '*/*',
      HttpHeaders.refererHeader: 'https://www.youtube.com/',
      'Origin': 'https://www.youtube.com',
    };
  }

  /// Extract audio for playback by caching the YouTube stream first.
  /// Windows/media_kit is unreliable with direct googlevideo URLs, so the
  /// player only receives a local file path.
  static Future<SongModel> extractAudio(
    YouTubeResult result, {
    PlaybackCancelCheck? shouldCancel,
  }) async {
    try {
      _throwIfCancelled(shouldCancel);
      final existing = await getCachedPath(result.videoId);
      if (existing != null) {
        _throwIfCancelled(shouldCancel);
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

      debugPrint(
        '[YouTubeService] Caching YouTube audio for playback: ${result.videoId}',
      );
      final cachedPath = await _downloadAudioDeduped(
        videoId: result.videoId,
        targetDir: (await _getCacheDir()).path,
        shouldCancel: shouldCancel,
      );
      _throwIfCancelled(shouldCancel);

      return SongModel.fromYouTube(
        videoId: result.videoId,
        title: result.title,
        artist: result.author,
        streamUrl: cachedPath,
        thumbnailUrl: result.thumbnailUrl,
        duration: result.duration,
      );
    } catch (e) {
      if (!isPlaybackCancelled(e)) {
        debugPrint('[YouTubeService] extractAudio error: $e');
      }
      rethrow;
    }
  }

  /// Cache a YouTube song locally and return a SongModel that points at the
  /// playable local file. Used as a Windows fallback when MPV rejects a signed
  /// googlevideo URL.
  static Future<SongModel> cacheForPlayback(SongModel song) async {
    if (!song.isYouTube) return song;

    final videoId = song.id.replaceFirst('yt_', '');
    final cachedPath =
        await getCachedPath(videoId) ??
        await _downloadAudioDeduped(
          videoId: videoId,
          targetDir: (await _getCacheDir()).path,
        );

    return SongModel.fromYouTube(
      videoId: videoId,
      title: song.title,
      artist: song.artist,
      streamUrl: cachedPath,
      thumbnailUrl: song.thumbnailUrl ?? '',
      duration: song.duration,
    );
  }

  static Future<String> _downloadAudioDeduped({
    required String videoId,
    required String targetDir,
    PlaybackCancelCheck? shouldCancel,
  }) async {
    final downloadKey = '$targetDir${Platform.pathSeparator}$videoId';
    final activeDownload = _activeDownloads[downloadKey];
    if (activeDownload != null) {
      debugPrint('[YouTubeService] Waiting for in-progress download: $videoId');
      final path = await activeDownload;
      _throwIfCancelled(shouldCancel);
      return path;
    }

    final downloadFuture = _downloadAudio(
      videoId: videoId,
      targetDir: targetDir,
      shouldCancel: shouldCancel,
    );
    _activeDownloads[downloadKey] = downloadFuture;

    try {
      return await downloadFuture;
    } finally {
      if (identical(_activeDownloads[downloadKey], downloadFuture)) {
        _activeDownloads.remove(downloadKey);
      }
    }
  }

  static Future<void> _deleteStaleTempFiles(
    String targetDir,
    String videoId,
  ) async {
    final dir = Directory(targetDir);
    if (!await dir.exists()) return;

    try {
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('$videoId.') && name.endsWith('.tmp')) {
          await entity.delete();
        }
      }
    } catch (e) {
      debugPrint('[YouTubeService] Temp cleanup skipped: $e');
    }
  }

  /// Download audio to a local file using youtube_explode's stream client.
  /// This handles YouTube range requests and manifest refreshes for us.
  static Future<String> _downloadAudio({
    required String videoId,
    required String targetDir,
    List<YoutubeApiClient>? ytClients,
    String clientLabel = 'default',
    int fallbackIndex = 0,
    PlaybackCancelCheck? shouldCancel,
  }) async {
    _throwIfCancelled(shouldCancel);
    if (_isRateLimited) {
      throw Exception(_rateLimitMessage);
    }

    final useFirstDownloadAttempt =
        ytClients == null && clientLabel == 'default' && fallbackIndex == 0;
    final effectiveAttempt = useFirstDownloadAttempt
        ? _downloadClientFallbacks.first
        : _DownloadClientAttempt(clientLabel, ytClients);
    final effectiveFallbackIndex = useFirstDownloadAttempt ? 1 : fallbackIndex;

    debugPrint(
      '[YouTubeService] Getting stream manifest for download: $videoId (${effectiveAttempt.label})',
    );

    late final StreamManifest manifest;
    try {
      manifest = await _client.videos.streams
          .getManifest(videoId, ytClients: effectiveAttempt.clients)
          .timeout(_manifestTimeout);
    } catch (e) {
      if (isPlaybackCancelled(e)) rethrow;
      if (_isRateLimitError(e)) {
        _markRateLimited();
        _freshClient();
        throw Exception(_rateLimitMessage);
      }
      if (effectiveFallbackIndex < _downloadClientFallbacks.length) {
        final fallback = _downloadClientFallbacks[effectiveFallbackIndex];
        debugPrint(
          '[YouTubeService] Manifest failed via ${effectiveAttempt.label}. '
          'Retrying with ${fallback.label}: $e',
        );
        _freshClient();
        return _downloadAudio(
          videoId: videoId,
          targetDir: targetDir,
          ytClients: fallback.clients,
          clientLabel: fallback.label,
          fallbackIndex: effectiveFallbackIndex + 1,
          shouldCancel: shouldCancel,
        );
      }
      rethrow;
    }
    _throwIfCancelled(shouldCancel);
    final audioStreams = manifest.audioOnly.toList();

    if (audioStreams.isEmpty) {
      throw Exception('No audio streams found for video $videoId');
    }

    final bestAudio = _selectBestStream(audioStreams);
    final ext = bestAudio.container.name == 'webm' ? 'webm' : 'm4a';
    final targetPath = '$targetDir${Platform.pathSeparator}$videoId.$ext';
    final totalBytes = bestAudio.size.totalBytes;

    // Check if already fully downloaded
    final existingTarget = File(targetPath);
    if (await existingTarget.exists()) {
      final existingLength = await existingTarget.length();
      final isComplete = totalBytes > 0
          ? existingLength >= (totalBytes * 0.98).floor()
          : existingLength > 1000;

      if (isComplete) {
        _throwIfCancelled(shouldCancel);
        debugPrint('[YouTubeService] Already downloaded: $targetPath');
        return targetPath;
      }

      debugPrint(
        '[YouTubeService] Removing incomplete download: $targetPath '
        '($existingLength/$totalBytes bytes)',
      );
      try {
        await existingTarget.delete();
      } catch (_) {}
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    await _deleteStaleTempFiles(targetDir, videoId);
    final tempPath = '$targetPath.${effectiveAttempt.label}.$timestamp.tmp';
    debugPrint(
      '[YouTubeService] Downloading ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB via ${effectiveAttempt.label} -> $targetPath',
    );

    try {
      // Let youtube_explode handle YouTube-specific range requests and manifest refreshes.
      final file = File(tempPath);
      final sink = file.openWrite();
      int downloadedBytes = 0;
      int lastLogPercent = 0;

      try {
        final stream = _client.videos.streams
            .get(bestAudio)
            .timeout(_downloadStallTimeout);

        await for (final chunk in stream) {
          _throwIfCancelled(shouldCancel);
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
      } finally {
        await sink.close();
      }

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
      if (isPlaybackCancelled(e)) {
        debugPrint('[YouTubeService] Download cancelled: $videoId');
        rethrow;
      }
      if (_isRateLimitError(e)) {
        _markRateLimited();
        _freshClient();
        throw Exception(_rateLimitMessage);
      }
      if (effectiveFallbackIndex < _downloadClientFallbacks.length) {
        final fallback = _downloadClientFallbacks[effectiveFallbackIndex];
        debugPrint(
          '[YouTubeService] Retrying download with ${fallback.label} client...',
        );
        _freshClient();
        return _downloadAudio(
          videoId: videoId,
          targetDir: targetDir,
          ytClients: fallback.clients,
          clientLabel: fallback.label,
          fallbackIndex: effectiveFallbackIndex + 1,
          shouldCancel: shouldCancel,
        );
      }
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
    return _downloadAudioDeduped(
      videoId: result.videoId,
      targetDir: dlDir.path,
    );
  }

  /// Extract audio from a YouTube URL directly (paste URL → play)
  static Future<SongModel> extractFromUrl(String url) async {
    try {
      final videoId = VideoId.parseVideoId(url);
      if (videoId == null) {
        throw Exception('Invalid YouTube URL');
      }
      if (_isRateLimited) {
        throw Exception(_rateLimitMessage);
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
    Map<String, String> headers = const {},
    int? totalBytes,
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

          final method = request.method.toUpperCase();
          final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
          final requestedRange = _ByteRange.parse(
            rangeHeader,
            target.totalBytes,
          );
          var targetUri = Uri.parse(target.sourceUrl);
          final shouldForceRange =
              targetUri.host.toLowerCase().endsWith('googlevideo.com') &&
              target.totalBytes != null;
          final upstreamRange =
              requestedRange ??
              (shouldForceRange ? _ByteRange(0, target.totalBytes! - 1) : null);
          final useRangeQuery =
              upstreamRange != null && _shouldUseRangeQuery(targetUri);

          debugPrint(
            '[YouTubeProxy] $method ${request.uri.path} '
            '${rangeHeader ?? ''}',
          );

          if (method == 'HEAD') {
            _writeProxyHeaders(
              request.response,
              target,
              statusCode: HttpStatus.ok,
              contentLength: target.totalBytes,
            );
            await request.response.close();
            return;
          }

          if (useRangeQuery) {
            targetUri = targetUri.replace(
              queryParameters: {
                ...targetUri.queryParameters,
                'range': upstreamRange.queryValue,
              },
            );
          }

          client = HttpClient();
          client.userAgent =
              target.headers[HttpHeaders.userAgentHeader] ??
              YouTubeService._desktopUserAgent;

          final ytRequest = await client.getUrl(targetUri);
          ytRequest.followRedirects = true;
          target.headers.forEach(ytRequest.headers.set);

          // Forward Range so MPV can seek the MP4/WebM metadata cleanly.
          if (upstreamRange != null && !useRangeQuery) {
            ytRequest.headers.set(
              HttpHeaders.rangeHeader,
              upstreamRange.headerValue,
            );
          } else if (rangeHeader != null && !useRangeQuery) {
            ytRequest.headers.set(HttpHeaders.rangeHeader, rangeHeader);
          }

          final ytResponse = await ytRequest.close();

          // Pass through the exact status code (200 OK or 206 Partial Content)
          final statusCode = _proxyStatusCode(
            requestedRange: requestedRange,
            upstreamRange: upstreamRange,
            upstreamStatusCode: ytResponse.statusCode,
          );

          // Forward crucial length and range response headers back to MPV
          final contentLength = ytResponse.headers.value(
            HttpHeaders.contentLengthHeader,
          );
          final contentRange = ytResponse.headers.value(
            HttpHeaders.contentRangeHeader,
          );
          final parsedLength = int.tryParse(contentLength ?? '');
          final responseContentRange = statusCode == HttpStatus.partialContent
              ? contentRange ??
                    (upstreamRange != null && target.totalBytes != null
                        ? upstreamRange.contentRangeHeader(
                            target.totalBytes!,
                            parsedLength,
                          )
                        : null)
              : null;

          _writeProxyHeaders(
            request.response,
            target,
            statusCode: statusCode,
            contentLength: statusCode >= HttpStatus.badRequest
                ? parsedLength
                : parsedLength ?? target.totalBytes,
            contentRange: responseContentRange,
          );

          if (ytResponse.statusCode >= HttpStatus.badRequest) {
            debugPrint(
              '[YouTubeProxy] Upstream HTTP ${ytResponse.statusCode} '
              'for ${targetUri.host}',
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
      headers: headers,
      totalBytes: totalBytes,
    );
    _trimOldStreams();

    return 'http://127.0.0.1:${_server!.port}/$streamId.$extension';
  }

  static int _proxyStatusCode({
    required _ByteRange? requestedRange,
    required _ByteRange? upstreamRange,
    required int upstreamStatusCode,
  }) {
    if (upstreamStatusCode >= HttpStatus.badRequest) {
      return upstreamStatusCode;
    }
    if (requestedRange != null) {
      return HttpStatus.partialContent;
    }
    if (upstreamRange != null &&
        upstreamStatusCode == HttpStatus.partialContent) {
      return HttpStatus.ok;
    }
    return upstreamStatusCode;
  }

  static void _writeProxyHeaders(
    HttpResponse response,
    _ProxyTarget target, {
    required int statusCode,
    int? contentLength,
    String? contentRange,
  }) {
    response.statusCode = statusCode;
    response.headers.set(HttpHeaders.contentTypeHeader, target.contentType);
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    if (contentLength != null && contentLength >= 0) {
      response.headers.set(HttpHeaders.contentLengthHeader, contentLength);
    }
    if (contentRange != null) {
      response.headers.set(HttpHeaders.contentRangeHeader, contentRange);
    }
  }

  static void _trimOldStreams() {
    while (_streams.length > 32) {
      _streams.remove(_streams.keys.first);
    }
  }

  static bool _shouldUseRangeQuery(Uri uri) {
    if (!uri.host.toLowerCase().endsWith('googlevideo.com')) return false;
    return uri.queryParameters['c']?.toUpperCase() != 'ANDROID';
  }
}

class _ProxyTarget {
  final String sourceUrl;
  final String contentType;
  final Map<String, String> headers;
  final int? totalBytes;

  const _ProxyTarget({
    required this.sourceUrl,
    required this.contentType,
    required this.headers,
    required this.totalBytes,
  });
}

class _ByteRange {
  final int start;
  final int? end;

  const _ByteRange(this.start, this.end);

  String get queryValue => end == null ? '$start-' : '$start-$end';
  String get headerValue => 'bytes=$queryValue';

  String contentRangeHeader(int totalBytes, int? contentLength) {
    final resolvedEnd = end ?? start + (contentLength ?? 1) - 1;
    return 'bytes $start-$resolvedEnd/$totalBytes';
  }

  static _ByteRange? parse(String? header, int? totalBytes) {
    if (header == null) return null;

    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null) return null;

    final startText = match.group(1) ?? '';
    final endText = match.group(2) ?? '';
    if (startText.isEmpty && endText.isEmpty) return null;

    if (startText.isEmpty) {
      final suffixLength = int.tryParse(endText);
      if (suffixLength == null || suffixLength <= 0 || totalBytes == null) {
        return null;
      }
      final start = suffixLength >= totalBytes ? 0 : totalBytes - suffixLength;
      return _ByteRange(start, totalBytes - 1);
    }

    final start = int.tryParse(startText);
    if (start == null || start < 0) return null;

    final end = endText.isEmpty
        ? (totalBytes == null ? null : totalBytes - 1)
        : int.tryParse(endText);
    if (end != null && end < start) return null;

    return _ByteRange(start, end);
  }
}

class _ResolvedYouTubeStream {
  final String url;
  final String contentType;
  final String extension;
  final Map<String, String> headers;
  final int totalBytes;

  const _ResolvedYouTubeStream({
    required this.url,
    required this.contentType,
    required this.extension,
    required this.headers,
    required this.totalBytes,
  });
}

class YouTubePlaybackCancelledException implements Exception {
  const YouTubePlaybackCancelledException();

  @override
  String toString() => 'YouTube playback request cancelled';
}

class _DownloadClientAttempt {
  final String label;
  final List<YoutubeApiClient>? clients;

  const _DownloadClientAttempt(this.label, this.clients);
}
