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

        progressHandler?(0.1)
        Log.info("Starting model download/load...", category: .transcription)

        // Download and load models
        do {
            Log.info("Calling AsrModels.downloadAndLoad(version: .v3)...", category: .transcription)
            let downloadedModels = try await AsrModels.downloadAndLoad(version: .v3)
            Log.info("Model download complete!", category: .transcription)

            progressHandler?(0.6)

            // Initialize ASR manager
            Log.info("Initializing ASR manager...", category: .transcription)
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: downloadedModels)
            Log.info("ASR manager initialized!", category: .transcription)

            progressHandler?(1.0)

            self.models = downloadedModels
            self.asrManager = manager
            self.isReady = true
            Log.info("FluidAudioProvider is READY", category: .transcription)
        } catch {
            Log.error("Model prepare failed: \(error)", category: .transcription)
            throw error
        }
    }

    func transcribe(_ samples: [Float], source: TranscriptSource) async throws -> TranscriptionResult {
        guard let manager = asrManager else {
            Log.error("transcribe called but manager is nil!", category: .transcription)
            throw TranscriptionError.notReady
        }

        guard !samples.isEmpty else {
            Log.debug("transcribe called with empty samples", category: .transcription)
            return TranscriptionResult(text: "", confidence: 0, source: source)
        }

        Log.debug("Transcribing \(samples.count) samples from \(source.rawValue)...", category: .transcription)

        // Map our TranscriptSource to FluidAudio's AudioSource
        let fluidSource: AudioSource = source == .you ? .microphone : .system
        let result = try await manager.transcribe(samples, source: fluidSource)

        Log.debug("Transcription result: \"\(result.text)\" (confidence: \(result.confidence))", category: .transcription)

        return TranscriptionResult(
            text: result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            confidence: result.confidence,
            source: source
        )
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
