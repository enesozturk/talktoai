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
        setupDeviceChangeObserver()

        // Apply saved microphone selection if any
        applySelectedMicrophone()
        
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
            title: "Hold Fn + Shift + K to talk",
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

        // Microphone selection submenu
        let microphoneSubmenu = NSMenu()

        let microphoneMenuItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        microphoneMenuItem.submenu = microphoneSubmenu
        microphoneMenuItem.tag = 401
        menu.addItem(microphoneMenuItem)

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

        // Populate microphone menu after menu is set
        updateMicrophoneMenu()
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

    // MARK: - Microphone Selection

    private func updateMicrophoneMenu() {
        guard let microphoneMenuItem = statusMenu?.item(withTag: 401),
              let submenu = microphoneMenuItem.submenu else { return }

        submenu.removeAllItems()

        // System Default option
        let defaultItem = NSMenuItem(
            title: "System Default",
            action: #selector(selectSystemDefaultMicrophone),
            keyEquivalent: ""
        )
        defaultItem.target = self
        defaultItem.state = config.selectedMicrophoneUID == nil ? .on : .off
        defaultItem.tag = 500
        submenu.addItem(defaultItem)

        submenu.addItem(NSMenuItem.separator())

        // List available input devices
        let devices = AudioDeviceManager.shared.getInputDevices()
        let selectedUID = config.selectedMicrophoneUID

        for (index, device) in devices.enumerated() {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(selectMicrophone(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device
            item.state = device.uid == selectedUID ? .on : .off
            item.tag = 501 + index
            submenu.addItem(item)
        }

        // Update the menu title to show current selection
        if let selectedUID = selectedUID,
           let device = devices.first(where: { $0.uid == selectedUID }) {
            microphoneMenuItem.title = "Microphone: \(device.name)"
        } else {
            microphoneMenuItem.title = "Microphone: System Default"
        }
    }

    @objc private func selectSystemDefaultMicrophone() {
        config.selectedMicrophoneUID = nil
        updateMicrophoneMenu()
        Logger.info("Switched to system default microphone", category: .audio)
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AudioDevice else { return }

        config.selectedMicrophoneUID = device.uid

        // Set as system default input device
        AudioDeviceManager.shared.setDefaultInputDevice(device)

        updateMicrophoneMenu()
        Logger.info("Selected microphone: \(device.name)", category: .audio)
    }

    private func setupDeviceChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(audioDevicesDidChange),
            name: AudioDeviceManager.devicesDidChangeNotification,
            object: nil
        )
    }

    @objc private func audioDevicesDidChange() {
        Logger.info("Audio devices changed, updating menu", category: .audio)
        updateMicrophoneMenu()
    }

    private func applySelectedMicrophone() {
        // If user has a saved microphone preference, set it as the system default
        guard let uid = config.selectedMicrophoneUID,
              let device = AudioDeviceManager.shared.findDevice(byUID: uid) else {
            return
        }

        AudioDeviceManager.shared.setDefaultInputDevice(device)
        Logger.info("Applied saved microphone: \(device.name)", category: .audio)
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
