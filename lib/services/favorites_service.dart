import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages persisted favorite song IDs using SharedPreferences.
class FavoritesService extends ChangeNotifier {
  static const String _key = 'favorite_song_ids';
  final Set<String> _favoriteIds = {};
  bool _isLoaded = false;

  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);
  bool get isLoaded => _isLoaded;

  /// Load favorites from disk
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key) ?? [];
    _favoriteIds
      ..clear()
      ..addAll(ids);
    _isLoaded = true;
    notifyListeners();
  }

  /// Check if a song is favorited
  bool isFavorite(String songId) => _favoriteIds.contains(songId);

  /// Toggle favorite status for a song
  Future<void> toggleFavorite(String songId) async {
    if (_favoriteIds.contains(songId)) {
      _favoriteIds.remove(songId);
    } else {
      _favoriteIds.add(songId);
    }
    notifyListeners();
    await _save();
  }

  /// Add a song to favorites
  Future<void> addFavorite(String songId) async {
    if (_favoriteIds.add(songId)) {
      notifyListeners();
      await _save();
    }
  }

  /// Remove a song from favorites
  Future<void> removeFavorite(String songId) async {
    if (_favoriteIds.remove(songId)) {
      notifyListeners();
      await _save();
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _favoriteIds.toList());
  }
}
