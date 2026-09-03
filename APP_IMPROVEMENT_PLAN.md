# Video Editor Improvement & Usability Plan

## Purpose

Turn the current Android Flutter prototype into a dependable, understandable
mobile editor for short-form videos. The next releases should favour a
reliable import → edit → preview → export workflow over adding more effects.

## Current-State Assessment

### What already works

- The editor has a capable non-destructive project model: clips retain their
  source range, speed, visual settings, audio, text overlays, transitions,
  and output aspect ratio until export.
- Core editing is broader than the landing screen suggests: users can add,
  trim, split, delete, reorder, speed up, crop/transform, filter, adjust,
  add music and text, set transitions, undo/redo, and export.
- Preview is designed for a multi-clip sequence with a bounded controller
  pool, project-time playhead, background-audio synchronization, and
  transition overlap playback.
- Export is staged and isolated from widgets: it renders segments, assembles
  cuts/transitions, mixes audio, burns text, then delivers the finished file.
- Drafts are copied into app storage and auto-saved, so recent projects can
  be restored after relaunch.

### Primary usability and delivery gaps

1. **The product promise is undersold.** The home screen says “Trim and
   export”, even though the editor supports a full multi-clip workflow. There
   is no first-run guidance, project naming, or explanation of timeline
   gestures.
2. **Discoverability does not scale.** A single, horizontally scrolling tool
   row contains many actions with abbreviated labels. Editing modes, selection
   state, long-press reorder, and transition placement are not taught in the
   interface.
3. **There is no explicit media-readiness policy.** Imports are probed, but
   users do not get up-front compatibility, duration, resolution, storage, or
   estimated-export feedback before committing to an edit.
4. **Reliability is not demonstrated by the repository.** The automated tests
   concentrate on models, timeline math, crop math, and FFmpeg filter strings;
   there are no service fakes, export integration tests, state tests, or
   end-to-end workflow tests. The project also has no CI configuration.
5. **Release readiness is incomplete.** Package metadata, Android application
   ID, launcher label, versioning strategy, release signing, privacy copy,
   support documentation, and device coverage remain template/default values.
6. **Platform scope is ambiguous.** Only Android platform files are present;
   supported Android versions/devices and whether iOS is in scope have not
   been stated.

## Product Decisions to Make Before Implementation

These decisions unblock implementation and testing. Record the answers in the
README and in release requirements.

| Decision | Recommended default | Why it matters |
| --- | --- | --- |
| Target user | Casual creator editing one short social video | Keeps workflows and performance goals focused. |
| Initial platform | Android API 24+ only | Matches the checked-in platform setup and FFmpeg dependency. |
| Supported media | MP4/MOV with H.264 + AAC first; clearly validate/reject the rest | Prevents exports that fail late after a long edit. |
| Project retention | Keep drafts until user deletes them, with a storage quota and cleanup UI | A two-day silent expiry risks losing meaningful work. |
| Export contract | H.264/AAC MP4, 720p/1080p, explicit output folder/gallery choice | Gives QA a stable, testable result. |
| Privacy posture | On-device processing; no upload; disclose local media copies | Builds trust and defines required in-app copy. |

## Delivery Roadmap

### Milestone 0 — Establish a testable baseline (P0)

**Goal:** make future changes safe before expanding the feature set.

1. Add a GitHub Actions workflow that runs `flutter pub get`, `flutter
   analyze`, and `flutter test` on every pull request.
2. Split `EditorState` behind injectable interfaces for media picking,
   probing/FFmpeg, export, session storage, clock/timers, and video playback.
   Keep production adapters in `services/` and use deterministic fakes in
   tests.
3. Add unit tests for state operations and error paths: import failure,
   selected-clip changes, trim/split/delete/reorder undo-redo, autosave
   debounce, project restore, export cancellation, and delivery failure.
4. Add widget tests for the home/recent-project state, editor selection and
   toolbar enablement, timeline interactions, export progress/error/success,
   and accessible labels. Add a small integration-test suite for the complete
   happy path using fixture media or mocked platform services.
5. Define performance budgets and collect them on representative low/mid/high
   Android devices: import time, thumbnail latency, seek latency, preview
   frame stability, peak memory, and export time/size.

**Exit criteria:** CI is green; a failed import/export is reproducible in a
test; one scripted edit/export workflow runs without device-specific manual
steps.

### Milestone 1 — Make first use and project management clear (P0)

**Goal:** a new user can start, resume, and safely leave a project without
guesswork.

1. Replace template README and home-screen copy with a concise feature list,
   supported-media guidance, on-device privacy statement, and Android support
   policy.
2. Add an import preflight sheet after file selection: filename, duration,
   resolution, approximate size, audio presence, compatibility result, and
   clear recovery actions. Do not copy media into a draft until it passes.
3. Add a three-step first-run coach mark: select clip, scrub/trim timeline,
   export. Persist dismissal, and expose it again under Help.
4. Add project rename, explicit save status (“Saving…”, “Saved”, “Needs
   attention”), manual duplicate/delete, and a project-details screen showing
   original media and draft storage usage.
5. Replace automatic two-day deletion with a configurable cleanup policy;
   warn before deletion and provide one-tap cleanup for old drafts and renders.

**Exit criteria:** a usability test participant can import, identify the
selected clip, resume a saved project, and intentionally remove a project
without facilitator instruction.

### Milestone 2 — Make editing controls discoverable and reversible (P0)

**Goal:** users can make common edits accurately on a phone.

