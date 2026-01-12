//
//  HotkeyManager.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import Cocoa
import Carbon.HIToolbox

/// Protocol for receiving hotkey events
protocol HotkeyDelegate: AnyObject {
    func didStartRecording()
    func didStopRecording()
}

/// Manages global push-to-talk hotkey detection using CGEventTap
/// Monitors key down/up events for the configured hotkey
final class HotkeyManager {
    
    weak var delegate: HotkeyDelegate?
    
    /// The key code to monitor (default: Right Option)
    var hotkeyCode: UInt16 = KeyCodes.defaultPushToTalkKey
    
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyDown = false
    
    init() {}
    
    deinit {
        stop()
    }
    
    /// Start monitoring for hotkey events
    /// Requires Accessibility permission
    func start() -> Bool {
        guard eventTap == nil else {
            Logger.warning("Hotkey manager already started", category: .hotkey)
            return true
        }
        
        // Create event tap for key events
        // We monitor flagsChanged for modifier keys, keyDown/keyUp for regular keys
        let eventMask: CGEventMask = (
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)
        )
        
        // Store self reference for the callback
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyEventCallback,
            userInfo: userInfo
        ) else {
            Logger.error("Failed to create event tap. Accessibility permission may be required.", category: .hotkey)
            return false
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Logger.info("Hotkey manager started, monitoring key: \(KeyCodes.name(for: hotkeyCode))", category: .hotkey)
            return true
        }
        
        Logger.error("Failed to create run loop source", category: .hotkey)
        return false
    }
    
    /// Stop monitoring for hotkey events
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            
            eventTap = nil
            runLoopSource = nil
            isKeyDown = false
            
            Logger.info("Hotkey manager stopped", category: .hotkey)
        }
    }
    
    /// Handle key event from the event tap
    fileprivate func handleKeyEvent(_ event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let eventType = event.type
        
        // For modifier keys, we use flagsChanged event
        if KeyCodes.isModifier(hotkeyCode) {
            if eventType == .flagsChanged && keyCode == hotkeyCode {
                // Check if the key is pressed or released by examining flags
                let flags = event.flags
                let isPressed = isModifierPressed(flags: flags, keyCode: hotkeyCode)
                
                if isPressed && !isKeyDown {
                    isKeyDown = true
                    Logger.debug("Hotkey pressed: \(KeyCodes.name(for: hotkeyCode))", category: .hotkey)
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.didStartRecording()
                    }
                } else if !isPressed && isKeyDown {
                    isKeyDown = false
                    Logger.debug("Hotkey released: \(KeyCodes.name(for: hotkeyCode))", category: .hotkey)
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.didStopRecording()
                    }
                }
            }
        } else {
            // For regular keys, use keyDown/keyUp
            if keyCode == hotkeyCode {
                if eventType == .keyDown && !isKeyDown {
                    isKeyDown = true
                    Logger.debug("Hotkey pressed: \(KeyCodes.name(for: hotkeyCode))", category: .hotkey)
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.didStartRecording()
                    }
                } else if eventType == .keyUp && isKeyDown {
                    isKeyDown = false
                    Logger.debug("Hotkey released: \(KeyCodes.name(for: hotkeyCode))", category: .hotkey)
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.didStopRecording()
                    }
                }
            }
        }
        
        // Return false to allow the event to pass through
        return false
    }
    
    /// Check if a specific modifier key is pressed based on flags
    private func isModifierPressed(flags: CGEventFlags, keyCode: UInt16) -> Bool {
        switch keyCode {
        case KeyCodes.leftShift, KeyCodes.rightShift:
            return flags.contains(.maskShift)
        case KeyCodes.leftControl, KeyCodes.rightControl:
            return flags.contains(.maskControl)
        case KeyCodes.leftOption, KeyCodes.rightOption:
            return flags.contains(.maskAlternate)
        case KeyCodes.leftCommand, KeyCodes.rightCommand:
            return flags.contains(.maskCommand)
        case KeyCodes.function:
            return flags.contains(.maskSecondaryFn)
        case KeyCodes.capsLock:
            return flags.contains(.maskAlphaShift)
        default:
            return false
        }
    }
}

/// C callback function for CGEventTap
private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    
    // Handle tap disabled event
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        // Re-enable the tap
        if let userInfo = userInfo {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }
    
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    _ = manager.handleKeyEvent(event)
    
    // Always pass the event through
    return Unmanaged.passUnretained(event)
}
