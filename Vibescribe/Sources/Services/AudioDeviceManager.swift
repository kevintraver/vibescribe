import Foundation
import CoreAudio
import AVFoundation

/// Represents an audio input device
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isDefault: Bool

    var idString: String { String(id) }
}

/// Manages audio input device enumeration and selection
final class AudioDeviceManager: @unchecked Sendable {
    static let shared = AudioDeviceManager()

    private init() {}

    /// Get all available audio input devices
    func getInputDevices() -> [AudioDevice] {
        var devices: [AudioDevice] = []

        // Get default input device
        let defaultDeviceId = getDefaultInputDeviceId()

        // Get all audio devices
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return devices }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIds = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIds
        )

        guard status == noErr else { return devices }

        for deviceId in deviceIds {
            // Check if device has input channels
            if hasInputChannels(deviceId), let device = getDeviceInfo(deviceId, isDefault: deviceId == defaultDeviceId) {
                devices.append(device)
            }
        }

        return devices
    }

    /// Get the default input device ID
    func getDefaultInputDeviceId() -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceId: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceId
        )

        return status == noErr ? deviceId : 0
    }

    /// Check if a device has input channels
    private func hasInputChannels(_ deviceId: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(deviceId, &propertyAddress, 0, nil, &dataSize)

        guard status == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, nil, &dataSize, bufferListPointer)

        guard status == noErr else { return false }

        let bufferList = bufferListPointer.pointee
        return bufferList.mNumberBuffers > 0
    }

    /// Get device info for a device ID
    private func getDeviceInfo(_ deviceId: AudioDeviceID, isDefault: Bool) -> AudioDevice? {
        // Get device name
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var nameRef: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<CFString>.size)

        var status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, nil, &dataSize, &nameRef)
        guard status == noErr, let name = nameRef?.takeRetainedValue() as String? else { return nil }

        // Get device UID
        propertyAddress.mSelector = kAudioDevicePropertyDeviceUID
        var uidRef: Unmanaged<CFString>?
        dataSize = UInt32(MemoryLayout<CFString>.size)

        status = AudioObjectGetPropertyData(deviceId, &propertyAddress, 0, nil, &dataSize, &uidRef)
        guard status == noErr, let uid = uidRef?.takeRetainedValue() as String? else { return nil }

        return AudioDevice(
            id: deviceId,
            uid: uid,
            name: name,
            isDefault: isDefault
        )
    }

    /// Find a device by its UID
    func findDevice(byUID uid: String) -> AudioDevice? {
        getInputDevices().first { $0.uid == uid }
    }

    /// Find a device by its ID
    func findDevice(byId id: AudioDeviceID) -> AudioDevice? {
        getInputDevices().first { $0.id == id }
    }
}
