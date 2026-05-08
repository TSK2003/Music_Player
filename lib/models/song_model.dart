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

  SongModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.streamUrl,
    required this.fileName,
    required this.artColor,
    required this.artColorSecondary,
    this.isLocal = false,
  });

  /// Parse a Google Drive filename to extract title and artist.
  /// Expected format: "Artist - Title.mp3" or just "Title.mp3"
  factory SongModel.fromDriveFile({
    required String fileId,
    required String fileName,
  }) {
    final parsed = _parseFileName(fileName);

    // Generate consistent colors from filename hash
    final hash = fileName.hashCode;
    final hue1 = (hash.abs() % 360).toDouble();
    final hue2 = ((hash.abs() * 7 + 137) % 360).toDouble();

    return SongModel(
      id: fileId,
      title: parsed.title,
      artist: parsed.artist,
      streamUrl: 'https://drive.google.com/uc?export=download&id=$fileId',
      fileName: fileName,
      artColor: HSLColor.fromAHSL(1.0, hue1, 0.7, 0.4).toColor(),
      artColorSecondary: HSLColor.fromAHSL(1.0, hue2, 0.6, 0.3).toColor(),
      isLocal: false,
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
    );
  }

  /// Parse filename into title and artist
  static _ParsedName _parseFileName(String fileName) {
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    String title;
    String artist;

    if (nameWithoutExt.contains(' - ')) {
      final parts = nameWithoutExt.split(' - ');
      artist = parts[0].trim();
      title = parts.sublist(1).join(' - ').trim();
    } else {
      title = nameWithoutExt.trim();
      artist = 'Unknown Artist';
    }

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
