//
//  AccessibilityManager.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import AppKit
import ApplicationServices

/// Manages accessibility-related functionality
/// - Detects if there's a focused text input field
/// - Determines whether to type or use clipboard
@MainActor
final class AccessibilityManager {
    
    /// Check if the currently focused element is an editable text field
    /// Returns true if we can type into the focused element
    func isFocusedElementEditable() -> Bool {
        guard let focusedElement = getFocusedElement() else {
            Logger.debug("No focused element found", category: .text)
            return false
        }
        
        // Check the role of the focused element
        guard let role = getRole(of: focusedElement) else {
            Logger.debug("Could not determine role of focused element", category: .text)
            return false
        }
        
        // Check if it's a text field or text area
        let editableRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSearchField" // kAXSearchFieldRole equivalent
        ]
        
        if editableRoles.contains(role) {
            Logger.debug("Focused element is editable: \(role)", category: .text)
            return true
        }
        
        // Also check if the element supports AXValue and is not read-only
        if supportsEditing(focusedElement) {
            Logger.debug("Focused element supports editing", category: .text)
            return true
        }
        
        Logger.debug("Focused element is not editable: \(role)", category: .text)
        return false
    }
    
    // MARK: - Private Helpers
    
    /// Get the currently focused UI element
    private func getFocusedElement() -> AXUIElement? {
        // Get the frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        
        // Get the focused UI element
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        
        guard result == .success, let element = focusedElement else {
            return nil
        }
        
        return (element as! AXUIElement)
    }
    
    /// Get the accessibility role of an element
    private func getRole(of element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleRef
        )
        
        guard result == .success, let role = roleRef as? String else {
            return nil
        }
        
        return role
    }
    
    /// Check if an element supports text editing
    private func supportsEditing(_ element: AXUIElement) -> Bool {
        // Check if the element has the AXValue attribute (indicates it can hold text)
        var valueRef: CFTypeRef?
        let valueResult = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        )
        
        guard valueResult == .success else {
            return false
        }
        
        // Check if the value is a string (text content)
        guard valueRef is String else {
            return false
        }
        
        // Check if the element is editable (not read-only)
        // If we can't determine, assume it's editable if it has a string value
        var editableRef: CFTypeRef?
        let editableResult = AXUIElementCopyAttributeValue(
            element,
            kAXIsEditableAttribute as CFString,
            &editableRef
        )
        
        if editableResult == .success, let isEditable = editableRef as? Bool {
            return isEditable
        }
        
        // If AXIsEditable is not available, check for AXValueSettable
        var settableRef: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &settableRef
        )
        
        if settableResult == .success {
            return settableRef.boolValue
        }
        
        // Default to true if we found a string value but couldn't determine editability
        return true
    }
}
