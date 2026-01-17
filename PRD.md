# Vibescribe PRD

## Product Overview

A macOS desktop app for live transcription of collaborative conversations. Captures real-time transcript with one-click copy to clipboard.

**Target Users:**
- Developers (pair programming, technical discussions, code reviews)
- Creative teams (brainstorms, design critiques, content planning)

---

## Product Decisions

### Core Behavior
| Decision | Choice | Notes |
|----------|--------|-------|
| **Session flow** | Manual start/stop + global hotkeys | User clicks Record/Stop, or uses keyboard shortcut from anywhere |
| **Window mode** | Normal window (default) | Option to toggle floating/always-on-top. Menu bar app in v2 |
| **Window size** | 600x500 | Sidebar (150px) + transcript area. Wider for session history. |
| **Speaker labels** | "You" / "Remote" | Based on audio source (mic = You, system = Remote) |
| **Line definition** | Continuous speech segment | New line on speaker change or 1.5s silence |
| **Copy behavior** | Text only (default) | Copies just the words, no speaker label. More options in v2 |
| **Timestamps** | Record but don't display | Stored in data model for future use, hidden in MVP UI |
| **macOS target** | macOS 15 Sequoia | Latest APIs, Apple Silicon optimized |
| **Hardware target** | Apple Silicon only (M1+) | ANE required for real-time performance, no Intel support |

### Audio Capture
| Decision | Choice | Notes |
|----------|--------|-------|
| **Mic selection** | System default + optional picker | Use system default, but allow selecting another mic |
| **System audio** | Optional single app picker | User can select an app, or skip (mic-only mode for Loopback users) |
| **Source requirement** | Mic required, app optional | Can record mic-only or mic + app. App-only not supported. |
| **Source selection UI** | Start recording dialog | When clicking Record, show quick picker for mic + optional app |
| **Remember sources** | Yes, auto-select last used | Pre-select previous mic + app on next launch |
| **App picker contents** | Apps with audio capability | Filter to apps known to produce audio (browsers, Zoom, Slack, etc.) |
| **No apps available** | Show empty state, mic-only | Display message, allow starting mic-only recording |

### Session & UI
| Decision | Choice | Notes |
|----------|--------|-------|
| **Sessions** | New session each recording | Every Start creates fresh session |
| **Session naming** | Click to rename | Default is timestamp, user can rename |
| **Session limit** | Warn at 1 hour, prompt for new | Modal prompting to start new session |
| **Storage limit** | Warn at 1GB | Show warning when database exceeds 1GB, suggest cleanup |
| **Transcript editing** | Read-only | No editing, preserves original transcription |
| **Auto-scroll** | Pause if user scrolls up | Resume auto-scroll when user scrolls back to bottom |
| **View history while recording** | Yes, recording continues | Can browse past sessions, recording runs in background |
| **Long sessions** | Paginate old lines | Show recent lines, load older ones on scroll |
| **Sidebar list** | Recent 50 + Load more | Show recent 50 sessions, button to load more |
| **Visual style** | Native macOS | System fonts, standard colors, matches OS appearance |
| **Session deletion** | Yes, swipe or button | Allow deleting sessions from sidebar in MVP |
| **Session export** | Yes, plain text | Export session as .txt file with speaker labels |
| **Crash recovery** | Prompt on next launch | Detect crash, offer to recover last session |
| **Sidebar shows duration** | Yes | Display recording duration alongside date/time |
| **Session retention** | Infinite until deleted | Keep all sessions forever, user manually deletes |
| **Window state** | Remember position/size | Restore window frame on next launch |
| **Multi-window** | Single window only | One window for sidebar + transcript + controls |

### Copy & Interaction
| Decision | Choice | Notes |
|----------|--------|-------|
| **Copy feedback** | Brief toast/checkmark | Small confirmation that disappears after 1-2 seconds |
| **Multi-select copy** | Yes, Cmd+click | Select multiple lines, copy all at once |
| **Multi-copy format** | Newline separated, no labels | Each line on its own line, text only |
| **Copy All button** | No | Use Cmd+A to select all, then copy |
| **Keyboard shortcuts** | Standard macOS | Cmd+C copy, Cmd+S stop, Cmd+P pause/resume |
| **Dock presence** | Always show in dock | Standard macOS app behavior |

