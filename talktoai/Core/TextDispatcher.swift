//
//  TextDispatcher.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import AppKit
import Carbon.HIToolbox

/// Dispatches transcribed text to the appropriate destination
/// - If there's a focused text input: types into it
/// - Otherwise: copies to clipboard
@MainActor
final class TextDispatcher {

    private let accessibilityManager: AccessibilityManager

    /// Bundle identifiers for terminal apps that need clipboard+paste approach
    private static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "io.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "com.panic.Prompt3",
        "com.panic.Prompt"
    ]

    /// Callback when text is dispatched
    var onTextDispatched: ((String, DispatchMethod) -> Void)?

    /// How the text was dispatched
    enum DispatchMethod {
        case typed
        case pasted
        case clipboard
    }

    init(accessibilityManager: AccessibilityManager) {
        self.accessibilityManager = accessibilityManager
    }

    /// Check if the frontmost app is a terminal
    private func isFrontmostAppTerminal() -> Bool {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let bundleId = frontmostApp.bundleIdentifier else {
            return false
        }
        let isTerminal = Self.terminalBundleIdentifiers.contains(bundleId)
        if isTerminal {
            Logger.info("Detected terminal app: \(bundleId)", category: .text)
        }
        return isTerminal
    }

    /// Dispatch text to the appropriate destination
    /// - Parameters:
    ///   - text: The text to dispatch
    ///   - autoSubmit: Whether to press Enter after typing
    /// - Returns: The method used to dispatch
    @discardableResult
    func dispatch(_ text: String, autoSubmit: Bool = false) -> DispatchMethod {
        guard !text.isEmpty else {
            Logger.warning("Attempted to dispatch empty text", category: .text)
            return .clipboard
        }

        // For terminal apps, use clipboard + paste approach for better reliability
        if isFrontmostAppTerminal() {
            Logger.info("Using clipboard+paste for terminal app", category: .text)
            pasteText(text, autoSubmit: autoSubmit)
            onTextDispatched?(text, .pasted)
            return .pasted
        }

        // For other apps, type character-by-character
        Logger.info("Typing text into focused field", category: .text)
        typeText(text, autoSubmit: autoSubmit)
        onTextDispatched?(text, .typed)
        return .typed
    }
    
    // MARK: - Paste (for terminal apps)

    /// Paste text using clipboard + Cmd+V (more reliable for terminal apps)
    private func pasteText(_ text: String, autoSubmit: Bool = false) {
        // Save current clipboard contents
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Copy text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Small delay to ensure clipboard is ready
        usleep(50000) // 50ms

        // Simulate Cmd+V
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9 // 'v' key

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            Logger.error("Failed to create Cmd+V key events", category: .text)
            return
        }

        // Add Command modifier
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        usleep(30000) // 30ms between down and up
        keyUp.post(tap: .cghidEventTap)

        Logger.info("✅ Posted Cmd+V paste event", category: .text)

        // Press Enter to submit if enabled
        if autoSubmit {
            // Longer delay for terminal apps to process the paste
            usleep(1000000) // 1000ms delay for terminal apps (Claude Code needs more time)
            Logger.info("🚀 Auto-submit enabled, pressing Enter...", category: .text)
            pressEnter(source: source)
        }

        // Optionally restore previous clipboard contents after a delay
        // (commented out as user might want to paste again)
        // DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        //     if let previous = previousContents {
        //         pasteboard.clearContents()
        //         pasteboard.setString(previous, forType: .string)
        //     }
        // }
        _ = previousContents // Silence unused variable warning
    }

    // MARK: - Typing

    /// Type text into the currently focused field using CGEvents
    private func typeText(_ text: String, autoSubmit: Bool = false) {
        // Use CGEventCreateKeyboardEvent to type each character
        // This approach respects the current keyboard layout

        let source = CGEventSource(stateID: .hidSystemState)

        for character in text {
            typeCharacter(character, source: source)
        }

        Logger.debug("Finished typing \(text.count) characters", category: .text)

        // Press Enter to submit if enabled
        if autoSubmit {
            // Longer delay for apps like Claude Code that need time to process input
            usleep(300000) // 300ms delay to ensure text is fully processed
            Logger.info("🚀 Auto-submit enabled, pressing Enter...", category: .text)
            pressEnter(source: source)
        }
    }

    /// Press the Enter/Return key to submit
    private func pressEnter(source: CGEventSource?) {
        let returnKeyCode: CGKeyCode = 36 // Return key

        // Create fresh events with a new source to avoid any contamination
        let freshSource = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: freshSource, virtualKey: returnKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: freshSource, virtualKey: returnKeyCode, keyDown: false) else {
            Logger.error("Failed to create Enter key events", category: .text)
            return
        }

        // Explicitly clear all modifier flags
        keyDown.flags = CGEventFlags(rawValue: 0)
        keyUp.flags = CGEventFlags(rawValue: 0)

        // Set keyboard event fields explicitly
        keyDown.setIntegerValueField(.keyboardEventKeycode, value: Int64(returnKeyCode))
        keyUp.setIntegerValueField(.keyboardEventKeycode, value: Int64(returnKeyCode))

        keyDown.post(tap: .cghidEventTap)
        usleep(50000) // 50ms between down and up
        keyUp.post(tap: .cghidEventTap)

        Logger.info("✅ Posted Enter key (keycode 36) with cleared flags", category: .text)
    }
    
    /// Type a single character
    private func typeCharacter(_ character: Character, source: CGEventSource?) {
        let string = String(character)
        
        // For complex characters, use the Unicode approach
        if let events = createKeyEventsForString(string, source: source) {
            for event in events {
                event.post(tap: .cghidEventTap)
            }
            // Small delay between characters for reliability
            usleep(1000) // 1ms
        }
    }
    
    /// Create key events to type a string using Unicode input
    private func createKeyEventsForString(_ string: String, source: CGEventSource?) -> [CGEvent]? {
        var events: [CGEvent] = []
        
        // Use key down event with Unicode string
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
            return nil
        }
        
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return nil
        }
        
        // Set the Unicode string
        var unicodeString = Array(string.utf16)
        keyDown.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)
        keyUp.keyboardSetUnicodeString(stringLength: unicodeString.count, unicodeString: &unicodeString)
        
        events.append(keyDown)
        events.append(keyUp)
        
        return events
    }
    
    // MARK: - Clipboard
    
    /// Copy text to the system clipboard
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        Logger.debug("Copied \(text.count) characters to clipboard", category: .text)
    }
    
    /// Convenience method to just copy without checking focus
    func copyToClipboardOnly(_ text: String) {
        copyToClipboard(text)
        onTextDispatched?(text, .clipboard)
    }
}
