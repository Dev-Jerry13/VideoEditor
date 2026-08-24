# Flutter Basic Video Editor — Development Prompt

Build a **basic mobile video editing application using Flutter**. The application should have a clean, modern, responsive UI and focus on essential video-editing functionality rather than advanced professional features.

## 1. Technology Stack

- Flutter
- Dart
- Material 3
- Use a suitable video playback package for preview
- Use FFmpeg through a maintained Flutter-compatible integration for actual video processing/export
- Use a suitable file picker/media picker for selecting videos and audio
- Use a lightweight state-management approach such as Provider, Riverpod, or ValueNotifier
- Follow clean architecture and keep video-processing logic separate from UI

## 2. Main Features

### Video Import

Allow the user to:

- Select a video from device storage/gallery
- Display the selected video's thumbnail
- Show video duration
- Load the video into the editor

### Video Preview

Create a large video preview area.

Features:

- Play/pause
- Seek
- Current timestamp
- Total duration
- Fullscreen preview
- Automatically update the preview position while playing

### Timeline

Create a simple horizontal timeline below the preview.

Display:

- Video thumbnails
- Start position
- End position
- Current playhead
- Selected editing range

The user should be able to drag the start and end handles to trim the video.

Example:

```text
┌───────────────────────────────────────────────┐
│  ▶                                            │
│             VIDEO PREVIEW                     │
│                                               │
└───────────────────────────────────────────────┘

00:05                                      00:30
  │                                           │
  ▼                                           ▼
╔═══════════════════════════════════════════════╗
║ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ▣ ║
╚═══════════════════════════════════════════════╝
  ▲                                           ▲
 Start                                        End
```

## 3. Editing Tools

Implement these tools first:

### Trim

Allow the user to select:

```text
Start Time
End Time
```

Only the selected section should be exported.

### Split

Allow the user to place the playhead at a specific position and split the video into two clips.

Example:

```text
Original:

[─────────────── VIDEO ───────────────]

                    │
                  Split
                    │

Result:

[────── Clip 1 ────][────── Clip 2 ────]
```

### Delete Clip

Allow the user to delete a selected clip after splitting.

### Merge Clips

Allow multiple clips to be reordered and merged into a single exported video.

### Video Speed

Provide:

- 0.5x
- 0.75x
- 1x
- 1.25x
- 1.5x
- 2x

### Volume

Provide a volume slider:

```text
0% ───────────────●──────── 100%
```

### Background Music

Allow the user to select an audio file from the device.

Provide:

- Add music
- Remove music
- Music volume
- Trim music to video duration

### Text Overlay

Allow the user to add basic text.

Controls:

- Text input
- Font size
- Position
- Text alignment
- Start time
- End time

Keep the first implementation simple.

## 4. Export

Create an Export screen/dialog.

Display:

```text
Export Video

Resolution
○ 720p
● 1080p

Quality
○ Low
● Medium
○ High

[ Export Video ]
```

Show export progress:

```text
Exporting...

██████████████░░░░░░ 72%

72%
```

After successful export:

- Save the video to device storage
- Display a preview
- Provide Share option
- Provide "Edit Again" option

## 5. UI Design

Use a modern video-editor style interface.

### Main Editor

```text
┌─────────────────────────────────┐
│ ←  Video Editor          Export │
├─────────────────────────────────┤
│                                 │
│                                 │
│          VIDEO PREVIEW          │
│                                 │
│                                 │
├─────────────────────────────────┤
│ 00:05              00:30        │
│                                 │
│  [▣][▣][▣][▣][▣][▣][▣][▣]       │
│      ▲ Playhead                 │
├─────────────────────────────────┤
│                                 │
│ ✂ Trim    ✂ Split    🗑 Delete  │
│                                 │
│ 🎵 Music   T Text    ⚡ Speed   │
│                                 │
│ 🔊 Volume  ↔ Crop    ↻ Rotate   │
│                                 │
└─────────────────────────────────┘
```

Use:

- Dark editor theme
- Rounded controls
- Clear icons
- Bottom toolbar
- Smooth animations
- Proper spacing
- Responsive layouts
- Material 3 components

Do not make the UI unnecessarily complicated.

## 6. Project Structure

Use a maintainable structure such as:

```text
lib/
├── main.dart
│
├── core/
│   ├── constants/
│   ├── theme/
│   └── utils/
│
├── models/
│   ├── video_project.dart
│   ├── video_clip.dart
│   └── audio_track.dart
│
├── services/
│   ├── video_service.dart
│   ├── ffmpeg_service.dart
│   ├── media_picker_service.dart
│   └── export_service.dart
│
├── screens/
│   ├── home_screen.dart
│   ├── editor_screen.dart
│   └── export_screen.dart
│
├── widgets/
│   ├── video_preview.dart
│   ├── video_timeline.dart
│   ├── timeline_clip.dart
│   ├── editor_toolbar.dart
│   ├── trim_handles.dart
│   └── export_progress.dart
│
└── state/
    └── editor_state.dart
```

## 7. Important Implementation Requirements

Do not perform heavy video processing directly inside Flutter UI code.

Create a dedicated service layer:

```dart
class FFmpegService {
  Future<String> trimVideo({
    required String inputPath,
    required Duration start,
    required Duration end,
  });

  Future<String> mergeVideos(List<String> videoPaths);

  Future<String> addAudio({
    required String videoPath,
    required String audioPath,
  });

  Future<String> changeSpeed({
    required String videoPath,
    required double speed,
  });

  Future<String> exportVideo({
    required String inputPath,
    required String outputPath,
  });
}
```

Keep FFmpeg commands isolated inside this service.

## 8. Performance

Optimize for mobile devices.

Requirements:

- Don't load the entire video into memory
- Generate timeline thumbnails asynchronously
- Cache generated thumbnails
- Avoid rebuilding the entire editor when the playhead moves
- Dispose video controllers correctly
- Show loading indicators during processing
- Run expensive processing outside the main UI flow where appropriate
- Handle large videos gracefully

## 9. Error Handling

Handle:

- Unsupported video formats
- Missing files
- Permission errors
- Insufficient storage
- FFmpeg failures
- Export cancellation
- Corrupted media
- User cancelling media selection

Show useful user-friendly error messages.

