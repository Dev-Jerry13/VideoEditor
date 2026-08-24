import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/ffmpeg_filters.dart';
import '../models/export_settings.dart';
import '../models/video_project.dart';
import 'ffmpeg_service.dart';

class ExportResult {
  const ExportResult({required this.outputPath});

  final String outputPath;

  String get fileName => outputPath.split(Platform.pathSeparator).last;
}

/// Orchestrates rendering a project to a shareable file.
///
/// Rendering always targets internal app storage; delivering the file to its
/// final destination (gallery, SAF folder, save dialog) is handled by
/// [SaveDestinationService] so a delivery failure never loses the render.
///
/// Pipeline stages:
/// 1. Every logical clip renders into a temporary session directory as an
///    independently encoded segment — trimmed, speed-adjusted and
///    (multi-clip only) normalized to a shared frame rate / canvas / audio
///    format so segments concatenate losslessly.
/// 2. Concatenation with the demuxer (stream copy), falling back to a
///    re-encoding filter graph.
/// 3. Optional audio mix (original volume ± background music).
/// 4. Optional text-overlay burn-in.
class ExportService {
  ExportService({FFmpegService? ffmpeg}) : _ffmpeg = ffmpeg ?? FFmpegService();

  final FFmpegService _ffmpeg;

  static const String _fontAssetRegular = 'assets/fonts/Roboto-Regular.ttf';
  static const String _fontAssetBold = 'assets/fonts/Roboto-Bold.ttf';

  /// Frame rate every exported segment is normalized to before concat.
  static const double _normalizedFps = 30;

  /// Share of the overall progress bar spent on concatenation.
  static const double _concatProgressShare = 0.06;

  /// Shares reserved for the optional post-processing stages.
  static const double _mixProgressShare = 0.10;
  static const double _textProgressShare = 0.16;

