//
//  AudioDeviceManager.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import AVFoundation
import CoreAudio

/// Represents an audio input device
struct AudioDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let uid: String

    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages audio input device enumeration and selection
final class AudioDeviceManager {

    static let shared = AudioDeviceManager()

    /// Notification posted when available devices change
    static let devicesDidChangeNotification = Notification.Name("AudioDeviceManagerDevicesDidChange")

    private var propertyListenerBlock: AudioObjectPropertyListenerBlock?

    private init() {
        setupDeviceChangeListener()
    }

    deinit {
        removeDeviceChangeListener()
    }

    /// Get all available audio input devices
    func getInputDevices() -> [AudioDevice] {
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

        guard status == noErr else {
            Logger.error("Failed to get audio devices data size: \(status)", category: .audio)
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            Logger.error("Failed to get audio devices: \(status)", category: .audio)
            return []
        }

        // Filter to only input devices
        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            guard hasInputStreams(deviceID: deviceID) else { return nil }
            guard let name = getDeviceName(deviceID: deviceID) else { return nil }
            guard let uid = getDeviceUID(deviceID: deviceID) else { return nil }
            return AudioDevice(id: deviceID, name: name, uid: uid)
        }
    }

    /// Get the current default input device
    func getDefaultInputDevice() -> AudioDevice? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != kAudioDeviceUnknown else {
            return nil
        }

        guard let name = getDeviceName(deviceID: deviceID) else { return nil }
        guard let uid = getDeviceUID(deviceID: deviceID) else { return nil }
        return AudioDevice(id: deviceID, name: name, uid: uid)
    }

    /// Set the default system input device
    /// - Parameter device: The device to set as default
    /// - Returns: true if successful
    @discardableResult
    func setDefaultInputDevice(_ device: AudioDevice) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = device.id
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &deviceID
        )

        if status == noErr {
            Logger.info("Set default input device to: \(device.name)", category: .audio)
            return true
        } else {
            Logger.error("Failed to set default input device: \(status)", category: .audio)
            return false
        }
    }

    /// Find a device by its UID
    func findDevice(byUID uid: String) -> AudioDevice? {
        getInputDevices().first { $0.uid == uid }
    }

    // MARK: - Private Methods

    private func hasInputStreams(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        return status == noErr && dataSize > 0
    }

    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &name
        )

        return status == noErr ? name as String : nil
    }

    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &uid
        )

        return status == noErr ? uid as String : nil
    }

    // MARK: - Device Change Listener

    private func setupDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        propertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: AudioDeviceManager.devicesDidChangeNotification,
                    object: self
                )
            }
        }

        if let block = propertyListenerBlock {
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                DispatchQueue.main,
                block
            )
        }
    }

    private func removeDeviceChangeListener() {
        guard let block = propertyListenerBlock else { return }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }
}
