//
//  PermissionsManager.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import AVFoundation
import Speech
import AppKit
import Combine

/// Manages all required system permissions for the app
/// - Microphone access
/// - Speech recognition
/// - Accessibility (for typing into other apps)
@MainActor
final class PermissionsManager: ObservableObject {
    
    @Published private(set) var microphoneGranted = false
    @Published private(set) var speechRecognitionGranted = false
    @Published private(set) var accessibilityGranted = false
    
    /// All critical permissions are granted
    var allPermissionsGranted: Bool {
        microphoneGranted && speechRecognitionGranted && accessibilityGranted
    }
    
    init() {
        checkAllPermissions()
    }
    
    /// Check current status of all permissions
    func checkAllPermissions() {
        checkMicrophonePermission()
        checkSpeechRecognitionPermission()
        checkAccessibilityPermission()
    }
    
    // MARK: - Microphone
    
    private func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
            Logger.info("Microphone permission: granted", category: .permissions)
        case .notDetermined:
            microphoneGranted = false
            Logger.info("Microphone permission: not determined", category: .permissions)
        case .denied, .restricted:
            microphoneGranted = false
            Logger.warning("Microphone permission: denied", category: .permissions)
        @unknown default:
            microphoneGranted = false
        }
    }
    
    func requestMicrophonePermission() async -> Bool {
        Logger.info("Requesting microphone permission", category: .permissions)
        
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneGranted = granted
        
        if granted {
            Logger.info("Microphone permission granted", category: .permissions)
        } else {
            Logger.warning("Microphone permission denied by user", category: .permissions)
        }
        
        return granted
    }
    
    // MARK: - Speech Recognition
    
    private func checkSpeechRecognitionPermission() {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechRecognitionGranted = true
            Logger.info("Speech recognition permission: granted", category: .permissions)
        case .notDetermined:
            speechRecognitionGranted = false
            Logger.info("Speech recognition permission: not determined", category: .permissions)
        case .denied, .restricted:
            speechRecognitionGranted = false
            Logger.warning("Speech recognition permission: denied", category: .permissions)
        @unknown default:
            speechRecognitionGranted = false
        }
    }
    
    func requestSpeechRecognitionPermission() async -> Bool {
        Logger.info("Requesting speech recognition permission", category: .permissions)
        
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let granted = status == .authorized
                Task { @MainActor in
                    self.speechRecognitionGranted = granted
                }
                
                if granted {
                    Logger.info("Speech recognition permission granted", category: .permissions)
                } else {
                    Logger.warning("Speech recognition permission denied", category: .permissions)
                }
                
                continuation.resume(returning: granted)
            }
        }
    }
    
    // MARK: - Accessibility
    
    func checkAccessibilityPermission() {
        // Check without prompting
        let trusted = AXIsProcessTrusted()
        accessibilityGranted = trusted
        
        if trusted {
            Logger.info("Accessibility permission: granted", category: .permissions)
        } else {
            Logger.info("Accessibility permission: not granted", category: .permissions)
        }
    }
    
    /// Prompts user to grant accessibility permission in System Preferences
    /// Returns current status (user must manually enable, then restart app or re-check)
    func requestAccessibilityPermission() -> Bool {
        Logger.info("Prompting for accessibility permission", category: .permissions)
        
        // This will show the system prompt to enable accessibility
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        accessibilityGranted = trusted
        return trusted
    }
    
    /// Opens System Preferences to Accessibility pane
    func openAccessibilityPreferences() {
        Logger.info("Opening Accessibility preferences", category: .permissions)
        
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Opens System Preferences to Microphone pane
    func openMicrophonePreferences() {
        Logger.info("Opening Microphone preferences", category: .permissions)
        
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Opens System Preferences to Speech Recognition pane
    func openSpeechRecognitionPreferences() {
        Logger.info("Opening Speech Recognition preferences", category: .permissions)
        
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Request all permissions sequentially
    func requestAllPermissions() async {
        _ = await requestMicrophonePermission()
        _ = await requestSpeechRecognitionPermission()
        _ = requestAccessibilityPermission()
    }
}
