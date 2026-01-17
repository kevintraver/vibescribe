import AVFoundation
import Foundation

/// Main service that orchestrates audio capture and transcription
/// Uses actor isolation for thread-safe state management
@MainActor
final class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()

    // MARK: - Configuration

    private let sampleRate: Double = 16000
    private let chunkDurationSeconds: TimeInterval = 1.5
    private var silenceDurationSeconds: TimeInterval = 1.5
    private var silenceThreshold: Float = 0.008

    private var chunkSamples: Int {
        Int(sampleRate * chunkDurationSeconds)
    }

    // MARK: - State

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var isDiarizerReady = false

    // MARK: - Components

    private let provider: FluidAudioProvider
    private let diarizer = AppAudioDiarizer()
    private let micBuffer = ThreadSafeAudioBuffer()
    private let appBuffer = ThreadSafeAudioBuffer()
    private var micCapture: MicCapture?
    private var appCapture: AppAudioCapture?
    private var chunkTimer: Timer?

    // MARK: - Current Session

    private weak var appState: AppState?

    // MARK: - Line Management (per speaker)

    private var currentLineIds: [SpeakerID: UUID] = [:]
    private var lastSpeechTimes: [SpeakerID: Date] = [:]

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

        // Initialize diarizer in background (non-blocking)
        Task {
            do {
                try await diarizer.initialize()
                await MainActor.run {
                    self.isDiarizerReady = true
                }
                Log.info("Diarizer initialized successfully", category: .transcription)
            } catch {
                Log.warning("Diarizer initialization failed (will use fallback): \(error)", category: .transcription)
            }
        }
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

        // Reset line state (per speaker tracking)
        currentLineIds.removeAll()
        lastSpeechTimes.removeAll()

        // Reset diarizer state for new recording
        Task {
            await diarizer.reset()
        }

        // Start mic capture (check actual permission status, not cached)
        let micPermissionGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        Log.info("Mic permission check: \(micPermissionGranted)", category: .audio)

        if micPermissionGranted {
            Log.info("Starting mic capture...", category: .audio)
            let mic = MicCapture(buffer: micBuffer)
            do {
                try mic.start(deviceId: micId)
                micCapture = mic
                Log.info("Mic capture started successfully", category: .audio)
            } catch {
                Log.error("Failed to start mic capture: \(error)", category: .audio)
            }
        } else {
            Log.warning("Mic permission not granted, skipping mic capture", category: .audio)
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

        PermissionsManager.shared.startMonitoringPermissions { [self] revoked in
            switch revoked {
            case .microphone:
                appState?.hasMicPermission = false
                appState?.showPermissionAlert("Microphone permission was revoked. Recording paused.")
                appState?.pauseRecording()
                pauseRecording()
            case .screenRecording:
                appState?.hasScreenPermission = false
                appState?.showPermissionAlert("Screen recording permission was revoked. App audio capture paused.")
                Task { @MainActor in
                    await stopAppCapture()
                }
            }
        }

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
        appCapture?.pause()
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

        appCapture?.resume()
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

        PermissionsManager.shared.stopMonitoringPermissions()
    }

    /// Stop app audio capture without ending the session
    func stopAppCapture() async {
        await appCapture?.stop()
        appCapture = nil
    }

    // MARK: - Chunk Processing

    private var chunkTimerFireCount = 0

    private func startChunkTimer() {
        chunkTimerFireCount = 0
        Log.info("Starting chunk timer with interval \(chunkDurationSeconds)s, chunkSamples needed: \(chunkSamples)", category: .audio)
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkDurationSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.processChunks()
            }
        }
    }

    private func stopChunkTimer() {
        Log.info("Stopping chunk timer after \(chunkTimerFireCount) fires", category: .audio)
        chunkTimer?.invalidate()
        chunkTimer = nil
    }

    /// Process accumulated audio chunks
    private func processChunks() async {
        guard !isPaused else {
            Log.debug("processChunks - skipped (paused)", category: .audio)
            return
        }

        chunkTimerFireCount += 1
        let micCount = micBuffer.count
        let appCount = appBuffer.count

        Log.info("processChunks #\(chunkTimerFireCount) - micBuffer: \(micCount), appBuffer: \(appCount), needed: \(chunkSamples)", category: .audio)

        // Process mic and app audio independently (no echo suppression needed)
        // Mic is always "You", app audio uses diarization for speaker identification
        if micCount >= chunkSamples {
            Log.debug("Processing mic chunk (\(micCount) samples)", category: .audio)
            await processMicChunk()
        }

        if appCount >= chunkSamples {
            Log.debug("Processing app chunk (\(appCount) samples)", category: .audio)
            await processAppChunk()
        }
    }

    private func processMicChunk() async {
        let samples = micBuffer.flush()
        Log.debug("processMicChunk - flushed \(samples.count) samples", category: .audio)

        guard !samples.isEmpty else {
            Log.debug("processMicChunk - no samples", category: .audio)
            return
        }

        let speaker: SpeakerID = .you
        let rms = calculateRMS(samples)

        // Check for silence
        if rms < silenceThreshold {
            Log.debug("processMicChunk - silence (RMS: \(String(format: "%.4f", rms)))", category: .audio)
            if let lastSpeech = lastSpeechTimes[speaker],
               Date().timeIntervalSince(lastSpeech) > silenceDurationSeconds {
                currentLineIds[speaker] = nil
            }
            return
        }

        lastSpeechTimes[speaker] = Date()
        Log.info("processMicChunk - speech detected (RMS: \(String(format: "%.4f", rms))), transcribing...", category: .transcription)

        do {
            let result = try await provider.transcribe(samples, speaker: speaker)

            guard !result.text.isEmpty else {
                Log.debug("processMicChunk - transcription returned empty text", category: .transcription)
                return
            }

            Log.info("Transcribed [You]: \"\(result.text)\"", category: .transcription)
            await handleTranscriptionResult(result)
        } catch {
            Log.error("Mic transcription error: \(error)", category: .transcription)
        }
    }

    private func processAppChunk() async {
        let samples = appBuffer.flush()
        guard !samples.isEmpty else { return }

        let rms = calculateRMS(samples)

        if rms < silenceThreshold {
            Log.debug("processAppChunk - silence (RMS: \(String(format: "%.4f", rms)))", category: .audio)
            // Check all remote speakers for silence timeout
            for speakerIndex in 0..<4 {
                let speaker: SpeakerID = .remote(speakerIndex: speakerIndex)
                if let lastSpeech = lastSpeechTimes[speaker],
                   Date().timeIntervalSince(lastSpeech) > silenceDurationSeconds {
                    currentLineIds[speaker] = nil
                }
            }
            return
        }

        // Determine speaker using diarization (or fallback to speaker 0)
        var speakerIndex = 0
        if await diarizer.isReady {
            do {
                if let detectedSpeaker = try await diarizer.getDominantSpeaker(samples: samples) {
                    speakerIndex = detectedSpeaker
                    Log.debug("Diarizer detected speaker \(speakerIndex)", category: .transcription)
                }
            } catch {
                Log.warning("Diarization failed, using fallback: \(error)", category: .transcription)
            }
        }

        let speaker: SpeakerID = .remote(speakerIndex: speakerIndex)
        lastSpeechTimes[speaker] = Date()

        Log.info("processAppChunk - speech detected (RMS: \(String(format: "%.4f", rms))), speaker: \(speaker.displayLabel)", category: .transcription)

        do {
            let result = try await provider.transcribe(samples, speaker: speaker)

            guard !result.text.isEmpty else { return }

            Log.info("Transcribed [\(speaker.displayLabel)]: \"\(result.text)\"", category: .transcription)
            await handleTranscriptionResult(result)
        } catch {
            Log.error("App transcription error: \(error)", category: .transcription)
        }
    }

    /// Handle transcription result and update session
    private func handleTranscriptionResult(_ result: TranscriptionResult) async {
        guard let appState, let session = appState.currentSession else {
            Log.warning("handleTranscriptionResult - no current session", category: .transcription)
            return
        }

        let speaker = result.speaker
        let currentLineId = currentLineIds[speaker]

        if let lineId = currentLineId, let existingLine = session.findLine(byId: lineId) {
            // Append to existing line
            let newText = existingLine.text + " " + result.text
            session.updateLine(id: lineId, text: newText)
            Log.debug("Updated line \(lineId): \"\(newText.suffix(50))\"", category: .transcription)

            // Also update in database
            if var line = session.findLine(byId: lineId) {
                line.text = newText
                appState.updateLine(line)
            }
        } else {
            // Create new line
            let newLine = TranscriptLine(
                text: result.text,
                speaker: speaker,
                timestamp: result.timestamp,
                sessionId: session.id
            )
            Log.debug("New line [\(speaker.displayLabel)]: \"\(result.text)\"", category: .transcription)

            // Track by ID for future appends
            currentLineIds[speaker] = newLine.id

            // Save to database
            appState.addLine(newLine)
        }
    }

    /// Process any remaining audio when stopping
    private func processRemainingAudio() async {
        // Process mic
        let micSamples = micBuffer.flush()
        if !micSamples.isEmpty && !isSilence(micSamples) {
            do {
                let result = try await provider.transcribe(micSamples, speaker: .you)
                if !result.text.isEmpty {
                    await handleTranscriptionResult(result)
                }
            } catch {
                Log.error("Final mic transcription error: \(error)", category: .transcription)
            }
        }

        // Process app (use last known speaker or default to speaker 0)
        let appSamples = appBuffer.flush()
        if !appSamples.isEmpty && !isSilence(appSamples) {
            var speakerIndex = 0
            if await diarizer.isReady {
                if let currentSpeaker = await diarizer.getCurrentSpeaker() {
                    speakerIndex = currentSpeaker
                }
            }
            let speaker: SpeakerID = .remote(speakerIndex: speakerIndex)

            do {
                let result = try await provider.transcribe(appSamples, speaker: speaker)
                if !result.text.isEmpty {
                    await handleTranscriptionResult(result)
                }
            } catch {
                Log.error("Final app transcription error: \(error)", category: .transcription)
            }
        }
    }

    // MARK: - Helpers

    /// Calculate RMS (root mean square) of audio samples
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }

    /// Simple silence detection using RMS threshold
    /// Note: 0.008 works well for typical room noise; speech is usually 0.01-0.05+
    private func isSilence(_ samples: [Float]) -> Bool {
        let rms = calculateRMS(samples)
        let isSilent = rms < silenceThreshold
        Log.debug("RMS: \(String(format: "%.6f", rms)), threshold: \(silenceThreshold), silent: \(isSilent)", category: .audio)
        return isSilent
    }
}
