# Video Editor

Video Editor is an Android Flutter app for assembling and exporting short
videos entirely on-device. Projects are non-destructive: source media is kept
unchanged while edits are stored in a draft and rendered only during export.

## Features

- Import a video, review its duration, resolution, audio availability, and
  file size before creating a project draft.
- Build a multi-clip timeline with trim, split, delete, reorder, undo, and
  redo controls.
- Preview clips with speed, crop, rotation, flip, filters, colour adjustments,
  text, background music, and transitions.
- Export MP4 video at 720p or 1080p to the gallery, a chosen folder, or a
  system save location; share or preview the completed result.
- Resume locally saved drafts from the Recent list.

## Requirements

- Flutter SDK compatible with the Dart SDK declared in `pubspec.yaml`.
- Android API 24 or later. The app currently ships Android platform files only.
- Device-supported video media. MP4 and MOV are recommended starting formats;
  every selection is probed before it is copied into a draft.

## Run locally

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## Architecture

- `lib/models/` contains the immutable project, clip, audio, text, transform,
  transition, and export-setting models.
- `lib/state/editor_state.dart` owns editing state, playback coordination,
  undo/redo, autosave, and export progress.
- `lib/services/` contains media picking, FFmpeg/FFprobe processing, timeline
  layout, thumbnails, saved sessions, export delivery, and save destinations.
- `lib/widgets/` contains the editor preview, timeline, controls, and export
  surfaces. Widgets do not construct FFmpeg commands.

## Data handling

Media is processed locally. Imported videos and audio are copied into the
app's private draft storage so a project can be resumed even when the original
file moves. Rendered videos are written to private app storage first, then
delivered to the gallery, a selected folder, or the system save dialog.
