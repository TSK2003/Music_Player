import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song_model.dart';

class DriveService {
  static const String _folderId = '1m2lIXYpdum1uqlaj-syVIBOOUK6WzYAO';

  /// Fetches song list from a public Google Drive folder.
  /// Uses Google Drive's public API to list files.
  static Future<List<SongModel>> fetchSongs() async {
    try {
      // Use Google Drive API v3 (public, no auth needed for public folders)
      final url = Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        '?q=%27$_folderId%27+in+parents+and+mimeType+contains+%27audio%27'
        '&fields=files(id,name,mimeType,size)'
        '&key=AIzaSyBMFMvwOJDcoKH-7OIJDOqiiD1S0Us6zgM'
        '&pageSize=100'
        '&orderBy=name',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final files = data['files'] as List<dynamic>? ?? [];

        return files
            .where((file) {
              final name = file['name'] as String? ?? '';
              return name.endsWith('.mp3') ||
                  name.endsWith('.m4a') ||
                  name.endsWith('.wav') ||
                  name.endsWith('.flac') ||
                  name.endsWith('.aac') ||
                  name.endsWith('.ogg');
            })
            .map((file) => SongModel.fromDriveFile(
                  fileId: file['id'] as String,
                  fileName: file['name'] as String,
                ))
            .toList();
      }

      // Fallback: try scraping the folder page
      return _fetchSongsFromFolderPage();
    } catch (e) {
      // Try fallback method
      return _fetchSongsFromFolderPage();
    }
  }

  /// Fallback: Scrape the public folder page for file IDs
  static Future<List<SongModel>> _fetchSongsFromFolderPage() async {
    try {
      final url = Uri.parse(
        'https://drive.google.com/drive/folders/$_folderId',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'Mozilla/5.0',
        },
      );

      if (response.statusCode == 200) {
        final body = response.body;
        final songs = <SongModel>[];

        // Extract file IDs and names from the page content
        // Google Drive embeds file data in script tags
        final fileIdRegex = RegExp(r'\["([a-zA-Z0-9_-]{25,})","([^"]+\.(?:mp3|m4a|wav|flac|aac|ogg))"');
        final matches = fileIdRegex.allMatches(body);

        for (final match in matches) {
          final fileId = match.group(1)!;
          final fileName = match.group(2)!;
          songs.add(SongModel.fromDriveFile(
            fileId: fileId,
            fileName: fileName,
          ));
        }

        if (songs.isNotEmpty) return songs;
      }

      // If both methods fail, return hardcoded sample for demo
      return _getDemoSongs();
    } catch (e) {
      return _getDemoSongs();
    }
  }

  /// Demo songs as absolute last fallback
  static List<SongModel> _getDemoSongs() {
    return [
      SongModel.fromDriveFile(
        fileId: 'demo_1',
        fileName: 'Ethereal Dreams - Nightfall.mp3',
      ),
      SongModel.fromDriveFile(
        fileId: 'demo_2',
        fileName: 'Cosmic Waves - Stellar Journey.mp3',
      ),
      SongModel.fromDriveFile(
        fileId: 'demo_3',
        fileName: 'Digital Horizon - Neon Pulse.mp3',
      ),
      SongModel.fromDriveFile(
        fileId: 'demo_4',
        fileName: 'Lunar Phase - Gravity.mp3',
      ),
      SongModel.fromDriveFile(
        fileId: 'demo_5',
        fileName: 'Aurora Beats - Electric Dawn.mp3',
      ),
    ];
  }
}
