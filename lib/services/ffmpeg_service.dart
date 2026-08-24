import 'dart:async';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/media_information.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:ffmpeg_kit_flutter_new/statistics.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/ffmpeg_filters.dart';
import '../core/utils/time_utils.dart';
import '../models/text_overlay.dart';
import '../models/clip_transition.dart' show TransitionType;

class MediaInfo {
  const MediaInfo({
    required this.duration,
    required this.width,
    required this.height,
    required this.hasAudio,
    this.rotation = 0,
  });

  final Duration duration;

  /// POST-ROTATION frame dimensions: when the stream carries a 90°/270°
  /// display-matrix rotation, width/height are swapped relative to the raw
  /// coded values. FFmpeg auto-rotates on decode, so these match the frames
  /// filter graphs actually receive.
  final int width;
  final int height;

  /// Raw metadata rotation in degrees (informational; [width]/[height] are
  /// already normalized).
  final int rotation;

  /// Whether the file carries an audio stream at all.
  final bool hasAudio;
}

/// All FFmpeg invocations live here; UI and state layers never build commands.
class FFmpegService {
  /// Session running a render/export command; the one [cancelActiveSession]
  /// targets.
  int? _activeSessionId;

  /// Session extracting filmstrip frames; tracked separately so cancelling
  /// an export can never hit a thumbnail job that happens to overlap.
  int? _thumbSessionId;

  bool get isProcessing => _activeSessionId != null;

