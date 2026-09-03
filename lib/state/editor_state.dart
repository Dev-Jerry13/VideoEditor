import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/utils/time_utils.dart';
import '../models/audio_track.dart';
import '../models/clip_transition.dart';
import '../models/export_settings.dart';
import '../models/text_overlay.dart';
import '../models/video_adjustments.dart';
import '../models/video_clip.dart';
import '../models/video_filter.dart';
import '../models/video_project.dart';
import '../models/video_transform.dart';
import '../services/export_service.dart';
import '../services/ffmpeg_service.dart';
import '../services/media_picker_service.dart';
import '../services/save_destination_service.dart';
import '../services/session_service.dart';
import '../services/thumbnail_service.dart';
import '../services/timeline_service.dart' show SegmentLayout;

enum ExportPhase { idle, exporting, success, failed }

/// Single source of truth for the editor screen.
///
/// The project holds an ordered list of immutable [VideoClip]s. Every edit
/// operation produces a new [VideoProject]; mutations go through this class
/// only — never from widgets directly.
///
/// Playback position is intentionally NOT pushed through notifyListeners:
/// [playbackPosition] carries PROJECT-timeline time (as opposed to raw
/// source time), and widgets that need it listen to that ValueNotifier, so
/// the moving playhead never rebuilds the rest of the editor.
class EditorState extends ChangeNotifier {
  EditorState()
    : _picker = MediaPickerService(),
      _thumbnails = ThumbnailService(),
      _ffmpeg = FFmpegService(),
      _exporter = ExportService(),
      _destinations = SaveDestinationService(),
      _sessions = SessionService() {
    unawaited(_loadSaveSettings());
    unawaited(_initSessions());
  }

  final MediaPickerService _picker;
  final ThumbnailService _thumbnails;
  final FFmpegService _ffmpeg;
  final ExportService _exporter;
  final SaveDestinationService _destinations;
  final SessionService _sessions;

  /// Id of the session backing the current project (null before any video
  /// is opened). Below it, media copies and project.json are stored.
  String? _sessionId;
  String? _posterPath;

  /// Most-recently-used sessions, newest first. Drafts remain available until
  /// the user removes them from Recent.
  final ValueNotifier<List<SessionRecord>> recentSessions = ValueNotifier(
    const [],
  );

  bool isRestoring = false;

  /// Debounces the autosave so rapid edits don't hammer the disk.
  Timer? _autosaveTimer;
  Future<void>? _autosaveInFlight;
  bool _disposed = false;

  /// Hidden second player used for background-music preview. Created
  /// lazily for the current music source and torn down whenever the track
  /// changes or the project closes.
  VideoPlayerController? _musicController;
  String? _musicControllerPath;

  /// Whether the last tick found the playhead inside the music window;
  /// lets [_onControllerTick] fire start/stop exactly once per crossing.
  bool _musicInsideWindow = false;

  // -- Phase 4: overlap (transition) playback ---------------------------------

  /// Clip currently fading IN alongside the active one while the playhead
  /// crosses a transition window. Null outside windows.
  String? _incomingClipId;
  String? _incomingSourcePath;

  VideoProject? _project;
  String? _selectedClipId;

  /// One initialized player per distinct source file, capped by an LRU
  /// policy so long sessions don't accumulate decoders. Same-source clip
  /// transitions are therefore seamless seeks; only cross-source jumps pay
  /// a (pool-warm) switch cost.
  final Map<String, VideoPlayerController> _playerPool = {};
  VideoPlayerController? _activeController;

  /// Clip currently loaded in [_activeController].
  String? _activeClipId;

  /// True while an internal controller switch/seek is in flight; tick
  /// events fired meanwhile carry stale positions and must be ignored.
  bool _movingPlayhead = false;

  /// Latest seek target requested while a move was already in flight; the
  /// running move picks it up afterwards so rapid scrubbing always lands
  /// on the newest position instead of dropping requests.
  Duration? _queuedSeek;

  bool isLoadingProject = false;
  bool isSavingProject = false;
  String? projectError;

  /// Message for rejected edit actions (invalid split position, deleting
  /// the only clip…). Cleared by the UI after surfacing it.
  String? actionError;

  /// Filmstrip frames per source path. Each strip covers the WHOLE source
  /// evenly, so frame i sits at source time `duration * i / length`; clips
  /// slice the strip by their own trim range.
  final ValueNotifier<Map<String, List<String>>> thumbnailStrips =
      ValueNotifier(const {});

  final Set<String> _pendingThumbSources = {};

  /// PROJECT-timeline mirror of the player position, refreshed by the
  /// active controller listener. Widgets listen here instead of rebuilding
  /// the whole editor per frame.
  final ValueNotifier<Duration> playbackPosition = ValueNotifier(Duration.zero);

  bool _lastPlaying = false;
  Timer? _playbackTimer;

