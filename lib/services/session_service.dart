import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/video_project.dart';
import 'ffmpeg_service.dart';

/// Lifetime of an editing session / recent entry before it is purged.
const Duration sessionLifetime = Duration(days: 2);

/// A single saved editing session (a draft project plus its copied media).
class SessionRecord {
  const SessionRecord({
    required this.id,
    required this.name,
    required this.lastOpenedAt,
    this.posterPath,
    this.clipCount = 0,
    this.totalMs = 0,
  });

  final String id;
  final String name;
  final DateTime lastOpenedAt;
  final String? posterPath;
  final int clipCount;
  final int totalMs;

  bool get isExpired =>
      DateTime.now().difference(lastOpenedAt) > sessionLifetime;

  Map<String, dynamic> toDbMap() => {
    'id': id,
    'name': name,
    'posterPath': posterPath,
    'lastOpenedAt': lastOpenedAt.millisecondsSinceEpoch,
    'clipCount': clipCount,
    'totalMs': totalMs,
  };

  static SessionRecord fromDbMap(Map<String, dynamic> row) => SessionRecord(
    id: row['id'] as String,
    name: row['name'] as String? ?? 'Project',
    posterPath: row['posterPath'] as String?,
    lastOpenedAt: DateTime.fromMillisecondsSinceEpoch(
      row['lastOpenedAt'] as int? ?? 0,
    ),
    clipCount: row['clipCount'] as int? ?? 0,
    totalMs: row['totalMs'] as int? ?? 0,
  );
}

/// Persists editing sessions across app launches.
///
/// Each session lives in a project directory under the app documents dir:
///   `.../sessions/<id>/project.json` - serialized [VideoProject]
///   `.../sessions/<id>/media/`       - copies of source video/audio
///   `.../sessions/<id>/poster.jpg`   - first-clip thumbnail for the Recent list
///
/// A SQLite database indexes every session (id, name, poster, timestamps) so
/// the Recent list can be queried without reading project JSON. Sessions older
/// than [sessionLifetime] are pruned along with their media.
class SessionService {
  SessionService({FFmpegService? ffmpeg}) : _ffmpeg = ffmpeg ?? FFmpegService();

  final FFmpegService _ffmpeg;

  Database? _db;
  Directory? _root;

  Future<Directory> _rootDir() async {
    return _root ??= Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'sessions'),
    );
  }

  Future<Database> _database() async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), 'video_editor_sessions.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            posterPath TEXT,
            lastOpenedAt INTEGER NOT NULL,
            clipCount INTEGER NOT NULL DEFAULT 0,
            totalMs INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
    return _db!;
  }

  Future<Directory> sessionDir(String id) async {
    final root = await _rootDir();
    final dir = Directory(p.join(root.path, id));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> mediaDir(String id) async {
    final dir = Directory(p.join((await sessionDir(id)).path, 'media'));
    await dir.create(recursive: true);
    return dir;
  }

  String _ext(String sourcePath) => p.extension(sourcePath).toLowerCase();
  static const Set<String> _videoExt = {
    '.mp4',
    '.mov',
    '.m4v',
    '.mkv',
    '.avi',
    '.webm',
    '.3gp',
  };
  static const Set<String> _audioExt = {
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.ogg',
    '.flac',
    '.opus',
  };
  static const Set<String> _safeExt = {..._videoExt, ..._audioExt};

  String _extFor(String src) {
    final e = _ext(src);
    final name = p.basename(src);
    final base = name.contains('.')
        ? name.substring(0, name.lastIndexOf('.'))
        : name;
    final safeBase = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final safeE = e.isNotEmpty && _safeExt.contains(e) ? e : '.bin';
    return '$safeBase$safeE';
  }

  /// Primary destination a fresh copy of [sourcePath] would get in this
  /// session's media folder (no collision suffix).
  Future<String> primaryMediaPath(String projectId, String sourcePath) async {
    final dir = await mediaDir(projectId);
    return p.join(dir.path, _extFor(sourcePath));
  }

  /// Copies [sourcePath] (a picked video or audio file) into this session's
  /// media folder so the saved session remains valid for up to two days.
  /// Returns the destination path. Re-adds of same-named files get a
  /// numeric suffix so existing clips are never silently overwritten.
  Future<String> storeMedia(String projectId, String sourcePath) async {
    final dir = await mediaDir(projectId);
    final base = _extFor(sourcePath);
    var destPath = p.join(dir.path, base);
    var index = 1;
    while (File(destPath).existsSync()) {
      destPath = p.join(
        dir.path,
        p.setExtension(base, '_$index${p.extension(base)}'),
      );
      index += 1;
    }
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  /// Saves [project] as session [projectId]. Writes project.json and updates
  /// the index. Returns the record that was stored.
  Future<SessionRecord> saveProject(
    String projectId,
    VideoProject project, {
    String? posterPath,
  }) async {
    final dir = await sessionDir(projectId);
    final file = File(p.join(dir.path, 'project.json'));
    await file.writeAsString(jsonEncode(project.toJson()));

    final totalMs = project.isEmpty ? 0 : project.totalDuration.inMilliseconds;
    final record = SessionRecord(
      id: projectId,
      name: project.name,
      lastOpenedAt: DateTime.now(),
      posterPath: posterPath,
      clipCount: project.clips.length,
      totalMs: totalMs,
    );

    final db = await _database();
    await db.insert(
      'sessions',
      record.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return record;
  }

  /// Loads the serialized project for [projectId], or null when missing.
  Future<VideoProject?> loadProject(String projectId) async {
    final dir = await sessionDir(projectId);
    final file = File(p.join(dir.path, 'project.json'));
    if (!file.existsSync()) return null;
    try {
      return VideoProject.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Extracts a single poster frame for the given video into the session
  /// folder and returns its path (or null on failure).
  Future<String?> generatePoster(
    String projectId,
    String videoPath,
    Duration duration,
  ) async {
    final dir = await sessionDir(projectId);
    final posterPath = p.join(dir.path, 'poster.jpg');
    try {
      await _ffmpeg.extractFrames(
        inputPath: videoPath,
        outputDirectory: dir.path,
        duration: duration,
        count: 1,
        maxWidth: 320,
      );
      final frame = p.join(dir.path, 'frame_001.jpg');
      if (File(frame).existsSync()) {
        if (File(posterPath).existsSync()) File(posterPath).deleteSync();
        await File(frame).rename(posterPath);
      }
      return File(posterPath).existsSync() ? posterPath : null;
    } catch (_) {
      return null;
    }
  }

  /// Lists all sessions, most-recently-opened first, pruning expired ones.
  Future<List<SessionRecord>> listRecent() async {
    final db = await _database();
    final rows = await db.query('sessions', orderBy: 'lastOpenedAt DESC');
    final records = rows.map(SessionRecord.fromDbMap).toList();

    final expired = records.where((r) => r.isExpired).toList();
    if (expired.isNotEmpty) {
      for (final r in expired) {
        await _deleteSession(r.id);
      }
    }
    return records.where((r) => !r.isExpired).toList();
  }

  Future<SessionRecord?> activeSession() async {
    final recent = await listRecent();
    return recent.isEmpty ? null : recent.first;
  }

  /// Permanently deletes a session (DB row + folder) and its media.
  Future<void> deleteSession(String id) async {
    final db = await _database();
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
    await _deleteSession(id);
  }

  Future<void> _deleteSession(String id) async {
    final root = await _rootDir();
    final dir = Directory(p.join(root.path, id));
    if (dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _db?.close();
    _db = null;
  }
}
