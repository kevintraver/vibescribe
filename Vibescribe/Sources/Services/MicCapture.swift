import Foundation
import AVFoundation

/// Captures audio from the microphone using AVAudioEngine
final class MicCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let buffer: ThreadSafeAudioBuffer
    private var isRunning = false

    /// Target format: 16kHz mono Float32
    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1

    /// Callback for audio level updates (for UI metering)
    var onAudioLevel: ((Float) -> Void)?

    init(buffer: ThreadSafeAudioBuffer) {
        self.buffer = buffer
    }

    /// Start capturing audio from the microphone
    /// - Parameter deviceId: Optional specific device ID, nil for system default
    func start(deviceId: String? = nil) throws {
        Log.info("MicCapture.start() called, deviceId: \(deviceId ?? "default")", category: .audio)

        guard !isRunning else {
            Log.warning("MicCapture already running", category: .audio)
            return
        }

        let inputNode = engine.inputNode

        // Get the native format of the input
        let inputFormat = inputNode.inputFormat(forBus: 0)
        Log.info("Input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch", category: .audio)

        // Create converter format (16kHz mono Float32)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: false
        ) else {
            Log.error("Failed to create output format", category: .audio)
            throw MicCaptureError.invalidFormat
        }

        Log.info("Target format: \(targetSampleRate)Hz, \(targetChannels)ch", category: .audio)

        // Create audio converter if formats differ
        let needsConversion = inputFormat.sampleRate != targetSampleRate ||
                              inputFormat.channelCount != targetChannels

        var converter: AVAudioConverter?
        if needsConversion {
            Log.info("Creating audio converter (format conversion needed)", category: .audio)
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        } else {
            Log.info("No format conversion needed", category: .audio)
        }

        var sampleCount = 0

        // Install tap on input node
        Log.info("Installing audio tap on input node...", category: .audio)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] inputBuffer, _ in
            guard let self else { return }

            let samples: [Float]

            if let converter {
                // Convert to target format
                let ratio = targetSampleRate / inputFormat.sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)

                guard let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: outputFrameCount
                ) else { return }

                var error: NSError?
                let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return inputBuffer
                }

                guard status != .error, let floatData = outputBuffer.floatChannelData else { return }
                samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(outputBuffer.frameLength)))
            } else {
                // Already in target format
                guard let floatData = inputBuffer.floatChannelData else { return }
                samples = Array(UnsafeBufferPointer(start: floatData[0], count: Int(inputBuffer.frameLength)))
            }

            // Append to buffer
            self.buffer.append(samples)

            // Log periodically
            sampleCount += samples.count
            if sampleCount % 16000 == 0 { // Log every ~1 second
                Log.debug("MicCapture: received \(sampleCount) total samples, buffer: \(self.buffer.count)", category: .audio)
            }

            // Calculate audio level for metering
            if let onAudioLevel = self.onAudioLevel {
                let level = self.calculateRMSLevel(samples)
                DispatchQueue.main.async {
                    onAudioLevel(level)
                }
            }
        }

        // Start the engine
        Log.info("Starting AVAudioEngine...", category: .audio)
        try engine.start()
        isRunning = true
        Log.info("MicCapture started successfully!", category: .audio)
    }

    /// Stop capturing audio
    func stop() {
        guard isRunning else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    /// Pause capture (keeps engine running but clears buffer)
    func pause() {
        guard isRunning else { return }
        engine.pause()
    }

    /// Resume capture
    func resume() throws {
        guard !engine.isRunning else { return }
        try engine.start()
    }

    /// Calculate RMS level for audio metering
    private func calculateRMSLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))

        // Convert to dB scale (clamped to reasonable range)
        let db = 20 * log10(max(rms, 0.0001))
        // Normalize to 0-1 range (assuming -60dB to 0dB range)
        return max(0, min(1, (db + 60) / 60))
    }
}

enum MicCaptureError: LocalizedError {
    case invalidFormat
    case deviceNotFound
    case captureStartFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Could not create audio format"
        case .deviceNotFound:
            return "Microphone device not found"
        case .captureStartFailed(let error):
            return "Failed to start capture: \(error.localizedDescription)"
        }
    }
}
