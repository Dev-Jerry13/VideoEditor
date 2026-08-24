import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../core/errors/app_exception.dart';

class MediaPickerService {
  /// Returns the picked video path, or null when the user cancels.
  Future<String?> pickVideo() async {
    final file = await FilePicker.pickFile(type: FileType.video);
    final path = file?.path;
    if (path == null) return null;

    if (!File(path).existsSync()) {
      throw const MissingFileException();
    }
    return path;
  }

  /// Returns the picked audio file path, or null when the user cancels.
  Future<String?> pickAudio() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    final path = file?.path;
    if (path == null) return null;

    if (!File(path).existsSync()) {
      throw const MissingFileException();
    }
    return path;
  }
}