## 10. Development Strategy

Implement the project incrementally.

### Phase 1

Build:

1. Home screen
2. Video picker
3. Video preview
4. Play/pause
5. Seek
6. Timeline
7. Trim
8. Export

### Phase 2

Add:

1. Split
2. Delete clip
3. Reorder clips
4. Merge clips

# Flutter Video Editor — Phase 2

Continue development of the existing Flutter video editor. **Do not rebuild Phase 1.** Preserve the existing video picker, preview player, timeline, trimming, and export functionality.

The goal of Phase 2 is to introduce **multi-clip editing**:

1. Split video
2. Delete clips
3. Reorder clips
4. Merge clips
5. Preview the complete edited sequence

---

## 1. Multi-Clip Project Model

Replace the assumption that the project contains only one video segment.

Create a project model similar to:

```dart
class VideoProject {
  final List<VideoClip> clips;
  final AudioTrack? audioTrack;
}
```

Each clip should contain:

```dart
class VideoClip {
  final String id;
  final String sourcePath;

  final Duration sourceStart;
  final Duration sourceEnd;

  final int order;

  Duration get duration => sourceEnd - sourceStart;
}
```

The original video can therefore become:

```text
Original Video
────────────────────────────────────

After splitting:

[ Clip 1 ][ Clip 2 ][ Clip 3 ][ Clip 4 ]
```

Do not physically create separate video files every time the user splits a clip. Prefer storing **source path + start/end timestamps** until export.

---

# 2. Split Functionality

Add a `Split` button to the editor toolbar.

The split operation should use the current playhead position.

Example:

```text
[────────────────────────────────────]
                ▲
              00:12
                │
              SPLIT
```

Result:

```text
Before:

[──────────────────────────────]

After:

[──────────────][──────────────]
      Clip 1        Clip 2
```

## Rules

- Do not allow splitting at exactly the beginning.
- Do not allow splitting at exactly the end.
- Do not create clips shorter than a configurable minimum duration, such as 100 ms.
- Preserve the original source video.
- Preserve clip order.

Example:

```dart
Future<void> splitCurrentClip() async {
  // Determine current clip.
  // Determine playhead position.
  // Validate split position.
  // Create two logical VideoClip objects.
  // Replace the original clip.
  // Update project state.
}
```

After splitting, automatically select the newly created clips appropriately.

---

# 3. Clip Selection

The timeline must support selecting individual clips.

Selected clip:

```text
┌─────────────────────────────────────────┐
│ [ Clip 1 ] │ [ CLIP 2 ] │ [ Clip 3 ]   │
│              SELECTED                  │
└─────────────────────────────────────────┘
```

The selected clip should have a clear visual state.

Display basic information:

```text
Clip 2
Duration: 00:07
```

When a clip is selected, editing operations such as:

- Split
- Delete
- Trim

should operate on that clip.

---

# 4. Delete Clip

Add a Delete button.

Example:

```text
[ Clip 1 ][ Clip 2 ][ Clip 3 ]
            ▲
          SELECTED

             ↓

[ Clip 1 ][ Clip 3 ]
```

Before deleting the final remaining clip, prevent the project from becoming empty.

If the user attempts to delete the only clip:

```text
Cannot delete the only clip.
```

After deletion:

- Select a sensible neighboring clip.
- Update timeline.
- Update total duration.
- Update preview.
- Update playhead position.

---

# 5. Reorder Clips

Allow users to reorder clips using drag and drop.

Example:

```text
Before:

[ Clip 1 ][ Clip 2 ][ Clip 3 ]

Drag Clip 3:

[ Clip 3 ][ Clip 1 ][ Clip 2 ]
```

Use Flutter's:

```dart
ReorderableListView
```

or implement a custom horizontal drag interaction if necessary.

However, because this is a video timeline, prefer a custom horizontal timeline interaction if it can be implemented reliably.

Each clip should display:

- Thumbnail
- Duration
- Selection state
- Clip index

Example:

```text
┌────────┐ ┌────────┐ ┌────────┐
│ ▣ ▣ ▣  │ │ ▣ ▣ ▣  │ │ ▣ ▣ ▣  │
│ Clip 1 │ │ Clip 2 │ │ Clip 3 │
│ 00:05  │ │ 00:08  │ │ 00:04  │
└────────┘ └────────┘ └────────┘
```

After reordering:

```text
VideoProject.clips
```

must reflect the new order.

---

# 6. Timeline Architecture

Upgrade the existing timeline to support multiple clips.

Example:

```text
00:00                                      00:25
 │                                           │
 ▼                                           ▼

┌──────────┬──────────────┬────────┬───────────┐
│ Clip 1   │    Clip 2    │ Clip 3 │   Clip 4  │
│ ▣ ▣ ▣ ▣  │  ▣ ▣ ▣ ▣ ▣  │ ▣ ▣ ▣ │ ▣ ▣ ▣ ▣  │
└──────────┴──────────────┴────────┴───────────┘
                         ▲
                       PLAYHEAD
```

The timeline must calculate its total duration from all clips:

```dart
Duration get totalDuration {
  return clips.fold(
    Duration.zero,
    (total, clip) => total + clip.duration,
  );
}
```

The playhead position represents the **combined project timeline**, not the source video's timestamp.

---

# 7. Global Timeline → Clip Position

Implement conversion between:

```text
Project timeline position
        ↓
Selected clip
        ↓
Source video timestamp
```

For example:

```text
Project timeline:

00:00 ───── Clip 1 ───── 00:05
00:05 ───── Clip 2 ───── 00:13
00:13 ───── Clip 3 ───── 00:18
```

If the global playhead is:

```text
00:09
```

then:

```text
Current clip = Clip 2
Position inside Clip 2 = 00:04
```

And the source video position should be:

```text
Clip 2 sourceStart + 00:04
```

Create a reusable helper:

```dart
ClipPosition resolveTimelinePosition(
  Duration projectPosition,
);
```

---

# 8. Continuous Preview

The preview player should play the entire project as if it were one video.

Example:

```text
Clip 1
   ↓
Clip 2
   ↓
Clip 3
   ↓
Clip 4
```

The user should not have to manually press play for each clip.

When Clip 1 finishes:

```text
Clip 1 → Clip 2
```

automatically.