  /// Probes [path] for duration, video dimensions and audio presence.
  ///
  /// Throws [MediaFormatException] when the file cannot be parsed as media.
  Future<MediaInfo> probe(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final MediaInformation? info = session.getMediaInformation();
      final durationString = info?.getDuration();

      if (durationString == null || info == null) {
        throw const MediaFormatException();
      }
      final duration = parseFfprobeSeconds(durationString);
      if (duration <= Duration.zero) {
        throw const MediaFormatException();
      }

      var width = 0;
      var height = 0;
      var rotation = 0;
      var bestArea = 0;
      var hasAudio = false;
      for (final stream in info.getStreams()) {
        if (stream.getType() == 'video') {
          final w = stream.getWidth() ?? 0;
          final h = stream.getHeight() ?? 0;
          // Files from other apps can carry small embedded cover-art video
          // streams; the real picture is always the largest one.
          if (w * h > bestArea) {
            bestArea = w * h;
            rotation = _streamRotation(stream.getAllProperties());
            width = w;
            height = h;
          }
        } else if (stream.getType() == 'audio') {
          hasAudio = true;
        }
      }
      // Normalize to post-rotation dims (FFmpeg autorotates on decode).
      final quarterOdd =
          rotation.abs() % 360 == 90 || rotation.abs() % 360 == 270;
      if (quarterOdd) {
        final tmp = width;
        width = height;
        height = tmp;
      }
      return MediaInfo(
        duration: duration,
        width: width,
        height: height,
        hasAudio: hasAudio,
        rotation: rotation,
      );
    } on AppException {
      rethrow;
    } catch (_) {
      throw const MediaFormatException();
    }
  }

  /// Extracts the metadata rotation (degrees) from a raw ffprobe stream
  /// map. Two encodings exist in the wild: modern builds expose a
  /// `side_data_list` entry with a `rotation` key, legacy builds put
  /// `rotate` inside `tags`. Missing/unparsable → 0.
  static int _streamRotation(Map<dynamic, dynamic>? props) {
    if (props == null) return 0;
    final sideData = props['side_data_list'];
    if (sideData is List) {
      for (final entry in sideData) {
        if (entry is Map) {
          final value = num.tryParse('${entry['rotation'] ?? ''}');
          if (value != null) return value.round();
        }
      }
    }
    final tags = props['tags'];
    if (tags is Map) {
      final value = num.tryParse('${tags['rotate'] ?? ''}');
      if (value != null) return value.round();
    }
    return 0;
  }

  /// Re-encodes `[start, start + duration)` of [inputPath] into
  /// [outputPath], optionally downscaling to [maxHeight] (never upscales).
  ///
  /// When [canvasWidth]/[canvasHeight] are set (multi-clip normalization),
  /// the frame is fitted inside that canvas and centered with black bars so
  /// every segment shares identical dimensions — required for lossless
  /// concatenation across mixed-aspect sources. Audio is forced to AAC
  /// 48 kHz stereo; silence is synthesized for sources without audio.
  ///
  /// When [fps] is set the output gets a constant frame rate.
  ///
  /// [visualFilter] is the per-clip look chain (crop → rotate → flip →
  /// color) applied BEFORE any timing/scaling so it always operates on
  /// original source pixels.
  ///
  /// [speed] applies `setpts` to the video and a chained `atempo` filter
  /// to the audio so both tracks stay in sync; the effective output
  /// duration becomes `duration / speed`.
  ///
  /// [onProgress] reports completion from 0.0 to 1.0 based on FFmpeg's
  /// output-time statistics.
  Future<void> processVideo({
    required String inputPath,
    required String outputPath,
    required Duration start,
    required Duration duration,
    required int crf,
    double speed = 1.0,
    int? sourceHeight,
    int? maxHeight,
    int? canvasWidth,
    int? canvasHeight,
    bool normalize = false,
    bool sourceHasAudio = true,
    double? fps,
    String? visualFilter,
    void Function(double progress)? onProgress,
  }) async {
    if (duration <= Duration.zero) {
      throw const ProcessingException('Nothing selected to export.');
    }

    final outputDuration = speed == 1.0
        ? duration
        : Duration(milliseconds: (duration.inMilliseconds / speed).round());

    String? videoFilter;
    if (canvasWidth != null && canvasHeight != null && canvasWidth > 0 &&
        canvasHeight > 0) {
      // Even dimensions keep yuv420p encoders happy.
      final w = canvasWidth - (canvasWidth % 2);
      final h = canvasHeight - (canvasHeight % 2);
      videoFilter =
          'scale=$w:$h:force_original_aspect_ratio=decrease,'
          'pad=$w:$h:(ow-iw)/2:(oh-ih)/2';
    } else {
      videoFilter = _scaleFilter(
        maxHeight: maxHeight,
        sourceHeight: sourceHeight,
      );
    }
    if (speed != 1.0) {
      final setpts =
          'setpts=PTS/${speed.toStringAsFixed(6)}';
      videoFilter = videoFilter == null ? setpts : '$setpts,$videoFilter';
    }
    if (visualFilter != null && visualFilter.isNotEmpty) {
      // Visuals first — crop/rotate/color must see untouched source frames.
      videoFilter = videoFilter == null
          ? visualFilter
          : '$visualFilter,$videoFilter';
    }

    List<String> silentAudioInput = const [];
    var audioMap = '0:a?';
    if (normalize && !sourceHasAudio) {
      silentAudioInput = [
        '-f',
        'lavfi',
        '-i',
        'anullsrc=channel_layout=stereo:sample_rate=48000',
      ];
      audioMap = '1:a';
    }

    // Real audio is tempo-adjusted; the synthesized silence needs no chain.
    final tempoChain =
        speed == 1.0 || (normalize && !sourceHasAudio) || !sourceHasAudio
            ? null
            : FfmpegFilters.buildAudioTempoFilter(speed);

    final command = [
      '-y',
      '-ss',
      formatSeconds(start),
      '-i',
      '"$inputPath"',
      ...silentAudioInput,
      '-t',
      formatSeconds(outputDuration),
      if (videoFilter != null) ...['-vf', videoFilter],
      if (tempoChain != null) ...['-af', tempoChain],
      if (fps != null) ...['-r', fps.toStringAsFixed(3)],
      '-map',
      '0:v:0',
      '-map',
      audioMap,
      '-c:v',
      'libx264',
      '-preset',
      AppConstants.videoCodecPreset,
      '-crf',
      '$crf',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-b:a',
      AppConstants.audioBitrate,
      '-ar',
      '48000',
      '-ac',
      '2',
      '-movflags',
      '+faststart',
      '"$outputPath"',
    ].join(' ');

    await _executeWithProgress(
      command: command,
      totalMs: outputDuration.inMilliseconds,
      onProgress: onProgress,
    );
  }

  /// Mixes the original video audio (attenuated by [originalAudioVolume])
  /// with an optional background-music window under the rendered video.
  /// The video stream is stream-copied — only audio is re-encoded.
  ///
  /// Handles every combination: no music (volume-only pass), music without
  /// original audio (music mapped alone), and full mixing via `amix` with
  /// normalization disabled so the two volumes mean what the UI shows.
  Future<void> mixAudioTrack({
    required String videoPath,
    required bool videoHasAudio,
    required double originalAudioVolume,
    required String outputPath,
    required Duration outputDuration,
    String? musicPath,
    Duration musicSourceStart = Duration.zero,
    Duration musicDuration = Duration.zero,
    Duration musicTimelineStart = Duration.zero,
    double musicVolume = 1.0,
    void Function(double progress)? onProgress,
  }) async {
    final hasMusic =
        musicPath != null && musicDuration > Duration.zero;

    var filterGraph = '';
    var audioMapArg = '';
    final inputs = <String>['-i', '"$videoPath"'];

    if (!hasMusic) {
      if (!videoHasAudio) {
        throw const ProcessingException('The project has no audio to mix.');
      }
      filterGraph = '[0:a]volume=${_volumeValue(originalAudioVolume)}[a]';
      audioMapArg = '[a]';
    } else {
      inputs.addAll([
        '-ss',
        formatSeconds(musicSourceStart),
        '-t',
        formatSeconds(musicDuration),
        '-i',
        '"$musicPath"',
      ]);
      final delay = musicTimelineStart > Duration.zero
          ? 'adelay=${musicTimelineStart.inMilliseconds}:all=1,'
          : '';
      final musicChain =
          '[1:a]${delay}volume=${_volumeValue(musicVolume)}[m]';

      if (videoHasAudio) {
        filterGraph = '[0:a]volume=${_volumeValue(originalAudioVolume)}[v];'
            '$musicChain;'
            '[v][m]amix=inputs=2:duration=first:dropout_transition=0:'
            'normalize=0[a]';
        audioMapArg = '[a]';
      } else {
        filterGraph = musicChain;
        audioMapArg = '[m]';
      }
    }

    final command = [
      '-y',
      ...inputs,
      '-filter_complex',
      '"$filterGraph"',
      '-map',
      '0:v:0',
      '-map',
      audioMapArg,
      '-c:v',
      'copy',
      '-c:a',
      'aac',
      '-b:a',
      AppConstants.audioBitrate,
      '-ar',
      '48000',
      '-ac',
      '2',
      '-movflags',
      '+faststart',
      '"$outputPath"',
    ].join(' ');

    await _executeWithProgress(
      command: command,
      totalMs: outputDuration.inMilliseconds,
      onProgress: onProgress,
    );
  }

  /// Burns [overlays] into the video with chained `drawtext` filters.
  /// Coordinates arrive normalized inside each overlay and are resolved
  /// against the actual output dimensions here.
  Future<void> applyTextOverlays({
    required String videoPath,
    required List<TextOverlay> overlays,
    required int canvasWidth,
    required int canvasHeight,
    required String fontRegularPath,
    required String fontBoldPath,
    required int crf,
    required String outputPath,
    required Duration outputDuration,
    void Function(double progress)? onProgress,
  }) async {
    if (overlays.isEmpty) return;

    final chain = overlays
        .map(
          (o) => FfmpegFilters.buildDrawTextFilter(
            o,
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            fontFilePath: o.bold ? fontBoldPath : fontRegularPath,
          ),
        )
        .join(',');

    final command = [
      '-y',
      '-i',
      '"$videoPath"',
      '-vf',
      '"$chain"',
      '-c:v',
      'libx264',
      '-preset',
      AppConstants.videoCodecPreset,
      '-crf',
      '$crf',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'copy',
      '-movflags',
      '+faststart',
      '"$outputPath"',
    ].join(' ');

    await _executeWithProgress(
      command: command,
      totalMs: outputDuration.inMilliseconds,
      onProgress: onProgress,
    );
  }

  static String _volumeValue(double v) => v.clamp(0.0, 1.0).toStringAsFixed(4);

  /// Concatenates already-encoded segment files with the concat demuxer and
  /// stream copying — fast and lossless because every segment was produced
  /// with identical encoding parameters.
  ///
  /// [segmentPathsFile] is a plain-text file listing `file '<path>'` lines.
  Future<void> concatVideos({
    required String segmentPathsFile,
    required String outputPath,
    required Duration totalDuration,
    void Function(double progress)? onProgress,
  }) async {
    final command = [
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      '"$segmentPathsFile"',
      '-c',
      'copy',
      '-movflags',
      '+faststart',
      '"$outputPath"',
    ].join(' ');

    await _executeWithProgress(
      command: command,
      totalMs: totalDuration.inMilliseconds,
      onProgress: onProgress,
    );
  }

  /// Joins rendered segments with per-boundary transitions.
  ///
  /// Active boundaries become chained `xfade`/`acrossfade` pairs; inactive
  /// ones become `concat` pairs — mixed sequences are handled inside one
  /// filter graph (see [FfmpegFilters.buildAssemblyFilterComplex]). The
  /// output is fully re-encoded once, so this path only runs when at least
  /// one transition exists; pure hard-cut assembly keeps the fast
  /// stream-copy concat demuxer route.
  Future<void> assembleWithTransitions({
    required List<String> inputPaths,
    required List<TransitionType> types,
    required List<Duration> overlaps,
    required List<Duration> outputDurations,
    required String outputPath,
    required int crf,
    void Function(double progress)? onProgress,
  }) async {
    if (inputPaths.length < 2) {
      throw const ProcessingException('Transitions need two clips.');
    }

    final graph = FfmpegFilters.buildAssemblyFilterComplex(
      outputDurations: outputDurations,
      types: types,
      overlaps: overlaps,
      videoLabel: 'vout',
      audioLabel: 'aout',
    );

    final netMs = outputDurations.fold<int>(
            0, (sum, d) => sum + d.inMilliseconds) -
        overlaps.fold<int>(0, (sum, d) => sum + d.inMilliseconds);

    final command = [
      '-y',
      for (final path in inputPaths) ...['-i', '"$path"'],
      '-filter_complex',
      '"$graph"',
      '-map',
      '[vout]',
      '-map',
      '[aout]',
      '-c:v',
      'libx264',
      '-preset',
      AppConstants.videoCodecPreset,
      '-crf',
      '$crf',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-b:a',
      AppConstants.audioBitrate,
      '-ar',
      '48000',
      '-ac',
      '2',
      '-movflags',
      '+faststart',
      '"$outputPath"',
    ].join(' ');

    await _executeWithProgress(
      command: command,
      totalMs: netMs,
      onProgress: onProgress,
    );
  }

  /// Fallback concatenation that re-encodes through the concat filter. Used
  /// when stream-copy concat fails (e.g. mismatched parameters).
  Future<void> concatVideosReencoding({
    required List<String> inputPaths,
    required String outputPath,
    required Duration totalDuration,
    void Function(double progress)? onProgress,
  }) async {
    if (inputPaths.isEmpty) {
      throw const ProcessingException('Nothing to concatenate.');
    }

    final inputs = <String>[
      for (final path in inputPaths) ...['-i', '"$path"'],
    ];
    // Build [0:v][0:a][1:v][1:a]...concat=n=N:v=1:a=1[v][a]
    final labels = StringBuffer();
    for (var i = 0; i < inputPaths.length; i++) {
      labels
        ..write('[$i:v:0]')
        ..write('[$i:a:0]');
    }
    final filter =
        '${labels}concat=n=${inputPaths.length}:v=1:a=1[v][a]';

    final command = [
      '-y',
      ...inputs,
      '-filter_complex',
      '"$filter"',
      '-map',
      '[v]',
      '-map',
      '[a]',
      '-c:v',
      'libx264',
      '-preset',
      AppConstants.videoCodecPreset,
      '-crf',
      '20',
      '-c:a',
      'aac',
      '-b:a',
      AppConstants.audioBitrate,
      '-ar',
      '48000',
      '-ac',
      '2',
      '-movflags',
      '+faststart',
      '"$outputPath"',
    ].join(' ');

    await _executeWithProgress(
      command: command,
      totalMs: totalDuration.inMilliseconds,
      onProgress: onProgress,
    );
  }

  /// Extracts [count] evenly spaced frames from [inputPath] as JPEGs named
  /// `frame_%03d.jpg` inside [outputDirectory]. Single FFmpeg pass using the
  /// fps filter — one process launch for the whole filmstrip.
  Future<void> extractFrames({
    required String inputPath,
    required String outputDirectory,
    required Duration duration,
    required int count,
    required int maxWidth,
  }) async {
    final seconds = duration.inMilliseconds / 1000.0;
    if (seconds <= 0 || count <= 0) return;

    final fps = (count / seconds).clamp(0.000001, 1000.0);
    final command = [
      '-y',
      '-i',
      '"$inputPath"',
      '-vf',
      'fps=${fps.toStringAsFixed(6)},scale=$maxWidth:-2',
      '-q:v',
      '4',
      '-frames:v',
      '$count',
      '"$outputDirectory/frame_%03d.jpg"',
    ].join(' ');

    await _runCommand(command);
  }

  Future<void> _executeWithProgress({
    required String command,
    required int totalMs,
    void Function(double progress)? onProgress,
  }) async {
    final completer = Completer<void>();

    void onStatistics(Statistics stats) {
      final processed = stats.getTime();
      if (processed <= 0) return;
      onProgress?.call((processed / totalMs).clamp(0.0, 1.0));
    }

    final session = await FFmpegKit.executeAsync(
      command,
      (FFmpegSession completedSession) {
        _activeSessionId = null;
        if (!completer.isCompleted) completer.complete();
      },
      null,
      onStatistics,
    );
    _activeSessionId = session.getSessionId();

    try {
      await completer.future;
      final code = await session.getReturnCode();

      if (ReturnCode.isSuccess(code)) return;
      if (ReturnCode.isCancel(code)) {
        throw const ExportCancelledException();
      }

      String detail = '';
      try {
        detail = (await session.getAllLogsAsString())?.trim() ?? '';
        if (detail.length > 400) {
          detail = detail.substring(detail.length - 400);
        }
      } catch (_) {}

      throw ProcessingException(
        detail.isEmpty ? 'Export failed.' : 'Export failed.\n$detail',
      );
    } finally {
      _activeSessionId = null;
    }
  }

  Future<void> _runCommand(String command) async {
    final completer = Completer<void>();

    final session = await FFmpegKit.executeAsync(
      command,
      (FFmpegSession completedSession) {
        _thumbSessionId = null;
        if (!completer.isCompleted) completer.complete();
      },
    );
    _thumbSessionId = session.getSessionId();

    try {
      await completer.future;
      final code = await session.getReturnCode();

      if (ReturnCode.isSuccess(code)) return;
      throw ProcessingException('FFmpeg failed with code ${code?.getValue()}.');
    } finally {
      _thumbSessionId = null;
    }
  }

  String? _scaleFilter({int? maxHeight, required int? sourceHeight}) {
    if (maxHeight == null) return null;
    if (sourceHeight != null && sourceHeight > 0 && sourceHeight <= maxHeight) {
      return null;
    }
    // Even dimensions keep yuv420p encoders happy.
    final target = maxHeight - (maxHeight % 2);
    return 'scale=-2:$target';
  }

  /// Cancels the running render/export session. Thumbnail extraction is
  /// deliberately left alone.
  void cancelActiveSession() {
    final id = _activeSessionId;
    if (id != null) {
      FFmpegKit.cancel(id);
    }
  }

  /// Cancels a running filmstrip extraction, if any.
  void cancelThumbnailSession() {
    final id = _thumbSessionId;
    if (id != null) {
      FFmpegKit.cancel(id);
    }
  }
}
