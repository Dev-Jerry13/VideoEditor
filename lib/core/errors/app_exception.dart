sealed class AppException implements Exception {
  const AppException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}

class MediaFormatException extends AppException {
  const MediaFormatException([
    super.message = 'This video format is not supported.',
  ]);
}

class MissingFileException extends AppException {
  const MissingFileException([
    super.message = 'The selected file could not be found.',
  ]);
}

class ProcessingException extends AppException {
  const ProcessingException([
    super.message = 'Video processing failed. Please try again.',
  ]);
}

class ExportCancelledException extends AppException {
  const ExportCancelledException() : super('Export cancelled.');
}

class StorageAccessException extends AppException {
  const StorageAccessException([
    super.message = 'Could not save the video to your gallery. '
        'The file is still available via Share.',
  ]);
}