  void _startPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (_activeController?.value.isPlaying ?? false) {
        _onControllerTick();
      } else {
        _stopPlaybackTimer();
      }
    });
  }

  void _stopPlaybackTimer() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
  }

  ExportPhase exportPhase = ExportPhase.idle;
  String? exportError;

  /// Currently selected text overlay (editor sheet / drag layer).
  String? _selectedTextId;

  /// True while the text editor sheet is open; gates the draggable
  /// overlay layer on the preview.
  bool textEditingSession = false;

  /// Label of the current export stage ("Merging clips", "Adding text"…),
  /// refreshed through [exportStageNotifier] without full rebuilds.
  String? exportStage;
  final ValueNotifier<String?> exportStageNotifier = ValueNotifier(null);
  ExportResult? lastExport;
  DeliveryResult? lastDelivery;

  SaveDestination saveDestination = SaveDestination.gallery;
  String? savedFolderName;

  /// Raw tree URI of the persisted folder, used as the picker's start point
  /// when the user re-picks. Not exposed to the UI.
  @visibleForTesting
  String? savedFolderUri;

  bool _delivering = false;

  /// ValueNotifier so the progress bar updates smoothly without rebuilding
  /// the rest of the UI on every FFmpeg statistic.
  final ValueNotifier<double> exportProgressValue = ValueNotifier(0);

  // -- Undo / redo ------------------------------------------------------------

  final List<VideoProject> _undoStack = [];
  final List<VideoProject> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Captures the current project for undo. Call BEFORE a mutation; for
  /// continuous interactions (handle drags, dialogs) call once up front so
  /// the whole gesture collapses into a single history entry.
  void pushUndoSnapshot() {
    final project = _project;
    if (project == null) return;
    _undoStack.add(project.copy());
    if (_undoStack.length > AppConstants.historyLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Registers a PREVIOUSLY captured snapshot as an undo entry — used by
  /// transactional UI like the trim dialog, which mutates live while open
  /// and only decides on completion whether the change should be undoable.
  void insertUndoSnapshot(VideoProject snapshot) {
    _undoStack.add(snapshot);
    if (_undoStack.length > AppConstants.historyLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    notifyListeners();
  }

  /// Registers [snapshot] (a pre-mutation copy) as undoable and swaps in
  /// [updated] as the live project.
  void _commitSnapshot(VideoProject snapshot, VideoProject updated) {
    _undoStack.add(snapshot);
    if (_undoStack.length > AppConstants.historyLimit) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _project = updated;
    _scheduleAutosave();
  }

  void undo() {
    if (_undoStack.isEmpty || _project == null) return;
    final previous = _project!;
    _adoptProject(_undoStack.removeLast());
    _redoStack.add(previous);
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty || _project == null) return;
    final previous = _project!;
    _adoptProject(_redoStack.removeLast());
    _undoStack.add(previous);
    notifyListeners();
  }

  // -- Project getters --------------------------------------------------------

  VideoPlayerController? get controller => _activeController;

  /// Id of the clip whose controller is on screen (may trail selection).
  String? get activeClipId => _activeClipId;

  /// Id of the clip currently blending in during a transition window
  /// (null outside windows). Read by the preview compositing layer.
  String? get incomingClipId => _incomingClipId;

  /// Controller backing [incomingClipId]; null unless a window is live.
  VideoPlayerController? get incomingController =>
      _incomingSourcePath == null ? null : _playerPool[_incomingSourcePath];

  VideoProject? get project => _project;
  String get projectName => _project?.name ?? 'Video Editor';
  List<VideoClip> get clips => _project?.clips ?? const [];
  bool get hasProject =>
      _project != null &&
      _project!.clips.isNotEmpty &&
      _activeController != null;
  bool get isVideoInitialized =>
      _activeController?.value.isInitialized ?? false;
  bool get isPlaying => _activeController?.value.isPlaying ?? false;
  Duration get totalDuration => _project?.totalDuration ?? Duration.zero;

  String? get selectedClipId => _selectedClipId;

  /// Index of the selected clip, or -1 when nothing is selected.
  int get selectedIndex => _project?.indexOf(_selectedClipId ?? '') ?? -1;

  VideoClip? get selectedClip {
    final index = selectedIndex;
    return index >= 0 ? _project!.clips[index] : null;
  }

  String? get selectedTextId => _selectedTextId;

  TextOverlay? get selectedText {
    final project = _project;
    final id = _selectedTextId;
    if (project == null || id == null) return null;
    for (final overlay in project.textOverlays) {
      if (overlay.id == id) return overlay;
    }
    return null;
  }

  // -- Trim getters (operate on the selected clip) -----------------------------

  Duration get trimStart => selectedClip?.trimStart ?? Duration.zero;
  Duration get trimEnd => selectedClip?.trimEnd ?? Duration.zero;

  /// Source duration of the selected clip; bounds trim UI sliders.
  Duration get sourceDuration => selectedClip?.sourceDuration ?? Duration.zero;

  // -- Project lifecycle -------------------------------------------------------

  Future<String?> pickVideoFile() async {
    try {
      return await _picker.pickVideo();
    } on AppException catch (e) {
      projectError = e.userMessage;
      notifyListeners();
      return null;
    }
  }

  /// Reads media metadata before creating a draft copy. This lets the import
  /// UI reject unsupported or corrupt files without consuming session storage.
  Future<MediaInfo?> inspectVideoFile(String path) async {
    try {
      return await _ffmpeg.probe(path);
    } on AppException catch (e) {
      projectError = e.userMessage;
    } catch (_) {
      projectError = 'This video could not be read. Choose another file.';
    }
    notifyListeners();
    return null;
  }

  /// Probes [path] and opens it as a fresh single-clip project.
  /// Returns true on success.
  Future<bool> openVideo(String path) async {
    closeProject();
    isLoadingProject = true;
    projectError = null;
    notifyListeners();

    try {
      final id = 'proj_${DateTime.now().microsecondsSinceEpoch}';
      // Validate the original before copying it into a session. A bad or
      // unsupported selection should never leave an orphaned draft on disk.
      final info = await _ffmpeg.probe(path);
      // Copy the picked source into app storage so the saved session keeps
      // a valid file for up to two days, even if the original moves.
      final storedPath = await _sessions.storeMedia(id, path);
      final clip = VideoClip(
        id: ClipId.next(),
        sourcePath: storedPath,
        sourceDuration: info.duration,
      );
      _project = VideoProject(name: 'Project', clips: [clip]);
      _selectedClipId = clip.id;
      _undoStack.clear();
      _redoStack.clear();
      _sessionId = id;
      _posterPath = null;

      await _activateController(
        storedPath,
        clipId: clip.id,
        seekTarget: Duration.zero,
      );
      if (_activeController == null) {
        throw const MediaFormatException(
          'This video could not be opened. The file may be corrupted.',
        );
      }

      unawaited(_generatePoster(storedPath, info.duration));

      isLoadingProject = false;
      notifyListeners();
      unawaited(_loadThumbnailsFor(storedPath, info.duration));
      unawaited(_refreshRecent());
      // Persist right away so a freshly picked (still unedited) video is
      // resumable even if the app is killed before the first edit.
      _scheduleAutosave();
      return true;
    } on AppException catch (e) {
      projectError = e.userMessage;
    } catch (_) {
      projectError =
          'This video could not be opened. The file may be corrupted.';
    } finally {
      isLoadingProject = false;
      notifyListeners();
    }
    return false;
  }

  /// Picks another video and appends it as a new clip after the selected
  /// one (or at the end). Returns true on success.
  Future<bool> addVideoToTimeline() async {
    if (_project == null || isLoadingProject) return false;

    final String? path;
    try {
      path = await _picker.pickVideo();
    } on AppException catch (e) {
      actionError = e.userMessage;
      notifyListeners();
      return false;
    }
    if (path == null) return false; // user cancelled the picker

    // Reject duplicates BEFORE copying: the prospective media path is what
    // any existing clip would have claimed, so a file already on the
    // timeline can never be added a second time.
    final id = _sessionId;
    if (id == null) return false;
    final prospective = await _sessions.primaryMediaPath(id, path);
    if (_playerPool.containsKey(prospective) ||
        _project!.clips.any((c) => c.sourcePath == prospective)) {
      actionError = 'That video is already part of the timeline.';
      notifyListeners();
      return false;
    }

    isLoadingProject = true;
    notifyListeners();
    try {
      // Fail before copying large invalid media into the draft directory.
      final info = await _ffmpeg.probe(path);
      // Copy the added source into the session media folder so the saved
      // project references a stable local file.
      final storedPath = await _sessions.storeMedia(id, path);
      final clip = VideoClip(
        id: ClipId.next(),
        sourcePath: storedPath,
        sourceDuration: info.duration,
      );

      final before = _project!;
      final anchor = selectedIndex;
      final order = List.of(before.clips);
      order.insert(anchor >= 0 ? anchor + 1 : order.length, clip);
      _commitSnapshot(
        before.copy(),
        before.withClips(order),
      );
      _selectedClipId = clip.id;

      isLoadingProject = false;
      notifyListeners();
      unawaited(_loadThumbnailsFor(storedPath, info.duration));
      _scheduleAutosave();
      return true;
    } on AppException catch (e) {
      actionError = e.userMessage;
    } catch (_) {
      actionError = 'This video could not be added. The file may be corrupted.';
    } finally {
      isLoadingProject = false;
      notifyListeners();
    }
    return false;
  }

  void closeProject() {
    // Flush any pending edits before tearing the project down so the
    // session file always matches what the user last saw.
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    unawaited(_saveSessionNow());

    _movingPlayhead = false;
    _activeClipId = null;
    _selectedClipId = null;
    _activeController = null;
    unawaited(_resetMusicPlayer());
    _musicInsideWindow = false;
    _incomingClipId = null;
    _incomingSourcePath = null;
    _overlapBusy = false;
    _selectedTextId = null;
    textEditingSession = false;
    exportStage = null;
    exportStageNotifier.value = null;
    for (final controller in _playerPool.values) {
      controller.removeListener(_onControllerTick);
      controller.dispose();
    }
    _playerPool.clear();
    _pendingThumbSources.clear();
    _project = null;
    _sessionId = null;
    _posterPath = null;
    _undoStack.clear();
    _redoStack.clear();
    thumbnailStrips.value = const {};
    playbackPosition.value = Duration.zero;
    exportPhase = ExportPhase.idle;
    exportProgressValue.value = 0;
    lastExport = null;
    lastDelivery = null;
    exportError = null;
    actionError = null;
    isSavingProject = false;
    notifyListeners();
  }

  /// Renames the current draft and queues an immediate durable save. Names
  /// are intentionally capped so the app bar and recent-project list remain
  /// readable on compact devices.
  void renameProject(String value) {
    final project = _project;
    final name = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (project == null) return;
    if (name.isEmpty) {
      actionError = 'Enter a project name.';
      notifyListeners();
      return;
    }
    if (name == project.name) return;
    _project = project.renamed(
      name.length > 60 ? name.substring(0, 60) : name,
    );
    _scheduleAutosave();
    notifyListeners();
  }

  void clearActionError() {
    if (actionError == null) return;
    actionError = null;
    notifyListeners();
  }

  // -- Thumbnails ---------------------------------------------------------------

  static int thumbnailCountFor(Duration duration) {
    final byInterval =
        (duration.inMilliseconds / AppConstants.thumbnailIntervalMs).ceil();
    return byInterval.clamp(
      AppConstants.thumbnailMinPerSource,
      AppConstants.thumbnailMaxPerSource,
    );
  }

  Future<void> _loadThumbnailsFor(String sourcePath, Duration duration) async {
    if (!_pendingThumbSources.add(sourcePath)) return;

    thumbnailStrips.value = {...thumbnailStrips.value, sourcePath: const []};

    // Frames stream in one by one so the filmstrip fills progressively.
    final accumulated = <String>[];
    void publish() {
      if (!_pendingThumbSources.contains(sourcePath)) return;
      thumbnailStrips.value = {
        ...thumbnailStrips.value,
        sourcePath: List.of(accumulated),
      };
    }

    try {
      await _thumbnails.generate(
        videoPath: sourcePath,
        duration: duration,
        count: thumbnailCountFor(duration),
        onThumbnail: (path) {
          accumulated.add(path);
          publish();
        },
      );
      publish();
    } catch (_) {
      // Strip stays empty/partial; the timeline still works without frames.
    } finally {
      _pendingThumbSources.remove(sourcePath);
    }
  }

  Future<void> _generatePoster(String videoPath, Duration duration) async {
    final id = _sessionId;
    if (id == null) return;
    final poster = await _sessions.generatePoster(id, videoPath, duration);
    if (poster != null && poster != _posterPath) {
      _posterPath = poster;
      // Persist the new thumbnail into the session index so the Recent
      // tile reflects it even if the app is killed right after opening.
      _scheduleAutosave();
    }
  }

  // -- Background music preview ---------------------------------------------------

  /// Returns a controller for [path], creating it lazily. Any previous
  /// player for a different source is disposed.
  VideoPlayerController _ensureMusicController(String path) {
    var controller = _musicController;
    if (controller == null || _musicControllerPath != path) {
      unawaited(_resetMusicPlayer());
      controller = VideoPlayerController.file(File(path));
      _musicController = controller;
      _musicControllerPath = path;
    }
    return controller;
  }

  Future<void> _resetMusicPlayer() async {
    final controller = _musicController;
    _musicController = null;
    _musicControllerPath = null;
    if (controller != null) {
      try {
        await controller.pause();
      } catch (_) {}
      await controller.dispose();
    }
  }

  void _pauseMusic() {
    final controller = _musicController;
    if (controller != null && controller.value.isPlaying) {
      unawaited(controller.pause());
    }
  }

  /// Aligns the hidden music player with [projectPosition]. Called from
  /// playback entry points only (play/pause/seek/clip boundary) — there is
  /// deliberately no tick listener; drift beyond
  /// [AppConstants.musicSyncTolerance] is corrected at the next seek or
  /// boundary crossing instead.
  Future<void> _syncMusicWithPlayhead(
    Duration projectPosition,
    bool playing,
  ) async {
    final project = _project;
    if (project == null) return;
    final track = project.musicTrack;
    if (track == null) {
      await _resetMusicPlayer();
      return;
    }

    final windowEnd = track.timelineStart + track.sourceDuration;
    final insideWindow =
        projectPosition >= track.timelineStart && projectPosition < windowEnd;
    if (!insideWindow) {
      _pauseMusic();
      return;
    }

    final target = track.sourceStart + (projectPosition - track.timelineStart);
    final controller = _ensureMusicController(track.sourcePath);
    if (!controller.value.isInitialized) {
      try {
        await controller.initialize();
      } catch (_) {
        actionError = 'Background music could not be played.';
        notifyListeners();
        return;
      }
      await controller.seekTo(target);
    } else {
      final drift = (controller.value.position - target).abs();
      if (drift > AppConstants.musicSyncTolerance ||
          !controller.value.isPlaying) {
        await controller.seekTo(target);
      }
    }
    await controller.setVolume(track.volume);
    if (playing) {
      if (!controller.value.isPlaying) await controller.play();
    } else {
      _pauseMusic();
    }
  }

  // -- Playback -----------------------------------------------------------------

  void togglePlayPause() {
    if (isPlaying) {
      pause();
    } else {
      unawaited(play());
    }
  }

  Future<void> play() async {
    final project = _project;
    if (project == null || project.isEmpty || !isVideoInitialized) return;

    // Restart from the beginning when the sequence has finished.
    if (playbackPosition.value >= project.totalDuration) {
      await _movePlayhead(Duration.zero);
    }
    final controller = _activeController;
    if (controller != null) {
      await controller.play();
      if (controller.value.isPlaying) {
        _lastPlaying = true;
        _startPlaybackTimer();
        unawaited(_syncMusicWithPlayhead(playbackPosition.value, true));
      }
    }
    notifyListeners();
  }

  Future<void> pause() async {
    _stopPlaybackTimer();
    await _activeController?.pause();
    _pauseMusic();
    _lastPlaying = false;
    unawaited(_teardownIncoming());
    notifyListeners();
  }

  /// Seeks the PROJECT timeline to [position], landing on the covering
  /// clip's source timestamp. Playing state carries across the jump.
  Future<void> seekTo(Duration position) async {
    await _movePlayhead(position);
  }

  /// Positions the correct pooled controller for [position]. Switches
  /// sources transparently and preserves the playing/paused state, so the
  /// same primitive serves scrubbing, clip-boundary advances and restarts.
  /// Concurrent requests coalesce: the newest target wins.
  Future<void> _movePlayhead(Duration position) async {
    if (_movingPlayhead) {
      _queuedSeek = position;
      return;
    }
    _movingPlayhead = true;
    try {
      var target = position;
      while (true) {
        _queuedSeek = null;
        await _performMove(target);
        final queued = _queuedSeek;
        if (queued == null) break;
        target = queued;
      }
    } finally {
      _movingPlayhead = false;
    }
  }

  Future<void> _performMove(Duration position) async {
    final project = _project;
    if (project == null || project.isEmpty) return;

    // A seek cancels any crossfade in flight: the window phase no longer
    // matches where the incoming clip was cued.
    await _teardownIncoming();

    final clamped = clampDuration(
      position,
      Duration.zero,
      project.totalDuration,
    );
    final resolved = project.clipAt(clamped);

    // Project time -> OUTPUT-local offset -> absolute SOURCE timestamp.
    final sourceTarget = project.sourceOffsetFor(
      resolved.clip,
      resolved.localPosition,
    );
    final wasPlaying = _activeController?.value.isPlaying ?? false;

    final target = await _activateController(
      resolved.clip.sourcePath,
      clipId: resolved.clip.id,
      seekTarget: sourceTarget,
    );
    if (target == null) {
      // Activation failed (missing/corrupt file): stop instead of letting
      // the old controller drift through untrimmed footage.
      await _activeController?.pause();
      _pauseMusic();
      return;
    }
    if (wasPlaying && !target.value.isPlaying) {
      await target.play();
    }
    playbackPosition.value = clamped;
    unawaited(_syncMusicWithPlayhead(clamped, target.value.isPlaying));
  }

  /// Ensures a controller for [sourcePath] exists, marks it active and
  /// seeks it to [seekTarget]. Returns the controller, or null on failure.
  Future<VideoPlayerController?> _activateController(
    String sourcePath, {
    required String? clipId,
    required Duration seekTarget,
  }) async {
    // Removing + re-inserting existing entries refreshes their recency, so
    // eviction follows least-recent-USE rather than creation order.
    var controller = _playerPool.remove(sourcePath);
    if (controller == null) {
      controller = VideoPlayerController.file(File(sourcePath));
      try {
        await controller.initialize();
      } catch (_) {
        await controller.dispose();
        actionError =
            'This video could not be opened. '
            'The file may have been moved or deleted.';
        notifyListeners();
        return null;
      }
      controller.addListener(_onControllerTick);
    }
    _playerPool[sourcePath] = controller;

    final previous = _activeController;
    if (!identical(previous, controller)) {
      if (clipId != null) _activeClipId = clipId;
      await previous?.pause();
      _activeController = controller;
      notifyListeners();
    }

    if (controller.value.position != seekTarget) {
      await controller.seekTo(seekTarget);
    }

    // Pooled controllers serve many clips over their lifetime; reapply
    // THIS clip's rate and the project's original-audio volume on every
    // activation so stale values never leak between clips.
    final clip = clipId == null ? null : _clipById(clipId);
    await controller.setPlaybackSpeed(clip?.speed ?? 1.0);
    await controller.setVolume(_project?.originalAudioVolume ?? 1.0);

    // Evict only after the active pointer is settled so the freshly
    // activated controller can never be evicted by its own activation.
    _evictIdleControllers();
    return controller;
  }

  void _evictIdleControllers() {
    while (_playerPool.length > AppConstants.previewControllerPoolSize) {
      String? eldestKey;
      for (final key in _playerPool.keys) {
        if (key == _activeController?.dataSource) continue;
        if (key == _incomingSourcePath) continue; // mid-crossfade
        eldestKey = key;
        break;
      }
      if (eldestKey == null) break; // everything left is active

      final evicted = _playerPool.remove(eldestKey);
      evicted?.removeListener(_onControllerTick);
      evicted?.dispose();
    }
  }

  /// Mirrors the active player position into [playbackPosition] (converted
  /// to project time) and advances across clip boundaries while playing.
  void _onControllerTick() {
    if (_movingPlayhead) return;
    final controller = _activeController;
    final project = _project;
    if (controller == null || project == null || project.isEmpty) return;
    if (!identical(controller, _playerPool[controller.dataSource])) return;

    final playing = controller.value.isPlaying;
    if (playing) {
      if (_playbackTimer == null || !_playbackTimer!.isActive) {
        _startPlaybackTimer();
      }
    }
    if (playing != _lastPlaying) {
      _lastPlaying = playing;
      notifyListeners();
    }

    final clip = _clipById(_activeClipId);
    if (clip == null || clip.sourcePath != controller.dataSource) return;

    final sourcePosition = controller.value.position;

    // Advance to the next clip once the current one plays past its end.
    if (controller.value.isPlaying && sourcePosition >= clip.trimEnd) {
      final index = project.indexOf(clip.id);
      final next = index >= 0 && index + 1 < project.clips.length
          ? project.clips[index + 1]
          : null;
      if (next != null && _incomingClipId == next.id) {
        // Crossfade window just completed: the incoming clip is ALREADY
        // playing at the right spot — promote it instead of restarting it.
        unawaited(_promoteIncoming(next));
      } else if (next != null) {
        unawaited(_movePlayhead(project.startOf(next)));
      } else {
        // End of the sequence: halt cleanly at the last clip's out-point
        // instead of drifting into untrimmed source footage.
        unawaited(_haltAtSequenceEnd(controller, clip));
      }
      return;
    }

    final localSource = clampDuration(
      sourcePosition,
      Duration.zero,
      clip.trimmedDuration,
    );
    // SOURCE position -> OUTPUT-local offset -> project time. Output runs
    // FASTER than source for speed > 1 (effectiveDuration = trimmed/speed),
    // so the conversion divides — the exact inverse of [sourceOffsetFor].
    final localOutput = Duration(
      milliseconds: (localSource.inMilliseconds / clip.speed).round(),
    );
    playbackPosition.value = project.projectTimeOf(clip, localOutput);

    // Transition window: bring up / ramp down the incoming clip while the
    // playhead crosses [seam, coveredEnd).
    unawaited(
      _updateOverlapPlayback(
        clip,
        playbackPosition.value,
        controller.value.isPlaying,
      ),
    );

    // Fire music start/stop exactly once per crossing of its window;
    // drift INSIDE the window stays uncorrected until the next seek or
    // clip boundary.
    final track = project.musicTrack;
    final insideWindow =
        track != null &&
        playbackPosition.value >= track.timelineStart &&
        playbackPosition.value < track.timelineStart + track.sourceDuration;
    if (insideWindow != _musicInsideWindow) {
      _musicInsideWindow = insideWindow;
      if (insideWindow) {
        unawaited(_syncMusicWithPlayhead(playbackPosition.value, true));
      } else {
        _pauseMusic();
      }
    }
  }

  VideoClip? _clipById(String? id) {
    final project = _project;
    if (id == null || project == null) return null;
    final index = project.indexOf(id);
    return index >= 0 ? project.clips[index] : null;
  }

  Future<void> _haltAtSequenceEnd(
    VideoPlayerController controller,
    VideoClip clip,
  ) async {
    _stopPlaybackTimer();
    await controller.pause();
    _pauseMusic();
    _musicInsideWindow = false;
    _lastPlaying = false;
    if (controller.value.position > clip.trimEnd) {
      await controller.seekTo(clip.trimEnd);
    }
    playbackPosition.value = _project?.totalDuration ?? Duration.zero;
    notifyListeners();
  }

  // -- Phase 4: overlap (transition) preview ------------------------------------
  //
  // Flutter-side proxy of the exported xfade: while the playhead crosses a
  // transition window the INCOMING clip plays alongside the active one and
  // both controller volumes ramp in opposite directions. The visual blend
  // itself is composed by the widget layer from a phase notifier; audio
  // crossfades for real right here.

  /// Guards re-entrant preparation while the incoming player initializes.
  bool _overlapBusy = false;

  Future<void> _updateOverlapPlayback(
    VideoClip clip,
    Duration projectPosition,
    bool playing,
  ) async {
    final project = _project;
    if (project == null || playing != true) {
      await _teardownIncoming();
      return;
    }
    final index = project.indexOf(clip.id);
    if (index < 0 || index + 1 >= project.clips.length) {
      await _teardownIncoming();
      return;
    }

    final segments = project.layout.segments;
    final seg = segments[index];
    final inWindow =
        seg.overlapAfter > Duration.zero &&
        projectPosition >= seg.seam &&
        projectPosition < seg.coveredEnd;

    if (!inWindow) {
      await _teardownIncoming();
      return;
    }

    final next = project.clips[index + 1];
    if (_incomingClipId != next.id) {
      await _prepareIncoming(next, seg);
    }
    _rampOverlapVolumes(project, projectPosition, seg);
  }

  /// Brings [next] into the pool, seeks it to where the window phase says
  /// it should be and starts it muted — volume arrives via the ramp.
  Future<void> _prepareIncoming(VideoClip next, SegmentLayout seg) async {
    if (_overlapBusy) return;
    _overlapBusy = true;
    try {
      await _teardownIncoming();

      var controller = _playerPool.remove(next.sourcePath);
      if (controller == null) {
        controller = VideoPlayerController.file(File(next.sourcePath));
        try {
          await controller.initialize();
        } catch (_) {
          await controller.dispose();
          return;
        }
        controller.addListener(_onControllerTick);
      }
      _playerPool[next.sourcePath] = controller;

      final phaseMs = (playbackPosition.value - seg.seam).inMilliseconds.clamp(
        0,
        1 << 40,
      );
      final targetSource = clampDuration(
        next.trimStart + Duration(milliseconds: (phaseMs * next.speed).round()),
        next.trimStart,
        next.trimEnd,
      );
      if ((controller.value.position - targetSource).abs() >
          AppConstants.musicSyncTolerance) {
        await controller.seekTo(targetSource);
      }
      await controller.setVolume(0);
      await controller.play();

      _incomingClipId = next.id;
      _incomingSourcePath = next.sourcePath;
    } finally {
      _overlapBusy = false;
    }
  }

  void _rampOverlapVolumes(
    VideoProject project,
    Duration projectPosition,
    SegmentLayout seg,
  ) {
    final windowMs = seg.overlapAfter.inMilliseconds;
    if (windowMs <= 0) return;
    final phase = ((projectPosition - seg.seam).inMilliseconds / windowMs)
        .clamp(0.0, 1.0);
    final base = project.originalAudioVolume;
    unawaited(_activeController?.setVolume(base * (1 - phase)));
    final incoming = _incomingSourcePath == null
        ? null
        : _playerPool[_incomingSourcePath];
    unawaited(incoming?.setVolume(base * phase));
  }

  /// Stops the incoming clip and restores the active one's volume. Safe to
  /// call repeatedly and from every playback entry point.
  Future<void> _teardownIncoming() async {
    final path = _incomingSourcePath;
    _incomingClipId = null;
    _incomingSourcePath = null;
    final controller = path == null ? null : _playerPool[path];
    if (controller == null || identical(controller, _activeController)) {
      return;
    }
    unawaited(controller.pause());
    unawaited(controller.setVolume(_project?.originalAudioVolume ?? 1.0));
  }

  /// Hands playback over to the incoming clip at the END of a transition
  /// window: it is already positioned and running, so no seek happens —
  /// the outgoing side pauses and its volume resets.
  Future<void> _promoteIncoming(VideoClip next) async {
    final path = _incomingSourcePath;
    final controller = path == null ? null : _playerPool[path];
    final outgoing = _activeController;
    if (controller == null || !controller.value.isPlaying) {
      // Window broke down mid-flight; fall back to the plain advance.
      _incomingClipId = null;
      _incomingSourcePath = null;
      final project = _project;
      if (project != null) {
        unawaited(_movePlayhead(project.startOf(next)));
      }
      return;
    }

    await outgoing?.pause();
    unawaited(outgoing?.setVolume(_project?.originalAudioVolume ?? 1.0));
    _activeController = controller;
    _activeClipId = next.id;
    _incomingClipId = null;
    _incomingSourcePath = null;

    final sourceLocal = clampDuration(
      controller.value.position - next.trimStart,
      Duration.zero,
      next.trimmedDuration,
    );
    final project = _project;
    if (project != null) {
      playbackPosition.value = project.projectTimeOf(
        next,
        Duration(
          milliseconds: (sourceLocal.inMilliseconds / next.speed).round(),
        ),
      );
    }
    notifyListeners();
  }

  /// Clip sitting under the given project position (or null when empty).
  VideoClip? clipAtProjectTime(Duration position) {
    final project = _project;
    if (project == null || project.isEmpty) return null;
    return project.clipAt(position).clip;
  }

  /// Marks [clipId] as the target of subsequent edit operations.
  void selectClip(String clipId) {
    if (_selectedClipId == clipId) return;
    final project = _project;
    if (project == null || project.indexOf(clipId) < 0) return;
    _selectedClipId = clipId;
    notifyListeners();
  }

  /// Project-timeline position where the selected clip begins.
  Duration get selectedClipStart =>
      _selectedClip == null ? Duration.zero : _project!.startOf(_selectedClip!);

  VideoClip? get _selectedClip => selectedClip;

  /// Whether the playhead currently sits deep enough inside its clip for a
  /// legal split (both halves ≥ [AppConstants.minClipDuration]).
  bool canSplitAt(Duration projectPosition) {
    final project = _project;
    if (project == null || project.isEmpty) return false;
    final resolved = project.clipAt(
      clampDuration(projectPosition, Duration.zero, project.totalDuration),
    );
    final offset = resolved.localPosition;
    return offset >= AppConstants.minClipDuration &&
        resolved.clip.effectiveDuration - offset >=
            AppConstants.minClipDuration;
  }

  // -- Edit operations -----------------------------------------------------------

  /// Splits the clip under the playhead at the playhead position and
  /// selects the left half. Throws nothing; failures land in [actionError].
  void splitAtPlayhead() {
    final project = _project;
    if (project == null || project.isEmpty) return;

    final position = clampDuration(
      playbackPosition.value,
      Duration.zero,
      project.totalDuration,
    );
    final resolved = project.clipAt(position);

    try {
      // splitClip measures from the trim start in SOURCE time.
      final sourceOffset = clampDuration(
        resolved.localPosition * resolved.clip.speed,
        Duration.zero,
        resolved.clip.trimmedDuration,
      );
      final updated = project.splitClip(
        resolved.clip.id,
        sourceOffset,
        minSegment: AppConstants.minClipDuration,
      );
      _commitSnapshot(project.copy(), updated);
      _selectedClipId = resolved.clip.id; // left half keeps the id
      notifyListeners();
    } on ClipOperationException catch (e) {
      actionError = e.message;
      notifyListeners();
    }
  }

  /// Deletes the selected clip (never the last one) and selects a sensible
  /// neighbour. The playhead follows the removed region.
  void deleteSelectedClip() {
    final project = _project;
    final selected = selectedClip;
    if (project == null || selected == null) return;

    if (project.clips.length <= 1) {
      actionError = 'Cannot delete the only clip.';
      notifyListeners();
      return;
    }

    try {
      final removedStart = project.startOf(selected);
      final removedLength = selected.effectiveDuration;
      final position = playbackPosition.value;

      Duration newPosition;
      if (position < removedStart) {
        newPosition = position; // before the removed clip: unaffected
      } else if (position <= removedStart + removedLength) {
        newPosition = removedStart; // inside: park at the seam
      } else {
        newPosition = position - removedLength; // after: shift left
      }

      final index = project.indexOf(selected.id);
      final updated = project.removeClip(selected.id);
      _commitSnapshot(project.copy(), updated);

      // Prefer the previous clip, fall back to the following one.
      final neighbourIndex = index > 0 ? index - 1 : 0;
      final remaining = updated.clips;
      _selectedClipId =
          remaining[neighbourIndex.clamp(0, remaining.length - 1)].id;

      playbackPosition.value = clampDuration(
        newPosition,
        Duration.zero,
        updated.totalDuration,
      );
      unawaited(_syncActiveClipWithPlayhead());
      notifyListeners();
    } on ClipOperationException catch (e) {
      actionError = e.message;
      notifyListeners();
    }
  }

  /// Reorders clips ([oldIndex] → [newIndex], ReorderableListView
  /// semantics). Pauses playback and keeps the moved clip selected.
  void reorderClips(int oldIndex, int newIndex) {
    final project = _project;
    if (project == null) return;
    if (oldIndex < 0 || oldIndex >= project.clips.length) return;

    pause();
    final movedId = project.clips[oldIndex].id;
    final reordered = project.reordered(oldIndex, newIndex);
    if (identical(reordered, project)) return;

    _commitSnapshot(project.copy(), reordered);
    _selectedClipId = movedId;
    playbackPosition.value = clampDuration(
      playbackPosition.value,
      Duration.zero,
      _project!.totalDuration,
    );
    unawaited(_syncActiveClipWithPlayhead());
    notifyListeners();
  }

  /// Applies a trim to the SELECTED clip. Live-updates during drags; wrap
  /// gestures/dialogs with [pushUndoSnapshot] for a single history entry.
  void setTrim({Duration? start, Duration? end}) {
    final project = _project;
    final selected = selectedClip;
    if (project == null || selected == null) return;

    var newStart = clampDuration(
      start ?? selected.trimStart,
      Duration.zero,
      selected.sourceDuration,
    );
    var newEnd = clampDuration(
      end ?? selected.trimEnd,
      Duration.zero,
      selected.sourceDuration,
    );

    if (newEnd - newStart < AppConstants.minTrimGap) {
      // Push whichever edge did not move so the minimum gap is preserved.
      if (newStart != selected.trimStart) {
        newStart = newEnd - AppConstants.minTrimGap;
      } else {
        newEnd = newStart + AppConstants.minTrimGap;
      }
    }
    if (newStart < Duration.zero ||
        newEnd > selected.sourceDuration ||
        newEnd <= newStart) {
      return;
    }

    try {
      _project = project.withTrim(
        selected.id,
        trimStart: newStart,
        trimEnd: newEnd,
        minSegment: AppConstants.minClipDuration,
      );
      _scheduleAutosave();
    } on ClipOperationException {
      return;
    }

    final controller = _activeController;
    if (controller != null &&
        controller.dataSource == selected.sourcePath &&
        !_selectedClipContains(controller.value.position)) {
      unawaited(controller.seekTo(newStart));
    }
    playbackPosition.value = clampDuration(
      playbackPosition.value,
      Duration.zero,
      _project!.totalDuration,
    );
    notifyListeners();
  }

  bool _selectedClipContains(Duration sourcePosition) {
    final selected = selectedClip;
    if (selected == null) return false;
    return sourcePosition >= selected.trimStart &&
        sourcePosition <= selected.trimEnd;
  }

  void resetTrim() {
    setTrim(start: Duration.zero, end: sourceDuration);
  }

  /// Restores an exact range (e.g. cancelling the trim dialog), bypassing
  /// minimum-gap adjustment.
  void resetTrimValues({required Duration start, required Duration end}) {
    final project = _project;
    final selected = selectedClip;
    if (project == null || selected == null) return;
    try {
      _project = project.withTrim(
        selected.id,
        trimStart: clampDuration(start, Duration.zero, selected.sourceDuration),
        trimEnd: clampDuration(end, Duration.zero, selected.sourceDuration),
        minSegment: Duration.zero,
      );
      _scheduleAutosave();
    } on ClipOperationException {
      return;
    }
    final controller = _activeController;
    if (controller != null &&
        controller.dataSource == selected.sourcePath &&
        !_selectedClipContains(controller.value.position)) {
      unawaited(controller.seekTo(selected.trimStart));
    }
    notifyListeners();
  }

  // -- Speed ----------------------------------------------------------------------

  /// Live speed mutation used while the speed selector is open. No history
  /// entry; the sheet registers one snapshot on confirmation so the whole
  /// interaction collapses into a single undo step.
  void applyClipSpeedLive(String clipId, double speed) {
    final project = _project;
    if (project == null) return;
    final clamped = speed.clamp(
      AppConstants.minPlaybackSpeed,
      AppConstants.maxPlaybackSpeed,
    );

    final controller = _activeController;
    final isActiveClip = controller != null && _activeClipId == clipId;

    try {
      _project = project.withSpeed(clipId, clamped);
      _scheduleAutosave();
    } on ClipOperationException {
      return;
    }

    if (isActiveClip) {
      final clip = _clipById(clipId);
      unawaited(controller.setPlaybackSpeed(clamped));
      if (clip != null) {
        // Preserve what is on screen: hold the controller's source
        // timestamp fixed and recompute where it lands in project time.
        final sourceLocal = clampDuration(
          controller.value.position - clip.trimStart,
          Duration.zero,
          clip.trimmedDuration,
        );
        final localOutput = Duration(
          milliseconds: (sourceLocal.inMilliseconds / clamped).round(),
        );
        playbackPosition.value = _project!.projectTimeOf(clip, localOutput);
      }
    } else {
      playbackPosition.value = clampDuration(
        playbackPosition.value,
        Duration.zero,
        _project!.totalDuration,
      );
    }
    notifyListeners();
  }

  /// Commits a speed change as a discrete undoable step.
  void updateClipSpeed(String clipId, double speed) {
    pushUndoSnapshot();
    applyClipSpeedLive(clipId, speed);
  }

  // -- Visual look (Phase 4) ------------------------------------------------------

  /// Live transform mutation while the crop/rotate sheet is open. No
  /// history entry; the sheet registers one snapshot on confirmation.
  void updateTransformLive(String clipId, VideoTransform value) {
    final project = _project;
    if (project == null) return;
    try {
      _project = project.withTransform(clipId, value);
      _scheduleAutosave();
    } on ClipOperationException {
      return;
    }
    _clampPlayheadToProject();
    notifyListeners();
  }

  void commitTransform(String clipId, VideoTransform value) {
    pushUndoSnapshot();
    updateTransformLive(clipId, value);
  }

  /// Live filter preset while the filter selector is open.
  void updateFilterLive(String clipId, VideoFilter value) {
    final project = _project;
    if (project == null) return;
    try {
      _project = project.withFilter(clipId, value);
      _scheduleAutosave();
    } on ClipOperationException {
      return;
    }
    notifyListeners();
  }

  void commitFilter(String clipId, VideoFilter value) {
    pushUndoSnapshot();
    updateFilterLive(clipId, value);
  }

  /// Live color adjustments while the adjustment panel is open. Channels
  /// are clamped defensively even though UI sliders are bounded.
  void updateAdjustmentsLive(String clipId, VideoAdjustments value) {
    final project = _project;
    if (project == null) return;
    final clamped = VideoAdjustments(
      brightness: VideoAdjustments.clamp(value.brightness),
      contrast: VideoAdjustments.clamp(value.contrast),
      saturation: VideoAdjustments.clamp(value.saturation),
      temperature: VideoAdjustments.clamp(value.temperature),
    );
    try {
      _project = project.withAdjustments(clipId, clamped);
      _scheduleAutosave();
    } on ClipOperationException {
      return;
    }
    notifyListeners();
  }

  void commitAdjustments(String clipId, VideoAdjustments value) {
    pushUndoSnapshot();
    updateAdjustmentsLive(clipId, value);
  }

  /// Restores crop/rotate/flip/filter/adjustments of the SELECTED clip to
  /// defaults as one discrete undo step (plan §15). Trim/speed untouched.
  void resetSelectedClipVisuals() {
    final project = _project;
    final selected = selectedClip;
    if (project == null || selected == null) return;
    if (selected.transform.isIdentity &&
        selected.filter == VideoFilter.none &&
        selected.adjustments.isNeutral) {
      return; // nothing to do — no empty history entry
    }
    _commitSnapshot(project.copy(), project.resetVisuals(selected.id));
    notifyListeners();
  }

  // -- Transitions (Phase 4) --------------------------------------------------------

  /// Raw transition stored AFTER [clipId] (its right seam), or null when
  /// none/inert.
  ClipTransition? transitionAfter(String clipId) =>
      _project?.transitionAfter(clipId);

  /// Whether a successor exists to blend into — the transition UI gates on it.
  bool hasSuccessorFor(String clipId) {
    final project = _project;
    if (project == null) return false;
    final index = project.indexOf(clipId);
    return index >= 0 && index + 1 < project.clips.length;
  }

  /// Raw transition stored AFTER the selected clip (its right seam), or
  /// null when none/inert.
  ClipTransition? get transitionAfterSelected {
    final selectedId = _selectedClipId;
    return selectedId == null ? null : _project?.transitionAfter(selectedId);
  }

  /// Effective overlap of the selected clip's right seam under current
  /// neighbour durations — what the timeline and export actually use.
  Duration get effectiveTransitionAfterSelected {
    final project = _project;
    final index = selectedIndex;
    if (project == null || index < 0 || index + 1 >= project.clips.length) {
      return Duration.zero;
    }
    return project.layout.segments[index].overlapAfter;
  }

  /// Largest overlap the selected clip's right seam can support; bounds
  /// duration pickers in the transition sheet.
  Duration get maxTransitionAfterSelected {
    final project = _project;
    final index = selectedIndex;
    if (project == null || index < 0 || index + 1 >= project.clips.length) {
      return Duration.zero;
    }
    final segments = project.layout.segments;
    return AppConstants.maxTransitionDuration(
      segments[index].effectiveDuration,
      segments[index + 1].effectiveDuration,
    );
  }

  /// Sets/clears the transition after [clipId] as one discrete undo step.
  /// Durations are stored raw and clamped by the resolver, so trimming a
  /// neighbour later never breaks the timeline.
  void setTransitionAfter(String clipId, ClipTransition transition) {
    final project = _project;
    if (project == null) return;
    try {
      _commitSnapshot(
        project.copy(),
        project.upsertTransition(clipId, transition),
      );
    } on ClipOperationException catch (e) {
      actionError = e.message;
    }
    notifyListeners();
  }

  /// Live transition mutation while the selector sheet is open. No history
  /// entry; the sheet registers its baseline snapshot on Apply.
  void setTransitionAfterLive(String clipId, ClipTransition transition) {
    final project = _project;
    if (project == null) return;
    try {
      _project = project.upsertTransition(clipId, transition);
      _scheduleAutosave();
    } on ClipOperationException {
      return;
    }
    notifyListeners();
  }

  // -- Output aspect ratio (Phase 4) ---------------------------------------------

  String? get outputAspectRatio => _project?.outputAspectRatio;

  void setOutputAspectRatio(String? ratio) {
    final project = _project;
    if (project == null) return;
    try {
      final updated = project.withOutputAspectRatio(ratio);
      if (!identical(updated, project)) {
        _commitSnapshot(project.copy(), updated);
        notifyListeners();
      }
    } on ClipOperationException catch (e) {
      actionError = e.message;
      notifyListeners();
    }
  }

  void _clampPlayheadToProject() {
    final project = _project;
    if (project == null) return;
    playbackPosition.value = clampDuration(
      playbackPosition.value,
      Duration.zero,
      project.totalDuration,
    );
  }

  // -- Volumes --------------------------------------------------------------------

  /// Live original-audio volume while the volume sheet is open. No history
  /// entry; the sheet registers the snapshot on confirmation.
  void setOriginalAudioVolumeLive(double volume) {
    final project = _project;
    if (project == null) return;
    final clamped = volume.clamp(0.0, AppConstants.maxAudioVolume);
    _project = project.withOriginalAudioVolume(clamped);
    _scheduleAutosave();
    final controller = _activeController;
    if (controller != null) {
      unawaited(controller.setVolume(clamped));
    }
    notifyListeners();
  }

  /// Live music volume while the volume sheet is open.
  void setMusicVolumeLive(double volume) {
    final project = _project;
    final track = project?.musicTrack;
    if (project == null || track == null) return;
    final clamped = volume.clamp(0.0, AppConstants.maxAudioVolume);
    _project = project.upsertAudioTrack(track.copyWith(volume: clamped));
    _scheduleAutosave();
    final controller = _musicController;
    if (controller != null && controller.value.isInitialized) {
      unawaited(controller.setVolume(clamped));
    }
    notifyListeners();
  }

  // -- Background music -------------------------------------------------------------

  /// Picks an audio file and lays it over the timeline starting at zero.
  /// Replaces any existing track. Returns true on success.
  Future<bool> addMusicFromPicker() async {
    final project = _project;
    if (project == null || isLoadingProject) return false;

    final String? path;
    try {
      path = await _picker.pickAudio();
    } on AppException catch (e) {
      actionError = e.userMessage;
      notifyListeners();
      return false;
    }
    if (path == null) return false;

    isLoadingProject = true;
    notifyListeners();
    try {
      // Copy the picked audio into the session media folder so the saved
      // project keeps a valid music source for up to two days.
      final id = _sessionId;
      if (id == null) throw const MediaFormatException();
      final storedPath = await _sessions.storeMedia(id, path);

      final info = await _ffmpeg.probe(storedPath);
      final track = AudioTrack(
        id: OverlayId.next('music'),
        sourcePath: storedPath,
        sourceStart: Duration.zero,
        sourceEnd: info.duration > Duration.zero
            ? info.duration
            : const Duration(seconds: 30),
      );
      _commitSnapshot(project.copy(), project.upsertAudioTrack(track));
      await _resetMusicPlayer();
      _musicInsideWindow = false;
      isLoadingProject = false;
      notifyListeners();
      return true;
    } on AppException catch (e) {
      actionError = e.userMessage;
    } catch (_) {
      actionError = 'This audio file could not be used as music.';
    } finally {
      isLoadingProject = false;
      notifyListeners();
    }
    return false;
  }

  /// Removes the music track entirely (one undo step).
  void removeMusic() {
    final project = _project;
    final track = project?.musicTrack;
    if (project == null || track == null) return;
    _commitSnapshot(project.copy(), project.withoutAudioTrack(track.id));
    unawaited(_resetMusicPlayer());
    _musicInsideWindow = false;
    notifyListeners();
  }

  // -- Text overlays ----------------------------------------------------------------

  /// Inserts a default overlay at the playhead, selects it and returns it
  /// so the caller can open the editor immediately.
  TextOverlay? addTextOverlay() {
    final project = _project;
    if (project == null || project.isEmpty) return null;

    final total = project.totalDuration;
    final desired = AppConstants.defaultTextOverlayDuration;
    final windowLength = desired > total ? total : desired;
    var start = clampDuration(playbackPosition.value, Duration.zero, total);
    if (start + windowLength > total) {
      start = total - windowLength;
    }

    final overlay = TextOverlay(
      id: OverlayId.next('text'),
      text: 'Text',
      startTime: start,
      endTime: start + windowLength,
    );
    _commitSnapshot(project.copy(), project.upsertTextOverlay(overlay));
    _selectedTextId = overlay.id;
    notifyListeners();
    return overlay;
  }

  /// Live overlay replacement while its editor sheet is open. No history
  /// entry; the sheet registers the snapshot on confirmation.
  void updateTextOverlayLive(TextOverlay overlay) {
    final project = _project;
    if (project == null) return;
    if (!project.textOverlays.any((o) => o.id == overlay.id)) return;
    _project = project.upsertTextOverlay(overlay);
    _scheduleAutosave();
    notifyListeners();
  }

  /// Live reposition from the preview drag layer (normalized 0..1).
  void updateTextPosition(String id, double x, double y) {
    final project = _project;
    if (project == null) return;
    final index = project.textOverlays.indexWhere((o) => o.id == id);
    if (index < 0) return;
    final current = project.textOverlays[index];
    final nx = x.clamp(0.0, 1.0);
    final ny = y.clamp(0.0, 1.0);
    if (nx == current.x && ny == current.y) return;
    _project = project.upsertTextOverlay(current.copyWith(x: nx, y: ny));
    _scheduleAutosave();
    notifyListeners();
  }

  void selectText(String? id) {
    if (_selectedTextId == id) return;
    final project = _project;
    if (id != null &&
        (project == null || !project.textOverlays.any((o) => o.id == id))) {
      return;
    }
    _selectedTextId = id;
    notifyListeners();
  }

  void setTextEditingSession(bool active) {
    if (textEditingSession == active) return;
    textEditingSession = active;
    notifyListeners();
  }

  /// Deletes the selected overlay (one undo step).
  void deleteSelectedText() {
    final project = _project;
    final selected = selectedText;
    if (project == null || selected == null) return;
    _commitSnapshot(project.copy(), project.withoutTextOverlay(selected.id));
    _selectedTextId = null;
    notifyListeners();
  }

  /// Repositions whichever controller should be live after structural edits
  /// (delete/reorder/undo) changed what sits under the playhead.
  Future<void> _syncActiveClipWithPlayhead() async {
    final project = _project;
    if (project == null || project.isEmpty) return;
    final position = clampDuration(
      playbackPosition.value,
      Duration.zero,
      project.totalDuration,
    );
    playbackPosition.value = position;
    await _movePlayhead(position);
  }

  void _adoptProject(VideoProject restored) {
    _project = restored;
    if (_selectedClipId == null || restored.indexOf(_selectedClipId!) < 0) {
      _selectedClipId = restored.isNotEmpty ? restored.clips.first.id : null;
    }
    if (_selectedTextId != null &&
        !restored.textOverlays.any((o) => o.id == _selectedTextId)) {
      _selectedTextId = null;
    }
    // Undo across a music edit swaps the source file underneath the
    // hidden player (or drops the track entirely); discard it and let the
    // next sync rebuild whatever the restored project needs.
    final track = restored.musicTrack;
    if (track == null || _musicControllerPath != track.sourcePath) {
      unawaited(_resetMusicPlayer());
    }
    _musicInsideWindow = false;
    playbackPosition.value = clampDuration(
      playbackPosition.value,
      Duration.zero,
      restored.totalDuration,
    );
    unawaited(_syncActiveClipWithPlayhead());
    _scheduleAutosave();
  }

  // -- Export --------------------------------------------------------------------

  Future<void> _loadSaveSettings() async {
    try {
      saveDestination = await _destinations.loadDestination();
      final folder = await _destinations.loadSavedFolder();
      savedFolderUri = folder?.uri;
      savedFolderName = folder?.name;
      notifyListeners();
    } catch (_) {
      // Defaults stay active when settings storage is unavailable.
    }
  }

  Future<void> _initSessions() async {
    try {
      final sessions = await _sessions.listRecent();
      if (_disposed) return;
      recentSessions.value = sessions;
      notifyListeners();
    } catch (_) {
      // Session storage unavailable; run without persistence.
    }
  }

  /// Queues an autosave that fires ~1.5s after the last change, so rapid
  /// edits coalesce into a single disk write.
  void _scheduleAutosave() {
    final id = _sessionId;
    if (id == null) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 1500), () {
      _autosaveTimer = null;
      _saveSessionNow();
    });
  }

  Future<void> _saveSessionNow() async {
    final id = _sessionId;
    final project = _project;
    // Capture the poster NOW; closeProject() clears the field right after
    // kicking off the final flush, so the in-flight save must not read it
    // lazily or the closing session would lose its thumbnail.
    final poster = _posterPath;
    if (id == null || project == null) return;
    // Serialize writes: each save chains after the previous one, always
    // persisting the newest snapshot, so rapid triggers can never reorder.
    isSavingProject = true;
    notifyListeners();
    final previous = _autosaveInFlight;
    final save = (previous ?? Future.value()).then(
      (_) => _doSaveSession(id, project, posterPath: poster),
    );
    _autosaveInFlight = save;
    try {
      await save;
    } catch (_) {}
    // A newer save may already be queued while this one completes. Only the
    // newest operation is allowed to clear the visible saving state.
    if (!_disposed && identical(_autosaveInFlight, save)) {
      isSavingProject = false;
      notifyListeners();
    }
  }

  Future<void> _doSaveSession(
    String id,
    VideoProject project, {
    String? posterPath,
  }) async {
    try {
      final record = await _sessions.saveProject(
        id,
        project,
        posterPath: posterPath,
      );
      if (_disposed) return;
      recentSessions.value = [
        record,
        ...recentSessions.value.where((r) => r.id != id),
      ];
      notifyListeners();
    } catch (_) {
      // Autosave failures are non-fatal; the in-memory project still works.
    }
  }

  /// Restores the most recent active session (if any exists and is not
  /// expired) and hands control back to [onRestored]. Returns the restored
  /// project id, or null when there is nothing to resume.
  Future<String?> restoreActiveSession() async {
    if (isRestoring) return null;
    try {
      final active = await _sessions.activeSession();
      if (active == null) return null;

      isRestoring = true;
      notifyListeners();
      try {
        final project = await _sessions.loadProject(active.id);
        if (project == null || project.isEmpty) {
          await _sessions.deleteSession(active.id);
          await _refreshRecent();
          return null;
        }
        final restored = await _openRestoredProject(active.id, project);
        if (!restored) {
          await _sessions.deleteSession(active.id);
          await _refreshRecent();
          return null;
        }
        return active.id;
      } finally {
        isRestoring = false;
        notifyListeners();
      }
    } catch (_) {
      // Storage failures must never crash the launch; fall back to home.
      return null;
    }
  }

  Future<void> _refreshRecent() async {
    try {
      final sessions = await _sessions.listRecent();
      if (_disposed) return;
      recentSessions.value = sessions;
      notifyListeners();
    } catch (_) {}
  }

  /// Deletes a saved session and its media.
  Future<void> deleteRecentSession(String id) async {
    if (id == _sessionId) {
      closeProject();
    }
    await _sessions.deleteSession(id);
    await _refreshRecent();
  }

  /// Opens a saved session from the Recent list (an explicit tap).
  Future<bool> openRecentSession(String id) async {
    if (isLoadingProject) return false;
    try {
      final project = await _sessions.loadProject(id);
      if (project == null || project.isEmpty) return false;
      final ok = await _openRestoredProject(id, project);
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Rebuilds the live project + players from a saved session, mirroring
  /// what [openVideo] does for a freshly picked file.
  Future<bool> _openRestoredProject(String id, VideoProject project) async {
    closeProject();
    isLoadingProject = true;
    projectError = null;
    notifyListeners();

    try {
      if (project.isEmpty) return false;

      _sessionId = id;
      _posterPath = await _sessions
          .sessionDir(id)
          .then((d) => '${d.path}/poster.jpg');

      // Activate the FIRST clip's controller; the playhead restore logic in
      // the editor seeks to the saved position on first tick.
      final first = project.clips.first;
      await _activateController(
        first.sourcePath,
        clipId: first.id,
        seekTarget: Duration.zero,
      );
      if (_activeController == null) return false;

      _project = project;
      _selectedClipId = first.id;
      _undoStack.clear();
      _redoStack.clear();
      playbackPosition.value = Duration.zero;

      isLoadingProject = false;
      notifyListeners();

      for (final clip in project.clips) {
        unawaited(_loadThumbnailsFor(clip.sourcePath, clip.sourceDuration));
      }
      _scheduleAutosave();
      await _refreshRecent();
      return true;
    } finally {
      isLoadingProject = false;
      notifyListeners();
    }
  }

  Future<void> setSaveDestination(SaveDestination destination) async {
    if (saveDestination == destination) return;
    saveDestination = destination;
    notifyListeners();
    unawaited(_destinations.setDestination(destination));

    // First time on "Device folder": open the picker right away so the user
    // never exports without a real folder behind the choice.
    if (destination == SaveDestination.folder && savedFolderUri == null) {
      await chooseSaveFolder();
    }
  }

  /// Opens the system directory picker and remembers the choice.
  /// Returns false when the user cancels.
  Future<bool> chooseSaveFolder() async {
    final picked = await _destinations.pickFolder(initialUri: savedFolderUri);
    if (picked == null) return false;
    savedFolderUri = picked.uri;
    savedFolderName = picked.name;
    if (saveDestination != SaveDestination.folder) {
      saveDestination = SaveDestination.folder;
      unawaited(_destinations.setDestination(SaveDestination.folder));
    }
    notifyListeners();
    return true;
  }

  Future<void> startExport({
    required ExportResolution resolution,
    required ExportQuality quality,
  }) async {
    final project = _project;
    if (project == null || project.isEmpty) return;
    if (exportPhase == ExportPhase.exporting) return;

    pause();
    exportPhase = ExportPhase.exporting;
    exportError = null;
    lastExport = null;
    lastDelivery = null;
    exportProgressValue.value = 0;
    exportStage = null;
    exportStageNotifier.value = null;
    notifyListeners();

    try {
      lastExport = await _exporter.renderProject(
        project: project,
        resolution: resolution,
        quality: quality,
        onProgress: (value) => exportProgressValue.value = value,
        onStage: (label) {
          exportStage = label;
          exportStageNotifier.value = label;
        },
      );
      exportProgressValue.value = 1;
      // Delivery may surface system UI (save dialog / permission prompt);
      // the sheet stays in the exporting phase until it resolves.
      await _deliver();
      exportPhase = ExportPhase.success;
    } on ExportCancelledException {
      exportPhase = ExportPhase.idle;
      exportProgressValue.value = 0;
    } on AppException catch (e) {
      exportError = e.userMessage;
      exportPhase = ExportPhase.failed;
    } catch (_) {
      exportError =
          'Something went wrong while exporting. Check free storage space '
          'and try again.';
      exportPhase = ExportPhase.failed;
    }
    notifyListeners();
  }

  Future<void> _deliver() async {
    if (_delivering || lastExport == null) return;
    _delivering = true;
    try {
      lastDelivery = await _destinations.deliver(
        filePath: lastExport!.outputPath,
        destination: saveDestination,
      );
    } catch (_) {
      lastDelivery = const DeliveryResult(status: DeliveryStatus.failed);
    } finally {
      _delivering = false;
    }
  }

  /// Re-runs delivery for the current render (e.g. after a cancelled or
  /// failed save attempt). No-ops when there is nothing to deliver.
  Future<void> redeliver() async {
    if (lastExport == null ||
        exportPhase != ExportPhase.success ||
        _delivering) {
      return;
    }
    notifyListeners();
    await _deliver();
    notifyListeners();
  }

  void cancelExport() => _exporter.cancel();

  void dismissExportSheet() {
    if (exportPhase == ExportPhase.exporting) return;
    exportPhase = ExportPhase.idle;
    exportProgressValue.value = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPlaybackTimer();
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    unawaited(_saveSessionNow());
    unawaited(_sessions.dispose());
    final music = _musicController;
    _musicController = null;
    _musicControllerPath = null;
    if (music != null) {
      unawaited(music.dispose());
    }
    _activeController = null;
    _incomingClipId = null;
    _incomingSourcePath = null;
    for (final controller in _playerPool.values) {
      controller.removeListener(_onControllerTick);
      controller.dispose();
    }
    _playerPool.clear();
    thumbnailStrips.dispose();
    playbackPosition.dispose();
    exportProgressValue.dispose();
    recentSessions.dispose();
    super.dispose();
  }
}
