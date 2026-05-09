import 'dart:async';
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import '../models/song_model.dart';
import 'audio_handler.dart';
import 'youtube_service.dart';

/// Simplified position data combining position, buffered position, and duration
class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}

class PlayerService extends ChangeNotifier {
  final AudioPlayerHandler audioHandler;

  List<SongModel> _songs = [];
  List<SongModel> _currentPlaylist = [];
  int _currentIndex = -1;
  SongModel? _currentSong;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;
  late final StreamSubscription<Object?> _playbackErrorSubscription;
  bool _handlingPlaybackError = false;

  // Shuffle & Repeat state
  bool _shuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;
  List<int>? _shuffleOrder;

  PlayerService(this.audioHandler) {
    _playbackErrorSubscription = audioHandler.player.errorStream.listen(
      _handlePlaybackError,
    );
  }

  // Getters
  List<SongModel> get songs => _songs;
  SongModel? get currentSong => _currentSong;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialized => _isInitialized;
  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get loopMode => _loopMode;
  bool get hasPrevious => _currentPlaylist.isNotEmpty;
  bool get hasNext => _currentPlaylist.isNotEmpty;

  /// Stream of playing state
  Stream<bool> get playingStream =>
      audioHandler.playbackState.map((state) => state.playing).distinct();

  /// Stream of processing state
  Stream<AudioProcessingState> get processingStateStream => audioHandler
      .playbackState
      .map((state) => state.processingState)
      .distinct();

