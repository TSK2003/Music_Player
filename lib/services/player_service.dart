import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import '../models/song_model.dart';
import 'audio_handler.dart';

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

  // Shuffle & Repeat state
  bool _shuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;
  List<int>? _shuffleOrder;

  PlayerService(this.audioHandler);

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
  Stream<bool> get playingStream => audioHandler.playbackState
      .map((state) => state.playing)
      .distinct();

  /// Stream of processing state
  Stream<AudioProcessingState> get processingStateStream =>
      audioHandler.playbackState
          .map((state) => state.processingState)
          .distinct();

  /// Combined position stream
  Stream<PositionData> get positionDataStream =>
      Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        AudioService.position,
        audioHandler.playbackState
            .map((state) => state.bufferedPosition)
            .distinct(),
        audioHandler.mediaItem
            .map((item) => item?.duration)
            .distinct(),
        (position, bufferedPosition, duration) => PositionData(
          position,
          bufferedPosition,
          duration ?? Duration.zero,
        ),
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

  /// Play a song — loads single song, keeps playlist reference for next/prev
  Future<void> playSong(SongModel song, {List<SongModel>? playlist}) async {
    try {
      _isLoading = true;
      _error = null;
      _currentSong = song;
      _currentPlaylist = playlist ?? _songs;
      _currentIndex = _currentPlaylist.indexWhere((s) => s.id == song.id);
      notifyListeners();

      if (_currentIndex == -1) {
        _currentIndex = 0;
      }

      // Build shuffle order if needed
      if (_shuffleEnabled) {
        _buildShuffleOrder();
      }

      final mediaItem = MediaItem(
        id: song.streamUrl,
        album: song.isLocal ? 'Local Music' : (song.isYouTube ? 'YouTube' : 'Music Player'),
        title: song.title,
        artist: song.artist,
        artUri: song.thumbnailUrl != null ? Uri.tryParse(song.thumbnailUrl!) : null,
        extras: {
          'songId': song.id,
          'isLocal': song.isLocal, // YouTube songs may stream via URL or play from cache
        },
      );

      await audioHandler.loadSingle(mediaItem);
      await audioHandler.play();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to play: ${e.toString()}';
      debugPrint('[PlayerService] Error: $_error');
      notifyListeners();
    }
  }  /// Toggle play/pause
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
          (_currentIndex - 1 + _currentPlaylist.length) % _currentPlaylist.length;
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
    audioHandler.stop();
    super.dispose();
  }
}

/// Loop modes
enum LoopMode { off, all, one }
