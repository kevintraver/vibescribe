# Vibescribe Audio Engineering

This document describes the audio signal flow, processing pipeline, and engineering decisions in Vibescribe from an audio engineering perspective.

---

## System Overview

Vibescribe captures audio from two simultaneous sources, processes them through independent pipelines, and submits complete utterances to a neural speech recognition model.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              AUDIO SOURCES                                   │
├─────────────────────────────────┬───────────────────────────────────────────┤
│         Microphone              │              Application Audio            │
│      (AVAudioEngine)            │            (ScreenCaptureKit)             │
│                                 │                                           │
│  Physical mic → ADC → Driver    │   App audio bus → System mixer → SCK     │
└───────────────┬─────────────────┴─────────────────────┬─────────────────────┘
                │                                       │
                ▼                                       ▼
┌───────────────────────────────┐     ┌───────────────────────────────────────┐
│     Format Conversion         │     │         Format Conversion             │
│  Native rate → 16kHz mono     │     │     48kHz stereo → 16kHz mono        │
│     Int16/Float → Float32     │     │         Float32 (preserved)           │
└───────────────┬───────────────┘     └─────────────────┬─────────────────────┘
                │                                       │
                ▼                                       ▼
┌───────────────────────────────┐     ┌───────────────────────────────────────┐
│   Thread-Safe Ring Buffer     │     │      Thread-Safe Ring Buffer          │
│        (micBuffer)            │     │          (appBuffer)                  │
└───────────────┬───────────────┘     └─────────────────┬─────────────────────┘
                │                                       │
                └───────────────────┬───────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │     Audio Polling (100ms)     │
                    │   Speech/Silence Detection    │
                    └───────────────┬───────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │    Speech Accumulation        │
                    │  (micSpeechBuffer/appBuffer)  │
                    └───────────────┬───────────────┘
                                    │
                            400ms silence detected
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │      ASR Model (Parakeet)     │
                    │   CoreML on Apple Neural Engine│
                    └───────────────────────────────┘
```

---

## Audio Capture

### Microphone Capture (AVAudioEngine)

**Source:** `Sources/Audio/MicCapture.swift`

The microphone is captured using Apple's AVAudioEngine, which provides a high-level interface to Core Audio.

```swift
// Audio format specification
let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16000,
    channels: 1,
    interleaved: false
)
```

**Signal Chain:**
```
Microphone element → ADC → Audio driver → AVAudioEngine input node
    → Format converter (if needed) → Tap → Callback → Buffer
```

**Key Parameters:**
| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Sample Rate | 16,000 Hz | Matches Parakeet model input requirement |
| Channels | 1 (mono) | Speech recognition doesn't benefit from stereo |
| Bit Depth | 32-bit float | Native processing format, normalized [-1.0, 1.0] |
| Buffer Size | 1600 samples | 100ms at 16kHz, balances latency vs overhead |

**Device Selection:**
- Enumerate devices via `AVCaptureDevice.DiscoverySession`
- Match by `uniqueID` for consistent selection
- Fallback to system default if selected device unavailable

### Application Audio Capture (ScreenCaptureKit)

**Source:** `Sources/Audio/AppAudioCapture.swift`

Application audio is captured using ScreenCaptureKit (macOS 13+), which provides access to individual application audio streams without capturing the display.

**Signal Chain:**
```
Application audio output → CoreAudio app bus → System audio server
    → ScreenCaptureKit stream → Sample buffer callback → Format conversion → Buffer
```

**Format Conversion:**
```swift
// ScreenCaptureKit delivers 48kHz stereo Float32
// Must convert to 16kHz mono Float32 for ASR

// Step 1: Stereo to mono mixdown
for i in 0..<frameCount {
    mono[i] = (left[i] + right[i]) * 0.5
}

// Step 2: Sample rate conversion (48kHz → 16kHz)
// Uses AVAudioConverter with linear interpolation
let converter = AVAudioConverter(from: input48kFormat, to: output16kFormat)
converter.convert(to: outputBuffer, from: inputBuffer)
```

**Key Parameters:**
| Parameter | Input | Output | Notes |
|-----------|-------|--------|-------|
| Sample Rate | 48,000 Hz | 16,000 Hz | 3:1 decimation |
| Channels | 2 (stereo) | 1 (mono) | Sum and average |
| Bit Depth | 32-bit float | 32-bit float | Preserved |

---

## Audio Buffering

### Thread-Safe Ring Buffer

**Source:** `Sources/Audio/ThreadSafeAudioBuffer.swift`

Audio callbacks occur on real-time audio threads. The buffer provides thread-safe handoff to the main processing thread.

```swift
final class ThreadSafeAudioBuffer: @unchecked Sendable {
    private var buffer: [Float] = []
    private let lock = NSLock()

    func append(_ samples: [Float]) {
        lock.lock()
        buffer.append(contentsOf: samples)
        lock.unlock()
    }

