import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
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
  SongModel? _currentSong;
  bool _isLoading = false;
  String? _error;
  bool _isInitialized = false;

  // Shuffle & Repeat state
  bool _shuffleEnabled = false;
  LoopMode _loopMode = LoopMode.off;

  PlayerService(this.audioHandler);

  // Getters
  List<SongModel> get songs => _songs;
  SongModel? get currentSong => _currentSong;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialized => _isInitialized;
  AudioPlayer get player => audioHandler.player;
  bool get shuffleEnabled => _shuffleEnabled;
  LoopMode get loopMode => _loopMode;

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

  /// Set the song list (appends to existing if merging)
  void setSongs(List<SongModel> songs) {
    _songs = songs;
    _isInitialized = true;
    notifyListeners();
  }

  /// Add songs to the existing list (for local files)
  void addSongs(List<SongModel> newSongs) {
    // Avoid duplicates by checking IDs
    final existingIds = _songs.map((s) => s.id).toSet();
    final unique = newSongs.where((s) => !existingIds.contains(s.id)).toList();
    _songs.addAll(unique);
    _isInitialized = true;
    notifyListeners();
  }

  /// Play a song from the list
  Future<void> playSong(SongModel song, {List<SongModel>? playlist}) async {
    try {
      _isLoading = true;
      _error = null;
      _currentSong = song;
      notifyListeners();

      final songsToPlay = playlist ?? _songs;
      final index = songsToPlay.indexWhere((s) => s.id == song.id);
      if (index == -1) return;

      // Convert to MediaItems
      final mediaItems = songsToPlay
          .map((s) => MediaItem(
                id: s.streamUrl,
                album: s.isLocal ? 'Local Music' : 'Music Player',
                title: s.title,
                artist: s.artist,
                artUri: null,
                extras: {
                  'songId': s.id,
                  'artColor': s.artColor.toARGB32(),
                  'artColorSecondary': s.artColorSecondary.toARGB32(),
                  'isLocal': s.isLocal,
                },
              ))
          .toList();

      await audioHandler.loadPlaylist(mediaItems, initialIndex: index);

      // Apply current shuffle/repeat settings
      await audioHandler.player.setShuffleModeEnabled(_shuffleEnabled);
      await audioHandler.player.setLoopMode(_loopMode);

      await audioHandler.play();

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to play: ${e.toString()}';
      notifyListeners();
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

  /// Seek to position
  Future<void> seekTo(Duration position) async {
    await audioHandler.seek(position);
  }

  /// Skip to next
  Future<void> next() async {
    await audioHandler.skipToNext();
    _updateCurrentSongFromIndex();
  }

  /// Skip to previous
  Future<void> previous() async {
    await audioHandler.skipToPrevious();
    _updateCurrentSongFromIndex();
  }

  /// Toggle shuffle mode
  Future<void> toggleShuffle() async {
    _shuffleEnabled = !_shuffleEnabled;
    await audioHandler.player.setShuffleModeEnabled(_shuffleEnabled);
    notifyListeners();
  }

  /// Cycle loop mode: off → all → one → off
  Future<void> cycleLoopMode() async {
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
    await audioHandler.player.setLoopMode(_loopMode);
    notifyListeners();
  }

  void _updateCurrentSongFromIndex() {
    final index = audioHandler.player.currentIndex;
    if (index != null && index < _songs.length) {
      _currentSong = _songs[index];
      notifyListeners();
    }
  }

  /// Listen to index changes and update current song
  void startListening() {
    audioHandler.player.currentIndexStream.listen((index) {
      if (index != null && index < _songs.length) {
        _currentSong = _songs[index];
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    audioHandler.stop();
    super.dispose();
  }
}