When Clip 2 finishes:

```text
Clip 2 → Clip 3
```

automatically.

The global playhead should continue moving smoothly.

---

# 9. Preview Implementation

Do not immediately physically merge all videos just to preview them.

Prefer logical playback:

```text
VideoProject
     │
     ├── Clip 1
     ├── Clip 2
     ├── Clip 3
     └── Clip 4
             ↓
       Preview Controller
```

The preview controller should:

1. Determine current clip.
2. Seek to the correct source timestamp.
3. Play until `sourceEnd`.
4. Move to the next clip.
5. Repeat.

Avoid unnecessary reinitialization of the video controller where possible.

---

# 10. Merge / Export

The final export should physically merge all logical clips.

For example:

```text
Clip 1
   +
Clip 2
   +
Clip 3
   +
Clip 4
   ↓
FFmpeg
   ↓
final_video.mp4
```

Use the existing FFmpeg service.

Extend it with something similar to:

```dart
Future<String> mergeClips({
  required List<VideoClip> clips,
  required String outputPath,
});
```

The implementation should:

- Trim each logical segment
- Preserve the desired order
- Concatenate the clips
- Produce one final video
- Report progress
- Handle errors
- Clean up temporary files

Do not modify the original source videos.

---

# 11. FFmpeg Processing

Keep FFmpeg commands isolated inside:

```text
services/
    ffmpeg_service.dart
```

Do not place FFmpeg commands directly inside widgets.

Example architecture:

```text
EditorScreen
     ↓
EditorState
     ↓
VideoProject
     ↓
FFmpegService
     ↓
Exported Video
```

---

# 12. State Management

The editor state should expose operations such as:

```dart
class EditorState {
  List<VideoClip> clips;

  VideoClip? selectedClip;

  Duration playheadPosition;

  void selectClip(String clipId);

  void splitClip();

  void deleteClip();

  void reorderClip(int oldIndex, int newIndex);

  Future<void> exportProject();
}
```

Keep state mutations centralized.

Avoid modifying the clip list directly from UI widgets.

---

# 13. Undo / Redo

Add basic undo/redo support if the existing architecture allows it.

Operations that should be undoable:

- Split
- Delete
- Reorder
- Trim

Example:

```text
↶ Undo       ↷ Redo
```

Maintain a history of project states or use command-based history.

Keep the implementation simple for Phase 2.

---

# 14. Updated Toolbar

The editor toolbar should now contain:

```text
┌─────────────────────────────────────┐
│ ✂ Trim   ✂ Split   🗑 Delete        │
│                                     │
│ ↶ Undo   ↷ Redo                     │
└─────────────────────────────────────┘
```

Do not overcrowd the toolbar.

Use a horizontally scrollable toolbar if necessary.

---

# 15. Project Structure

Update the existing architecture:

```text
lib/
├── models/
│   ├── video_project.dart
│   ├── video_clip.dart
│   └── audio_track.dart
│
├── services/
│   ├── video_service.dart
│   ├── ffmpeg_service.dart
│   ├── preview_service.dart
│   └── export_service.dart
│
├── state/
│   └── editor_state.dart
│
├── screens/
│   ├── home_screen.dart
│   ├── editor_screen.dart
│   └── export_screen.dart
│
└── widgets/
    ├── video_preview.dart
    ├── video_timeline.dart
    ├── timeline_clip.dart
    ├── clip_toolbar.dart
    ├── playhead.dart
    └── export_progress.dart
```

---

# 16. Important Constraints

Do not implement Phase 3 features yet.

Do NOT add:

- Background music
- Text overlays
- Filters
- Transitions
- Stickers
- Advanced effects
- Color grading

Phase 2 should only focus on:

```text
Multi-Clip Editing

       ↓

Split
Delete
Reorder
Merge
Continuous Preview
```

---

# 17. Acceptance Criteria

Phase 2 is complete when the following workflow works reliably:

```text
Select Video
      ↓
Preview
      ↓
Trim
      ↓
Split
      ↓
[Clip 1] [Clip 2]
      ↓
Split Clip 2
      ↓
[Clip 1] [Clip 2] [Clip 3]
      ↓
Delete Clip 2
      ↓
[Clip 1] [Clip 3]
      ↓
Reorder
      ↓
[Clip 3] [Clip 1]
      ↓
Preview Entire Project
      ↓
Export
      ↓
Single final MP4
```

Test the implementation with:

- Short videos
- Long videos
- Multiple splits
- Deleting clips
- Reordering clips
- Trimming after splitting
- Exporting multiple clips
- Playing the entire project continuously

Make sure there are no crashes, memory leaks, broken playhead positions, or incorrect clip durations.

### Phase 3

Add:

1. Background music
2. Volume
3. Playback speed
4. Text overlays

# Flutter Video Editor — Phase 3

Continue development of the existing Flutter video editor from **Phase 1 and Phase 2**.

Do not rebuild the application or replace the existing architecture.

Phase 3 adds:

1. Background music
2. Audio volume control
3. Video playback speed
4. Text overlays
5. Timeline synchronization
6. Export support for all new features

The existing functionality must continue working:

- Video import
- Video preview
- Trim
- Split
- Delete clips
- Reorder clips
- Multi-clip timeline
- Continuous preview
- Export

---

# 1. Background Music

Allow the user to add an audio file from the device.

Supported workflow:

```text
Select Video
      ↓
Add Music
      ↓
Select Audio
      ↓
Preview
      ↓
Adjust Music
      ↓
Export
```

Add a `Music` button to the editor toolbar.

Example:

```text
┌───────────────────────────────────┐
│ ✂ Trim   ✂ Split   🗑 Delete      │
│ 🎵 Music  ⚡ Speed  T Text        │
└───────────────────────────────────┘
```

---

# 2. Audio Track Model

Create a dedicated model:

```dart
class AudioTrack {
  final String id;
  final String sourcePath;

  final Duration sourceStart;
  final Duration sourceEnd;

  final Duration timelineStart;

  final double volume;

  const AudioTrack({
    required this.id,
    required this.sourcePath,
    required this.sourceStart,
    required this.sourceEnd,
    required this.timelineStart,
    required this.volume,
  });
}
```

The project should support:

```dart
class VideoProject {
  final List<VideoClip> clips;
  final List<AudioTrack> audioTracks;
}
```

