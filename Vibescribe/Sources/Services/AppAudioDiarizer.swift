import Foundation
@preconcurrency import FluidAudio

/// Wrapper around Sortformer for streaming speaker diarization of app audio
/// Processes audio chunks and returns the dominant speaker index (0-3)
actor AppAudioDiarizer {
    private var diarizer: SortformerDiarizer?
    private let config = SortformerConfig.default
    private(set) var isReady = false

    /// Initialize the diarizer (downloads model if needed)
    func initialize() async throws {
        Log.info("Initializing AppAudioDiarizer...", category: .transcription)

        let models = try await SortformerModelInference.loadFromHuggingFace(
            config: config,
            computeUnits: .all
        )

        let newDiarizer = SortformerDiarizer(config: config)
        newDiarizer.initialize(models: models)

        diarizer = newDiarizer
        isReady = true

        Log.info("AppAudioDiarizer initialized", category: .transcription)
    }

    /// Process audio samples and return the dominant speaker index
    /// Returns nil if no clear speaker is detected
    func getDominantSpeaker(samples: [Float]) throws -> Int? {
        guard let diarizer else {
            throw DiarizerError.notInitialized
        }

        // Process the samples through Sortformer
        guard let result = try diarizer.processSamples(samples) else {
            return nil
        }

        // Find the dominant speaker across all frames in this chunk
        return findDominantSpeaker(result: result)
    }

    /// Get the current dominant speaker from recent predictions
    /// Useful for checking who is currently speaking
    func getCurrentSpeaker() -> Int? {
        guard let diarizer else { return nil }

        let timeline = diarizer.timeline
        let numFrames = timeline.numFrames

        guard numFrames > 0 else { return nil }

        // Look at the last few frames to determine current speaker
        let framesToCheck = min(5, numFrames)
        var speakerScores: [Float] = [0, 0, 0, 0]

        for frameOffset in 0..<framesToCheck {
            let frame = numFrames - 1 - frameOffset
            for speaker in 0..<4 {
                let prob = timeline.probability(speaker: speaker, frame: frame)
                // Weight more recent frames higher
                let weight: Float = Float(framesToCheck - frameOffset) / Float(framesToCheck)
                speakerScores[speaker] += prob * weight
            }
        }

        // Find the speaker with highest score
        var maxScore: Float = 0.3  // Minimum threshold
        var dominantSpeaker: Int?

        for (speaker, score) in speakerScores.enumerated() {
            if score > maxScore {
                maxScore = score
                dominantSpeaker = speaker
            }
        }

        return dominantSpeaker
    }

    /// Reset the diarizer state (call when starting a new recording)
    func reset() {
        diarizer?.reset()
        Log.debug("AppAudioDiarizer reset", category: .transcription)
    }

    /// Clean up resources
    func cleanup() {
        diarizer?.cleanup()
        diarizer = nil
        isReady = false
        Log.info("AppAudioDiarizer cleaned up", category: .transcription)
    }

    // MARK: - Private Helpers

    private func findDominantSpeaker(result: SortformerChunkResult) -> Int? {
        let frameCount = result.frameCount
        let numSpeakers = 4

        guard frameCount > 0 else { return nil }

        // Aggregate probabilities across all frames
        var speakerScores: [Float] = [0, 0, 0, 0]

        for frame in 0..<frameCount {
            for speaker in 0..<numSpeakers {
                speakerScores[speaker] += result.getSpeakerPrediction(speaker: speaker, frame: frame)
            }
        }

        // Find the speaker with highest aggregate score
        var maxScore: Float = 0
        var dominantSpeaker: Int?

        for (speaker, score) in speakerScores.enumerated() {
            if score > maxScore {
                maxScore = score
                dominantSpeaker = speaker
            }
        }

        // Require minimum average probability of 0.3 per frame
        let threshold = Float(frameCount) * 0.3
        if maxScore < threshold {
            return nil
        }

        return dominantSpeaker
    }
}
