import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer(
    userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/122.0.0.0 Safari/537.36',
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        prioritizeTimeOverSizeThresholds: true,
      ),
      darwinLoadControl: DarwinLoadControl(),
    ),
  );

  AudioPlayerHandler() {
    // Broadcast playback state changes
    _player.playbackEventStream.listen((event) {
      _broadcastState(event);
    });

    // Handle processing state changes
    _player.processingStateStream.listen((state) {
      debugPrint('[AudioHandler] State: $state');
      if (state == ProcessingState.completed) {
        // Notify listeners that song completed — PlayerService handles next
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.completed,
          ),
        );
      }
    });

    // Broadcast current duration
    _player.durationStream.listen((duration) {
      final currentItem = mediaItem.value;
      if (currentItem != null && duration != null) {
        mediaItem.add(currentItem.copyWith(duration: duration));
      }
    });

    // Listen to errors and log them
    _player.errorStream.listen((error) {
      debugPrint('[AudioHandler] Playback error: $error');
    });
  }

  AudioPlayer get player => _player;

  String _redactedUriForLog(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasQuery) {
      return value.length <= 100 ? value : '${value.substring(0, 100)}...';
    }

    const sensitiveKeys = {'access_token', 'key', 'signature', 'sig', 'token'};
    final query = Map<String, dynamic>.from(uri.queryParameters);
    for (final key in sensitiveKeys) {
      if (query.containsKey(key)) {
        query[key] = 'REDACTED';
      }
    }

    final redacted = uri.replace(queryParameters: query).toString();
    return redacted.length <= 140
        ? redacted
        : '${redacted.substring(0, 140)}...';
  }

  void _broadcastState(PlaybackEvent event) {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (_player.playing) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: _player.playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: 0,
      ),
    );
  }

  /// Load and play a single song (avoids ConcatenatingAudioSource bugs on Windows)
  Future<void> loadSingle(MediaItem item) async {
    mediaItem.add(item);
    queue.add([item]);

    final uri = item.id;
    try {
      await _player.stop();

      if (uri.startsWith('http://') || uri.startsWith('https://')) {
        debugPrint('[AudioHandler] Loading URL: ${_redactedUriForLog(uri)}');
        await _player.setAudioSource(
          AudioSource.uri(Uri.parse(uri)),
          preload: true,
        );
      } else {
        debugPrint('[AudioHandler] Loading file: $uri');
        await _player.setAudioSource(AudioSource.file(uri), preload: true);
      }
    } catch (e) {
      debugPrint('[AudioHandler] Failed to load: $e');
      rethrow;
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    // Handled by PlayerService
  }

  @override
  Future<void> skipToPrevious() async {
    // Handled by PlayerService
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }
}
