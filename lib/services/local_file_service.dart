import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song_model.dart';

/// Service for picking and persisting local audio files.
class LocalFileService {
  static const String _key = 'local_song_paths';

  static const List<String> _audioExtensions = [
    'mp3', 'm4a', 'wav', 'flac', 'aac', 'ogg', 'wma',
  ];

  /// Open a file picker to select audio files
  static Future<List<SongModel>> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _audioExtensions,
      allowMultiple: true,
      dialogTitle: 'Select Music Files',
    );

    if (result == null || result.files.isEmpty) return [];

    final songs = <SongModel>[];
    for (final file in result.files) {
      if (file.path != null) {
        songs.add(SongModel.fromLocalFile(file.path!));
      }
    }

    // Persist the selected paths
    if (songs.isNotEmpty) {
      await _savePaths(songs.map((s) => s.streamUrl).toList());
    }

    return songs;
  }

  /// Pick an entire folder of audio files
  static Future<List<SongModel>> pickFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Music Folder',
    );

    if (result == null) return [];

    final dir = Directory(result);
    final songs = <SongModel>[];

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final ext = entity.path.split('.').last.toLowerCase();
        if (_audioExtensions.contains(ext)) {
          songs.add(SongModel.fromLocalFile(entity.path));
        }
      }
    }

    // Sort by filename
    songs.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    // Persist
    if (songs.isNotEmpty) {
      await _savePaths(songs.map((s) => s.streamUrl).toList());
    }

    return songs;
  }

  /// Load previously saved local files (if they still exist)
  static Future<List<SongModel>> loadSavedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_key) ?? [];
    final songs = <SongModel>[];

    for (final path in paths) {
      if (await File(path).exists()) {
        songs.add(SongModel.fromLocalFile(path));
      }
    }

    return songs;
  }

  /// Save file paths to persistent storage
  static Future<void> _savePaths(List<String> newPaths) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(_key) ?? [];
    final allPaths = {...existing, ...newPaths}.toList();
    await prefs.setStringList(_key, allPaths);
  }

  /// Clear all saved local file paths
  static Future<void> clearSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
