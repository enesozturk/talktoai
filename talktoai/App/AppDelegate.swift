//
//  AppDelegate.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import AppKit
import SwiftUI
import AVFoundation
import Combine

/// Main application delegate that coordinates all components
/// This is a menu-bar/background app with no dock icon
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    
    // Core managers
    private let permissionsManager = PermissionsManager()
    private let hotkeyManager = HotkeyManager()
    private let audioRecorder = AudioRecorder()
    private var transcriber: any Transcriber
    private lazy var accessibilityManager = AccessibilityManager()
    private lazy var textDispatcher = TextDispatcher(accessibilityManager: accessibilityManager)

    // Configuration
    private let config = TranscriberConfig.shared

    override init() {
        self.transcriber = config.createTranscriber()
        super.init()
    }
    
    // State
    private let recordingState = RecordingState()
    private var floatingPanelController: FloatingPanelController?
    private var hasDispatchedText = false  // Prevents duplicate text dispatch

    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - App Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.info("TalkToAI starting up", category: .general)
        
        // Set as accessory app (no dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        // Setup components
        setupStatusItem()
        setupDelegates()
        setupStateObservers()
        setupFloatingPanel()
        
        // Request permissions on first launch
        Task {
            await requestPermissionsIfNeeded()
            startHotkeyMonitoring()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Logger.info("TalkToAI shutting down", category: .general)
        hotkeyManager.stop()
        audioRecorder.stop()
    }
    
    // MARK: - Setup
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "TalkToAI")
            button.image?.isTemplate = true
        }
        
        setupStatusMenu()
    }
    
    private func setupStatusMenu() {
        let menu = NSMenu()

        // Status indicator
        let statusItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
        statusItem.tag = 100 // Tag for updating later
        menu.addItem(statusItem)

        // Current provider indicator
        let providerItem = NSMenuItem(title: "Provider: \(transcriber.displayName)", action: nil, keyEquivalent: "")
        providerItem.tag = 101
        providerItem.isEnabled = false
        menu.addItem(providerItem)

        menu.addItem(NSMenuItem.separator())

        // Hotkey info
        let hotkeyItem = NSMenuItem(
            title: "Hold \(KeyCodes.name(for: hotkeyManager.hotkeyCode)) to talk",
            action: nil,
            keyEquivalent: ""
        )
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)

        menu.addItem(NSMenuItem.separator())

        // Transcriber provider submenu
        let providerSubmenu = NSMenu()

        let appleItem = NSMenuItem(
            title: TranscriberProvider.apple.displayName,
            action: #selector(selectAppleProvider),
            keyEquivalent: ""
        )
        appleItem.target = self
        appleItem.state = config.selectedProvider == .apple ? .on : .off
        appleItem.tag = 200
        providerSubmenu.addItem(appleItem)

        let elevenLabsItem = NSMenuItem(
            title: TranscriberProvider.elevenLabs.displayName,
            action: #selector(selectElevenLabsProvider),
            keyEquivalent: ""
        )
        elevenLabsItem.target = self
        elevenLabsItem.state = config.selectedProvider == .elevenLabs ? .on : .off
        elevenLabsItem.tag = 201
        providerSubmenu.addItem(elevenLabsItem)

        providerSubmenu.addItem(NSMenuItem.separator())

        let configureAPIKeyItem = NSMenuItem(
            title: "Configure ElevenLabs API Key...",
            action: #selector(configureElevenLabsAPIKey),
            keyEquivalent: ""
        )
        configureAPIKeyItem.target = self
        providerSubmenu.addItem(configureAPIKeyItem)

        let providerMenuItem = NSMenuItem(title: "Speech Provider", action: nil, keyEquivalent: "")
        providerMenuItem.submenu = providerSubmenu
        menu.addItem(providerMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Auto-submit toggle
        let autoSubmitItem = NSMenuItem(
            title: "Auto-Submit (Press Enter)",
            action: #selector(toggleAutoSubmit),
            keyEquivalent: ""
        )
        autoSubmitItem.target = self
        autoSubmitItem.state = config.autoSubmitEnabled ? .on : .off
        autoSubmitItem.tag = 301
        menu.addItem(autoSubmitItem)

        menu.addItem(NSMenuItem.separator())

        // Permissions
        let permissionsItem = NSMenuItem(title: "Check Permissions...", action: #selector(showPermissions), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit TalkToAI", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusMenu = menu
        self.statusItem?.menu = menu
    }

    private func updateProviderMenuState() {
        guard let menu = statusMenu else { return }

        // Update provider indicator
        if let providerItem = menu.item(withTag: 101) {
            providerItem.title = "Provider: \(transcriber.displayName)"
        }

        // Update checkmarks in submenu
        if let submenu = menu.item(withTitle: "Speech Provider")?.submenu {
            submenu.item(withTag: 200)?.state = config.selectedProvider == .apple ? .on : .off
            submenu.item(withTag: 201)?.state = config.selectedProvider == .elevenLabs ? .on : .off
        }
    }

    @objc private func selectAppleProvider() {
        switchTranscriberProvider(to: .apple)
        updateProviderMenuState()
    }

    @objc private func selectElevenLabsProvider() {
        if !config.hasElevenLabsAPIKey {
            configureElevenLabsAPIKey()
            return
        }
        switchTranscriberProvider(to: .elevenLabs)
        updateProviderMenuState()
    }

    @objc private func configureElevenLabsAPIKey() {
        let alert = NSAlert()
        alert.messageText = "ElevenLabs API Key"
        alert.informativeText = "Enter your ElevenLabs API key to use Scribe v2 for transcription.\n\nGet your API key at: https://elevenlabs.io/app/settings/api-keys"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textField.placeholderString = "xi-xxxxxxxx..."
        textField.stringValue = config.elevenLabsAPIKey ?? ""
        alert.accessoryView = textField

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let apiKey = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            config.elevenLabsAPIKey = apiKey

            if !apiKey.isEmpty && config.selectedProvider == .elevenLabs {
                // Refresh the transcriber with new API key
                switchTranscriberProvider(to: .elevenLabs)
            }

            Logger.info("ElevenLabs API key updated", category: .speech)
        }
    }

    @objc private func toggleAutoSubmit() {
        config.autoSubmitEnabled.toggle()
        if let autoSubmitItem = statusMenu?.item(withTag: 301) {
            autoSubmitItem.state = config.autoSubmitEnabled ? .on : .off
        }
    }

    private func setupDelegates() {
        hotkeyManager.delegate = self
        audioRecorder.delegate = self
        transcriber.delegate = self
    }

    /// Switches to a different transcription provider
    func switchTranscriberProvider(to provider: TranscriberProvider) {
        config.selectedProvider = provider
        transcriber.stop()
        transcriber = config.createTranscriber()
        transcriber.delegate = self
        Logger.info("Switched to transcriber: \(transcriber.displayName)", category: .speech)
    }
    
    private func setupStateObservers() {
        // Observe recording state changes to update UI
        recordingState.$showIndicator
            .receive(on: DispatchQueue.main)
            .sink { [weak self] shouldShow in
                if shouldShow {
                    self?.floatingPanelController?.show()
                } else {
                    self?.floatingPanelController?.hide()
                }
            }
            .store(in: &cancellables)
        
        // Update status bar icon based on state
        recordingState.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateStatusBarIcon(for: status)
            }
            .store(in: &cancellables)
    }
    
    private func setupFloatingPanel() {
        floatingPanelController = FloatingPanelController(recordingState: recordingState)
    }
    
    // MARK: - Permissions
    
    private func requestPermissionsIfNeeded() async {
        if !permissionsManager.allPermissionsGranted {
            await permissionsManager.requestAllPermissions()
        }
    }
    
    private func startHotkeyMonitoring() {
        guard permissionsManager.accessibilityGranted else {
            Logger.warning("Cannot start hotkey monitoring - accessibility not granted", category: .hotkey)
            showPermissionsAlert()
            return
        }
        
        if !hotkeyManager.start() {
            Logger.error("Failed to start hotkey monitoring", category: .hotkey)
        }
    }
    
    private func showPermissionsAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "TalkToAI needs Accessibility permission to detect the push-to-talk hotkey. Please enable it in System Settings > Privacy & Security > Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        
        if alert.runModal() == .alertFirstButtonReturn {
            permissionsManager.openAccessibilityPreferences()
        }
    }
    
    // MARK: - UI Updates
    
    private func updateStatusBarIcon(for status: RecordingStatus) {
        guard let button = statusItem?.button else { return }
        
        let imageName: String
        switch status {
        case .recording:
            imageName = "mic.fill"
            button.contentTintColor = .systemRed
        case .processing:
            imageName = "ellipsis.circle"
            button.contentTintColor = .systemOrange
        case .error:
            imageName = "exclamationmark.triangle"
            button.contentTintColor = .systemYellow
        case .idle:
            imageName = "mic.fill"
            button.contentTintColor = nil // Use template
        }
        
        button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "TalkToAI")
        button.image?.isTemplate = status == .idle
        
        // Update status text in menu
        if let statusMenuItem = statusMenu?.item(withTag: 100) {
            switch status {
            case .recording:
                statusMenuItem.title = "Recording..."
            case .processing:
                statusMenuItem.title = "Processing..."
            case .error(let message):
                statusMenuItem.title = "Error: \(message)"
            case .idle:
                statusMenuItem.title = "Ready"
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func showPermissions() {
        permissionsManager.openAccessibilityPreferences()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Recording Flow
    
    private func startRecording() {
        guard permissionsManager.microphoneGranted else {
            Logger.warning("Cannot start recording - microphone not granted", category: .audio)
            recordingState.fail(with: "Microphone permission required")
            Task {
                _ = await permissionsManager.requestMicrophonePermission()
            }
            return
        }

        // Speech recognition permission only needed for Apple provider
        if config.selectedProvider == .apple && !permissionsManager.speechRecognitionGranted {
            Logger.warning("Cannot start recording - speech recognition not granted", category: .speech)
            recordingState.fail(with: "Speech recognition permission required")
            Task {
                _ = await permissionsManager.requestSpeechRecognitionPermission()
            }
            return
        }

        // Check ElevenLabs API key for ElevenLabs provider
        if config.selectedProvider == .elevenLabs && !config.hasElevenLabsAPIKey {
            Logger.warning("Cannot start recording - ElevenLabs API key not configured", category: .speech)
            recordingState.fail(with: "ElevenLabs API key required")
            configureElevenLabsAPIKey()
            return
        }

        hasDispatchedText = false  // Reset for new recording session
        recordingState.startRecording()

        do {
            try transcriber.startRecognition()
            try audioRecorder.start()
        } catch {
            Logger.error("Failed to start recording: \(error.localizedDescription)", category: .audio)
            recordingState.fail(with: error.localizedDescription)
        }
    }
    
    private func stopRecording() {
        audioRecorder.stop()

        // Tell the transcriber we're done sending audio
        transcriber.finishRecognition()

        // Give the transcriber a moment to process the final audio buffer
        // then grab whatever text we have
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            let text = self.transcriber.currentTranscription
            self.transcriber.stop()
            self.handleFinalTranscription(text)
        }
    }
}

// MARK: - HotkeyDelegate

extension AppDelegate: HotkeyDelegate {
    func didStartRecording() {
        Logger.info("Hotkey pressed - starting recording", category: .hotkey)
        startRecording()
    }
    
    func didStopRecording() {
        Logger.info("Hotkey released - stopping recording", category: .hotkey)
        stopRecording()
    }
}

// MARK: - AudioRecorderDelegate

extension AppDelegate: AudioRecorderDelegate {
    nonisolated func audioRecorder(_ recorder: AudioRecorder, didReceiveBuffer buffer: AVAudioPCMBuffer) {
        // Forward audio buffer to transcriber - this is safe because append is thread-safe
        Task { @MainActor in
            transcriber.appendAudioBuffer(buffer)
        }
    }
    
    nonisolated func audioRecorderDidStartRecording(_ recorder: AudioRecorder) {
        Task { @MainActor in
            Logger.debug("Audio recording started", category: .audio)
        }
    }
    
    nonisolated func audioRecorderDidStopRecording(_ recorder: AudioRecorder) {
        Task { @MainActor in
            Logger.debug("Audio recording stopped", category: .audio)
        }
    }
}

// MARK: - TranscriberDelegate

extension AppDelegate: TranscriberDelegate {
    nonisolated func transcriber(_ transcriber: any Transcriber, didReceivePartialResult text: String) {
        Task { @MainActor in
            recordingState.updateTranscription(text)
        }
    }

    nonisolated func transcriber(_ transcriber: any Transcriber, didFinishWithResult text: String) {
        Task { @MainActor in
            handleFinalTranscription(text)
        }
    }

    nonisolated func transcriber(_ transcriber: any Transcriber, didFailWithError error: Error) {
        Task { @MainActor in
            recordingState.fail(with: error.localizedDescription)
        }
    }
    
    @MainActor
    private func handleFinalTranscription(_ text: String) {
        // Prevent duplicate dispatch (can be called from delegate and timeout)
        guard !hasDispatchedText else {
            Logger.debug("Text already dispatched, skipping duplicate", category: .text)
            return
        }

        guard !text.isEmpty else {
            recordingState.complete(with: "")
            return
        }

        hasDispatchedText = true  // Mark as dispatched

        // Always dispatch (type into focused field, or copy to clipboard if no field)
        let method = textDispatcher.dispatch(text, autoSubmit: config.autoSubmitEnabled)

        switch method {
        case .typed:
            Logger.info("Text typed into focused field", category: .text)
        case .pasted:
            Logger.info("Text pasted into terminal app", category: .text)
        case .clipboard:
            Logger.info("Text copied to clipboard", category: .text)
            NSSound.beep()
        }

        recordingState.complete(with: text)
    }
}
