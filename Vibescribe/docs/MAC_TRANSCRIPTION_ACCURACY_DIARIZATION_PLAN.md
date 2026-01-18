# Mac Transcription Accuracy + Diarization Improvement Plan

## Scope
- macOS only (ignore iOS)
- Focus: ASR accuracy + diarization quality across the transcription apps

## Reviewed Code (key areas)
- FluidAudio diarization pipeline + configs: `FluidAudio/Sources/FluidAudio/Diarizer/Core/*`, `FluidAudio/Sources/FluidAudio/Diarizer/Offline/Core/*`
- Audio conversion + VAD: `FluidAudio/Sources/FluidAudio/Shared/AudioConverter.swift`, `FluidAudio/Sources/FluidAudio/VAD/*`
- App integrations:
  - FluidVoice meeting transcription: `FluidVoice/Sources/Fluid/Services/MeetingTranscriptionService.swift`
  - VoiceInk cloud transcription (Soniox): `VoiceInk/VoiceInk/Services/CloudTranscription/SonioxTranscriptionService.swift`
  - Hex/Handy transcription flows: `Hex/Hex/Features/Transcription/*`, `Handy/src-tauri/src/managers/transcription.rs`

## Observations (Mac)
- Diarization accuracy is mostly config-driven (offline step ratio, overlap handling, min segment duration, clustering thresholds) and defaults lean speed-first.
- Audio conversion lacks a normalization/cleanup path known to fix multi-speaker collapse on messy inputs.
- VAD defaults are strict (high threshold), likely reducing recall in quiet speech.
- Some Mac app flows do not run diarization at all (FluidVoice meeting transcription) or explicitly disable it (VoiceInk Soniox request).

## Plan
1. Establish Mac baselines using existing tooling
   - Run FluidAudio diarization benchmarks (streaming + offline) and a small real-world test set.
   - Capture DER/RTFx, miss/FA/SE breakdowns, and failure cases to target.

2. Improve audio preprocessing + VAD for Mac
   - Add a macOS-only normalization/cleanup path for diarization/file pipelines, gated by format detection.
   - Tune VAD defaults for higher recall in file/meeting workflows (lower threshold, segmentation adjustments).

3. Upgrade diarization configs for accuracy mode
   - Offline diarizer: increase step ratio, allow overlaps, reduce min segment duration.
   - Expose speaker count constraints (min/max/exact) where user knows the count.
   - Refine SpeakerManager thresholds and post-processing to reduce fragmentation.

4. Wire diarization into Mac app flows
   - FluidVoice meeting transcription: add diarization stage and speaker-labeled output.
   - VoiceInk Soniox: add a diarization toggle (enable speaker labels when desired).
   - Keep Hex/Handy as text-only unless explicitly needed.

5. Re-run benchmarks and iterate
   - Compare before/after metrics, adjust thresholds, and lock in Mac defaults.

## Decision Points
- Which app should be the first integration target (FluidVoice vs VoiceInk)?
- Do you want a user-visible “Accuracy vs Speed” toggle, or make accuracy the default on Mac?