### Global Hotkey
| Decision | Choice | Notes |
|----------|--------|-------|
| **Hotkey** | User configurable | Let user set their own shortcut in settings |
| **Hotkey when not recording** | Start with last sources | No dialog, immediately start using remembered mic/app |
| **Hotkey when paused** | Resume recording | Hotkey resumes capture from paused state |
| **Hotkey brings to foreground** | Configurable | User can choose whether hotkey brings app to front |
| **Hotkey debounce** | 500ms | Ignore repeated presses within 500ms to prevent accidental toggles |
| **Recording indicator** | Red dot + pulse animation | Classic recording indicator in window |
| **Click Record while recording** | Ignore (no-op) | Clicking Record again does nothing if already recording |

### Error Handling
| Decision | Choice | Notes |
|----------|--------|-------|
| **Permissions timing** | During first-run setup | Request mic + screen recording upfront before anything else |
| **Permissions denied** | Inline error + retry | Display message in UI with button to open System Settings |
| **Model download failure** | Show retry button | Block recording until download succeeds |
| **Model download blocking** | Yes, block until complete | Cannot record until model is downloaded |
| **Transcription failures** | Silent skip | Skip failed chunk, continue recording |
| **Model** | Parakeet v3 only | Multilingual, simpler UX, one model to download |
| **App quits during recording** | Pause and notify | Pause system audio capture, show notification, continue mic |
| **Mic disconnect** | Pause and alert | Pause recording, show alert to reconnect or stop |
| **Hotkey conflict** | Warn on conflict | Show warning if chosen hotkey is already in use system-wide |
| **Model updates** | No auto-update check | Use downloaded model until user clears cache |
| **Clear model cache** | Yes, in Settings | Allow users to delete model and re-download |
| **Diagnostics export** | Yes, in Settings | Export logs + system info (no audio) for troubleshooting |
| **Always-on-top persistence** | UserDefaults | Remember preference, apply on next launch |
| **Mic unavailable on launch** | Fall back to system default | If last-used mic is unplugged, silently use system default |
| **Model download interruption** | Resume from where left off | Support partial downloads, continue on network reconnect |
| **System audio capture failure** | Pause and alert | If stream fails mid-session, pause recording and show dialog |
| **Unsupported macOS version** | Show alert and quit | Display message explaining macOS 15+ required, then exit |
| **1-hour warning type** | Modal dialog | Requires user action: "Continue Recording" or "Stop and Save" |
| **Event logging** | Structured logs to file | Log start/stop/pause/errors for diagnostics export |

### Transcription Behavior
| Decision | Choice | Notes |
|----------|--------|-------|
| **Line ordering** | Timestamp-based interleaving | Use sub-chunk timestamps to interleave mic/app lines accurately |
| **Line updates** | Append to existing line | Mutable lines - continue adding until silence or speaker change |
| **Typing indicator** | Subtle blinking cursor | Show at end of line while transcription continues |
| **Silence detection** | Silero VAD (neural) | FluidAudio's Silero VAD: <2ms inference, 32ms chunks, robust to noise |
| **Silence duration** | User configurable | Default 1.5s silence ends a line. User can adjust in Settings. |
| **Chunk boundaries** | Smart boundary detection | Detect silence/pauses for natural boundaries, avoid cutting words |
| **Simultaneous speech** | Interleaved by timestamp | When both speak at once, order lines by actual timing |
| **Parallel transcription** | Yes, both streams concurrent | Transcribe mic and app audio in parallel for lower latency |
| **Transcription failure** | Silent skip | Skip failed chunk, don't show error marker |
| **Browser audio** | Capture all app audio | No tab-specific capture. All browser audio captured together. |
| **Noise reduction** | None | Send raw audio to model. Let Parakeet handle it. |
| **Language detection** | Auto-detect from audio | Parakeet v3 auto-detects. No user input needed. |
| **Profanity** | Show raw, uncensored | Transcribe exactly what's said. |
| **Confidence display** | No distinction | Show all text the same regardless of confidence level |
| **Target latency** | Under 2 seconds | Text should appear within 2s of speech |
| **Processing indicator** | Subtle spinner/dots | Show transcription in progress during any lag |
| **Persistence** | SQLite database | More robust than JSON, supports queries |
| **Auto-save frequency** | Every chunk (~1.5s) | Write after each transcription for maximum data safety |
| **Draft text** | Yes, show while processing | Display provisional text that updates when transcription completes |
| **Timestamp storage** | Start time only | Record when each line began, sufficient for ordering |
| **Mid-session source change** | Allowed, same session | Can switch mic/app mid-recording, session continues |
| **Source change indication** | None | Transcript continues seamlessly, no marker when sources change |
| **Pause behavior** | Mute streams (keep alive) | Keep audio streams alive but stop processing - faster resume |
| **Buffer overflow** | Keep all, catch up | Never drop audio, transcription catches up (FluidAudio is fast) |
| **Offline mode** | Fully offline after download | No network required after initial model download |
| **Localization** | English only for MVP | UI strings in English, localization is post-MVP |