Use a list rather than a single audio track so the architecture can later support multiple tracks.

For Phase 3, however, the UI only needs to expose one background-music track.

---

# 3. Add Music UI

When the user taps:

```text
🎵 Music
```

open a bottom sheet.

Example:

```text
┌─────────────────────────────────────┐
│ Add Music                            │
├─────────────────────────────────────┤
│                                     │
│ 🎵 Select Audio                     │
│                                     │
│ ─────────────────────────────────── │
│                                     │
│ Selected: background.mp3            │
│                                     │
│ Volume                              │
│ 0% ─────────●──────────── 100%      │
│                                     │
│ Start                               │
│ 00:00                               │
│                                     │
│ Duration                            │
│ 00:15                               │
│                                     │
│        [ Remove ] [ Apply ]         │
└─────────────────────────────────────┘
```

---

# 4. Audio Trimming

Allow the user to select the portion of the audio that should be used.

Example:

```text
Audio

[────────────────────────────────────]

     ▲                       ▲
   Start                     End
```

The audio should be automatically constrained to the project duration.

For example:

```text
Video duration = 00:30
Music duration = 01:20
```

The exported music should only cover:

```text
00:00 → 00:30
```

Do not require the user to manually trim music to exactly match the video.

---

# 5. Music Timeline

Add an audio track underneath the video timeline.

Example:

```text
VIDEO
┌──────────┬────────────┬───────────┐
│ Clip 1   │   Clip 2   │   Clip 3  │
└──────────┴────────────┴───────────┘
             ▲
           Playhead

MUSIC
┌────────────────────────────────────┐
│ 🎵 background.mp3                  │
└────────────────────────────────────┘
```

The audio track should visually indicate:

- Start position
- End position
- Audio name
- Volume
- Timeline duration

---

# 6. Original Video Audio

Add an audio-volume control for the original video's audio.

Example:

```text
Original Audio

0% ───────────────●────────── 100%
```

Default:

```text
100%
```

The user should be able to mute the original video:

```text
🔇 Mute
```

or adjust it:

```text
0% → 100%
```

Store this setting in the project:

```dart
double originalAudioVolume = 1.0;
```

---

# 7. Music Volume

Music should have an independent volume control.

```dart
double musicVolume = 1.0;
```

Example:

```text
Original Audio: 80%
Background Music: 35%
```

The two audio streams must be mixed during export.

---

# 8. Audio Preview

The preview should play:

```text
Video
 +
Original Audio
 +
Background Music
```

synchronized with the global project timeline.

The user should hear the correct audio when:

- Playing
- Pausing
- Seeking
- Moving between clips
- Scrubbing the timeline

Avoid restarting the audio unnecessarily every time the playhead moves.

---

# 9. FFmpeg Audio Mixing

Keep all FFmpeg operations inside:

```text
services/ffmpeg_service.dart
```

Add:

```dart
Future<String> addBackgroundMusic({
  required String videoPath,
  required String audioPath,
  required String outputPath,
  required double videoVolume,
  required double musicVolume,
});
```

The final output should contain:

```text
Original Video Audio
          +
Background Music
          ↓
      Final MP4
```

Use appropriate FFmpeg audio filters such as:

```text
volume
amix
atrim
adelay
```

Do not hardcode FFmpeg commands inside UI widgets.

---

# 10. Video Speed

Add a `Speed` tool.

When selected, show:

```text
Playback Speed

0.25x
0.5x
0.75x
1.0x
1.25x
1.5x
2.0x
```

Default:

```text
1.0x
```

The speed should apply to the selected clip.

Example:

```text
Clip 1 → 1.0x
Clip 2 → 2.0x
Clip 3 → 0.5x
```

---

# 11. Store Speed Per Clip

Update `VideoClip`:

```dart
class VideoClip {
  final String id;
  final String sourcePath;

  final Duration sourceStart;
  final Duration sourceEnd;

  final double speed;

  final int order;
}
```

Example:

```text
Clip 1
Duration: 5 sec
Speed: 1.0x

Clip 2
Duration: 8 sec
Speed: 2.0x

Clip 3
Duration: 4 sec
Speed: 0.5x
```

The timeline duration must account for playback speed.

Formula:

```text
outputDuration = sourceDuration / speed
```

For example:

```text
Source duration = 10 sec
Speed = 2.0x

Output duration = 5 sec
```

---

# 12. Speed Preview

The preview must respect clip speed.

Example:

```text
[ Clip 1 ] → normal
     ↓
[ Clip 2 ] → 2x
     ↓
[ Clip 3 ] → 0.5x
```

When transitioning between clips, automatically apply the next clip's speed.

The global project timeline must use the resulting output durations.

---

# 13. FFmpeg Speed Processing

Use FFmpeg's video and audio timing filters appropriately.

For video:

```text
setpts
```

For audio:

```text
atempo
```

Remember that `atempo` has constraints on supported speed ranges, so implement a helper that chains multiple `atempo` filters when required.

Example:

```dart
String buildAudioTempoFilter(double speed) {
  // Generate appropriate atempo chain.
}
```

Do not simply modify the video speed while leaving its audio unchanged.

---

# 14. Text Overlay

Add a `Text` button.

When the user taps:

```text
T Text
```

show a text editor.

Example:

```text
┌──────────────────────────────────┐
│ Add Text                          │
├──────────────────────────────────┤
│                                  │
│ [ Enter your text...           ] │
│                                  │
│ Font Size                         │
│ ───────────●────────────          │
│                                  │
│ Alignment                         │
│ [ Left ] [ Center ] [ Right ]     │
│                                  │
│ Position                          │
│       ↑                           │
│    ←  ●  →                       │
│       ↓                           │
│                                  │
│ Start: 00:03                     │
│ End:   00:08                     │
│                                  │
│          [ Apply ]                │
└──────────────────────────────────┘
```

---

# 15. Text Overlay Model

Create:

```dart
class TextOverlay {
  final String id;

  final String text;

  final double fontSize;

  final double x;
  final double y;

  final Duration startTime;
  final Duration endTime;

  final TextAlign alignment;
}
```

The project becomes:

