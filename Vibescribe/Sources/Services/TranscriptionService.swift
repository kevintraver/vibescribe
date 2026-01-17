import Foundation

/// Main service that orchestrates audio capture and transcription
/// Uses actor isolation for thread-safe state management
@MainActor
final class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()

    // MARK: - Configuration

    private let sampleRate: Double = 16000
    private let chunkDurationSeconds: TimeInterval = 1.5
    private var silenceDurationSeconds: TimeInterval = 0.8
    private var silenceThreshold: Float = 0.008

    private var chunkSamples: Int {
        Int(sampleRate * chunkDurationSeconds)
    }

    // MARK: - State

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false

    // MARK: - Components

    private let provider: FluidAudioProvider
    private let micBuffer = ThreadSafeAudioBuffer()
    private let appBuffer = ThreadSafeAudioBuffer()
    private var micCapture: MicCapture?
    private var appCapture: AppAudioCapture?
    private var chunkTimer: Timer?

    // MARK: - Current Session

    private weak var appState: AppState?

    // MARK: - Line Management

    private var currentMicLine: TranscriptLine?
    private var currentAppLine: TranscriptLine?
    private var lastMicSpeechTime: Date?
    private var lastAppSpeechTime: Date?

    // MARK: - Initialization

    private init() {
        provider = FluidAudioProvider()
    }

    /// Set the app state for updating UI
    func setAppState(_ state: AppState) {
        self.appState = state
    }

    /// Update silence duration from settings
    func updateSilenceDuration(_ duration: TimeInterval) {
        silenceDurationSeconds = duration
    }

    /// Update silence threshold from settings (RMS level below which audio is considered silence)
    func updateSilenceThreshold(_ threshold: Float) {
        silenceThreshold = threshold
        Log.info("Silence threshold updated to \(threshold)", category: .audio)
    }

    // MARK: - Model Management

    /// Check if models are ready
    var isReady: Bool {
        provider.isReady
    }

    /// Prepare the transcription provider (download/load models)
    func prepare(progressHandler: ((Double) -> Void)? = nil) async throws {
        try await provider.prepare(progressHandler: progressHandler)
    }

    /// Clear model cache
    func clearCache() async throws {
        try await provider.clearCache()
    }

    // MARK: - Recording Control

    /// Start recording with specified sources
    func startRecording(micId: String?, appBundleId: String?) async {
        Log.info("startRecording called - micId: \(micId ?? "default"), appBundleId: \(appBundleId ?? "none")", category: .audio)

        guard !isRecording else {
            Log.warning("Already recording, ignoring startRecording call", category: .audio)
            return
        }

        // Check if model is ready
        Log.info("Model ready: \(provider.isReady)", category: .transcription)
        if !provider.isReady {
            Log.error("Model not ready! Cannot start transcription.", category: .transcription)
        }

        // Clear buffers
        micBuffer.clear()
        appBuffer.clear()
        Log.debug("Buffers cleared", category: .audio)

        // Reset line state
        currentMicLine = nil
        currentAppLine = nil
        lastMicSpeechTime = nil
        lastAppSpeechTime = nil

        // Start mic capture
        Log.info("Starting mic capture...", category: .audio)
        let mic = MicCapture(buffer: micBuffer)
        do {
            try mic.start(deviceId: micId)
            micCapture = mic
            Log.info("Mic capture started successfully", category: .audio)
        } catch {
            Log.error("Failed to start mic capture: \(error)", category: .audio)
        }

        // Start app capture if specified
        if let bundleId = appBundleId {
            Log.info("Starting app capture for: \(bundleId)", category: .audio)
            let app = AppAudioCapture(buffer: appBuffer)
            do {
                try await app.start(bundleId: bundleId)
                appCapture = app
                Log.info("App capture started successfully", category: .audio)
            } catch {
                Log.error("Failed to start app capture: \(error)", category: .audio)
            }
        }

        // Start chunk processing timer
        Log.info("Starting chunk timer (interval: \(chunkDurationSeconds)s)", category: .audio)
        startChunkTimer()

        isRecording = true
        isPaused = false
        Log.info("Recording started!", category: .audio)
    }

    /// Pause recording
    func pauseRecording() {
        Log.info("pauseRecording() called, isRecording: \(isRecording), isPaused: \(isPaused)", category: .audio)
        guard isRecording, !isPaused else {
            Log.warning("pauseRecording() guard failed", category: .audio)
            return
        }

        micCapture?.pause()
        stopChunkTimer()

        // Clear buffers (discard audio during pause)
        micBuffer.clear()
        appBuffer.clear()

        isPaused = true
        Log.info("Recording paused", category: .audio)
    }

    /// Resume recording
    func resumeRecording() {
        Log.info("resumeRecording() called, isRecording: \(isRecording), isPaused: \(isPaused)", category: .audio)
        guard isRecording, isPaused else {
            Log.warning("resumeRecording() guard failed", category: .audio)
            return
        }

        do {
            try micCapture?.resume()
            Log.info("Mic capture resumed", category: .audio)
        } catch {
            Log.error("Failed to resume mic capture: \(error)", category: .audio)
        }

        startChunkTimer()
        isPaused = false
        Log.info("Recording resumed", category: .audio)
    }

    /// Stop recording
    func stopRecording() async {
        guard isRecording else { return }

        // Process any remaining audio
        await processRemainingAudio()

        // Stop captures
        micCapture?.stop()
        micCapture = nil

        await appCapture?.stop()
        appCapture = nil

        stopChunkTimer()

        isRecording = false
        isPaused = false
    }

    // MARK: - Chunk Processing

    private func startChunkTimer() {
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkDurationSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.processChunks()
            }
        }
    }

    private func stopChunkTimer() {
        chunkTimer?.invalidate()
        chunkTimer = nil
    }

    /// Process accumulated audio chunks
    private func processChunks() async {
        guard !isPaused else { return }

        let micCount = micBuffer.count
        let appCount = appBuffer.count

        Log.debug("processChunks - micBuffer: \(micCount), appBuffer: \(appCount), needed: \(chunkSamples)", category: .audio)

        // Process mic and app audio in parallel
        await withTaskGroup(of: Void.self) { group in
            // Process mic audio
            if micCount >= chunkSamples {
                Log.debug("Processing mic chunk (\(micCount) samples)", category: .audio)
                group.addTask { @MainActor in
                    await self.processMicChunk()
                }
            }

            // Process app audio
            if appCount >= chunkSamples {
                Log.debug("Processing app chunk (\(appCount) samples)", category: .audio)
                group.addTask { @MainActor in
                    await self.processAppChunk()
                }
            }
        }
    }

    private func processMicChunk() async {
        let samples = micBuffer.flush()
        Log.debug("processMicChunk - flushed \(samples.count) samples", category: .audio)

        guard !samples.isEmpty else {
            Log.debug("processMicChunk - no samples", category: .audio)
            return
        }

        // Check for silence (simple RMS threshold)
        if isSilence(samples) {
            Log.debug("processMicChunk - silence detected", category: .audio)
            // Check if we should start a new line after silence
            if let lastSpeech = lastMicSpeechTime,
               Date().timeIntervalSince(lastSpeech) > silenceDurationSeconds {
                currentMicLine = nil
            }
            return
        }

        lastMicSpeechTime = Date()
        Log.info("processMicChunk - speech detected, transcribing \(samples.count) samples...", category: .transcription)

        do {
            let result = try await provider.transcribe(samples, source: .you)

            guard !result.text.isEmpty else {
                Log.debug("processMicChunk - transcription returned empty text", category: .transcription)
                return
            }

            Log.info("Transcribed: \"\(result.text)\"", category: .transcription)
            await handleTranscriptionResult(result, source: .you)
        } catch {
            Log.error("Mic transcription error: \(error)", category: .transcription)
        }
    }

    private func processAppChunk() async {
        let samples = appBuffer.flush()
        guard !samples.isEmpty else { return }

        if isSilence(samples) {
            if let lastSpeech = lastAppSpeechTime,
               Date().timeIntervalSince(lastSpeech) > silenceDurationSeconds {
                currentAppLine = nil
            }
            return
        }

        lastAppSpeechTime = Date()

        do {
            let result = try await provider.transcribe(samples, source: .remote)

            guard !result.text.isEmpty else { return }

            await handleTranscriptionResult(result, source: .remote)
        } catch {
            print("App transcription error: \(error)")
        }
    }

    /// Handle transcription result and update session
    private func handleTranscriptionResult(_ result: TranscriptionResult, source: TranscriptSource) async {
        guard let session = appState?.currentSession else { return }

        let currentLine = source == .you ? currentMicLine : currentAppLine

        if let line = currentLine {
            // Append to existing line
            let newText = line.text + " " + result.text
            session.updateLastLine(with: newText, for: source)

            // Update our reference
            if source == .you {
                currentMicLine?.text = newText
            } else {
                currentAppLine?.text = newText
            }
        } else {
            // Create new line
            let newLine = TranscriptLine(
                text: result.text,
                source: source,
                timestamp: result.timestamp,
                sessionId: session.id
            )
            session.addLine(newLine)

            if source == .you {
                currentMicLine = newLine
            } else {
                currentAppLine = newLine
            }
        }
    }

    /// Process any remaining audio when stopping
    private func processRemainingAudio() async {
        // Process mic
        let micSamples = micBuffer.flush()
        if !micSamples.isEmpty && !isSilence(micSamples) {
            do {
                let result = try await provider.transcribe(micSamples, source: .you)
                if !result.text.isEmpty {
                    await handleTranscriptionResult(result, source: .you)
                }
            } catch {
                print("Final mic transcription error: \(error)")
            }
        }

        // Process app
        let appSamples = appBuffer.flush()
        if !appSamples.isEmpty && !isSilence(appSamples) {
            do {
                let result = try await provider.transcribe(appSamples, source: .remote)
                if !result.text.isEmpty {
                    await handleTranscriptionResult(result, source: .remote)
                }
            } catch {
                print("Final app transcription error: \(error)")
            }
        }
    }

    // MARK: - Helpers

    /// Simple silence detection using RMS threshold
    /// Note: 0.008 works well for typical room noise; speech is usually 0.01-0.05+
    private func isSilence(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return true }

        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        let isSilent = rms < silenceThreshold
        Log.debug("RMS: \(String(format: "%.6f", rms)), threshold: \(silenceThreshold), silent: \(isSilent)", category: .audio)
        return isSilent
    }
}