---

## Research Findings

### Transcription Engines Comparison

| Engine | Used By | Pros | Cons |
|--------|---------|------|------|
| **WhisperKit** | Hex | Swift-native, CoreML optimized | Larger models, slower cold start |
| **whisper.cpp** | VoiceInk, FluidVoice | Lightweight, fast, many model sizes | C++ binding complexity |
| **Parakeet + FluidAudio** | All 4 apps | Apple Silicon optimized, fastest inference | ~650MB model download |
| **Apple Speech** | VoiceInk, FluidVoice | Zero download, built-in | Less accurate, no customization |

### FluidAudio/Parakeet Details

- **Parakeet** = CoreML speech-to-text model (TDT architecture, ~650MB)
  - v2: English-only, 2.1% WER (highest accuracy)
  - v3: Multilingual, 25 European languages
- **FluidAudio** = Pure Swift framework that runs Parakeet models
  - GitHub: https://github.com/FluidInference/FluidAudio
  - **DeepWiki available**: Use `mcp__deepwiki__read_wiki_contents` for detailed documentation
  - Handles model download from HuggingFace, caching, inference
  - Zero external dependencies for core ASR

### Why FluidAudio over WhisperKit

| Metric | FluidAudio (Parakeet) | WhisperKit |
|--------|----------------------|-----------|
| **Speed** | 145-210x RTFx | ~50-80x RTFx |
| **English WER** | 2.1% (v2) | ~3-5% |
| **Languages** | 25 European (v3) | 99 |
| **Memory** | 1.2MB streaming | Higher |
| **Integration** | Pure Swift, SPM direct | MLX-based |
| **Cold start** | ~3.5s | Similar |

For developer/creative team users (English + European languages), FluidAudio's speed and accuracy advantages outweigh WhisperKit's language breadth.

### Real-Time Transcription

| App | Real-time? | Approach |
|-----|-----------|----------|
| **FluidVoice** | Yes (macOS 26+ only) | Apple SpeechAnalyzer streaming API |
| **Hex, Handy, VoiceInk** | No | Post-recording or chunked |

**MVP Approach**: Chunked "near real-time" — buffer 1.5-2s audio chunks, transcribe each chunk as it completes, append to transcript.

### Audio Capture Approaches

| Approach | Used By | Pros | Cons |
|----------|---------|------|------|
| **AVAudioEngine** | FluidVoice | Flexible, streaming support | More setup code |
| **AVAudioRecorder** | Hex | Simple API | Less control |
| **AUHAL** | VoiceInk | Real-time callbacks, low latency | Complex, low-level |

### Speaker Diarization Finding

**None of the 4 researched apps implement true speaker diarization.** It requires separate models and adds significant complexity.

**MVP Approach**: Use audio source as speaker proxy:
- Mic input → "You"
- System audio → "Remote"

#### Diarization Research (for Post-MVP)

| Solution | Architecture | RTF | Latency | DER | License |
|----------|--------------|-----|---------|-----|---------|
| **FluidAudio (Sortformer)** | EEND streaming | ~0.02x | ~1.04s | ~17.7% | CC-BY 4.0 ✓ |
| **FluidAudio (Pyannote)** | Modular + clustering | ~0.02x | Batch | ~17.7% | MIT code, check weights |
| **Apple SpeechAnalyzer** | Native (black box) | ~0.015x | <1.0s | Unknown | Bundled with OS |
| **Sherpa-Onnx** | ONNX Runtime | ~0.1-0.5x | Variable | Variable | Apache 2.0 |
| **WhisperX** | PyTorch (Python) | >1.0x | Batch only | ~pyannote | MIT |