```dart
class VideoProject {
  final List<VideoClip> clips;
  final List<AudioTrack> audioTracks;
  final List<TextOverlay> textOverlays;
}
```

---

# 16. Text Position

Use normalized coordinates rather than fixed pixels.

Example:

```dart
double x = 0.5;
double y = 0.5;
```

Meaning:

```text
x = 0.5 → center horizontally
y = 0.5 → center vertically
```

This allows the overlay to work with:

- 720p
- 1080p
- Different aspect ratios
- Different device sizes

---

# 17. Text Editing on Preview

When a text overlay is selected, show it directly over the video preview.

Example:

```text
┌───────────────────────────────┐
│                               │
│                               │
│       HELLO WORLD             │
│            ●                  │
│                               │
│                               │
└───────────────────────────────┘
```

Allow the user to drag the text around the preview.

The preview position should update the normalized:

```text
x
y
```

coordinates.

---

# 18. Text Timing

Each text overlay should have:

```text
Start Time
End Time
```

Example:

```text
Text 1
00:00 → 00:05

Text 2
00:06 → 00:12
```

The text should only appear during its assigned interval.

On the timeline:

```text
VIDEO
┌──────────┬──────────┬──────────┐
│ Clip 1   │ Clip 2   │ Clip 3   │
└──────────┴──────────┴──────────┘

TEXT
┌──────────────┐
│ Hello World  │
└──────────────┘
      ┌────────────────┐
      │ Second Text    │
      └────────────────┘
```

---

# 19. Text Styling

For Phase 3, support only basic styling:

- Font size
- Bold
- Text alignment
- Basic text color
- Basic background
- Position

Do not implement advanced typography yet.

Do not add:

- Animated text
- Custom font marketplace
- Text shadows
- Stroke effects
- Text transitions

Those can be added later.

---

# 20. Text Rendering During Export

Text overlays must be included in the final exported video.

Keep FFmpeg logic in:

```text
FFmpegService
```

Generate appropriate FFmpeg `drawtext` filters.

Do not hardcode absolute screen coordinates.

Convert normalized coordinates:

```text
x = 0.5
y = 0.5
```

into the output video's actual dimensions.

Example concept:

```text
normalized coordinates
        ↓
video dimensions
        ↓
FFmpeg drawtext
        ↓
final video
```

Handle text escaping correctly for:

- `'`
- `"`
- `:`
- `\`
- Newlines

---

# 21. Updated Timeline

The timeline should now contain three logical tracks:

```text
VIDEO
┌──────────┬──────────────┬──────────┐
│ Clip 1   │    Clip 2    │ Clip 3   │
└──────────┴──────────────┴──────────┘

TEXT
      ┌──────────────┐
      │ Hello World  │
      └──────────────┘

AUDIO
┌────────────────────────────────────┐
│ 🎵 background.mp3                  │
└────────────────────────────────────┘
```

All tracks must share the same global timeline.

The playhead must move through all tracks simultaneously.

---

# 22. Updated Editor State

Extend the existing state:

```dart
class EditorState {
  List<VideoClip> clips;

  List<AudioTrack> audioTracks;

  List<TextOverlay> textOverlays;

  Duration playheadPosition;

  VideoClip? selectedClip;

  TextOverlay? selectedText;

  double originalAudioVolume;

  void addMusic();

  void removeMusic();

  void updateMusicVolume(double volume);

  void updateOriginalAudioVolume(double volume);

  void updateClipSpeed(
    String clipId,
    double speed,
  );

  void addTextOverlay();

  void updateTextOverlay();

  void deleteTextOverlay();
}
```

Keep all modifications centralized in the editor state.

---

# 23. Export Pipeline

The export pipeline now becomes:

```text
Video Clips
     │
     ├── Trim
     ├── Speed
     └── Reorder
           │
           ▼
      Video Processing
           │
           ├─────────────┐
           │             │
Original Audio      Background Music
           │             │
           └──────┬──────┘
                  ▼
             Audio Mixing
                  │
                  ▼
            Text Overlays
                  │
                  ▼
             Final MP4
```

The final export must contain:

- All clips
- Correct clip order
- Clip speed
- Original audio volume
- Background music
- Music volume
- Text overlays
- Correct text timing

---

# 24. Export Progress

Show meaningful progress:

```text
Preparing clips       20%
Processing video      40%
Processing audio      60%
Adding text           80%
Finalizing video      100%
```

Do not freeze the UI during export.

Allow the user to cancel export if the FFmpeg integration supports cancellation.

---

# 25. Performance Requirements

Pay particular attention to performance.

Do not:

- Decode entire videos into memory
- Generate unnecessary temporary files
- Reinitialize video controllers unnecessarily
- Rebuild the entire editor for every timeline update
- Process video on every UI interaction

Use:

- Cached thumbnails
- Lazy thumbnail generation
- Debounced timeline updates
- Efficient state updates
- Temporary-file cleanup

---

# 26. Error Handling

Handle:

```text
Invalid audio file
Unsupported audio format
FFmpeg failure
Text rendering failure
Invalid speed
Missing source video
Insufficient storage
Export cancellation
Permission errors
```

Display clear messages.

Never expose raw FFmpeg errors directly to users unless useful for debugging.

---

# 27. Undo / Redo

Extend Phase 2 undo/redo to include:

- Add music
- Remove music
- Change music volume
- Change original audio volume
- Change clip speed
- Add text
- Edit text
- Move text
- Delete text
- Change text timing

---

# 28. Updated Project Structure

Use:

```text
lib/
├── models/
│   ├── video_project.dart
│   ├── video_clip.dart
│   ├── audio_track.dart
│   └── text_overlay.dart
│
├── services/
│   ├── ffmpeg_service.dart
│   ├── video_service.dart
│   ├── audio_service.dart
│   ├── preview_service.dart
│   └── export_service.dart
│
├── state/
│   └── editor_state.dart
│
├── screens/
│   ├── home_screen.dart
│   ├── editor_screen.dart
│   └── export_screen.dart
│
└── widgets/
    ├── video_preview.dart
    ├── video_timeline.dart
    ├── timeline_clip.dart
    ├── audio_track.dart
    ├── text_track.dart
    ├── text_overlay_editor.dart
    ├── editor_toolbar.dart
    ├── speed_selector.dart
    ├── music_editor.dart
    └── export_progress.dart
