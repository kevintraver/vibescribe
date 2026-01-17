import Foundation

/// Thread-safe audio buffer with pre-allocated capacity
/// Critical: Avoids malloc in real-time audio callbacks
final class ThreadSafeAudioBuffer: @unchecked Sendable {
    /// Pre-allocate for ~10s of audio at 16kHz
    private static let maxCapacity = 16000 * 10

    private var buffer: [Float]
    private let lock = NSLock()

    init() {
        // Reserve capacity upfront - critical for real-time audio quality
        buffer = []
        buffer.reserveCapacity(Self.maxCapacity)
    }

    /// Append samples to the buffer
    /// Thread-safe for use in audio callbacks
    func append(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(contentsOf: samples)
    }

    /// Append samples from an unsafe buffer pointer
    /// More efficient for AVAudioEngine callbacks
    func append(from pointer: UnsafePointer<Float>, count: Int) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(contentsOf: UnsafeBufferPointer(start: pointer, count: count))
    }

    /// Flush and return all samples, clearing the buffer
    /// Keeps pre-allocated capacity for reuse
    func flush() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let samples = buffer
        buffer.removeAll(keepingCapacity: true)
        return samples
    }

    /// Peek at current samples without removing
    func peek() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    /// Current number of samples in buffer
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    /// Whether the buffer is empty
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffer.isEmpty
    }

    /// Clear the buffer, keeping capacity
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll(keepingCapacity: true)
    }

    /// Duration of audio in buffer at given sample rate
    func duration(sampleRate: Double = 16000) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return Double(buffer.count) / sampleRate
    }
}
