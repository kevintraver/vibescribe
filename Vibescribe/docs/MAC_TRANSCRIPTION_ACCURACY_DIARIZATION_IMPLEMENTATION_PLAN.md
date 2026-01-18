# Mac Transcription Accuracy + Diarization Implementation Plan (VibeScribe)

## Goals
- Improve ASR accuracy for mic and app audio without hurting realtime latency.
- Add optional diarization for multi-speaker remote audio (app audio only).
- Keep the default UX simple: "You" vs "Remote" unless diarization is enabled.

## Decisions Needed
- Diarization mode: streaming vs post-session.
- Default behavior on Mac: accuracy-first vs speed-first.
- Where diarization applies: app audio only vs mixed stream.

## Phase 0: Baseline + Instrumentation
- Define a small, repeatable test set (mic-only, app-only, mixed, quiet speech).
- Add metrics logging for:
  - Chunk latency (capture -> transcript line)
  - VAD hit/miss rates (mic vs app)
  - WER/CER samples for mic + app
  - DER for app-only diarization test clips
- Capture failure cases (quiet rooms, crosstalk, app audio with music).

## Phase 1: Audio Preprocessing + VAD Tuning
- Add per-source normalization/cleanup for app audio before transcription/diarization.
- Implement noise-floor calibration at session start (mic + app).
- Use per-source VAD thresholds (lower for app audio, adaptive for mic).
- Add an internal "accuracy mode" preset that enables more aggressive VAD recall.

## Phase 2: Diarization Integration (App Audio)
- If post-session:
  - Store app audio to disk when diarization is enabled.
  - Run FluidAudio offline diarizer after stop.
  - Map diarization segments to transcript lines by timestamp.
- If streaming:
  - Feed app audio chunks into diarizer in parallel.
  - Buffer diarization results and update speaker labels in-place.
- Expose speaker constraints (min/max/exact) when user knows speaker count.

## Phase 3: Data Model + UI
- Extend DB schema to store:
  - Speaker ID per line (or per token segment)
  - Start/end timestamps for lines
  - Optional diarization confidence
- Add UI toggle: "Enable speaker labels (remote audio)".
- Display labels as "Remote 1/Remote 2" when diarization is on.
- Keep copy/export behavior as text-only by default.

## Phase 4: Evaluation + Rollout
- Re-run baseline suite and compare DER/RTFx/latency.
- Validate no regression in realtime UX on Apple Silicon.
- Gate diarization behind a toggle until metrics stabilize.

## Risks / Notes
- Streaming diarization may increase latency; post-session is safer for MVP.
- Storing raw app audio increases disk usage; needs retention policy.
- Mixed-stream diarization is likely unnecessary given separate mic/app capture.
