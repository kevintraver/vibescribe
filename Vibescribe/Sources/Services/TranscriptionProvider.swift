import Foundation

/// Protocol for transcription engine abstraction
/// Allows swapping engines without changing core logic
protocol TranscriptionProvider: Sendable {
    /// Display name of the provider
    var name: String { get }

    /// Whether this provider is available on the current system
    var isAvailable: Bool { get }

    /// Whether the provider is ready to transcribe (models loaded)
    var isReady: Bool { get }

    /// Prepare the provider (download/load models)
    /// - Parameter progressHandler: Callback for progress updates (0.0 - 1.0)
    func prepare(progressHandler: ((Double) -> Void)?) async throws

    /// Transcribe audio samples
    /// - Parameters:
    ///   - samples: Float32 audio samples at 16kHz mono
    ///   - source: The source of the audio (mic or system)
    /// - Returns: Transcription result
    func transcribe(_ samples: [Float], source: TranscriptSource) async throws -> TranscriptionResult

    /// Check if models exist on disk (for quick startup check)
    func modelsExistOnDisk() -> Bool

    /// Clear cached models
    func clearCache() async throws
}

/// Errors that can occur during transcription
enum TranscriptionError: LocalizedError {
    case notReady
    case modelDownloadFailed(Error)
    case transcriptionFailed(Error)
    case invalidAudioFormat
    case providerUnavailable

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Transcription provider is not ready"
        case .modelDownloadFailed(let error):
            return "Failed to download model: \(error.localizedDescription)"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .invalidAudioFormat:
            return "Invalid audio format"
        case .providerUnavailable:
            return "Transcription provider is not available"
        }
    }
}
