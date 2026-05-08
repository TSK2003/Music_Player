import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song_model.dart';

class DriveService {
  static String folderId = '1m2lIXYpdum1uqlaj-syVIBOOUK6WzYAO';
  static String apiKey = 'AIzaSyBMFMvwOJDcoKH-7OIJDOqiiD1S0Us6zgM';

  static Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    folderId = prefs.getString('drive_folder_id') ?? '1m2lIXYpdum1uqlaj-syVIBOOUK6WzYAO';
    apiKey = prefs.getString('drive_api_key') ?? 'AIzaSyBMFMvwOJDcoKH-7OIJDOqiiD1S0Us6zgM';
  }

  static Future<void> saveConfig(String newFolderId, String newApiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('drive_folder_id', newFolderId);
    await prefs.setString('drive_api_key', newApiKey);
    folderId = newFolderId;
    apiKey = newApiKey;
  }

  /// Fetches ALL songs from a public Google Drive folder, including subfolders.
  /// Subfolder names will be used as the song's "category".
  static Future<List<SongModel>> fetchSongs() async {
    try {
      final allSongs = <SongModel>[];
      
      // 1. Fetch audio files directly in the root folder (uncategorized)
      final rootSongs = await _fetchAudioInFolder(folderId, null);
      allSongs.addAll(rootSongs);

      // 2. Fetch subfolders in the root folder
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        '?q=%27$folderId%27+in+parents+and+mimeType=%27application/vnd.google-apps.folder%27'
        '&fields=files(id,name)'
        '&key=$apiKey'
        '&orderBy=name'
      );
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final folders = data['files'] as List<dynamic>? ?? [];
        
        // 3. Fetch audio files for each subfolder and tag them with the folder name
        for (final folder in folders) {
          final folderId = folder['id'] as String;
          final folderName = folder['name'] as String;
          final folderSongs = await _fetchAudioInFolder(folderId, folderName);
          allSongs.addAll(folderSongs);
        }
      }

      if (allSongs.isNotEmpty) return allSongs;
      return _getDemoSongs();
    } catch (e) {
      debugPrint('[DriveService] Error fetching: $e');
      return _getDemoSongs();
    }
  }

  static Future<List<SongModel>> _fetchAudioInFolder(String folderId, String? category) async {
    final folderSongs = <SongModel>[];
    String? nextPageToken;

    try {
      do {
        final url = Uri.parse(
          'https://www.googleapis.com/drive/v3/files'
          '?q=%27$folderId%27+in+parents+and+mimeType+contains+%27audio%27'
          '&fields=nextPageToken,files(id,name)'
          '&key=$apiKey'
          '&pageSize=1000'
          '&orderBy=name'
          '${nextPageToken != null ? '&pageToken=$nextPageToken' : ''}',
        );

        final response = await http.get(url);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final files = data['files'] as List<dynamic>? ?? [];
          
          final songs = files
              .where((file) {
                final name = file['name'] as String? ?? '';
                final lowerName = name.toLowerCase();
                return lowerName.endsWith('.mp3') ||
                    lowerName.endsWith('.m4a') ||
                    lowerName.endsWith('.wav') ||
                    lowerName.endsWith('.flac') ||
                    lowerName.endsWith('.aac') ||
                    lowerName.endsWith('.ogg');
              })
              .map((file) => SongModel.fromDriveFile(
                    fileId: file['id'] as String,
                    fileName: file['name'] as String,
                    apiKey: apiKey,
                    category: category,
                  ))
              .toList();
              
          folderSongs.addAll(songs);
          nextPageToken = data['nextPageToken'] as String?;
        } else {
          break;
        }
      } while (nextPageToken != null);
    } catch (e) {
      debugPrint('[DriveService] Error fetching folder $folderId: $e');
    }

    return folderSongs;
  }

  /// Demo songs as absolute last fallback using valid direct public URLs
  static List<SongModel> _getDemoSongs() {
    return [
      SongModel(
        id: 'demo_1',
        title: 'Ethereal Dreams - Nightfall',
        artist: 'Unknown Artist',
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
        fileName: 'Ethereal Dreams - Nightfall.mp3',
        artColor: const Color(0xFF6A1B9A),
        artColorSecondary: const Color(0xFF8E24AA),
        isLocal: false,
        category: 'Demo Tracks',
      ),
      SongModel(
        id: 'demo_2',
        title: 'Cosmic Waves - Stellar Journey',
        artist: 'Unknown Artist',
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
        fileName: 'Cosmic Waves - Stellar Journey.mp3',
        artColor: const Color(0xFF1565C0),
        artColorSecondary: const Color(0xFF1976D2),
        isLocal: false,
        category: 'Demo Tracks',
      ),
      SongModel(
        id: 'demo_3',
        title: 'Digital Horizon - Neon Pulse',
        artist: 'Unknown Artist',
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
        fileName: 'Digital Horizon - Neon Pulse.mp3',
        artColor: const Color(0xFFC62828),
        artColorSecondary: const Color(0xFFD32F2F),
        isLocal: false,
        category: 'Demo Tracks',
      ),
      SongModel(
        id: 'demo_4',
        title: 'Lunar Phase - Gravity',
        artist: 'Unknown Artist',
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
        fileName: 'Lunar Phase - Gravity.mp3',
        artColor: const Color(0xFF2E7D32),
        artColorSecondary: const Color(0xFF388E3C),
        isLocal: false,
        category: 'Demo Tracks',
      ),
      SongModel(
        id: 'demo_5',
        title: 'Aurora Beats - Electric Dawn',
        artist: 'Unknown Artist',
        streamUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
        fileName: 'Aurora Beats - Electric Dawn.mp3',
        artColor: const Color(0xFFE65100),
        artColorSecondary: const Color(0xFFF57C00),
        isLocal: false,
        category: 'Demo Tracks',
      ),
    ];
  }
}
