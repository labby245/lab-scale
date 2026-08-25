/// A media file the user has selected for processing.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

const Set<String> kVideoExtensions = {
  '.mp4', '.mov', '.m4v', '.webm', '.avi', '.mkv',
};

const Set<String> kImageExtensions = {
  '.jpg', '.jpeg', '.png', '.webp', '.tiff', '.bmp',
};

class MediaFile {
  const MediaFile({
    required this.path,
    required this.sizeBytes,
    required this.isImage,
  });

  final String path;
  final int sizeBytes;
  final bool isImage;

  bool get isVideo => !isImage;
  String get displayName => p.basename(path);
  String get baseName => p.basenameWithoutExtension(path);

  String get formattedSize {
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// Builds a [MediaFile] from a path, or null when the extension is not
  /// something LabScale can process.
  static MediaFile? tryFrom(String path) {
    final ext = p.extension(path).toLowerCase();
    final isImage = kImageExtensions.contains(ext);
    if (!isImage && !kVideoExtensions.contains(ext)) return null;

    final file = File(path);
    if (!file.existsSync()) return null;

    return MediaFile(
      path: path,
      sizeBytes: file.lengthSync(),
      isImage: isImage,
    );
  }

  /// Recursively collects every supported media file under [directory].
  static List<MediaFile> collectFromDirectory(String directory) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const [];

    final found = <MediaFile>[];
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final media = tryFrom(entity.path);
      if (media != null) found.add(media);
    }
    found.sort((a, b) => a.path.compareTo(b.path));
    return found;
  }

  /// Expands a mixed list of file and directory paths into media files.
  static List<MediaFile> collectFromPaths(Iterable<String> paths) {
    final found = <MediaFile>[];
    for (final path in paths) {
      if (Directory(path).existsSync()) {
        found.addAll(collectFromDirectory(path));
      } else {
        final media = tryFrom(path);
        if (media != null) found.add(media);
      }
    }
    return found;
  }
}