    func flush() -> [Float] {
        lock.lock()
        let samples = buffer
        buffer.removeAll(keepingCapacity: true)
        lock.unlock()
        return samples
    }
}
```

**Design Considerations:**
- `NSLock` for mutual exclusion (lighter than `DispatchQueue`)
- `removeAll(keepingCapacity: true)` avoids repeated allocations
- No maximum size limit (relies on polling frequency to drain)

---

## Silence Detection

### RMS (Root Mean Square) Calculation

Audio energy is measured using RMS, which provides a perceptually-relevant measure of signal level.

```swift
func calculateRMS(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
    return sqrt(sumOfSquares / Float(samples.count))
}
```

**Mathematical Definition:**
```
RMS = √(1/N × Σ(x[i]²))

where:
  N = number of samples
  x[i] = sample value at index i
```

**Why RMS:**
- Correlates with perceived loudness better than peak amplitude
- Smooths out transients that could cause false triggers
- Standard metric in audio engineering for level measurement

### Threshold Selection

```swift
private var silenceThreshold: Float = 0.008
```

| RMS Value | Interpretation |
|-----------|----------------|
| 0.000 - 0.005 | Digital silence, noise floor |
| 0.005 - 0.010 | Room tone, quiet environment |
| 0.010 - 0.030 | Soft speech, distant voice |
| 0.030 - 0.100 | Normal speech |
| 0.100 - 0.300 | Loud speech |
| > 0.300 | Very loud, possible clipping |

The threshold of 0.008 is set just above typical room noise to detect speech onset while avoiding false triggers from HVAC, computer fans, etc.

---

## Pause-Based Submission

### Speech State Machine

Each audio source maintains an independent state machine:

```
                    ┌─────────────────┐
                    │     SILENCE     │
                    │  (buffer empty) │
                    └────────┬────────┘
                             │
                   RMS >= threshold
                             │
                             ▼
                    ┌─────────────────┐
                    │   ACCUMULATING  │◄─────┐
                    │ (collecting     │      │
                    │  speech samples)│      │ RMS >= threshold
                    └────────┬────────┘      │
                             │               │
                   RMS < threshold           │
                             │               │
                             ▼               │
                    ┌─────────────────┐      │
                    │  SILENCE_WAIT   │──────┘
                    │ (timing silence)│
                    └────────┬────────┘
                             │
                   silence >= 400ms
                             │
                             ▼
                    ┌─────────────────┐
                    │     SUBMIT      │
                    │ (send to ASR)   │
                    └────────┬────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │     SILENCE     │
                    │  (buffer empty) │
                    └─────────────────┘
```

### Timing Parameters

```swift
private let pollIntervalSeconds: TimeInterval = 0.1      // 100ms
private let speechEndDelaySeconds: TimeInterval = 0.4    // 400ms
private let minSpeechSamples: Int = 4800                 // 300ms @ 16kHz
```

**Poll Interval (100ms):**
- Chosen to balance responsiveness vs CPU overhead
- 100ms provides ~10 decisions per second
- At 16kHz, each poll processes ~1600 samples

**Speech End Delay (400ms):**
- Natural pause between words: 150-300ms
- Natural pause between sentences: 400-800ms
- 400ms catches sentence boundaries while allowing natural word pauses
- Shorter values (200ms) would split mid-phrase
- Longer values (800ms) would feel laggy

**Minimum Speech Duration (300ms):**
- Filters out transients (coughs, clicks, breaths)
- Most words are >200ms in duration
- Prevents sending noise bursts to ASR

---

## Sample Rate Considerations

### Why 16kHz?

The Parakeet ASR model is trained on 16kHz audio. This is standard for speech recognition because:

1. **Nyquist Theorem:** Speech fundamental frequencies range 85-255Hz (male-female). Harmonics and formants extend to ~4kHz. 16kHz sampling captures up to 8kHz (Nyquist limit), sufficient for speech.

2. **Bandwidth Efficiency:** 16kHz is 1/3 the data of 48kHz CD-quality audio, reducing:
   - Memory usage
   - Processing time
   - Model inference latency

3. **Historical Precedent:** Telephony uses 8kHz; wideband telephony uses 16kHz. Most speech datasets are 16kHz.

### Resampling Quality

When converting from 48kHz (ScreenCaptureKit) to 16kHz:

```
Original: 48,000 samples/second
Target:   16,000 samples/second
Ratio:    3:1 decimation
```

**Anti-Aliasing:**
Before decimation, a low-pass filter must remove frequencies above 8kHz to prevent aliasing. AVAudioConverter handles this automatically with a high-quality polyphase filter.

---

## Latency Analysis

### End-to-End Latency Budget

| Stage | Latency | Notes |
|-------|---------|-------|
| Microphone ADC | 1-5ms | Hardware dependent |
| Audio buffer fill | 0-100ms | Depends on when poll occurs |
| Silence detection | 400ms | Intentional pause detection |
| ASR inference | 50-200ms | Depends on utterance length |
| UI update | <16ms | Main thread |
| **Total** | **450-720ms** | From end of speech to display |

### Latency Tradeoffs

**Lower `speechEndDelaySeconds` (e.g., 200ms):**
- Faster response
- May split phrases mid-sentence
- More API calls (if cloud-based)

**Higher `speechEndDelaySeconds` (e.g., 800ms):**
- Better phrase grouping
- Feels sluggish
- User may think app is frozen

The 400ms value balances perceived responsiveness with linguistic completeness.

---

## Bit Depth and Dynamic Range

### Float32 Processing

All internal processing uses 32-bit floating point:

```
Range: [-1.0, +1.0] (normalized)
Precision: ~24 bits of mantissa
Dynamic range: ~144 dB (theoretical)
```

**Advantages:**
- No clipping concerns during mixing/processing
- Headroom for gain adjustments
- Native format for Apple audio APIs
- No quantization noise accumulation

### Conversion to Model Input

Parakeet expects Float32 input in the range [-1.0, 1.0], which matches our internal format. No conversion needed at inference time.

---

## Channel Configuration

### Mono vs Stereo

Speech recognition models are trained on mono audio. Stereo provides no benefit and doubles processing requirements.

**Stereo to Mono Mixdown:**
```swift
// Sum-and-average method
for i in 0..<frameCount {
    mono[i] = (left[i] + right[i]) * 0.5
}
```

The 0.5 factor prevents clipping when channels are correlated (in-phase).

**Alternative: Select Single Channel**
```swift
// Use left channel only (common for headset mics)
mono = left
```

We use sum-and-average because application audio may have different content in each channel (e.g., music with vocals panned).

---

## Diarization Integration

### Speaker Identification Flow

For application audio (remote speakers), the Sortformer diarization model identifies who is speaking:

```
Audio samples (16kHz mono Float32)
            │
            ▼
    ┌───────────────────┐
    │  Sortformer Model │
    │  (4 speaker slots)│
    └─────────┬─────────┘
            │
            ▼
    Speaker probabilities per 80ms frame
    [P(spk0), P(spk1), P(spk2), P(spk3)]
            │
            ▼
    Select dominant speaker (argmax)
            │
            ▼
    Tag transcription with speaker ID
