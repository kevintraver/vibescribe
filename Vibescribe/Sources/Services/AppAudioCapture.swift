import Foundation
import ScreenCaptureKit
import AVFoundation

/// Captures audio from a specific application using ScreenCaptureKit
final class AppAudioCapture: NSObject, @unchecked Sendable {
    private var stream: SCStream?
    private let buffer: ThreadSafeAudioBuffer
    private var isRunning = false

    /// Target format: 16kHz mono
    private let targetSampleRate: Int = 16000
    private let targetChannels: Int = 1

    /// Callback for audio level updates
    var onAudioLevel: ((Float) -> Void)?

    init(buffer: ThreadSafeAudioBuffer) {
        self.buffer = buffer
        super.init()
    }

    /// Start capturing audio from a specific application
    /// - Parameter bundleId: Bundle identifier of the app to capture
    func start(bundleId: String) async throws {
        guard !isRunning else { return }

        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        // Find the target application
        guard let targetApp = content.applications.first(where: { $0.bundleIdentifier == bundleId }) else {
            throw AppCaptureError.appNotFound(bundleId)
        }

        // Create content filter for the app's audio
        // Use SCContentFilter with the target application
        let filter = SCContentFilter(desktopIndependentWindow: content.windows.first { window in
            window.owningApplication?.bundleIdentifier == targetApp.bundleIdentifier
        } ?? content.windows.first!)

        // Configure stream for audio only
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = targetSampleRate
        configuration.channelCount = targetChannels

        // We're only capturing audio, so minimize video impact
        configuration.width = 1
        configuration.height = 1
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps minimum

        // Create and start stream
        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)

        // Add audio output handler
        try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))

        try await newStream.startCapture()

        self.stream = newStream
        self.isRunning = true
    }

    /// Stop capturing audio
    func stop() async {
        guard isRunning else { return }

        if let stream {
            try? await stream.stopCapture()
        }

        stream = nil
        isRunning = false
    }

    /// Convert CMSampleBuffer to Float32 samples
    private func convertToSamples(_ sampleBuffer: CMSampleBuffer) -> [Float]? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == kCMBlockBufferNoErr, let dataPointer else {
            return nil
        }

        // Get the format description
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let sampleCount = length / Int(asbd.pointee.mBytesPerFrame)

        // Convert based on format
        if asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            // Already Float32
            let floatPointer = UnsafeRawPointer(dataPointer).bindMemory(to: Float.self, capacity: sampleCount)
            return Array(UnsafeBufferPointer(start: floatPointer, count: sampleCount))
        } else if asbd.pointee.mBitsPerChannel == 16 {
            // Int16 to Float32 conversion
            let int16Pointer = UnsafeRawPointer(dataPointer).bindMemory(to: Int16.self, capacity: sampleCount)
            var samples = [Float](repeating: 0, count: sampleCount)
            for i in 0..<sampleCount {
                samples[i] = Float(int16Pointer[i]) / 32768.0
            }
            return samples
        }

        return nil
    }

    /// Calculate RMS level for audio metering
    private func calculateRMSLevel(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }

        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / Float(samples.count))

        let db = 20 * log10(max(rms, 0.0001))
        return max(0, min(1, (db + 60) / 60))
    }
}

// MARK: - SCStreamDelegate

extension AppAudioCapture: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isRunning = false
        print("Stream stopped with error: \(error)")
    }
}

// MARK: - SCStreamOutput

extension AppAudioCapture: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        guard let samples = convertToSamples(sampleBuffer) else { return }

        // Append to buffer
        buffer.append(samples)

        // Update audio level
        if let onAudioLevel {
            let level = calculateRMSLevel(samples)
            DispatchQueue.main.async {
                onAudioLevel(level)
            }
        }
    }
}

enum AppCaptureError: LocalizedError {
    case appNotFound(String)
    case permissionDenied
    case captureStartFailed(Error)

    var errorDescription: String? {
        switch self {
        case .appNotFound(let bundleId):
            return "Application not found: \(bundleId)"
        case .permissionDenied:
            return "Screen recording permission denied"
        case .captureStartFailed(let error):
            return "Failed to start capture: \(error.localizedDescription)"
        }
    }
}
