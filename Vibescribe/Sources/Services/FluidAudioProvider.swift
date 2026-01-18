import Foundation
@preconcurrency import FluidAudio

/// FluidAudio/Parakeet transcription provider
/// Uses Apple Neural Engine for fast, accurate transcription
final class FluidAudioProvider: @unchecked Sendable {
    let name = "FluidAudio (Parakeet v3)"
    let isAvailable = true

    private var asrManager: AsrManager?
    private var models: AsrModels?
    private(set) var isReady = false

    init() {
        Log.info("FluidAudioProvider initialized", category: .transcription)
        Log.info("Models exist on disk: \(modelsExistOnDisk())", category: .transcription)
    }

    func prepare(progressHandler: ((Double) -> Void)?) async throws {
        Log.info("prepare() called, isReady: \(isReady)", category: .transcription)

        guard !isReady else {
            Log.info("Already ready, skipping prepare", category: .transcription)
            return
        }

        progressHandler?(0.0)
        Log.info("Starting model download/load...", category: .transcription)

        // Download and load models
        do {
            Log.info("Calling AsrModels.downloadAndLoad(version: .v3)...", category: .transcription)
            let downloadedModels = try await AsrModels.downloadAndLoad(version: .v3)
            Log.info("Model download complete!", category: .transcription)

            progressHandler?(0.5)

            // Initialize ASR manager with custom config
            Log.info("Initializing ASR manager...", category: .transcription)
            let tdtConfig = TdtConfig(maxSymbolsPerStep: 20)  // Doubled from default 10
            let asrConfig = ASRConfig(tdtConfig: tdtConfig)
            Log.info("TDT config: maxSymbolsPerStep=\(tdtConfig.maxSymbolsPerStep)", category: .transcription)
            let manager = AsrManager(config: asrConfig)
            try await manager.initialize(models: downloadedModels)
            Log.info("ASR manager initialized!", category: .transcription)

            progressHandler?(0.9)

            self.models = downloadedModels
            self.asrManager = manager

            // Warm-up: Run dummy inference to pre-compile Metal shaders for ANE
            // This reduces first-inference latency by 2-5 seconds
            Log.info("Running warm-up inference to compile Metal shaders...", category: .transcription)
            try await performWarmup(manager: manager)
            Log.info("Warm-up complete!", category: .transcription)

            progressHandler?(1.0)

            self.isReady = true
            Log.info("FluidAudioProvider is READY", category: .transcription)
        } catch {
            Log.error("Model prepare failed: \(error)", category: .transcription)
            throw error
        }
    }

    func transcribe(_ samples: [Float], speaker: SpeakerID) async throws -> TranscriptionResult {
        guard let manager = asrManager else {
            Log.error("transcribe called but manager is nil!", category: .transcription)
            throw TranscriptionError.notReady
        }

        guard !samples.isEmpty else {
            Log.debug("transcribe called with empty samples", category: .transcription)
            return TranscriptionResult(text: "", confidence: 0, speaker: speaker)
        }

        Log.debug("Transcribing \(samples.count) samples for \(speaker.displayLabel)...", category: .transcription)

        // Map our SpeakerID to FluidAudio's AudioSource
        let fluidSource: AudioSource = speaker.isYou ? .microphone : .system
        let result = try await manager.transcribe(samples, source: fluidSource)

        Log.debug("Transcription result: \"\(result.text)\" (confidence: \(result.confidence))", category: .transcription)

        return TranscriptionResult(
            text: result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            confidence: result.confidence,
            speaker: speaker
        )
    }

    /// Perform warm-up inference to pre-compile Metal shaders for ANE
    /// This eliminates JIT compilation delay on first real transcription
    private func performWarmup(manager: AsrManager) async throws {
        // Generate 1 second of silent audio (16kHz sample rate)
        let sampleRate = 16000
        let silentSamples = [Float](repeating: 0.0, count: sampleRate)

        // Run transcription on silent audio - this triggers shader compilation
        // We don't care about the result, just that the pipeline executes
        _ = try await manager.transcribe(silentSamples, source: .microphone)
    }

    func modelsExistOnDisk() -> Bool {
        let cacheDir = AsrModels.defaultCacheDirectory()
        let v3Dir = cacheDir.deletingLastPathComponent().appendingPathComponent("parakeet-tdt-0.6b-v3-coreml")
        return FileManager.default.fileExists(atPath: v3Dir.path)
    }

    func clearCache() async throws {
        let cacheDir = AsrModels.defaultCacheDirectory()
        let v3Dir = cacheDir.deletingLastPathComponent().appendingPathComponent("parakeet-tdt-0.6b-v3-coreml")

        if FileManager.default.fileExists(atPath: v3Dir.path) {
            try FileManager.default.removeItem(at: v3Dir)
        }

        asrManager = nil
        models = nil
        isReady = false
    }
}
