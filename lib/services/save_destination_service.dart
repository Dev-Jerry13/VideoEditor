import 'dart:io';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:gal/gal.dart';
import 'package:saf/saf.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';

enum SaveDestination { gallery, folder, askEveryTime }

enum DeliveryStatus { saved, cancelled, failed }

/// Outcome of moving a rendered export to its final location.
class DeliveryResult {
  const DeliveryResult({required this.status, this.locationLabel});

  final DeliveryStatus status;

  /// Human-readable description of where the file ended up, when saved.
  final String? locationLabel;
}

/// Persists the user's preferred export destination and performs delivery of a
/// rendered file to that destination.
///
/// Rendering always writes to internal app storage first; this service only
/// moves/copies the finished file, so a failed delivery never loses work.
class SaveDestinationService {
  static const _keyMode = 'export.saveDestination';
  static const _keyFolderUri = 'export.folderUri';
  static const _keyFolderName = 'export.folderName';

  final Saf _saf = Saf();
  final SafStream _safStream = SafStream();

  Future<SaveDestination> loadDestination() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyMode);
      return SaveDestination.values.firstWhere(
        (d) => d.name == raw,
        orElse: () => SaveDestination.gallery,
      );
    } catch (_) {
      return SaveDestination.gallery;
    }
  }

  Future<void> setDestination(SaveDestination destination) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMode, destination.name);
    } catch (_) {
      // Preference loss degrades gracefully to the default.
    }
  }

  /// Returns the persisted folder choice, or null when nothing was saved or
  /// the SAF permission grant is gone (e.g. cleared app data).
  Future<({String uri, String name})?> loadSavedFolder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uri = prefs.getString(_keyFolderUri);
      final name = prefs.getString(_keyFolderName);
      if (uri == null || name == null) return null;

      final grants = await _saf.persistedPermissions();
      final alive = grants.any((g) => g.uri == uri && g.write);
      if (!alive) return null;
      return (uri: uri, name: name);
    } catch (_) {
      return null;
    }
  }

  Future<void> forgetSavedFolder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uri = prefs.getString(_keyFolderUri);
      if (uri != null) {
        try {
          await _saf.releasePersistedPermission(uri);
        } catch (_) {}
      }
      await prefs.remove(_keyFolderUri);
      await prefs.remove(_keyFolderName);
    } catch (_) {}
  }

  /// Opens the system directory picker. Persists the grant on success.
  /// Returns null when the user cancels.
  Future<({String uri, String name})?> pickFolder({String? initialUri}) async {
    try {
      final dir = await _saf.pickDirectory(initialUri: initialUri);
      if (dir == null) return null;
      await _persistFolder(dir.uri, dir.name);
      return (uri: dir.uri, name: dir.name);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistFolder(String uri, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyFolderUri, uri);
      await prefs.setString(_keyFolderName, name);
    } catch (_) {}
  }

  /// Copies [filePath] to wherever [destination] points.
  ///
  /// Never throws: failures come back as [DeliveryStatus.failed] so the
  /// exported render stays available for Share / retry.
  Future<DeliveryResult> deliver({
    required String filePath,
    required SaveDestination destination,
  }) async {
    final fileName = filePath.split(Platform.pathSeparator).last;
    switch (destination) {
      case SaveDestination.gallery:
        return _toGallery(filePath);
      case SaveDestination.folder:
        final folder = await loadSavedFolder();
        // Stale grant or lost preference: fall back to asking once.
        if (folder == null) return _viaSaveDialog(filePath);
        return _toFolder(filePath, fileName, folder);
      case SaveDestination.askEveryTime:
        return _viaSaveDialog(filePath);
    }
  }

  Future<DeliveryResult> _toGallery(String path) async {
    try {
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
      await Gal.putVideo(path, album: AppConstants.galleryAlbum);
      return DeliveryResult(
        status: DeliveryStatus.saved,
        locationLabel: 'Gallery · "${AppConstants.galleryAlbum}" album',
      );
    } catch (_) {
      return const DeliveryResult(status: DeliveryStatus.failed);
    }
  }

  Future<DeliveryResult> _toFolder(
    String path,
    String fileName,
    ({String uri, String name}) folder,
  ) async {
    try {
      final result = await _safStream.pasteLocalFile(
        path,
        folder.uri,
        fileName,
        'video/mp4',
        overwrite: false,
      );
      final written = result.fileName ?? fileName;
      return DeliveryResult(
        status: DeliveryStatus.saved,
        locationLabel: '${folder.name}/$written',
      );
    } catch (_) {
      return const DeliveryResult(status: DeliveryStatus.failed);
    }
  }

  Future<DeliveryResult> _viaSaveDialog(String path) async {
    try {
      final savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(sourceFilePath: path),
      );
      if (savedPath == null) {
        return const DeliveryResult(status: DeliveryStatus.cancelled);
      }
      final name = savedPath.split(Platform.pathSeparator).last;
      return DeliveryResult(
        status: DeliveryStatus.saved,
        locationLabel: name,
      );
    } catch (_) {
      return const DeliveryResult(status: DeliveryStatus.failed);
    }
  }
}
