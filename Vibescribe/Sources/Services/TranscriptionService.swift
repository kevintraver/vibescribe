import AVFoundation
import Foundation
@preconcurrency import FluidAudio

/// Main service that orchestrates audio capture and transcription
/// Uses actor isolation for thread-safe state management
@MainActor
final class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()

    // MARK: - Configuration

    private let sampleRate: Double = 16000
    private var silenceDurationSeconds: TimeInterval = 1.0  // Reduced from 1.5s for more frequent line breaks

    // VAD configuration (Silero VAD neural network-based detection)
    private let vadThreshold: Float = 0.5  // Speech probability threshold (0.5 = balanced, 0.85 = conservative)
    private let vadChunkSize: Int = 4096   // Silero VAD expects 4096 samples (256ms at 16kHz)

    // Legacy RMS threshold (used as fallback if VAD not ready)
    private var silenceThreshold: Float = 0.012

    // Pause-based submission configuration (optimized based on VoiceInk/Handy analysis)
    private let pollIntervalSeconds: TimeInterval = 0.1  // Check every 100ms
    private let speechEndDelaySeconds: TimeInterval = 0.35  // Submit after 350ms of silence (was 400ms)
    private let minSpeechSamples: Int = 4000  // Minimum 250ms of speech (was 300ms)

    // Pre-roll buffer configuration (captures audio before speech detection)
    private let preRollDurationSeconds: TimeInterval = 0.3  // 300ms pre-roll buffer
    private var preRollSamples: Int { Int(sampleRate * preRollDurationSeconds) }

    // Onset detection (requires consecutive speech frames to trigger)
    private let onsetFramesRequired: Int = 2  // Require 2 consecutive speech frames (200ms)

    private var pollSamples: Int {
        Int(sampleRate * pollIntervalSeconds)
    }

    // MARK: - State

    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var isDiarizerReady = false
    @Published private(set) var isVadReady = false

    // MARK: - Audio Levels for Visualization

    /// Recent audio levels for waveform visualization (0.0 to 1.0), per source
    @Published private(set) var micAudioLevels: [Float] = []
    @Published private(set) var appAudioLevels: [Float] = []
    private let maxAudioLevelSamples = 80  // Number of samples in waveform

    /// Whether mic capture is active
    var isMicActive: Bool { micCapture != nil }

    /// Whether app capture is active
    var isAppActive: Bool { appCapture != nil }

    // MARK: - Components

    private let provider: FluidAudioProvider
    private let diarizer = AppAudioDiarizer()
    private var vadManager: VadManager?
    private let micBuffer = ThreadSafeAudioBuffer()
    private let appBuffer = ThreadSafeAudioBuffer()
    private var micCapture: MicCapture?
    private var appCapture: AppAudioCapture?
    private var chunkTimer: Timer?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    // MARK: - Current Session

    private weak var appState: AppState?

    // MARK: - Line Management (per speaker)

    private var currentLineIds: [SpeakerID: UUID] = [:]
    private var lastSpeechTimes: [SpeakerID: Date] = [:]

    // MARK: - Pause-Based Submission State

    /// Accumulated speech samples waiting for silence to trigger submission
    private var micSpeechBuffer: [Float] = []
    private var appSpeechBuffer: [Float] = []

    /// When silence started (nil = currently speaking)
    private var micSilenceStart: Date?
    private var appSilenceStart: Date?

    /// Pre-roll ring buffer (captures audio before speech detection)
    private var micPreRollBuffer: [Float] = []
    private var appPreRollBuffer: [Float] = []

    /// Onset detection counters (consecutive speech frames)
    private var micOnsetCount: Int = 0
    private var appOnsetCount: Int = 0

    // MARK: - VAD State (Silero VAD)

    /// Buffers for accumulating samples for VAD processing (needs 4096 samples)
    private var micVadBuffer: [Float] = []
    private var appVadBuffer: [Float] = []

    /// Last VAD probability (for smooth transitions and waveform visualization)
    private var lastMicVadProbability: Float = 0.0
    private var lastAppVadProbability: Float = 0.0

    // MARK: - Initialization

    private init() {
        provider = FluidAudioProvider()
        setupMemoryPressureHandling()
    }

    /// Set up memory pressure monitoring to handle low memory gracefully
    private func setupMemoryPressureHandling() {
        memoryPressureSource = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )

        memoryPressureSource?.setEventHandler { [weak self] in
            guard let self, let source = self.memoryPressureSource else { return }

            let event = source.data
            if event.contains(.critical) {
                Log.warning("Critical memory pressure detected", category: .audio)
                // On critical pressure, warn user but keep recording
                // The model is essential for transcription, so we can't unload it
                Task { @MainActor in
                    self.appState?.showPermissionAlert(
                        "Memory is critically low. Consider closing other apps to prevent issues."
                    )
                }
            } else if event.contains(.warning) {
                Log.info("Memory pressure warning received", category: .audio)
                // Clear any non-essential buffers to reduce memory usage
                self.micAudioLevels.removeAll(keepingCapacity: true)
                self.appAudioLevels.removeAll(keepingCapacity: true)
            }
        }

        memoryPressureSource?.resume()
        Log.info("Memory pressure handling initialized", category: .audio)
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

        // Initialize VAD in background (non-blocking)
        Task {
            do {
                let config = VadConfig(defaultThreshold: vadThreshold)
                let manager = try await VadManager(config: config)
                await MainActor.run {
                    self.vadManager = manager
                    self.isVadReady = true
                }
                Log.info("Silero VAD initialized successfully (threshold: \(self.vadThreshold))", category: .transcription)
            } catch {
                Log.warning("VAD initialization failed (will use RMS fallback): \(error)", category: .transcription)
            }
        }

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

        // Reset speech buffers
        micSpeechBuffer.removeAll()
        appSpeechBuffer.removeAll()
        micSilenceStart = nil
        appSilenceStart = nil

        // Reset pre-roll buffers and onset counters
        micPreRollBuffer.removeAll()
        appPreRollBuffer.removeAll()
        micOnsetCount = 0
        appOnsetCount = 0

        // Reset VAD state
        micVadBuffer.removeAll()
        appVadBuffer.removeAll()
        lastMicVadProbability = 0.0
        lastAppVadProbability = 0.0

        // Reset audio levels
        micAudioLevels.removeAll()
        appAudioLevels.removeAll()

        // Start audio polling timer
        Log.info("Starting audio poll timer (interval: \(pollIntervalSeconds)s)", category: .audio)
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

    private var pollTimerFireCount = 0

    private func startChunkTimer() {
        pollTimerFireCount = 0
        Log.info("Starting poll timer with interval \(pollIntervalSeconds)s", category: .audio)
        chunkTimer = Timer.scheduledTimer(withTimeInterval: pollIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollAudio()
            }
        }
    }

    private func stopChunkTimer() {
        Log.info("Stopping poll timer after \(pollTimerFireCount) fires", category: .audio)
        chunkTimer?.invalidate()
        chunkTimer = nil
    }

    /// Poll audio buffers and detect speech/silence transitions
    private func pollAudio() async {
        guard !isPaused else { return }

        pollTimerFireCount += 1

        // Poll mic audio
        let micSamples = micBuffer.flush()
        if !micSamples.isEmpty {
            await processMicSamples(micSamples)
        } else {
            // No new samples, but check for silence timeout to submit accumulated speech
            await checkMicSilenceTimeout()
        }

        // Poll app audio
        let appSamples = appBuffer.flush()
        if !appSamples.isEmpty {
            await processAppSamples(appSamples)
        } else {
            await checkAppSilenceTimeout()
        }
    }

    /// Process mic samples with pause-based submission
    private func processMicSamples(_ samples: [Float]) async {
        // Detect speech using Silero VAD (neural network) or RMS fallback
        let isSpeech = await detectSpeech(samples: samples, ismic: true)

        // Update audio levels for waveform visualization using VAD probability
        let normalizedLevel = lastMicVadProbability
        micAudioLevels.append(normalizedLevel)
        if micAudioLevels.count > maxAudioLevelSamples {
            micAudioLevels.removeFirst()
        }

        // Always update pre-roll buffer (ring buffer for capturing audio before speech)
        micPreRollBuffer.append(contentsOf: samples)
        while micPreRollBuffer.count > preRollSamples {
            micPreRollBuffer.removeFirst(min(samples.count, micPreRollBuffer.count - preRollSamples))
        }

        if isSpeech {
            micOnsetCount += 1
            micSilenceStart = nil
            lastSpeechTimes[.you] = Date()

            // Only start accumulating after onset threshold is met (reduces false triggers)
            if micOnsetCount >= onsetFramesRequired {
                // On first confirmed speech, prepend pre-roll buffer to capture word onset
                if micSpeechBuffer.isEmpty && !micPreRollBuffer.isEmpty {
                    micSpeechBuffer.append(contentsOf: micPreRollBuffer)
                    Log.debug("Prepended \(micPreRollBuffer.count) pre-roll samples", category: .audio)
                }

                // Accumulate speech samples
                micSpeechBuffer.append(contentsOf: samples)

                // Create placeholder line if this is start of new speech
                if currentLineIds[.you] == nil, let appState, let session = appState.currentSession {
                    let placeholderLine = TranscriptLine(
                        text: "",
                        speaker: .you,
                        sessionId: session.id
                    )
                    currentLineIds[.you] = placeholderLine.id
                    appState.addLine(placeholderLine)
                    Log.info("Created placeholder line \(placeholderLine.id.uuidString.prefix(8)) for [You]", category: .transcription)
                }

                // Update speaker and line state to listening
                appState?.speakerStates[.you] = .listening
                if let lineId = currentLineIds[.you] {
                    appState?.lineStates[lineId] = .listening
                }

                Log.debug("Mic speech: VAD=\(String(format: "%.2f", lastMicVadProbability)), buffer=\(micSpeechBuffer.count)", category: .audio)
            }
        } else {
            // Silence detected - reset onset counter
            micOnsetCount = 0

            if micSilenceStart == nil && !micSpeechBuffer.isEmpty {
                // Just transitioned to silence - start timer
                micSilenceStart = Date()
                Log.debug("Mic silence started, buffer=\(micSpeechBuffer.count)", category: .audio)
            }
            await checkMicSilenceTimeout()
        }
    }

    /// Check if mic silence timeout reached and submit accumulated speech
    private func checkMicSilenceTimeout() async {
        guard let silenceStart = micSilenceStart else { return }
        guard !micSpeechBuffer.isEmpty else { return }

        let silenceDuration = Date().timeIntervalSince(silenceStart)
        if silenceDuration >= speechEndDelaySeconds {
            // Silence timeout - submit accumulated speech
            let samples = micSpeechBuffer
            micSpeechBuffer.removeAll()
            micSilenceStart = nil

            if samples.count >= minSpeechSamples {
                // Set state to processing before transcription
                appState?.speakerStates[.you] = .processing
                if let lineId = currentLineIds[.you] {
                    appState?.lineStates[lineId] = .processing
                }

                Log.info("Mic submitting \(samples.count) samples after \(String(format: "%.2f", silenceDuration))s silence", category: .transcription)
                await transcribeMicSamples(samples)
            } else {
                Log.debug("Mic discarding \(samples.count) samples (below minimum \(minSpeechSamples))", category: .audio)
            }

            // Check for line finalization after longer silence
            if let lastSpeech = lastSpeechTimes[.you],
               Date().timeIntervalSince(lastSpeech) > silenceDurationSeconds {
                // Mark line and speaker as idle
                if let lineId = currentLineIds[.you] {
                    appState?.lineStates[lineId] = .idle
                    Log.info("State: line \(lineId.uuidString.prefix(8)) -> IDLE (finalized)", category: .transcription)
                }
                appState?.speakerStates[.you] = .idle
                currentLineIds[.you] = nil
            }
        }
    }

    /// Process app samples with pause-based submission
    private func processAppSamples(_ samples: [Float]) async {
        // Detect speech using Silero VAD (neural network) or RMS fallback
        let isSpeech = await detectSpeech(samples: samples, ismic: false)

        // Update audio levels for waveform visualization using VAD probability
        let normalizedLevel = lastAppVadProbability
        appAudioLevels.append(normalizedLevel)
        if appAudioLevels.count > maxAudioLevelSamples {
            appAudioLevels.removeFirst()
        }

        // Always update pre-roll buffer (ring buffer for capturing audio before speech)
        appPreRollBuffer.append(contentsOf: samples)
        while appPreRollBuffer.count > preRollSamples {
            appPreRollBuffer.removeFirst(min(samples.count, appPreRollBuffer.count - preRollSamples))
        }

        if isSpeech {
            appOnsetCount += 1
            appSilenceStart = nil

            // Only start accumulating after onset threshold is met (reduces false triggers)
            if appOnsetCount >= onsetFramesRequired {
                // On first confirmed speech, prepend pre-roll buffer to capture word onset
                if appSpeechBuffer.isEmpty && !appPreRollBuffer.isEmpty {
                    appSpeechBuffer.append(contentsOf: appPreRollBuffer)
                    Log.debug("App prepended \(appPreRollBuffer.count) pre-roll samples", category: .audio)
                }

                // Accumulate speech samples
                appSpeechBuffer.append(contentsOf: samples)

                // Update state to listening for all potential remote speakers
                // (We don't know which speaker until diarization runs)
                for speakerIndex in 0..<4 {
                    let speaker: SpeakerID = .remote(speakerIndex: speakerIndex)
                    if let lineId = currentLineIds[speaker] {
                        appState?.lineStates[lineId] = .listening
                        appState?.speakerStates[speaker] = .listening
                    }
                }

                Log.debug("App speech: VAD=\(String(format: "%.2f", lastAppVadProbability)), buffer=\(appSpeechBuffer.count)", category: .audio)
            }
        } else {
            // Silence detected - reset onset counter
            appOnsetCount = 0

            if appSilenceStart == nil && !appSpeechBuffer.isEmpty {
                appSilenceStart = Date()
                Log.debug("App silence started, buffer=\(appSpeechBuffer.count)", category: .audio)
            }
            await checkAppSilenceTimeout()
        }
    }

    /// Check if app silence timeout reached and submit accumulated speech
    private func checkAppSilenceTimeout() async {
        guard let silenceStart = appSilenceStart else { return }
        guard !appSpeechBuffer.isEmpty else { return }

        let silenceDuration = Date().timeIntervalSince(silenceStart)
        if silenceDuration >= speechEndDelaySeconds {
            // Silence timeout - submit accumulated speech
            let samples = appSpeechBuffer
            appSpeechBuffer.removeAll()
            appSilenceStart = nil

            if samples.count >= minSpeechSamples {
                // Set state to processing for all remote speakers with active lines
                for speakerIndex in 0..<4 {
                    let speaker: SpeakerID = .remote(speakerIndex: speakerIndex)
                    if let lineId = currentLineIds[speaker] {
                        appState?.lineStates[lineId] = .processing
                        appState?.speakerStates[speaker] = .processing
                    }
                }

                Log.info("App submitting \(samples.count) samples after \(String(format: "%.2f", silenceDuration))s silence", category: .transcription)
                await transcribeAppSamples(samples)
            } else {
                Log.debug("App discarding \(samples.count) samples (below minimum \(minSpeechSamples))", category: .audio)
            }

            // Check for line finalization after longer silence
            for speakerIndex in 0..<4 {
                let speaker: SpeakerID = .remote(speakerIndex: speakerIndex)
                if let lastSpeech = lastSpeechTimes[speaker],
                   Date().timeIntervalSince(lastSpeech) > silenceDurationSeconds {
                    // Mark line and speaker as idle
                    if let lineId = currentLineIds[speaker] {
                        appState?.lineStates[lineId] = .idle
                    }
                    appState?.speakerStates[speaker] = .idle
                    currentLineIds[speaker] = nil
                }
            }
        }
    }

    /// Transcribe accumulated mic speech samples
    private func transcribeMicSamples(_ samples: [Float]) async {
        let speaker: SpeakerID = .you

        do {
            let result = try await provider.transcribe(samples, speaker: speaker)

            if result.text.isEmpty {
                Log.debug("Mic transcription returned empty text", category: .transcription)
                return
            }

            Log.info("Transcribed [You]: \"\(result.text)\" (\(samples.count) samples)", category: .transcription)
            await handleTranscriptionResult(result)
        } catch {
            Log.error("Mic transcription error: \(error)", category: .transcription)
        }
    }

    /// Transcribe accumulated app speech samples with diarization
    private func transcribeAppSamples(_ samples: [Float]) async {
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

        do {
            let result = try await provider.transcribe(samples, speaker: speaker)

            guard !result.text.isEmpty else {
                Log.debug("App transcription returned empty text", category: .transcription)
                return
            }

            Log.info("Transcribed [\(speaker.displayLabel)]: \"\(result.text)\" (\(samples.count) samples)", category: .transcription)
            await handleTranscriptionResult(result)
        } catch {
            Log.error("App transcription error: \(error)", category: .transcription)
        }
    }

    /// Handle transcription result and update session
    private func handleTranscriptionResult(_ result: TranscriptionResult) async {
        guard let appState else {
            Log.error("handleTranscriptionResult - appState is nil!", category: .transcription)
            return
        }

        guard let session = appState.currentSession else {
            Log.error("handleTranscriptionResult - currentSession is nil!", category: .transcription)
            return
        }

        let speaker = result.speaker
        let currentLineId = currentLineIds[speaker]

        // Track remote speakers for display logic
        if case .remote(let speakerIndex) = speaker {
            appState.recordRemoteSpeaker(speakerIndex)
        }

        Log.info("handleTranscriptionResult [\(appState.speakerDisplayLabel(for: speaker))] - currentLineId: \(currentLineId?.uuidString.prefix(8) ?? "nil"), session.lines: \(session.lines.count)", category: .transcription)

        if let lineId = currentLineId, let existingLine = session.findLine(byId: lineId) {
            // Append to existing line (or replace if placeholder was empty)
            let newText = existingLine.text.isEmpty ? result.text : existingLine.text + " " + result.text
            session.updateLine(id: lineId, text: newText)
            Log.info("UPDATED line \(lineId.uuidString.prefix(8)): \"\(newText.suffix(50))\"", category: .transcription)

            // Mark line as listening (still accumulating)
            appState.lineStates[lineId] = .listening
            appState.speakerStates[speaker] = .listening
            Log.info("State: UPDATED line \(lineId.uuidString.prefix(8)) -> LISTENING (lineStates count: \(appState.lineStates.count))", category: .transcription)

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
            Log.info("NEW line [\(speaker.displayLabel)] id:\(newLine.id.uuidString.prefix(8)): \"\(result.text)\"", category: .transcription)

            // Track by ID for future appends
            currentLineIds[speaker] = newLine.id

            // Mark line as listening (new line, still accumulating)
            appState.lineStates[newLine.id] = .listening
            appState.speakerStates[speaker] = .listening
            Log.info("State: NEW line \(newLine.id.uuidString.prefix(8)) -> LISTENING (lineStates count: \(appState.lineStates.count))", category: .transcription)

            // Save to database and session
            appState.addLine(newLine)
            Log.info("After addLine - session.lines: \(session.lines.count)", category: .transcription)
        }
    }

    /// Process any remaining audio when stopping
    private func processRemainingAudio() async {
        // Process any remaining samples in capture buffers
        let remainingMic = micBuffer.flush()
        if !remainingMic.isEmpty {
            micSpeechBuffer.append(contentsOf: remainingMic)
        }
        let remainingApp = appBuffer.flush()
        if !remainingApp.isEmpty {
            appSpeechBuffer.append(contentsOf: remainingApp)
        }

        // Submit accumulated mic speech
        if micSpeechBuffer.count >= minSpeechSamples {
            Log.info("Final mic transcription: \(micSpeechBuffer.count) samples", category: .transcription)
            await transcribeMicSamples(micSpeechBuffer)
        }
        micSpeechBuffer.removeAll()

        // Submit accumulated app speech
        if appSpeechBuffer.count >= minSpeechSamples {
            Log.info("Final app transcription: \(appSpeechBuffer.count) samples", category: .transcription)
            await transcribeAppSamples(appSpeechBuffer)
        }
        appSpeechBuffer.removeAll()
    }

    // MARK: - VAD (Voice Activity Detection)

    /// Detect speech using Silero VAD neural network, with RMS fallback
    /// - Parameters:
    ///   - samples: Audio samples to analyze
    ///   - ismic: True for mic audio, false for app audio
    /// - Returns: True if speech detected
    private func detectSpeech(samples: [Float], ismic: Bool) async -> Bool {
        // Add samples to VAD buffer
        if ismic {
            micVadBuffer.append(contentsOf: samples)
        } else {
            appVadBuffer.append(contentsOf: samples)
        }

        // Get reference to correct buffer
        var vadBuffer = ismic ? micVadBuffer : appVadBuffer

        // If VAD not ready, fall back to RMS-based detection
        guard let vad = vadManager, isVadReady else {
            let rms = calculateRMS(samples)
            let probability = min(rms * 10, 1.0)  // Normalize to 0-1
            if ismic {
                lastMicVadProbability = probability
            } else {
                lastAppVadProbability = probability
            }
            return rms >= silenceThreshold
        }

        // Process VAD when we have enough samples (4096 = 256ms at 16kHz)
        if vadBuffer.count >= vadChunkSize {
            // Extract chunk for VAD processing
            let chunk = Array(vadBuffer.prefix(vadChunkSize))

            // Remove processed samples from buffer
            vadBuffer.removeFirst(vadChunkSize)
            if ismic {
                micVadBuffer = vadBuffer
            } else {
                appVadBuffer = vadBuffer
            }

            do {
                // Process chunk through VAD using public API
                let results = try await vad.process(chunk)

                // Get probability from first result (we process one chunk at a time)
                let probability = results.first?.probability ?? 0.0

                // Update last probability
                if ismic {
                    lastMicVadProbability = probability
                } else {
                    lastAppVadProbability = probability
                }

                // Return speech detection result
                return probability >= vadThreshold
            } catch {
                Log.warning("VAD processing failed, using RMS fallback: \(error)", category: .audio)
                // Fall back to RMS
                let rms = calculateRMS(samples)
                if ismic {
                    lastMicVadProbability = min(rms * 10, 1.0)
                } else {
                    lastAppVadProbability = min(rms * 10, 1.0)
                }
                return rms >= silenceThreshold
            }
        }

        // Not enough samples yet - use last known probability
        let lastProbability = ismic ? lastMicVadProbability : lastAppVadProbability
        return lastProbability >= vadThreshold
    }

    // MARK: - Helpers

    /// Calculate RMS (root mean square) of audio samples
    private func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }

    /// Simple silence detection using RMS threshold (legacy fallback)
    /// Note: 0.008 works well for typical room noise; speech is usually 0.01-0.05+
    private func isSilence(_ samples: [Float]) -> Bool {
        let rms = calculateRMS(samples)
        let isSilent = rms < silenceThreshold
        Log.debug("RMS: \(String(format: "%.6f", rms)), threshold: \(silenceThreshold), silent: \(isSilent)", category: .audio)
        return isSilent
    }
}
