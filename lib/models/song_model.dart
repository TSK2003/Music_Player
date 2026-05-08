import 'package:flutter/material.dart';

class SongModel {
  final String id;
  final String title;
  final String artist;
  final String streamUrl;
  final String fileName;
  final Color artColor;
  final Color artColorSecondary;
  final bool isLocal;
  final String? category;

  SongModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.streamUrl,
    required this.fileName,
    required this.artColor,
    required this.artColorSecondary,
    this.isLocal = false,
    this.category,
  });

  /// Create from a Google Drive file.
  /// Uses googleapis.com direct media URL which doesn't redirect
  /// (unlike the uc?export=download URL which breaks audio players).
  factory SongModel.fromDriveFile({
    required String fileId,
    required String fileName,
    String apiKey = '',
    String? category,
  }) {
    final parsed = _parseFileName(fileName);

    // Generate consistent colors from filename hash
    final hash = fileName.hashCode;
    final hue1 = (hash.abs() % 360).toDouble();
    final hue2 = ((hash.abs() * 7 + 137) % 360).toDouble();

    // Use the Drive API v3 direct media download URL
    // This streams audio directly without redirects
    final streamUrl = apiKey.isNotEmpty
        ? 'https://www.googleapis.com/drive/v3/files/$fileId?alt=media&key=$apiKey'
        : 'https://drive.google.com/uc?export=download&id=$fileId';

    return SongModel(
      id: fileId,
      title: parsed.title,
      artist: parsed.artist,
      streamUrl: streamUrl,
      fileName: fileName,
      artColor: HSLColor.fromAHSL(1.0, hue1, 0.7, 0.4).toColor(),
      artColorSecondary: HSLColor.fromAHSL(1.0, hue2, 0.6, 0.3).toColor(),
      isLocal: false,
      category: category,
    );
  }

  /// Create a SongModel from a local file path.
  factory SongModel.fromLocalFile(String filePath) {
    final fileName = filePath.split(RegExp(r'[\\/]')).last;
    final parsed = _parseFileName(fileName);

    // Generate consistent colors from file path hash
    final hash = filePath.hashCode;
    final hue1 = (hash.abs() % 360).toDouble();
    final hue2 = ((hash.abs() * 7 + 137) % 360).toDouble();

    return SongModel(
      id: 'local_${filePath.hashCode.abs()}',
      title: parsed.title,
      artist: parsed.artist,
      streamUrl: filePath,
      fileName: fileName,
      artColor: HSLColor.fromAHSL(1.0, hue1, 0.7, 0.4).toColor(),
      artColorSecondary: HSLColor.fromAHSL(1.0, hue2, 0.6, 0.3).toColor(),
      isLocal: true,
      category: 'Local',
    );
  }

  /// Smart filename parser:
  /// 1. Strips common suffixes like _spotdown.org, _masstamilan, etc.
  /// 2. Extracts artist from "Artist - Title" or movie from "(From MovieName)"
  /// 3. Cleans up underscores used as quotes
  static _ParsedName _parseFileName(String fileName) {
    // Remove file extension
    String name = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

    // Strip common download site suffixes
    name = name.replaceAll(RegExp(r'[_\-\s]*(spotdown\.org|masstamilan|isaimini|starmusiq|tamilwire|saavn|pagalworld|downloadming)$', caseSensitive: false), '');

    // Clean up multiple underscores/spaces
    name = name.replaceAll(RegExp(r'_+'), ' ').trim();

    String title;
    String artist = 'Unknown Artist';

    // Try "Artist - Title" format first
    if (name.contains(' - ')) {
      final parts = name.split(' - ');
      artist = parts[0].trim();
      title = parts.sublist(1).join(' - ').trim();
    } else {
      title = name.trim();

      // Try to extract movie name from "(From MovieName)" or "(From _MovieName_)"
      final movieMatch = RegExp(r'\(From\s+[_"]?([^)_"]+)[_"]?\)', caseSensitive: false).firstMatch(title);
      if (movieMatch != null) {
        artist = movieMatch.group(1)?.trim() ?? 'Unknown Artist';
        // Clean up the title — remove the "(From ...)" part for a cleaner look
        // but keep it if the title would be too short
        final cleanTitle = title.replaceAll(movieMatch.group(0)!, '').trim();
        if (cleanTitle.length >= 3) {
          title = cleanTitle;
        }
      }
    }

    // Final cleanup: remove trailing/leading special chars
    title = title.replaceAll(RegExp(r'^[\s_\-]+|[\s_\-]+$'), '');
    artist = artist.replaceAll(RegExp(r'^[\s_\-]+|[\s_\-]+$'), '');

    if (title.isEmpty) title = fileName;
    if (artist.isEmpty) artist = 'Unknown Artist';

    return _ParsedName(title: title, artist: artist);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is SongModel && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class _ParsedName {
  final String title;
  final String artist;
  const _ParsedName({required this.title, required this.artist});
}