**Key Finding**: FluidAudio includes **two diarization approaches**:

1. **Sortformer (streaming)** - Best for real-time UI
   - End-to-End Neural Diarization (EEND) - single pass, no clustering
   - ~1.04s latency, processes 50x faster than real-time
   - CC-BY 4.0 license (commercial OK with NVIDIA attribution)

2. **Pyannote (batch)** - Best for final accuracy
   - Modular pipeline: segmentation → embeddings → clustering
   - Higher accuracy for complex multi-speaker scenarios
   - MIT code, but verify model weights for commercial use

**FluidAudio Components**:
- **Silero VAD**: 32ms chunks, <2ms inference, ~15MB memory, <5% CPU
- **Diarization**: Sortformer or Pyannote (both CoreML-optimized for ANE)
- **ASR**: Parakeet (already using for transcription)

```swift
// Streaming diarization (real-time)
let sortformer = SortformerDiarizer()
sortformer.processSamples(audioBuffer) // Returns speaker labels per frame

// Batch diarization (post-recording)
let diarizer = DiarizerManager(config: .default)
let result = diarizer.diarize(audioData: buffer)
```

**Strategic Recommendation**:
- **Real-time (live view)**: Use Sortformer - low latency, streaming-native
- **Post-processing (final transcript)**: Use Pyannote - higher accuracy

**Integration Approach** (post-MVP):
1. Add `DiarizationService` with toggle for Sortformer vs Pyannote mode
2. Run diarization in parallel with transcription (same audio buffer)
3. Merge speaker IDs with transcription timestamps
4. Replace source-based labels ("You"/"Remote") with true speaker IDs

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Stack | SwiftUI (native macOS) | Best UX, native permissions |
| Audio capture | AVAudioEngine (mic) + ScreenCaptureKit (system) | Proven pattern from FluidVoice |
| Transcription | **FluidAudio/Parakeet v3** (MVP) | Fastest (210x RTFx), best accuracy, pure Swift |
| Engine abstraction | Protocol-based | Swap engines without changing core logic |
| Speaker separation | Audio source proxy (mic vs system) | Practical MVP approach |
| Persistence | SQLite in App Support | Robust, auto-save every chunk |

### Engine Abstraction

```swift
protocol TranscriptionProvider {
    var name: String { get }
    var isAvailable: Bool { get }
    var isReady: Bool { get }

    func prepare(progressHandler: ((Double) -> Void)?) async throws
    func transcribe(_ samples: [Float]) async throws -> TranscriptionResult
    func modelsExistOnDisk() -> Bool
    func clearCache() async throws
}
```

**MVP**: `FluidAudioProvider` (Parakeet v3)
**Future**: `WhisperKitProvider`, `AppleSpeechProvider`

---

## MVP Architecture

```
┌─────────────────────────────────────────────────┐
│                   SwiftUI App                   │
├─────────────────────────────────────────────────┤
│  TranscriptView                                 │
│  ├── Source-labeled lines (You / Remote)       │
│  ├── Copy button per line                       │
│  └── Auto-scroll with history                   │
├─────────────────────────────────────────────────┤
│  AudioCaptureManager                            │
│  ├── Mic input (AVAudioEngine)                  │
│  └── System audio (ScreenCaptureKit)            │
├─────────────────────────────────────────────────┤
│  TranscriptionService                           │
│  └── TranscriptionProvider (protocol)           │
│      └── FluidAudioProvider (MVP - Parakeet v3) │
│      └── [Future: WhisperKit, AppleSpeech...]   │
├─────────────────────────────────────────────────┤
│  SessionManager                                 │
│  ├── Transcript storage (SQLite)                │
│  └── Session history                            │
└─────────────────────────────────────────────────┘
```

---

## MVP Features (v0.1)

