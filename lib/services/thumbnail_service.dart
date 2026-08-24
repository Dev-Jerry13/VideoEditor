import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import 'ffmpeg_service.dart';

/// Builds the timeline filmstrip by extracting frames through FFmpeg.
///
/// Frames are cached on disk keyed by video path + frame count; a complete
/// cache is reused without launching FFmpeg again.
class ThumbnailService {
  ThumbnailService({FFmpegService? ffmpeg}) : _ffmpeg = ffmpeg ?? FFmpegService();

  final FFmpegService _ffmpeg;

  Future<List<String>> generate({
    required String videoPath,
    required Duration duration,
    required int count,
    void Function(String path)? onThumbnail,
  }) async {
    if (duration <= Duration.zero || count <= 0) return const [];

    final cacheDir = Directory(
      '${(await getTemporaryDirectory()).path}'
      '/thumbs/${videoPath.hashCode}_$count',
    );
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    var files = _frameFiles(cacheDir).toList();
    if (files.length < count) {
      await _ffmpeg.extractFrames(
        inputPath: videoPath,
        outputDirectory: cacheDir.path,
        duration: duration,
        count: count,
        maxWidth: AppConstants.thumbnailMaxWidth,
      );
      files = _frameFiles(cacheDir).toList();
    }

    final paths = <String>[];
    for (final file in files.take(count)) {
      paths.add(file.path);
      onThumbnail?.call(file.path);
    }
    return paths;
  }

  Iterable<File> _frameFiles(Directory dir) {
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jpg'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }
}