1. Reorganize the toolbar into labelled groups: **Edit** (split, delete,
reorder), **Audio**, **Canvas** (crop, rotate, aspect), and **Look** (filter,
adjust, text, transition). Use a bottom sheet or compact tabs instead of one
long unlabeled carousel; retain a visible undo/redo pair.
2. Add contextual empty/selection states: explain that Split needs a playhead
inside the selected clip, Delete cannot remove the last clip, and Transition
applies at the selected clip’s outgoing edge.
3. Provide a persistent timeline legend and gesture hints: tap to select,
drag playhead to seek, drag handles to trim, long-press then drag to reorder.
Show a larger selection outline, haptic feedback where supported, and a
confirmation/undo snackbar for destructive actions.
4. Improve precision: tap-to-type timecode, zoomable timeline scale, snapping
to clip boundaries, minimum-duration indicators, and a one-frame/100 ms
nudge control. Ensure all mutations use a single undo transaction.
5. Make text, crop, audio, and transition editing explicitly transactional:
offer Apply/Cancel/Reset, prevent accidental dismissal from committing a
partial edit, and clearly show the affected timeline interval.

**Exit criteria:** on a 360 dp-wide device, a user can split, trim, reorder,
add background music, add text, undo each operation, and identify what will
be exported.

### Milestone 3 — Harden preview and export (P0)

**Goal:** preview accurately predicts a finished, recoverable export.

1. Validate source files, free storage, output paths, and requested output
dimensions before rendering. Map FFmpeg failures to actionable messages
including the failed stage, retry action, and “save project” option.
2. Add an export summary before start: total duration, aspect ratio,
resolution, quality, estimated output size/time, destination, and any
normalization notices (letterboxing, re-encoding, muted source audio).
3. Preserve an export job record with project snapshot, settings, stage, and
output path. On app restart, clean orphan temporary directories and show a
clear result for interrupted jobs rather than silently losing context.
4. Test the render pipeline with small checked-in/generated fixtures covering
single clip, different source sizes, no-source-audio, music, text, filters,
speed, hard cuts, every transition type, cancellation, and unwritable output.
Verify duration, streams, dimensions, and key frames with `ffprobe`.
5. Add a preview/export parity checklist. Where GPU preview cannot reproduce
an FFmpeg effect exactly, label the preview as approximate and provide a
short low-resolution “test render” option.
6. Move long-running work to a user-visible foreground-safe execution model
where Android policy requires it; handle lifecycle interruption, rotation,
and app backgrounding deliberately.

**Exit criteria:** every supported edit combination produces a playable MP4
with the expected duration/aspect/audio; cancellation and delivery failures
leave the editable draft intact.

### Milestone 4 — Accessibility, resilience, and performance (P1)

**Goal:** the primary workflow remains usable across devices and conditions.

1. Audit every icon-only control for semantic label, tooltip, 48 dp minimum
touch target, focus order, contrast, dynamic text scaling, and screen-reader
announcements for selection, progress, errors, and undo.
2. Add layout tests at compact phones, large phones, landscape, tablets, and
large font sizes. Ensure the preview, timeline, sheets, and export controls do
not overflow or hide primary actions.
3. Cache thumbnails by source file identity and extraction settings; cancel
off-screen work; cap disk cache size; show placeholders and retry states.
4. Profile controller-pool lifecycle and transition playback for leaks and
race conditions. Add telemetry-free local diagnostic logs that users can
optionally export for support.
5. Test low-storage, missing-source, process-death restoration, interrupted
copy, app background/foreground, audio focus changes, and media permissions.

**Exit criteria:** the core workflow meets the agreed performance budget on
the lowest supported device and passes accessibility/lifecycle test matrices.

### Milestone 5 — Release readiness (P1)

**Goal:** produce a trustworthy installable release.

1. Replace placeholder package name, app label, description, icon variants,
versioning, and debug signing with product-owned release configuration.
2. Document privacy/data handling, third-party notices, supported formats,
storage behavior, and a support/contact path. Add an in-app About/Help screen.
3. Create a release checklist: clean install, upgrade, first import, resume,
export to each destination, share, cancellation, localization fallback, and
store-policy verification.
4. Establish crash/error reporting only after privacy review, with opt-in or
clear disclosure as required. Track anonymous aggregate reliability metrics
only if product policy permits it.

**Exit criteria:** a signed release candidate passes the device matrix and
the release checklist, with no P0 defects open.

## Recommended Technical Work Sequence

1. Introduce dependency injection and tests without changing user-visible
behavior.
2. Implement import preflight and durable project management.
3. Rework editing information architecture and timeline precision.
4. Add export preflight/job recovery and FFmpeg fixture tests.
5. Perform accessibility/performance hardening.
6. Complete release configuration and documentation.

This order intentionally avoids expanding effects until the existing feature
set is understandable, testable, and reliable.

## Definition of Done for Each Change

- State/model changes have unit tests, including invalid input and undo/redo
  behavior when relevant.
- UI changes have widget tests at compact width and large text scale, with
  semantic labels for interactive controls.
- Export-affecting changes include an FFmpeg fixture assertion for output
  duration, dimensions, stream presence, and playback.
- Error messages state what happened, preserve the project, and offer a
  recovery path.
- The project is analyzed and tested in CI, and the manual device checklist
  covers import, preview, edit, export, share, resume, and cancellation.

## Success Metrics

Measure from moderated usability sessions and release QA before adding new
effects:

| Metric | Initial target |
| --- | --- |
| New-user completion of import → trim → export | at least 8 of 10 users unaided |
| Successful supported-media export rate | at least 99% in release QA matrix |
| Draft recovery after normal relaunch | 100% of tested cases |
| P0 accessibility violations in primary workflow | 0 |
| Test coverage of state/model/export decision branches | agreed threshold, with all known failure paths covered |
| Export parity defects in regression fixture suite | 0 |