### Recording Flow
- [ ] Record button opens "Start Recording" dialog
- [ ] Dialog shows: mic dropdown, app dropdown (for system audio)
- [ ] Pre-select last used mic and app (fall back to system default if unavailable)
- [ ] Start button begins dual capture (mic + selected app)
- [ ] **Large, prominent Pause/Resume button** while recording
- [ ] **Large Stop button** to end session
- [ ] Global hotkey (user configurable) toggles recording (500ms debounce)
- [ ] Red dot + pulse animation while recording (pauses when paused)
- [ ] Stop button ends recording, auto-saves session
- [ ] Allow changing mic/app sources mid-session (session continues)

### Audio Capture
- [ ] Mic capture via AVAudioEngine (16kHz mono Float32)
- [ ] System audio capture via ScreenCaptureKit (single app filter)
- [ ] Dual capture: mic and app audio simultaneously
- [ ] Dropdown to select mic (default: system default)
- [ ] Dropdown to select running app for system audio

### Transcription
- [ ] FluidAudio/Parakeet v3 (multilingual)
- [ ] Chunked processing: buffer 1.5s, transcribe, append
- [ ] New line on speaker change OR 1.5s silence
- [ ] Source labels: "You" (mic) / "Remote" (system audio)
- [ ] Draft text shown while processing (updates when complete)
- [ ] Mutable lines: append to existing line until silence/speaker change

### Window Layout
- [ ] Window size: 600x500 (wider for sidebar + transcript)
- [ ] Left sidebar (~150px fixed): session history list
- [ ] Right area: transcript view + controls
- [ ] Resizable window, sidebar stays fixed width
- [ ] Native macOS styling (system fonts, colors)
- [ ] Always-on-top toggle

### Transcript UI
- [ ] Always auto-scroll to bottom
- [ ] Copy button per line (text only, no label)
- [ ] Read-only (no editing)

### Recording Controls (highly visible)
- [ ] **Large Pause button** (yellow/orange) - pauses capture, keeps session open
- [ ] **Large Resume button** (green) - resumes capture after pause
- [ ] **Large Stop button** (red) - ends session, auto-saves
- [ ] Recording indicator: red dot + pulse (animates when recording, static when paused)
- [ ] Visual state: "Recording" / "Paused" / "Stopped" clearly shown

### Session Lifecycle
- **Recording**: Capturing audio, transcribing, auto-saving continuously
- **Paused**: Audio capture stopped, session still open, can resume
- **Stopped**: Session ended, transcript visible, "New Recording" button shown

### Session Management
- [ ] Auto-save every chunk (~1.5s) to SQLite (no data loss on crash)
- [ ] Pause just stops capture, session remains open
- [ ] Stop ends session, transcript stays visible
- [ ] "New Recording" button appears after Stop
- [ ] Warn at 1 hour with prompt to start new session
- [ ] SQLite database in `~/Library/Application Support/Vibescribe/`
- [ ] Swipe or button to delete sessions from sidebar

### Session History (Sidebar)
- [ ] Left sidebar shows list of past sessions
- [ ] Each entry: date/time, duration, preview of first line
- [ ] Chronological order (most recent first)
- [ ] Click session to view full transcript on right
- [ ] Current/active session highlighted at top

### First-Run Setup
- [ ] Request mic permission (show inline error + retry if denied)
- [ ] Request screen recording permission (for system audio)
- [ ] Model download progress indicator (~650MB, 3-5 min)

### Settings (Preferences Window)
- [ ] Global hotkey configuration
- [ ] Silence duration threshold (default: 1.5s) - how long silence before new line
- [ ] Always-on-top toggle (persisted)
- [ ] Clear model cache button
- [ ] Export diagnostics button (logs + system info, no audio)

### Data Model
- [ ] `TranscriptLine`: text, source (you/remote), timestamp (hidden in MVP)
- [ ] `Session`: id, startTime, endTime, duration, lines[]
- [ ] Store last used mic ID and app bundle ID in UserDefaults
- [ ] Store window frame in UserDefaults

---

## Post-MVP Features

### v0.2
- [ ] Menu bar presence/app mode
- [ ] Copy entire transcript button
- [ ] Copy with speaker labels option
- [ ] Show/hide timestamps toggle
- [ ] Custom speaker labels
- [ ] Audio recording + playback (save raw audio alongside transcripts)
- [ ] UI localization (prepare NSLocalizedString infrastructure)

