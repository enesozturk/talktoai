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
/// Monitors Fn + Shift + K for push-to-talk activation
final class HotkeyManager {

    weak var delegate: HotkeyDelegate?

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false

    // Track modifier states
    private var isFnDown = false
    private var isShiftDown = false
    private var isKDown = false
    
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
            Logger.info("Hotkey manager started, monitoring: Fn + Shift + K", category: .hotkey)
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
            isRecording = false
            isFnDown = false
            isShiftDown = false
            isKDown = false

            Logger.info("Hotkey manager stopped", category: .hotkey)
        }
    }
    
    /// Handle key event from the event tap
    /// Monitors Fn + Shift + K for push-to-talk
    /// Returns true if the event should be blocked (consumed)
    fileprivate func handleKeyEvent(_ event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let eventType = event.type
        let flags = event.flags
        var shouldBlockEvent = false

        // Track Fn and Shift via flagsChanged events
        if eventType == .flagsChanged {
            // Track Fn key
            if keyCode == KeyCodes.function {
                isFnDown = flags.contains(.maskSecondaryFn)
            }
            // Track Shift key (either left or right)
            if keyCode == KeyCodes.leftShift || keyCode == KeyCodes.rightShift {
                isShiftDown = flags.contains(.maskShift)
            }
        }

        // Track K key via keyDown/keyUp events
        if keyCode == KeyCodes.keyK {
            if eventType == .keyDown {
                isKDown = true
                // Block K key when Fn + Shift are held to prevent typing
                if isFnDown && isShiftDown {
                    shouldBlockEvent = true
                }
            } else if eventType == .keyUp {
                isKDown = false
                // Also block the key up event when in hotkey mode
                if isFnDown && isShiftDown {
                    shouldBlockEvent = true
                }
            }
        }

        // Check if all three keys are pressed
        let allPressed = isFnDown && isShiftDown && isKDown

        if allPressed && !isRecording {
            isRecording = true
            Logger.debug("Fn + Shift + K pressed - starting recording", category: .hotkey)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didStartRecording()
            }
        } else if !allPressed && isRecording {
            isRecording = false
            Logger.debug("Hotkey released - stopping recording", category: .hotkey)
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.didStopRecording()
            }
        }

        return shouldBlockEvent
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
    let shouldBlock = manager.handleKeyEvent(event)

    // Block the event if it's part of our hotkey combo (prevents typing K)
    if shouldBlock {
        return nil
    }

    return Unmanaged.passUnretained(event)
}
