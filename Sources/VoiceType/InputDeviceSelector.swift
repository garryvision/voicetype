import CoreAudio
import Foundation

/// Picks the capture device. When the system default input is a Bluetooth headset
/// (AirPods, headphones), opening its mic switches the headset to the call profile
/// (HFP): music drops to mono 16 kHz for as long as the mic is open. In that case
/// VoiceType records from the Mac's built-in microphone instead.
enum InputDeviceSelector {
    struct Device {
        let id: AudioDeviceID
        let name: String
    }

    private static let bluetoothTransports: Set<UInt32> = [
        kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE,
    ]

    /// Built-in mic to use instead of the default input, or nil to keep the default.
    static func preferredDevice() -> Device? {
        guard Settings.avoidBluetoothMic,
              let defaultID = defaultInputID(),
              let transport = transportType(of: defaultID),
              bluetoothTransports.contains(transport),
              let builtIn = builtInMicrophone()
        else { return nil }
        return builtIn
    }

    static func builtInMicrophone() -> Device? {
        for id in allDeviceIDs()
        where transportType(of: id) == kAudioDeviceTransportTypeBuiltIn && hasInput(id) {
            return Device(id: id, name: name(of: id) ?? "Built-in Microphone")
        }
        return nil
    }

    // MARK: - Core Audio helpers

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultInputID() -> AudioDeviceID? {
        var addr = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func transportType(of id: AudioDeviceID) -> UInt32? {
        var addr = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioDeviceID) -> String? {
        var addr = address(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr,
              let name = value?.takeRetainedValue() else { return nil }
        return name as String
    }
}