  Future<ExportResult> renderProject({
    required VideoProject project,
    required ExportResolution resolution,
    required ExportQuality quality,
    void Function(double progress)? onProgress,
    void Function(String stage)? onStage,
  }) async {
    if (project.isEmpty) {
      throw const ProcessingException('Nothing to export.');
    }

    final exportDir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}'
      '${Platform.pathSeparator}${AppConstants.exportsDirName}',
    );
    if (!exportDir.existsSync()) exportDir.createSync(recursive: true);

    final outputPath =
        '${exportDir.path}${Platform.pathSeparator}'
        'video_editor_${DateTime.now().millisecondsSinceEpoch}.mp4';

    final sessionId = DateTime.now().millisecondsSinceEpoch;
    final tempDir =
        Directory('${exportDir.path}${Platform.pathSeparator}temp_$sessionId');
    tempDir.createSync(recursive: true);

    try {
      await _render(
        project: project,
        resolution: resolution,
        quality: quality,
        outputPath: outputPath,
        tempDir: tempDir,
        onProgress: onProgress,
        onStage: onStage,
      );
      return ExportResult(outputPath: outputPath);
    } finally {
      _cleanupTemp(tempDir);
    }
  }

  Future<void> _render({
    required VideoProject project,
    required ExportResolution resolution,
    required ExportQuality quality,
    required String outputPath,
    required Directory tempDir,
    void Function(double progress)? onProgress,
    void Function(String stage)? onStage,
  }) async {
    final clips = project.clips;

    final hasMusic = project.audioTracks.isNotEmpty;
    // Tolerant compare so a slider that landed on exactly 100% skips work.
    final needsVolumePass =
        (project.originalAudioVolume - 1.0).abs() > 0.001;
    final needsMix = hasMusic || needsVolumePass;
    final needsText = project.textOverlays.isNotEmpty;

    // The untouched single-trimmed-clip render keeps its direct fast path:
    // no normalization, no post stages, nothing between decode and deliver.
    if (clips.length == 1 && !needsMix && !needsText &&
        clips.first.speed == 1.0) {
      onStage?.call('Rendering video');
      await _renderSegment(
        clipIndex: 0,
        project: project,
        resolution: resolution,
        quality: quality,
        segmentPath: outputPath,
        probeCache: {},
        weightStart: 0,
        weightEnd: 1,
        onProgress: onProgress,
      );
      return;
    }

    final totalMs = project.totalDuration.inMilliseconds.toDouble();
    assert(totalMs > 0, 'non-empty projects always have positive duration');

    final postShares =
        _concatProgressShare +
        (needsMix ? _mixProgressShare : 0) +
        (needsText ? _textProgressShare : 0);
    final segmentsShare = 1 - postShares;

    final probeCache = <String, MediaInfo>{};
    for (final clip in clips) {
      if (!probeCache.containsKey(clip.sourcePath)) {
        probeCache[clip.sourcePath] = await _ffmpeg.probe(clip.sourcePath);
      }
    }

    // Canvas aspect: an explicit override wins; otherwise the FIRST clip's
    // POST-VISUAL frame decides (its crop/rotation change the shape the
    // preview shows). Mixed aspect ratios letterbox into it. Never upscale
    // beyond either the target resolution or the source height.
    final first = probeCache[clips.first.sourcePath]!;
    var canvasHeight = resolution.height;
    if (first.height > 0 && first.height < canvasHeight) {
      canvasHeight = first.height;
    }
    final arOverride = project.outputAspectRatio;
    final int canvasWidth;
    if (arOverride != null) {
      final parts = arOverride.split(':');
      canvasWidth =
          (canvasHeight * int.parse(parts[0]) / int.parse(parts[1])).round();
    } else {
      // First clip's post-crop frame size; rotation swaps it.
      var srcW = first.width.toDouble();
      var srcH = first.height.toDouble();
      final crop = clips.first.transform.crop;
      if (!crop.isIdentity && srcW > 0 && srcH > 0) {
        srcW *= crop.widthFraction;
        srcH *= crop.heightFraction;
      }
      if (clips.first.transform.transform.rotation.swapsDimensions) {
        final tmp = srcW;
        srcW = srcH;
        srcH = tmp;
      }
      canvasWidth = srcW > 0 && srcH > 0
          ? (canvasHeight * srcW / srcH).round()
          : canvasHeight * 16 ~/ 9;
    }

    // Render each logical clip as a standalone normalized segment.
    onStage?.call('Rendering clips');
    final segmentPaths = <String>[];
    // Progress weights normalize against the GROSS sum of segment lengths
    // (transitions make the assembled timeline shorter than its parts).
    var grossMs = 0.0;
    for (final clip in clips) {
      grossMs += clip.effectiveDuration.inMilliseconds;
    }
    var consumedMs = 0.0;
    for (var i = 0; i < clips.length; i++) {
      final segmentPath =
          '${tempDir.path}${Platform.pathSeparator}segment_${_pad(i + 1)}.mp4';
      segmentPaths.add(segmentPath);

      final weightStart = consumedMs / grossMs * segmentsShare;
      consumedMs += clips[i].effectiveDuration.inMilliseconds;
      final weightEnd = consumedMs / grossMs * segmentsShare;

      await _renderSegment(
        clipIndex: i,
        project: project,
        resolution: resolution,
        quality: quality,
        segmentPath: segmentPath,
        probeCache: probeCache,
        normalize: true,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
        weightStart: weightStart,
        weightEnd: weightEnd,
        onProgress: onProgress,
      );
    }

    var currentVideo = '${tempDir.path}'
        '${Platform.pathSeparator}concatenated.mp4';
    var cursor = segmentsShare;

    void reportAssembly(double local) =>
        onProgress?.call(cursor + local * _concatProgressShare);

    // -- Stage: assembly -------------------------------------------------------
    // Any active transition switches to the re-encoding xfade/concat graph
    // (one extra encode — unavoidable, xfade needs overlapping inputs).
    // Pure hard-cut sequences keep the lossless stream-copy demuxer path.
    // A failing transition assembly falls back to plain concat so a bad
    // filter never loses the user's render (plan §30).
    final layout = project.layout;
    final joins = layout.segments.sublist(0, layout.segments.length - 1);
    final hasTransitions =
        joins.any((s) => s.overlapAfter > Duration.zero);

    if (hasTransitions) {
      onStage?.call('Applying transitions');
      try {
        await _ffmpeg.assembleWithTransitions(
          inputPaths: segmentPaths,
          types: [for (final s in joins) s.transitionAfter.type],
          overlaps: [for (final s in joins) s.overlapAfter],
          outputDurations: [
            for (final s in layout.segments) s.effectiveDuration,
          ],
          outputPath: currentVideo,
          crf: quality.crf,
          onProgress: reportAssembly,
        );
      } on ProcessingException {
        await _concatSegments(
          segmentPaths: segmentPaths,
          tempDir: tempDir,
          outputPath: currentVideo,
          totalDuration: project.totalDuration,
          onProgress: reportAssembly,
        );
      }
    } else {
      onStage?.call('Merging clips');
      await _concatSegments(
        segmentPaths: segmentPaths,
        tempDir: tempDir,
        outputPath: currentVideo,
        totalDuration: project.totalDuration,
        onProgress: reportAssembly,
      );
    }
    cursor += _concatProgressShare;

    // -- Stage: audio mix --------------------------------------------------------
    if (needsMix) {
      onStage?.call(hasMusic ? 'Mixing audio' : 'Adjusting audio');
      final mixed = '${tempDir.path}${Platform.pathSeparator}mixed.mp4';
      final track = project.musicTrack;
      // The music window auto-clamps to whatever timeline it can cover.
      final musicDuration = track == null || track.sourceDuration <= Duration.zero
          ? Duration.zero
          : Duration(
              milliseconds: track.sourceDuration.inMilliseconds
                  .clamp(0, project.totalDuration.inMilliseconds),
            );

      await _ffmpeg.mixAudioTrack(
        videoPath: currentVideo,
        // Normalized multi-clip output always carries an audio stream
        // (silence synthesized); single-clip renders depend on the source.
        videoHasAudio: clips.length == 1 ? first.hasAudio : true,
        originalAudioVolume: project.originalAudioVolume,
        outputPath: mixed,
        outputDuration: project.totalDuration,
        musicPath: track?.sourcePath,
        musicSourceStart: track?.sourceStart ?? Duration.zero,
        musicDuration: musicDuration,
        musicTimelineStart: track?.timelineStart ?? Duration.zero,
        musicVolume: track?.volume ?? 1.0,
        onProgress: (local) =>
            onProgress?.call(cursor + local * _mixProgressShare),
      );
      currentVideo = mixed;
      cursor += _mixProgressShare;
    }

    // -- Stage: text overlays ------------------------------------------------------
    if (needsText) {
      onStage?.call('Adding text');
      final fonts = await _stageFonts(tempDir);
      final withText =
          '${tempDir.path}${Platform.pathSeparator}texted.mp4';
      await _ffmpeg.applyTextOverlays(
        videoPath: currentVideo,
        overlays: project.textOverlays,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
        fontRegularPath: fonts.$1,
        fontBoldPath: fonts.$2,
        crf: quality.crf,
        outputPath: withText,
        outputDuration: project.totalDuration,
        onProgress: (local) =>
            onProgress?.call(cursor + local * _textProgressShare),
      );
      currentVideo = withText;
    }

    // Land the result at the promised output path (stages wrote to temp).
    if (currentVideo != outputPath) {
      await File(currentVideo).rename(outputPath);
    }
  }

  /// Stream-copy concat via the demuxer, with the re-encoding filter
  /// fallback when parameters mismatch.
  Future<void> _concatSegments({
    required List<String> segmentPaths,
    required Directory tempDir,
    required String outputPath,
    required Duration totalDuration,
    void Function(double progress)? onProgress,
  }) async {
    final listFile = File(
      '${tempDir.path}${Platform.pathSeparator}concat.txt',
    );
    await listFile.writeAsString(
      segmentPaths.map(_concatEntry).join('\n'),
      flush: true,
    );

    try {
      await _ffmpeg.concatVideos(
        segmentPathsFile: listFile.path,
        outputPath: outputPath,
        totalDuration: totalDuration,
        onProgress: onProgress,
      );
    } on ProcessingException {
      await _ffmpeg.concatVideosReencoding(
        inputPaths: segmentPaths,
        outputPath: outputPath,
        totalDuration: totalDuration,
        onProgress: onProgress,
      );
    }
  }

  Future<void> _renderSegment({
    required int clipIndex,
    required VideoProject project,
    required ExportResolution resolution,
    required ExportQuality quality,
    required String segmentPath,
    required Map<String, MediaInfo> probeCache,
    bool normalize = false,
    int? canvasWidth,
    int? canvasHeight,
    required double weightStart,
    required double weightEnd,
    void Function(double progress)? onProgress,
  }) async {
    final clip = project.clips[clipIndex];
    final info = probeCache[clip.sourcePath] ??
        await _ffmpeg.probe(clip.sourcePath);

    // Per-clip look (crop → rotate → flip → color) burned into the segment.
    final visualFilter = FfmpegFilters.buildVideoFilterChain(
      clip,
      sourceWidth: info.width,
      sourceHeight: info.height,
    );
    // A rotation that swaps dimensions makes the "source height" check for
    // downscaling meaningless — normalization (canvas pad) covers it in
    // multi-clip projects; standalone renders skip scaling instead.
    final swapsDims = clip.transform.transform.rotation.swapsDimensions;
    final maxHeight =
        normalize || swapsDims || info.height <= resolution.height
            ? null
            : resolution.height;

    await _ffmpeg.processVideo(
      inputPath: clip.sourcePath,
      outputPath: segmentPath,
      start: clip.trimStart,
      duration: clip.trimmedDuration,
      speed: clip.speed,
      crf: quality.crf,
      sourceHeight: info.height,
      // Never upscale: skip scaling when the source is already smaller.
      maxHeight: maxHeight,
      normalize: normalize,
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      sourceHasAudio: info.hasAudio,
      fps: normalize ? _normalizedFps : null,
      visualFilter: visualFilter,
      onProgress: (local) => onProgress?.call(
        weightStart + local * (weightEnd - weightStart),
      ),
    );
  }

  /// Copies the bundled Roboto fonts next to the session temp files so
  /// drawtext receives plain filesystem paths.
  Future<(String, String)> _stageFonts(Directory tempDir) async {
    final fontDir =
        Directory('${tempDir.path}${Platform.pathSeparator}fonts');
    if (!fontDir.existsSync()) fontDir.createSync(recursive: true);

    Future<String> stage(String asset, String name) async {
      final target = File(
        '${fontDir.path}${Platform.pathSeparator}$name',
      );
      if (!target.existsSync()) {
        final data = await rootBundle.load(asset);
        await target.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      return target.path;
    }

    final regular = await stage(_fontAssetRegular, 'Roboto-Regular.ttf');
    final bold = await stage(_fontAssetBold, 'Roboto-Bold.ttf');
    return (regular, bold);
  }

  /// Concat-demuxer list entry.
  ///
  /// Backslashes are converted to forward slashes (FFmpeg accepts them on
  /// every platform and they need no escaping inside single quotes); an
  /// embedded quote follows the shell-style `'\''` escape sequence.
  String _concatEntry(String path) {
    final normalized = path.replaceAll(r'\', '/');
    return "file '${normalized.replaceAll("'", r"'\''")}'";
  }

  String _pad(int index) => index.toString().padLeft(3, '0');

  void _cleanupTemp(Directory dir) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // Leftover temp files are cleaned by the OS eventually; never surface
      // a cleanup failure as an export error.
    }
  }

  void cancel() => _ffmpeg.cancelActiveSession();
}
