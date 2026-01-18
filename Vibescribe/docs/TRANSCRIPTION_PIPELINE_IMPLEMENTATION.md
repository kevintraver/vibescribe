# Transcription Pipeline Implementation

## Summary

This document defines the implementation steps for reliability fixes after the
pause-based submission change. It addresses transcript loading, line
finalization, pause semantics, and session duration accuracy.

## Goals

- Ensure transcripts reload correctly across app restarts.
- Avoid appending new speech to old transcript lines after long silences.
- Define and apply consistent pause behavior for audio buffers and timers.
- Preserve accurate session durations when pausing and stopping.

## Non-Goals

- Model accuracy tuning or diarization improvements.
- UI changes beyond necessary metadata handling.

## Open Decisions

- Should pausing discard in-flight speech buffers or submit them before pausing?
- Should paused duration be persisted to the database for historical sessions?

## Implementation Steps

### 1. Fix Transcript Loading Column

Files:
- `Vibescribe/Sources/Services/DatabaseManager.swift`

Changes:
- Update `loadLines` query to select `speaker` (not `source`).
- Keep legacy compatibility by detecting `source` at runtime or via a migration.

Acceptance:
- Existing transcripts reload correctly on startup.
- Fresh installs with no legacy data load properly.

### 2. Line Finalization After Silence

Files:
- `Vibescribe/Sources/Services/TranscriptionService.swift`

Changes:
- Track silence duration even when no new samples are arriving.
- Clear `currentLineIds` once `silenceDurationSeconds` elapses after last speech,
  regardless of whether a buffer is currently non-empty.

Acceptance:
- After a long pause, new speech begins a new transcript line.

### 3. Pause Semantics and Buffer Reset

Files:
- `Vibescribe/Sources/Services/TranscriptionService.swift`

Changes:
- On pause, clear `micSpeechBuffer`/`appSpeechBuffer` and reset
  `micSilenceStart`/`appSilenceStart` to avoid stale submissions.
- Decide between discard vs submit behavior for in-flight buffers and implement
  it consistently.

Acceptance:
- Pausing never results in immediate stale submissions on resume.
- Post-resume speech is not merged with pre-pause audio.

### 4. Session Duration Accuracy on Stop

Files:
- `Vibescribe/Sources/Models/Session.swift`
- `Vibescribe/Sources/Models/AppState.swift`

Changes:
- On stop, if `pauseStartTime` is set, fold that time into `pausedDuration`
  and clear `pauseStartTime` before finalizing `endTime`.

Acceptance:
- Session duration is stable and consistent after stopping while paused.

### 5. Optional: Persist Pause Metadata

Files:
- `Vibescribe/Sources/Services/DatabaseManager.swift`
- `Vibescribe/Sources/Models/Session.swift`

Changes:
- If persisting pause data, add columns to `sessions` (e.g. `paused_duration`).
- Update save/load to include the new fields and provide a migration path.

Acceptance:
- Session duration remains accurate after app relaunch.

## Testing Plan

- Start a session, speak, pause, wait, resume, speak again.
- Confirm transcript lines do not merge across the pause.
- Stop while paused and verify the duration is correct in the UI.
- Relaunch app and verify transcripts reload with correct speakers.

## Risks

- Schema changes require careful migration to avoid data loss.
- Silence detection changes could alter perceived latency if mis-tuned.