### Future
- [ ] True speaker diarization via FluidAudio (pyannote models, 7-11% DER)
- [ ] LLM post-processing (cleanup, summarize)
- [ ] Export formats (markdown, JSON)
- [ ] Additional transcription engines (WhisperKit for 99 languages)
- [ ] Search/filter sessions in sidebar
- [ ] Speaker enrollment (learn voices for consistent labeling)

---

## Dependencies

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/FluidInference/FluidAudio", from: "0.8.0"),
]
```

**Note**: FluidAudio is pure Swift with zero external dependencies for core ASR. Models (~650MB for Parakeet v3) are downloaded from HuggingFace on first run and cached in `~/Library/Application Support/FluidAudio/Models/`.

---

## Files to Create

```
Vibescribe/
├── Vibescribe.xcodeproj
├── Vibescribe/
│   ├── VibescribeApp.swift              # App entry point, window config
│   ├── ContentView.swift                # Main window container
│   ├── Views/
│   │   ├── SidebarView.swift            # Session history list (left)
│   │   ├── SessionRowView.swift         # Single session in sidebar
│   │   ├── TranscriptView.swift         # Transcript list with auto-scroll
│   │   ├── TranscriptLineView.swift     # Single line + copy button
│   │   ├── ControlsView.swift           # Pause/Resume/Stop, always-on-top
│   │   ├── StartRecordingDialog.swift   # Mic + app picker before recording
│   │   ├── SetupView.swift              # First-run: permissions + model download
│   │   ├── SettingsView.swift           # Hotkey config, preferences
│   │   └── RecordingIndicator.swift     # Red dot + pulse animation
│   ├── Models/
│   │   ├── TranscriptLine.swift         # Line model: text, source, timestamp
│   │   ├── Session.swift                # Session: id, times, lines[]
│   │   ├── AudioSource.swift            # Enum: .you (mic), .remote (app)
│   │   └── TranscriptionResult.swift    # Unified result from any provider
│   ├── Services/
│   │   ├── AudioCaptureManager.swift    # AVAudioEngine + ScreenCaptureKit
│   │   ├── MicCapture.swift             # AVAudioEngine tap for mic
│   │   ├── AppAudioCapture.swift        # ScreenCaptureKit for app audio
│   │   ├── TranscriptionService.swift   # Orchestrates providers + chunking
│   │   ├── TranscriptionProvider.swift  # Protocol for engine abstraction
│   │   ├── FluidAudioProvider.swift     # FluidAudio/Parakeet implementation
│   │   ├── DatabaseManager.swift        # SQLite persistence for sessions
│   │   ├── HotkeyManager.swift          # Global hotkey registration
│   │   ├── PermissionsManager.swift     # Mic + screen recording permissions
│   │   ├── DiagnosticsManager.swift     # Export logs + system info
│   │   └── EventLogger.swift            # Structured event logging (start/stop/pause/errors)
│   ├── Utilities/
│   │   └── ThreadSafeAudioBuffer.swift  # Lock-protected audio buffer
│   └── Vibescribe.entitlements          # Permissions
└── Vibescribe/Info.plist
```

---

## Implementation Order

1. **Project setup** — Create Xcode project, add FluidAudio dependency, configure entitlements
2. **Model management** — Download/load Parakeet model with progress UI
3. **Mic capture** — AVAudioEngine tap, 16kHz mono conversion
4. **Transcription** — FluidAudio integration, chunked processing
5. **Transcript UI** — Display lines with source labels, copy buttons
6. **System audio** — ScreenCaptureKit capture (requires screen recording permission)
7. **Session persistence** — SQLite database for sessions
8. **Settings** — Preferences window, hotkey config, silence thresholds
9. **Polish** — Always-on-top toggle, diagnostics export, setup flow

---

## Key Implementation Details

### Audio Format
All engines expect: **16kHz mono Float32**
```swift
let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                           sampleRate: 16000,
                           channels: 1,
                           interleaved: false)
```

### ScreenCaptureKit App-Specific Capture
```swift
import ScreenCaptureKit

// Get list of running apps with audio
let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
let appsWithAudio = content.applications.filter { $0.applicationName != "Vibescribe" }

// Create filter for specific app (e.g., Zoom)
let targetApp = appsWithAudio.first { $0.bundleIdentifier == "us.zoom.xos" }
let filter = SCContentFilter(desktopIndependentWindow: nil) // or app-specific filter

