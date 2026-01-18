# Pause-Based Audio Submission

## Problem

The previous implementation used **fixed 1.5-second chunk intervals** for audio processing. A timer fired every 1.5s and submitted whatever audio was in the buffer to Parakeet for transcription. This caused accuracy issues because:

1. Chunks could split words mid-syllable (e.g., "hel-" in one chunk, "-lo" in the next)
2. Chunks with mostly silence confused the model
3. Natural speech pauses didn't align with arbitrary 1.5s boundaries
4. The model received incomplete utterances, reducing context for accurate transcription

---

## Solution: Pause-Based Submission

Instead of fixed intervals, the new approach:

1. **Continuously monitors** audio at 100ms intervals
2. **Accumulates speech** into a buffer while talking
3. **Detects silence** (400ms threshold) to identify end of utterance
4. **Submits complete utterances** to the model

---

## File-by-File Changes

### `Sources/Services/TranscriptionService.swift`

#### Removed

```swift
private let chunkDurationSeconds: TimeInterval = 1.5
private var chunkSamples: Int { Int(sampleRate * chunkDurationSeconds) }
```

#### Added - Configuration

```swift
private let pollIntervalSeconds: TimeInterval = 0.1    // Check every 100ms
private let speechEndDelaySeconds: TimeInterval = 0.4  // Submit after 400ms silence
private let minSpeechSamples: Int = 4800               // Min 300ms of speech (16000 * 0.3)
```

#### Added - State Tracking

```swift
// Accumulated speech waiting for silence
private var micSpeechBuffer: [Float] = []
private var appSpeechBuffer: [Float] = []

// When silence started (nil = currently speaking)
private var micSilenceStart: Date?
private var appSilenceStart: Date?
```

#### Changed - Timer Setup

```swift
// OLD: Fire every 1.5s, process fixed chunks
chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkDurationSeconds, repeats: true) { ... }

// NEW: Poll every 100ms, detect speech/silence transitions
chunkTimer = Timer.scheduledTimer(withTimeInterval: pollIntervalSeconds, repeats: true) { ... }
```

#### Changed - Processing Flow

Old flow (`processChunks`):

```
Timer fires → Check if buffer >= 24000 samples → Flush & transcribe
```

New flow (`pollAudio` → `processMicSamples` → `checkMicSilenceTimeout`):

```
Timer fires (100ms) →
  Get samples from capture buffer →
  Calculate RMS →
  If speech (RMS >= threshold):
    Append to speechBuffer
    Reset silenceStart
  If silence (RMS < threshold):
    If speechBuffer not empty and silenceStart is nil:
      Set silenceStart = now (transition to silence)
    If silenceStart exists and elapsed >= 400ms:
      Submit speechBuffer to model
      Clear speechBuffer
```

#### New Methods

| Method | Purpose |
|--------|---------|
| `pollAudio()` | Called every 100ms, polls both mic and app buffers |
| `processMicSamples(_:)` | Accumulates mic speech, detects silence transitions |
| `processAppSamples(_:)` | Accumulates app speech, detects silence transitions |
| `checkMicSilenceTimeout()` | Checks if 400ms silence elapsed, triggers submission |
| `checkAppSilenceTimeout()` | Same for app audio |
| `transcribeMicSamples(_:)` | Sends accumulated mic speech to Parakeet |
| `transcribeAppSamples(_:)` | Sends accumulated app speech to Parakeet (with diarization) |

---

### `Sources/Services/FluidAudioProvider.swift`

#### Changed - ASR Configuration

```swift
// OLD: Default config
let manager = AsrManager(config: .default)

// NEW: Custom TDT config with doubled maxSymbolsPerStep
let tdtConfig = TdtConfig(maxSymbolsPerStep: 20)  // Default was 10
let asrConfig = ASRConfig(tdtConfig: tdtConfig)
let manager = AsrManager(config: asrConfig)
```

**Why:** `maxSymbolsPerStep` controls how many tokens the TDT decoder can emit per audio frame. Doubling it allows faster speech to be decoded without truncation.

---

### `Sources/Models/Session.swift`

#### Added - Pause Tracking Properties

```swift
var pausedDuration: TimeInterval = 0    // Total time spent paused
var pauseStartTime: Date?               // When current pause started (nil if not paused)
```

#### Changed - Duration Calculation

```swift
// OLD: Simple elapsed time
var duration: TimeInterval {
    let end = endTime ?? Date()
    return end.timeIntervalSince(startTime)
}

// NEW: Subtract paused time
var duration: TimeInterval {
    let end = endTime ?? Date()
    let totalElapsed = end.timeIntervalSince(startTime)
    let currentPauseTime = pauseStartTime.map { Date().timeIntervalSince($0) } ?? 0
    return totalElapsed - pausedDuration - currentPauseTime
}
```

#### Added - Pause/Resume Methods

```swift
func pause() {
    guard pauseStartTime == nil else { return }
    pauseStartTime = Date()
}

func resume() {
    guard let pauseStart = pauseStartTime else { return }
    pausedDuration += Date().timeIntervalSince(pauseStart)
    pauseStartTime = nil
}
```

---

### `Sources/Models/AppState.swift`

#### Changed - Hook Session Pause/Resume

```swift
func pauseRecording() {
    guard recordingState.canPause else { return }
    recordingState = .paused
    currentSession?.pause()  // NEW: Track pause start time
    // ...
}

func resumeRecording() {
    guard recordingState.canResume else { return }
    recordingState = .recording
    currentSession?.resume()  // NEW: Accumulate paused duration
    // ...
}
```

---

## Data Flow Comparison

### Before (Fixed Chunks)

```
Audio → Buffer → [1.5s timer] → Flush 24000 samples → Transcribe → Result
                     ↑
            May split mid-word
```

### After (Pause-Based)

```
Audio → Buffer → [100ms poll] → RMS check
                      ↓
              Speech? → Accumulate in speechBuffer
              Silence? → Start silence timer
                              ↓
                      400ms elapsed? → Submit complete utterance → Transcribe → Result
```

---

## Key Parameters

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `pollIntervalSeconds` | 0.1s | How often to check for speech/silence |
| `speechEndDelaySeconds` | 0.4s | Silence duration before submitting |
| `minSpeechSamples` | 4800 | Minimum samples (300ms) to transcribe |
| `maxSymbolsPerStep` | 20 | TDT decoder tokens per frame (doubled) |

---

## Expected Improvements

1. **Better accuracy** - Complete utterances sent to model instead of arbitrary chunks
2. **No split words** - Speech boundaries align with natural pauses
3. **Less noise** - Silence-heavy chunks no longer confuse the model
4. **Faster speech support** - Doubled `maxSymbolsPerStep` handles rapid talkers
