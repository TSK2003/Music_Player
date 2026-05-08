import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class AudioPlayerHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  AudioPlayerHandler() {
    // Broadcast playback state changes
    _player.playbackEventStream.listen((event) {
      _broadcastState(event);
    });

    // Handle processing state changes
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        skipToNext();
      }
    });

    // Broadcast current duration
    _player.durationStream.listen((duration) {
      final currentItem = mediaItem.value;
      if (currentItem != null && duration != null) {
        mediaItem.add(currentItem.copyWith(duration: duration));
      }
    });

    // Handle current index changes in playlist
    _player.currentIndexStream.listen((index) {
      if (index != null && queue.value.isNotEmpty && index < queue.value.length) {
        mediaItem.add(queue.value[index]);
      }
    });

    // Listen to errors
    _player.errorStream.listen((error) {
      // ignore for now
    });
  }

  AudioPlayer get player => _player;

  void _broadcastState(PlaybackEvent event) {
    playbackState.add(playbackState.value.copyWith(
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
      queueIndex: event.currentIndex,
    ));
  }

  Future<void> loadPlaylist(List<MediaItem> items, {int initialIndex = 0}) async {
    queue.add(items);
    
    final sources = items.map((item) {
      final uri = item.id;
      // Local files use file path directly, Drive files use HTTP URL
      if (uri.startsWith('http://') || uri.startsWith('https://')) {
        return AudioSource.uri(Uri.parse(uri));
      } else {
        // Local file path — convert to file:// URI
        return AudioSource.file(uri);
      }
    }).toList();

    // ignore: deprecated_member_use
    final playlist = ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: sources,
    );

    await _player.setAudioSource(
      playlist,
      initialIndex: initialIndex,
      initialPosition: Duration.zero,
    );

    if (items.isNotEmpty && initialIndex < items.length) {
      mediaItem.add(items[initialIndex]);
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
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await _player.seek(Duration.zero, index: index);
    mediaItem.add(queue.value[index]);
    play();
  }

  @override
  Future<void> skipToNext() async {
    final currentIndex = _player.currentIndex ?? 0;
    final nextIndex = (currentIndex + 1) % queue.value.length;
    await skipToQueueItem(nextIndex);
  }

  @override
  Future<void> skipToPrevious() async {
    final currentIndex = _player.currentIndex ?? 0;
    // If more than 3 seconds into song, restart current song
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    final prevIndex = (currentIndex - 1 + queue.value.length) % queue.value.length;
    await skipToQueueItem(prevIndex);
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }
}