// Configure stream for audio only
let config = SCStreamConfiguration()
config.capturesAudio = true
config.sampleRate = 16000
config.channelCount = 1

// Create and start stream
let stream = SCStream(filter: filter, configuration: config, delegate: self)
try await stream.startCapture()
```

### Dual Audio Capture Architecture
```
┌─────────────────────────────────────────────────────┐
│                 AudioCaptureManager                 │
├─────────────────────────────────────────────────────┤
│  MicCapture (AVAudioEngine)                         │
│  ├── Input tap at 16kHz mono                        │
│  └── → micBuffer (ThreadSafeAudioBuffer)            │
├─────────────────────────────────────────────────────┤
│  AppCapture (ScreenCaptureKit)                      │
│  ├── SCStream filtered to single app                │
│  └── → appBuffer (ThreadSafeAudioBuffer)            │
├─────────────────────────────────────────────────────┤
│  ChunkProcessor (Timer every 1.5s)                  │
│  ├── Flush micBuffer → transcribe → "You" line      │
│  └── Flush appBuffer → transcribe → "Remote" line   │
└─────────────────────────────────────────────────────┘
```

### Chunked Transcription Pattern
1. **Audio buffering**: Collect samples in thread-safe buffer (separate for mic/app)
2. **Chunk trigger**: Timer fires every 1.5 seconds
3. **Silence detection**: If buffer has <1.5s of non-silence, wait for more
4. **Transcribe chunk**: Send chunk to FluidAudio
5. **Append result**: Add transcribed text with source label ("You" or "Remote")
6. **Line break logic**: New line if source changes OR 1.5s silence detected

```swift
// Chunk size: 1.5s minimum for Parakeet
let chunkDuration: TimeInterval = 1.5
let chunkSamples = Int(16000 * chunkDuration) // 24,000 samples
let silenceThreshold: Float = 0.01 // RMS below this = silence
```

### FluidAudio Setup
```swift
import FluidAudio

// Download & load models (first run: ~3-5 min, cached after)
let models = try await AsrModels.downloadAndLoad(version: .v3)

// Initialize manager
let asrManager = AsrManager(config: .default)
try await asrManager.initialize(models: models)

// Transcribe from Float32 samples (16kHz mono)
let result = try await asrManager.transcribe(samples, source: .system)
print(result.text)        // Transcribed text
print(result.confidence)  // 0.0-1.0
print(result.rtfx)        // Real-time factor (~210x on M4)
```

### Thread-Safe Audio Buffer
```swift
final class ThreadSafeAudioBuffer {
    private var buffer: [Float] = []
    private let lock = NSLock()

    func append(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(contentsOf: samples)
    }

    func flush() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let samples = buffer
        buffer.removeAll()
        return samples
    }

    func peek() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
```

### Start Recording Dialog
```swift
struct StartRecordingDialog: View {
    @State var selectedMic: AudioDeviceID?
    @State var selectedApp: SCRunningApplication?

