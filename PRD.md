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

### Audio Capture
| Decision | Choice | Notes |
|----------|--------|-------|
| **Mic selection** | System default + optional picker | Use system default, but allow selecting another mic |
| **System audio** | Optional single app picker | User can select an app, or skip (mic-only mode for Loopback users) |
| **Source requirement** | Mic required, app optional | Can record mic-only or mic + app. App-only not supported. |
| **Source selection UI** | Start recording dialog | When clicking Record, show quick picker for mic + optional app |
| **Remember sources** | Yes, auto-select last used | Pre-select previous mic + app on next launch |
| **App picker contents** | All running apps | Show every running app, user picks which to capture |

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

### Copy & Interaction
| Decision | Choice | Notes |
|----------|--------|-------|
| **Copy feedback** | Brief toast/checkmark | Small confirmation that disappears after 1-2 seconds |
| **Multi-select copy** | Yes, Cmd+click | Select multiple lines, copy all at once |
| **Dock presence** | Always show in dock | Standard macOS app behavior |

### Global Hotkey
| Decision | Choice | Notes |
|----------|--------|-------|
| **Hotkey** | User configurable | Let user set their own shortcut in settings |
| **Hotkey when not recording** | Start with last sources | No dialog, immediately start using remembered mic/app |
| **Hotkey when paused** | Resume recording | Hotkey resumes capture from paused state |
| **Hotkey brings to foreground** | Configurable | User can choose whether hotkey brings app to front |
| **Recording indicator** | Red dot + pulse animation | Classic recording indicator in window |

### Error Handling
| Decision | Choice | Notes |
|----------|--------|-------|
| **Permissions timing** | During first-run setup | Request mic + screen recording upfront before anything else |
| **Permissions denied** | Inline error + retry | Display message in UI with button to open System Settings |
| **Model download failure** | Show retry button | Block recording until download succeeds |
| **Model download blocking** | Yes, block until complete | Cannot record until model is downloaded |
| **Transcription failures** | Show error marker | Display [Transcription Failed] in transcript |
| **Model** | Parakeet v3 only | Multilingual, simpler UX, one model to download |
| **App quits during recording** | Pause and notify | Pause system audio capture, show notification, continue mic |
| **Mic disconnect** | Pause and alert | Pause recording, show alert to reconnect or stop |
| **Hotkey conflict** | Warn on conflict | Show warning if chosen hotkey is already in use system-wide |

### Transcription Behavior
| Decision | Choice | Notes |
|----------|--------|-------|
| **Line ordering** | Timestamp-based interleaving | Use sub-chunk timestamps to interleave mic/app lines accurately |
| **Silence detection** | Per source, fixed 1.5s | 1.5s silence in mic ends "You" line. Not user-adjustable. |
| **Chunk boundaries** | Smart boundary detection | Detect silence/pauses for natural boundaries, avoid cutting words |
| **Simultaneous speech** | Interleaved by timestamp | When both speak at once, order lines by actual timing |
| **Parallel transcription** | Yes, both streams concurrent | Transcribe mic and app audio in parallel for lower latency |
| **Transcription failure** | Show [Transcription Failed] | Display error marker in transcript so user knows audio was lost |
| **Browser audio** | Capture all app audio | No tab-specific capture. All browser audio captured together. |
| **Noise reduction** | None | Send raw audio to model. Let Parakeet handle it. |
| **Language detection** | Auto-detect from audio | Parakeet v3 auto-detects. No user input needed. |
| **Profanity** | Show raw, uncensored | Transcribe exactly what's said. |
| **Confidence display** | No distinction | Show all text the same regardless of confidence level |
| **Target latency** | Under 2 seconds | Text should appear within 2s of speech |
| **Processing indicator** | Subtle spinner/dots | Show transcription in progress during any lag |
| **Persistence** | SQLite database | More robust than JSON, supports queries |
| **Auto-save frequency** | Every chunk (~1.5s) | Write after each transcription for maximum data safety |

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

**None of the 4 researched apps implement true speaker diarization.** It requires separate models (pyannote, resemblyzer) and adds significant complexity.

**MVP Approach**: Use audio source as speaker proxy:
- Mic input → "You"
- System audio → "Remote"

**Future**: Investigate pyannote, WhisperX, NeMo for true diarization.

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
│  ├── Transcript storage (JSON)                  │
│  └── Session history                            │
└─────────────────────────────────────────────────┘
```

---

## MVP Features (v0.1)

### Recording Flow
- [ ] Record button opens "Start Recording" dialog
- [ ] Dialog shows: mic dropdown, app dropdown (for system audio)
- [ ] Pre-select last used mic and app
- [ ] Start button begins dual capture (mic + selected app)
- [ ] **Large, prominent Pause/Resume button** while recording
- [ ] **Large Stop button** to end session
- [ ] Global hotkey (user configurable) toggles recording
- [ ] Red dot + pulse animation while recording (pauses when paused)
- [ ] Stop button ends recording, auto-saves session

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
- [ ] Click session to view full transcript on right
- [ ] Current/active session highlighted at top

### First-Run Setup
- [ ] Request mic permission (show inline error + retry if denied)
- [ ] Request screen recording permission (for system audio)
- [ ] Model download progress indicator (~650MB, 3-5 min)

### Data Model
- [ ] `TranscriptLine`: text, source (you/remote), timestamp (hidden in MVP)
- [ ] `Session`: id, startTime, endTime, lines[]
- [ ] Store last used mic ID and app bundle ID in UserDefaults

---

## Post-MVP Features

### v0.2
- [ ] Menu bar presence/app mode
- [ ] Copy entire transcript button
- [ ] Copy with speaker labels option
- [ ] Show/hide timestamps toggle
- [ ] Custom speaker labels

### Future
- [ ] True speaker diarization (pyannote or similar)
- [ ] LLM post-processing (cleanup, summarize)
- [ ] Keyboard shortcuts for copy
- [ ] Export formats (markdown, JSON)
- [ ] Additional transcription engines (WhisperKit for 99 languages)

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
│   │   └── PermissionsManager.swift     # Mic + screen recording permissions
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
7. **Session persistence** — Save/load JSON transcripts
8. **Polish** — Always-on-top toggle, global hotkey, setup flow

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
}
```

---

## Verification Checklist

### First Run
- [ ] App launches on macOS 15
- [ ] Prompts for mic permission
- [ ] Shows inline error + retry if mic denied
- [ ] Prompts for screen recording permission
- [ ] Model download starts with progress indicator
- [ ] Model download completes (~3-5 min, ~650MB)

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

### Edge Cases
- [ ] No crash if selected app quits during recording
- [ ] Graceful handling if no apps with audio running
- [ ] Works with AirPods / external mics

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
- **Research apps**: Hex, FluidVoice, VoiceInk, Handy (in `/Users/kevin/code/transcription-apps`)
