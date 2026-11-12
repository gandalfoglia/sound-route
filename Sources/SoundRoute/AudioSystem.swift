import CoreAudio
import Foundation

/// Which side of the audio route we are talking about.
enum Direction: String, Codable, CaseIterable, Identifiable {
    case output
    case input

    var id: String { rawValue }

    var title: String { self == .output ? "Output" : "Input" }

    var symbol: String { self == .output ? "speaker.wave.2.fill" : "mic.fill" }

    var scope: AudioObjectPropertyScope {
        self == .output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
    }

    var defaultDeviceSelector: AudioObjectPropertySelector {
        self == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
    }
}

/// A snapshot of one CoreAudio device that is currently attached.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    /// Persistent identifier (survives reconnects/reboots). Used to remember priorities.
    let uid: String
    let name: String
    let transport: UInt32
    let canBeDefaultOutput: Bool
    let canBeDefaultInput: Bool

    func supports(_ direction: Direction) -> Bool {
        direction == .output ? canBeDefaultOutput : canBeDefaultInput
    }

    var symbol: String { AudioSystem.symbol(forTransport: transport) }
}

/// Thin, read-mostly wrapper around the CoreAudio HAL C API.
enum AudioSystem {
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    // MARK: Reading

    static func devices() -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id -> AudioDevice? in
            guard let uid = string(id, kAudioDevicePropertyDeviceUID),
                  uint32(id, kAudioDevicePropertyIsHidden) != 1
            else { return nil }
            let name = string(id, kAudioObjectPropertyName) ?? "Unknown device"
            let out = channelCount(id, .output) > 0 && uint32(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioObjectPropertyScopeOutput) == 1
            let inp = channelCount(id, .input) > 0 && uint32(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: kAudioObjectPropertyScopeInput) == 1
            guard out || inp else { return nil }
            return AudioDevice(
                id: id,
                uid: uid,
                name: name,
                transport: uint32(id, kAudioDevicePropertyTransportType) ?? 0,
                canBeDefaultOutput: out,
                canBeDefaultInput: inp
            )
        }
    }

    static func defaultDevice(_ direction: Direction) -> AudioDeviceID? {
        var addr = address(direction.defaultDeviceSelector)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    // MARK: Writing

    /// Makes `device` the system default for `direction`.
    /// For output, optionally also moves alert / system sounds.
    @discardableResult
    static func setDefault(_ device: AudioDeviceID, for direction: Direction, includeSystemSounds: Bool = false) -> Bool {
        var id = device
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = address(direction.defaultDeviceSelector)
        let ok = AudioObjectSetPropertyData(system, &addr, 0, nil, size, &id) == noErr
        if ok, direction == .output, includeSystemSounds {
            var sysAddr = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
            AudioObjectSetPropertyData(system, &sysAddr, 0, nil, size, &id)
        }
        return ok
    }

    // MARK: Change notifications

    /// Registers `handler` for device list / default device changes. Returns a token that
    /// removes the listeners when passed to `removeListeners`.
    static func addListeners(_ handler: @escaping () -> Void) -> [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] {
        let selectors = [
            kAudioHardwarePropertyDevices,
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
        ]
        return selectors.map { selector in
            var addr = address(selector)
            let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
            AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main, block)
            return (addr, block)
        }
    }

    static func removeListeners(_ tokens: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)]) {
        for (addr, block) in tokens {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(system, &a, DispatchQueue.main, block)
        }
    }

    // MARK: Helpers

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func uint32(
        _ id: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> UInt32? {
        var addr = address(selector, scope: scope)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func channelCount(_ id: AudioObjectID, _ direction: Direction) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: direction.scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func symbol(forTransport transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "headphones"
        case kAudioDeviceTransportTypeUSB: return "cable.connector"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "display"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        case kAudioDeviceTransportTypeThunderbolt: return "bolt.horizontal"
        case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return "waveform"
        default: return "hifispeaker"
        }
    }
}