    var body: some View {
        VStack {
            // Mic picker
            Picker("Microphone", selection: $selectedMic) {
                ForEach(availableMics) { mic in
                    Text(mic.name).tag(mic.id)
                }
            }

            // App picker (running apps with audio)
            Picker("Capture audio from", selection: $selectedApp) {
                ForEach(runningApps) { app in
                    Label(app.applicationName, image: app.icon)
                        .tag(app)
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Button("Start Recording") { startRecording() }
                    .keyboardShortcut(.return)
            }
        }
        .onAppear { loadLastUsedSources() }
    }
}
```

### UserDefaults Keys
```swift
enum DefaultsKey {
    static let lastMicID = "lastMicID"
    static let lastAppBundleID = "lastAppBundleID"
    static let globalHotkey = "globalHotkey"
    static let alwaysOnTop = "alwaysOnTop"
    static let windowFrame = "windowFrame"
    static let silenceDuration = "silenceDuration"      // Default: 1.5 seconds
}
```

---

## Verification Checklist

### First Run
- [ ] App launches on macOS 15
- [ ] Shows alert and quits on older macOS versions (14 and below)
- [ ] Prompts for mic permission
- [ ] Shows inline error + retry if mic denied
- [ ] Prompts for screen recording permission
- [ ] Model download starts with progress indicator
- [ ] Model download resumes after network interruption
- [ ] Model download completes (~3-5 min, ~650MB)
- [ ] App works fully offline after model is downloaded

### Recording Flow
- [ ] Click Record opens Start Recording dialog
- [ ] Dialog shows mic dropdown with available mics
- [ ] Dialog shows app dropdown with running apps
- [ ] Last used mic/app pre-selected on subsequent launches
- [ ] Start Recording begins capture
- [ ] Red dot + pulse animation visible while recording
- [ ] Pause button stops capture, keeps session open
- [ ] Resume button resumes capture after pause
- [ ] Stop button ends session, transcript stays visible
- [ ] "New Recording" button appears after Stop

### Transcription
- [ ] Speak into mic, see "You:" prefixed lines appear
- [ ] Play audio in selected app, see "Remote:" prefixed lines
- [ ] Lines appear within ~2s of speech (chunked processing)
- [ ] New line created after 1.5s silence
- [ ] Dual capture works: mic and app audio interleaved
- [ ] Draft text appears while processing, updates when complete
- [ ] Same line is appended to until silence or speaker change
- [ ] Can change mic/app sources mid-session (session continues)

### Window & Layout
- [ ] Window opens at 600x500
- [ ] Window is resizable
- [ ] Sidebar visible on left (~150px)
- [ ] Sidebar shows list of past sessions
- [ ] Click past session to view its transcript
- [ ] Current session highlighted in sidebar
- [ ] Transcript auto-scrolls to bottom
- [ ] Copy button on each line works
- [ ] Copied text is plain text (no speaker label)
- [ ] Always-on-top toggle works

### Global Hotkey
- [ ] Can configure custom hotkey in settings
- [ ] Hotkey toggles recording from any app
- [ ] Hotkey works when app is in background

### Session Management
- [ ] New session created each recording
- [ ] Session auto-saves every chunk to SQLite (no data loss on crash)
- [ ] Warning at 1 hour prompts to start new session
- [ ] SQLite database in `~/Library/Application Support/Vibescribe/`
- [ ] Past sessions appear in sidebar
- [ ] Can click past session to view its transcript
- [ ] Can delete sessions via swipe or button

### Settings
- [ ] Settings window opens from menu bar (Cmd+,)
- [ ] Can configure global hotkey
- [ ] Can adjust silence duration (1.5s default)
- [ ] Always-on-top toggle persists across launches
- [ ] Clear model cache works (deletes, prompts re-download)
- [ ] Export diagnostics creates log file

### Edge Cases
- [ ] No crash if selected app quits during recording
- [ ] Graceful handling if no apps with audio running
- [ ] Works with AirPods / external mics
- [ ] Window position/size restored on launch

---

## Future Engine Support

The `TranscriptionProvider` protocol enables adding engines without changing core logic:

| Engine | Implementation | When to Add |
|--------|----------------|-------------|
| **WhisperKit** | `WhisperKitProvider` | 99 languages support needed |
| **SwiftWhisper** | `SwiftWhisperProvider` | Intel Mac support, smaller models |
| **Apple Speech** | `AppleSpeechProvider` | Zero download option, instant start |
| **Apple SpeechAnalyzer** | `SpeechAnalyzerProvider` | True real-time streaming (macOS 26+) |

---

## References

- **FluidAudio**: https://github.com/FluidInference/FluidAudio
  - DeepWiki MCP available for detailed documentation
  - Includes transcription (Parakeet) AND diarization (pyannote) support
- **Research apps**: Hex, FluidVoice, VoiceInk, Handy (in `/Users/kevin/code/transcription-apps`)

### Diarization Research Sources
- [pyannote/pyannote-audio](https://github.com/pyannote/pyannote-audio) - Neural speaker diarization
- [FluidAudio Speaker Diarization](https://cocoapods.org/pods/FluidAudio) - Swift SDK with CoreML
- [Near-Real-Time Speaker Diarization on CoreML](https://inference.plus/p/low-latency-speaker-diarization-on)
- [WhisperX](https://github.com/m-bain/whisperX) - ASR with word-level timestamps & diarization
- [Resemblyzer](https://github.com/resemble-ai/Resemblyzer) - Voice embeddings for recognition