```

---

# 29. Phase 3 Acceptance Test

The following complete workflow must work:

```text
Import Video
     ↓
Trim
     ↓
Split
     ↓
Delete Clip
     ↓
Reorder Clips
     ↓
Select Clip
     ↓
Change Clip Speed
     ↓
Add Background Music
     ↓
Adjust Music Volume
     ↓
Adjust Original Audio
     ↓
Add Text
     ↓
Move Text
     ↓
Set Text Timing
     ↓
Preview Entire Project
     ↓
Export
     ↓
Final MP4
```

The exported video must accurately match the preview:

```text
Video        ✓
Clip order   ✓
Clip speed   ✓
Audio        ✓
Music        ✓
Text         ✓
Timing       ✓
```

---

# 30. Important Scope Restriction

Do not implement Phase 4 yet.

Do not add:

- Video transitions
- Filters
- Crop
- Rotate
- Stickers
- Animations
- Keyframes
- Color grading
- Advanced audio effects

Phase 3 should establish a solid foundation for **multi-track video editing**.

The architecture should make it straightforward to add those features later without rewriting the editor.

# Flutter Video Editor — Phase 4

Continue development of the existing Flutter video editor from Phases 1–3.

Do **not** rebuild the application or replace the existing architecture.

Phase 4 adds:

1. Crop
2. Rotate
3. Flip
4. Aspect-ratio presets
5. Basic visual filters
6. Clip transitions
7. Basic visual adjustments
8. Preview synchronization
9. FFmpeg export support

The goal is to move from a basic editor toward a lightweight CapCut-style editor without introducing unnecessary complexity.

---

# 1. Phase 4 Editor Toolbar

Update the editor toolbar:

```text
┌────────────────────────────────────────────┐
│ ✂ Trim   Split   Delete   🎵 Music         │
│ T Text   ⚡ Speed  Crop   Rotate            │
│ 🎨 Filter   Adjust   Transition            │
└────────────────────────────────────────────┘
```

Use a horizontally scrollable toolbar.

When a clip is selected, visual editing tools should operate on that clip.

---

# 2. Crop

Add a crop editor.

When the user taps:

```text
Crop
```

show a crop interface over the video preview.

Example:

```text
┌───────────────────────────────┐
│                               │
│     ┌───────────────────┐     │
│     │                   │     │
│     │     VIDEO         │     │
│     │                   │     │
│     └───────────────────┘     │
│                               │
├───────────────────────────────┤
│ Original  16:9  9:16  1:1    │
│ 4:3       3:4   Free          │
│                               │
│             [ Apply ]         │
└───────────────────────────────┘
```

Support:

- Free crop
- 16:9
- 9:16
- 1:1
- 4:3
- 3:4
- Original

---

# 3. Crop Model

Add crop information to `VideoClip`.

Use normalized coordinates:

```dart
class CropSettings {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const CropSettings({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
}
```

Example:

```text
left   = 0.10
top    = 0.05
right  = 0.90
bottom = 0.95
```

Do not store crop coordinates as fixed screen pixels.

This allows the project to work with different video resolutions.

---

# 4. Interactive Crop

The user should be able to drag crop handles.

Example:

```text
┌─────────────────────────────┐
│ ●────────────────────────●  │
│ │                         │ │
│ │       VIDEO             │ │
│ │                         │ │
│ ●────────────────────────●  │
└─────────────────────────────┘
```

Support:

- Corner handles
- Edge handles
- Dragging the crop area
- Aspect-ratio locking
- Reset crop

Provide:

```text
[ Reset ]                  [ Apply ]
```

Do not modify the source video while the user is adjusting the crop.

Store the crop settings in project state and apply them during export.

---

# 5. Aspect Ratio

Create an aspect-ratio selector:

```text
Original
16:9
9:16
1:1
4:3
3:4
```

Common use cases:

```text
16:9 → YouTube / landscape
9:16 → Shorts / Reels / TikTok
1:1  → Square
4:3  → Traditional video
```

The preview should update immediately when the aspect ratio changes.

---

# 6. Rotate

Add a Rotate tool.

Controls:

```text
↶ 90°
↷ 90°
180°
Reset
```

Example:

```text
[ ↶ ] [ ↷ ] [ 180° ] [ Reset ]
```

Store rotation as:

```dart
enum Rotation {
  none,
  clockwise90,
  clockwise180,
  clockwise270,
}
```

Do not physically rotate the video until export.

---

# 7. Flip

Support:

```text
Flip Horizontal
Flip Vertical
```

Example:

```text
↔ Horizontal
↕ Vertical
```

Store this in the clip's transformation settings:

```dart
class TransformSettings {
  final Rotation rotation;
  final bool flipHorizontal;
  final bool flipVertical;
}
```

---

# 8. Transform Model

Keep visual transformation settings together:

```dart
class VideoTransform {
  final CropSettings crop;
  final TransformSettings transform;

  final double scale;
  final double positionX;
  final double positionY;
}
```

This should make it possible to extend the system later with:

- Zoom
- Pan
- Keyframes

without redesigning the model.

---

# 9. Basic Filters

Add a `Filter` tool.

Create a filter selection panel:

```text
┌────────────────────────────────────────┐
│ Filters                                │
├────────────────────────────────────────┤
│ Original   Bright   Contrast           │
│ Warm       Cool     Vintage             │
│ B&W       Fade      Cinema              │
└────────────────────────────────────────┘
```

Start with a small number of filters.

Recommended initial filters:

```text
Original
Grayscale
Warm
Cool
Vintage
High Contrast
Bright
Fade
```

---

# 10. Filter Model

Create:

```dart
enum VideoFilter {
  none,
  grayscale,
  warm,
  cool,
  vintage,
  highContrast,
  bright,
  fade,
}
```

Each clip should have:

```dart
VideoFilter filter;
```

The filter must apply only to the selected clip.

Example:

```text
Clip 1 → Original
Clip 2 → Vintage
Clip 3 → Grayscale
```

---

# 11. Filter Preview

The filter should be visible immediately in the video preview.

Do not require an export just to see the filter.

For preview, use an efficient Flutter-side rendering approach where possible.

Avoid repeatedly running FFmpeg just to update a preview filter.

---

# 12. Filter Export

During final export, convert the selected filter into FFmpeg filters.

Examples of concepts to use:

```text
eq
colorbalance
hue
curves
colorchannelmixer
```

Keep filter construction inside:

```text
FFmpegService
```

Create a helper:

```dart
String buildVideoFilter(
  VideoClip clip,
);
```

This function should combine:

```text
Crop
+
Rotation
+
Flip
+
Brightness
+
Contrast
+
Color Filter
```

into one appropriate FFmpeg filter chain.

---

# 13. Basic Adjustments

Add an `Adjust` tool.

Controls:

```text
Brightness
──────────●──────────

Contrast
──────────●──────────

Saturation
──────────●──────────

Temperature
──────────●──────────
```

Use sensible ranges.

For example:

```text
Brightness: -100 → +100
Contrast:   -100 → +100
Saturation: -100 → +100
Temperature: -100 → +100
```

Do not expose raw FFmpeg values directly to the user.

---

# 14. Adjustment Model

Create:

```dart
class VideoAdjustments {
  final double brightness;
  final double contrast;
  final double saturation;
  final double temperature;

  const VideoAdjustments({
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.temperature = 0,
  });
}
```

Attach adjustments to each clip.

---

# 15. Reset Adjustments

Every visual editing panel should have:

```text
[ Reset ]
```

Reset should restore:

```text
Crop       → Original
Rotation   → 0°
Flip       → Off
Filter     → Original
Brightness → 0
Contrast   → 0
Saturation → 0
Temperature → 0
```

Do not reset unrelated properties such as:

- Trim
- Speed
- Audio
- Text

---

# 16. Transitions

Add transitions between adjacent clips.

Example:

```text
[ Clip 1 ] ── Transition ── [ Clip 2 ]
```

Add a transition button between clips:

```text
[ Clip 1 ]    ✚    [ Clip 2 ]
```

Tapping it opens:

```text
Transitions

None
Fade
Dissolve
Black
White
Slide Left
Slide Right
Zoom
```

Keep the first version simple.

---

# 17. Transition Model

Create:

```dart
enum TransitionType {
  none,
  fade,
  dissolve,
  black,
  white,
  slideLeft,
  slideRight,
  zoom,
}
```

Then:

```dart
class ClipTransition {
  final TransitionType type;
  final Duration duration;

  const ClipTransition({
    required this.type,
    required this.duration,
  });
}
```

Each transition belongs to the boundary between two clips.

For example:

```text
Clip 1
   │
   ▼
Transition 1
   │
   ▼
Clip 2
   │
   ▼
Transition 2
   │
   ▼
Clip 3
```

---

# 18. Transition Duration

Allow:

```text
0.25 sec
0.5 sec
0.75 sec
1.0 sec
1.5 sec
2.0 sec
```

Default:

```text
0.5 sec
```

Do not allow the transition duration to exceed what the adjacent clips can support.

For example:

```text
Clip 1 = 0.3 sec
Clip 2 = 0.4 sec
```

A 2-second transition should not be allowed.

Clamp or reject invalid values.

---

# 19. Transition Preview

The preview should show the transition between clips.

Example:

```text
Clip 1
   ↓
Fade
   ↓
Clip 2
```

The user should see the effect while scrubbing or playing.

Do not require final export to preview a basic transition.

---

# 20. Transition Export

Implement transitions during FFmpeg export.

Keep transition generation inside:

```text
FFmpegService
```

Use appropriate FFmpeg mechanisms such as:

```text
xfade
```

for video transitions.

For transitions that involve audio, use suitable audio crossfade logic.

The export pipeline must maintain:

```text
Video transition
+
Audio continuity
```

Do not produce abrupt audio cuts when a visual transition is applied.

---

# 21. Project Timeline

The timeline should now look like:

```text
VIDEO

┌──────────┐   ┌──────────────┐   ┌──────────┐
│ Clip 1   │ + │    Clip 2    │ + │ Clip 3   │
└──────────┘   └──────────────┘   └──────────┘
                 ↑
              Transition


TEXT

      ┌──────────────┐
      │ Hello World  │
      └──────────────┘


AUDIO

┌─────────────────────────────────────────────┐
│ 🎵 Background Music                        │
└─────────────────────────────────────────────┘
```

The global playhead must remain synchronized across:

- Video
- Transitions
- Text
- Audio
- Speed-adjusted clips

---

# 22. Timeline Duration

Because transitions overlap adjacent clips, do not calculate project duration simply by summing clip durations.

Use:

```text
totalDuration =
sum(clip durations)
-
sum(valid transition overlap durations)
```

Ensure the same timing calculation is used by:

- Timeline
- Preview
- Export
- Text timing
- Audio timing

Create a single duration-calculation service rather than duplicating this logic.

---

# 23. Preview Architecture

Update the preview system:

```text
VideoProject
      ↓
Timeline Resolver
      ↓
Current Clip
      ↓
Visual Transform
      ↓
Filter
      ↓
Transition
      ↓
Text Overlay
      ↓
Audio
      ↓
Preview
```

The preview should remain responsive.

Avoid running full FFmpeg exports for every preview interaction.

---

# 24. Export Architecture

The final export pipeline should become:

```text
                 Video Clips
                     │
        ┌────────────┼────────────┐
        ↓            ↓            ↓
      Trim         Speed       Transform
        │            │            │
        └────────────┼────────────┘
                     ↓
                  Filters
                     ↓
                Transitions
                     ↓
               Video Output
                     │
           ┌─────────┴─────────┐
           ↓                   ↓
     Original Audio       Background Music
           │                   │
           └─────────┬─────────┘
                     ↓
                 Audio Mix
                     ↓
               Text Overlays
                     ↓
                Final MP4
```

The export service should coordinate the process.

---

# 25. FFmpeg Service

Expand the service:

```dart
class FFmpegService {

  Future<String> processClip({
    required VideoClip clip,
    required String outputPath,
  });

  Future<String> mergeClips({
    required List<VideoClip> clips,
    required String outputPath,
  });

  Future<String> applyTransitions({
    required List<VideoClip> clips,
    required String outputPath,
  });

  Future<String> addAudio({
    required String videoPath,
    required List<AudioTrack> audioTracks,
    required String outputPath,
  });

  Future<String> applyTextOverlays({
    required String videoPath,
    required List<TextOverlay> overlays,
    required String outputPath,
  });

  Future<String> exportProject({
    required VideoProject project,
    required String outputPath,
  });
}
```

Do not expose FFmpeg implementation details to UI widgets.

---

# 26. Export Temporary Files

Use a controlled temporary directory.

Example:

```text
temporary/
├── clip_001.mp4
├── clip_002.mp4
├── clip_003.mp4
├── processed_001.mp4
├── processed_002.mp4
└── final.mp4
```

Clean temporary files after successful export.

Also clean them after failed or cancelled exports.

Never delete the user's original media.

---

# 27. Undo / Redo

Extend Phase 3 history to support:

- Crop
- Rotate
- Flip
- Aspect ratio
- Filter
- Brightness
- Contrast
- Saturation
- Temperature
- Add transition
- Remove transition
- Transition duration

Undo/redo must restore the complete project state correctly.

---

# 28. Updated Data Model

The architecture should now look approximately like:

```dart
class VideoClip {
  final String id;
  final String sourcePath;

  final Duration sourceStart;
  final Duration sourceEnd;

  final double speed;

  final VideoTransform transform;
  final VideoFilter filter;
  final VideoAdjustments adjustments;

  final int order;
}
```

And:

```dart
class VideoProject {
  final List<VideoClip> clips;
  final List<ClipTransition> transitions;
  final List<AudioTrack> audioTracks;
  final List<TextOverlay> textOverlays;

  final double originalAudioVolume;

  final String? outputAspectRatio;
}
```

Keep models immutable where practical and update them through the editor state.

---

# 29. Performance Requirements

Phase 4 introduces substantially more processing.

Follow these rules:

- Never run FFmpeg for simple UI preview interactions.
- Cache generated thumbnails.
- Cache filter previews where useful.
- Avoid unnecessary video-controller recreation.
- Avoid rebuilding unrelated timeline tracks.
- Process exports asynchronously.
- Clean temporary files.
- Prevent multiple exports from running simultaneously.
- Display progress.
- Allow cancellation where supported.

---

# 30. Error Handling

Handle:

```text
Invalid crop dimensions
Unsupported aspect ratio
Invalid transition duration
FFmpeg filter failure
Unsupported video codec
Missing source clip
Insufficient storage
Export cancellation
Corrupt source video
Invalid transformation
```

Provide user-friendly errors.

Example:

```text
Unable to export the video.

The selected transition could not be processed.
Try reducing the transition duration.
```

Do not expose raw command-line errors in production UI.

---

# 31. Updated Project Structure

Use:

```text
lib/
├── models/
│   ├── video_project.dart
│   ├── video_clip.dart
│   ├── video_transform.dart
│   ├── video_adjustments.dart
│   ├── audio_track.dart
│   ├── text_overlay.dart
│   └── clip_transition.dart
│
├── services/
│   ├── ffmpeg_service.dart
│   ├── video_service.dart
│   ├── audio_service.dart
│   ├── preview_service.dart
│   ├── timeline_service.dart
│   └── export_service.dart
│
├── state/
│   └── editor_state.dart
│
├── screens/
│   ├── home_screen.dart
│   ├── editor_screen.dart
│   └── export_screen.dart
│
└── widgets/
    ├── video_preview.dart
    ├── video_timeline.dart
    ├── timeline_clip.dart
    ├── transition_marker.dart
    ├── text_track.dart
    ├── audio_track.dart
    ├── crop_editor.dart
    ├── transform_controls.dart
    ├── filter_selector.dart
    ├── adjustment_panel.dart
    ├── transition_selector.dart
    └── export_progress.dart
```

---

# 32. Phase 4 Acceptance Test

The following complete workflow must work:

```text
Import Video
      ↓
Trim
      ↓
Split
      ↓
Reorder Clips
      ↓
Change Clip Speed
      ↓
Crop Clip
      ↓
Rotate Clip
      ↓
Flip Clip
      ↓
Apply Filter
      ↓
Adjust Brightness / Contrast
      ↓
Add Transition
      ↓
Set Transition Duration
      ↓
Add Music
      ↓
Add Text
      ↓
Preview Entire Project
      ↓
Export
      ↓
Final MP4
```

Verify the exported video contains:

```text
✓ Correct clip order
✓ Correct trimming
✓ Correct speed
✓ Correct crop
✓ Correct rotation
✓ Correct flip
✓ Correct filters
✓ Correct adjustments
✓ Correct transitions
✓ Correct music
✓ Correct original audio
✓ Correct text
✓ Correct timing
✓ Correct aspect ratio
```

---

# 33. Testing Requirements

Test with:

### Video formats

- MP4
- MOV
- WebM where supported

### Orientations

- Landscape
- Portrait
- Square

### Clip configurations

```text
1 clip
2 clips
5 clips
10+ clips
```

### Editing combinations

Test combinations such as:

```text
Crop + Rotate
Crop + Filter
Speed + Transition
Speed + Music
Filter + Text
Crop + Text
Multiple transitions
Multiple text overlays
```

Ensure combinations do not break export.

---

# 34. Scope Restriction

Do not implement Phase 5 yet.

Do not add:

- Keyframe animation
- Motion tracking
- Advanced transitions
- Chroma key / green screen
- Stickers
- GIFs
- Advanced audio effects
- Voice-over recording
- AI features
- LUT support
- Professional color grading

Phase 4 should establish a reliable **visual editing and transition system** on top of the existing multi-track editor.

The most important requirement is:

**Preview behavior and exported-video behavior must remain synchronized.**

## 11. Code Quality

Write production-quality Flutter code.

- Use null safety
- Avoid unnecessary dependencies
- Use reusable widgets
- Separate UI, state, and processing logic
- Add comments only where they explain non-obvious logic
- Handle lifecycle/disposal correctly
- Avoid hardcoded screen dimensions
- Make the application responsive
- Keep functions small and focused

Before implementing advanced functionality, make sure the basic workflow works:

```text
Pick Video
    ↓
Preview
    ↓
Trim
    ↓
Preview Trimmed Result
    ↓
Export
    ↓
Save Video
```

Start by implementing **Phase 1 completely and cleanly**. Do not implement all advanced features at once.