  /// Combined position stream
  Stream<PositionData> get positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        AudioService.position,
        audioHandler.playbackState
            .map((state) => state.bufferedPosition)
            .distinct(),
        audioHandler.mediaItem.map((item) => item?.duration).distinct(),
        (position, bufferedPosition, duration) =>
            PositionData(position, bufferedPosition, duration ?? Duration.zero),
      );

  /// Current media item stream
  Stream<MediaItem?> get mediaItemStream => audioHandler.mediaItem;

  /// Set the song list
  void setSongs(List<SongModel> songs) {
    _songs = songs;
    _isInitialized = true;
    notifyListeners();
  }

  /// Add songs to the existing list (for local files)
  void addSongs(List<SongModel> newSongs) {
    final existingIds = _songs.map((s) => s.id).toSet();
    final unique = newSongs.where((s) => !existingIds.contains(s.id)).toList();
    _songs.addAll(unique);
    _isInitialized = true;
    notifyListeners();
  }

  MediaItem _mediaItemFor(SongModel song) {
    return MediaItem(
      id: song.streamUrl,
      album: song.isLocal
          ? 'Local Music'
          : (song.isYouTube ? 'YouTube' : 'Music Player'),
      title: song.title,
      artist: song.artist,
      artUri: song.thumbnailUrl != null
          ? Uri.tryParse(song.thumbnailUrl!)
          : null,
      extras: {'songId': song.id, 'isLocal': song.isLocal},
    );
  }

  void _replaceSong(SongModel song) {
    final songIndex = _songs.indexWhere((s) => s.id == song.id);
    if (songIndex == -1) {
      _songs.add(song);
    } else {
      _songs[songIndex] = song;
    }

    final playlistIndex = _currentPlaylist.indexWhere((s) => s.id == song.id);
    if (playlistIndex == -1) {
      _currentPlaylist = [song];
      _currentIndex = 0;
    } else {
      _currentPlaylist[playlistIndex] = song;
      _currentIndex = playlistIndex;
    }
  }

  bool _isRemoteUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  Future<bool> _tryCachedYouTubeFallback(
    SongModel song,
    int loadId,
    Object directError,
  ) async {
    if (!song.isYouTube || !_isRemoteUrl(song.streamUrl)) return false;

    debugPrint(
      '[PlayerService] Direct YouTube stream failed, caching fallback: '
      '$directError',
    );

    try {
      final cachedSong = await YouTubeService.cacheForPlayback(song);
      if (_loadId != loadId) return true;

      _replaceSong(cachedSong);
      _currentSong = cachedSong;
      _error = null;

      await audioHandler.loadSingle(_mediaItemFor(cachedSong));
      if (_loadId != loadId) return true;

      await audioHandler.play();
      return true;
    } catch (fallbackError) {
      debugPrint(
        '[PlayerService] Cached YouTube fallback failed: $fallbackError',
      );
      return false;
    }
  }

  /// Handles playback errors that arrive after setAudioSource has succeeded.
  Future<void> _handlePlaybackError(Object playbackError) async {
    if (_handlingPlaybackError || _isLoading) return;

    final song = _currentSong;
    if (song == null || !song.isYouTube || !_isRemoteUrl(song.streamUrl)) {
      return;
    }

    final currentLoadId = _loadId;
    _handlingPlaybackError = true;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final handled = await _tryCachedYouTubeFallback(
        song,
        currentLoadId,
        playbackError,
      );

      if (!handled && _loadId == currentLoadId) {
        _error = 'Failed to play: ${playbackError.toString()}';
        _currentSong = null;
        _currentIndex = -1;
        debugPrint('[PlayerService] Error: $_error');
      }
    } finally {
      _handlingPlaybackError = false;
      if (_loadId == currentLoadId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  int _loadId = 0;

  /// Play a song - loads single song, keeps playlist reference for next/prev
  Future<void> playSong(SongModel song, {List<SongModel>? playlist}) async {
    final currentLoadId = ++_loadId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (playlist != null) {
        _currentPlaylist = playlist;
      } else if (_currentPlaylist.isEmpty) {
        _currentPlaylist = [song];
      }

      _currentSong = song;
      _currentIndex = _currentPlaylist.indexWhere((s) => s.id == song.id);

      if (_currentIndex == -1) {
        _currentIndex = 0;
      }

      // Build shuffle order if needed
      if (_shuffleEnabled) {
        _buildShuffleOrder();
      }

      final mediaItem = _mediaItemFor(song);

      // If a new song was selected while we were prepping this one, abort.
      if (_loadId != currentLoadId) return;

      await audioHandler.loadSingle(mediaItem);

      if (_loadId != currentLoadId) return;

      await audioHandler.play();
    } catch (e) {
      if (_loadId == currentLoadId) {
        if (await _tryCachedYouTubeFallback(song, currentLoadId, e)) {
          return;
        }

        _error = 'Failed to play: ${e.toString()}';
        _currentSong = null;
        _currentIndex = -1;
        debugPrint('[PlayerService] Error: $_error');
      }
    } finally {
      if (_loadId == currentLoadId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Toggle play/pause
  Future<void> togglePlayPause() async {
    if (audioHandler.player.playing) {
      await audioHandler.pause();
    } else {
      await audioHandler.play();
    }
  }

  /// Pause playing
  Future<void> pause() async {
    await audioHandler.pause();
  }

  /// Seek to position
  Future<void> seekTo(Duration position) async {
    await audioHandler.seek(position);
  }

  /// Skip to next song
  Future<void> next() async {
    if (_currentPlaylist.isEmpty) return;

    int nextIndex;
    if (_shuffleEnabled && _shuffleOrder != null) {
      final shufflePos = _shuffleOrder!.indexOf(_currentIndex);
      final nextShufflePos = (shufflePos + 1) % _shuffleOrder!.length;
      nextIndex = _shuffleOrder![nextShufflePos];
    } else {
      nextIndex = (_currentIndex + 1) % _currentPlaylist.length;
    }

    // If loop is off and we've wrapped around, stop
    if (!_shuffleEnabled && nextIndex == 0 && _loopMode == LoopMode.off) {
      return;
    }

    // If loop one, replay current
    if (_loopMode == LoopMode.one) {
      await seekTo(Duration.zero);
      await audioHandler.play();
      return;
    }

    _currentIndex = nextIndex;
    final nextSong = _currentPlaylist[_currentIndex];
    await playSong(nextSong, playlist: _currentPlaylist);
  }

  /// Skip to previous song
  Future<void> previous() async {
    if (_currentPlaylist.isEmpty) return;

    // If more than 3 seconds in, restart current song
    if (audioHandler.player.position.inSeconds > 3) {
      await seekTo(Duration.zero);
      return;
    }

    int prevIndex;
    if (_shuffleEnabled && _shuffleOrder != null) {
      final shufflePos = _shuffleOrder!.indexOf(_currentIndex);
      final prevShufflePos =
          (shufflePos - 1 + _shuffleOrder!.length) % _shuffleOrder!.length;
      prevIndex = _shuffleOrder![prevShufflePos];
    } else {
      prevIndex =
          (_currentIndex - 1 + _currentPlaylist.length) %
          _currentPlaylist.length;
    }

    _currentIndex = prevIndex;
    final prevSong = _currentPlaylist[_currentIndex];
    await playSong(prevSong, playlist: _currentPlaylist);
  }

  /// Toggle shuffle mode
  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    if (_shuffleEnabled) {
      _buildShuffleOrder();
    } else {
      _shuffleOrder = null;
    }
    notifyListeners();
  }

  /// Build a random shuffle order starting from current index
  void _buildShuffleOrder() {
    final indices = List.generate(_currentPlaylist.length, (i) => i);
    indices.remove(_currentIndex);
    indices.shuffle(Random());
    _shuffleOrder = [_currentIndex, ...indices];
  }

  /// Cycle loop mode: off → all → one → off
  void cycleLoopMode() {
    switch (_loopMode) {
      case LoopMode.off:
        _loopMode = LoopMode.all;
        break;
      case LoopMode.all:
        _loopMode = LoopMode.one;
        break;
      case LoopMode.one:
        _loopMode = LoopMode.off;
        break;
    }
    notifyListeners();
  }

  /// Listen for song completion to auto-advance
  void startListening() {
    audioHandler.playbackState.listen((state) {
      if (state.processingState == AudioProcessingState.completed) {
        next();
      }
    });
  }

  @override
  void dispose() {
    _playbackErrorSubscription.cancel();
    audioHandler.stop();
    super.dispose();
  }
}

/// Loop modes
enum LoopMode { off, all, one }