```

**Frame Rate:**
- Sortformer outputs at 12.5 Hz (80ms frames)
- Multiple frames averaged for utterance-level speaker ID

---

## Memory Management

### Buffer Sizing

```swift
// Speech buffer grows during accumulation
private var micSpeechBuffer: [Float] = []

// Typical sizes:
// - 1 second of speech: 16,000 samples × 4 bytes = 64 KB
// - 10 seconds of speech: 640 KB
// - 60 seconds of speech: 3.84 MB
```

**Safeguards:**
- Buffers cleared after submission
- `removeAll(keepingCapacity: true)` reuses allocated memory
- No explicit size limit (assumes reasonable utterance lengths)

### Real-Time Thread Safety

Audio callbacks execute on real-time threads with strict timing requirements:

```swift
// DO NOT in audio callback:
// - Allocate memory (malloc)
// - Take locks that might block
// - Call Objective-C methods (may autorelease)
// - Log to disk

// Safe operations:
// - Lock-free ring buffer append
// - Pre-allocated buffer writes
// - Atomic operations
```

Our `ThreadSafeAudioBuffer` uses `NSLock` which is acceptable for the brief append operations, but a lock-free ring buffer would be ideal for production.

---

## Error Handling

### Audio Interruptions

```swift
// Handle audio session interruptions
NotificationCenter.default.addObserver(
    forName: AVAudioSession.interruptionNotification,
    ...
) { notification in
    // Pause capture, notify user
}
```

### Device Disconnection

```swift
// Handle device removal
NotificationCenter.default.addObserver(
    forName: .AVAudioEngineConfigurationChange,
    ...
) { notification in
    // Attempt reconnection or fallback to default device
}
```

---

## Performance Characteristics

### CPU Usage

| Component | CPU % (M1) | Notes |
|-----------|------------|-------|
| Mic capture | <1% | Hardware-assisted |
| App capture | 1-2% | ScreenCaptureKit overhead |
| RMS calculation | <0.1% | Simple arithmetic |
| Resampling | <0.5% | vDSP-accelerated |
| Buffer management | <0.1% | Memory copies |
| **Total capture** | **2-4%** | |

### Memory Usage

| Component | Memory | Notes |
|-----------|--------|-------|
| Capture buffers | ~100 KB | Pre-allocated |
| Speech buffers | 64 KB - 4 MB | Depends on utterance length |
| Audio format objects | ~1 KB | Metadata |
| **Total audio** | **~200 KB typical** | Excluding ASR model |

---

## Summary

Vibescribe's audio engineering prioritizes:

1. **Low latency** - 100ms polling, immediate buffer access
2. **Accuracy** - Complete utterances via pause detection
3. **Dual-source** - Independent mic and app audio pipelines
4. **Efficiency** - 16kHz mono, Float32, minimal processing
5. **Thread safety** - Lock-protected buffers, main-thread processing

The pause-based submission model ensures the ASR model receives complete linguistic units (phrases/sentences) rather than arbitrary time slices, improving transcription accuracy while maintaining real-time responsiveness.
