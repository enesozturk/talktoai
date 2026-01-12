//
//  FloatingPanel.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import SwiftUI
import AppKit

/// A floating panel that shows recording status
/// Appears near the top-center of the screen while recording
class FloatingPanelController: NSObject {
    
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingPanelView>?
    private let recordingState: RecordingState
    
    init(recordingState: RecordingState) {
        self.recordingState = recordingState
        super.init()
    }
    
    /// Show the floating panel
    @MainActor
    func show() {
        guard panel == nil else { return }
        
        // Create the SwiftUI content
        let contentView = FloatingPanelView(state: recordingState)
        let hostingView = NSHostingView(rootView: contentView)
        self.hostingView = hostingView
        
        // Calculate panel size and position
        let panelSize = NSSize(width: 280, height: 80)
        
        // Position at top-center of main screen
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelOrigin = NSPoint(
            x: screenFrame.midX - panelSize.width / 2,
            y: screenFrame.maxY - panelSize.height - 60 // 60px from top
        )
        
        let panelFrame = NSRect(origin: panelOrigin, size: panelSize)
        
        // Create the panel
        let panel = NSPanel(
            contentRect: panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView
        
        // Don't steal focus from current app
        panel.hidesOnDeactivate = false
        
        self.panel = panel
        
        // Show with animation
        panel.alphaValue = 0
        panel.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        
        Logger.debug("Floating panel shown", category: .general)
    }
    
    /// Hide the floating panel
    @MainActor
    func hide() {
        guard let panel = panel else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel = nil
            self?.hostingView = nil
        })
        
        Logger.debug("Floating panel hidden", category: .general)
    }
    
    /// Update visibility based on recording state
    @MainActor
    func updateVisibility() {
        if recordingState.showIndicator {
            show()
        } else {
            hide()
        }
    }
}

/// SwiftUI view for the floating panel content
struct FloatingPanelView: View {
    @ObservedObject var state: RecordingState
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Recording indicator
                recordingDot
                
                // Status text
                statusText
            }
            
            // Transcription preview (if any)
            if !state.transcription.isEmpty {
                Text(state.transcription)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(backgroundView)
    }
    
    private var recordingDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .stroke(dotColor.opacity(0.3), lineWidth: 2)
                    .scaleEffect(state.isRecording ? 1.5 : 1.0)
                    .opacity(state.isRecording ? 0 : 1)
                    .animation(
                        state.isRecording ?
                            Animation.easeOut(duration: 0.8).repeatForever(autoreverses: false) :
                            .default,
                        value: state.isRecording
                    )
            )
    }
    
    private var dotColor: Color {
        switch state.status {
        case .recording:
            return .red
        case .processing:
            return .orange
        case .error:
            return .yellow
        case .idle:
            return .green
        }
    }
    
    private var statusText: Text {
        switch state.status {
        case .recording:
            return Text("Listening...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        case .processing:
            return Text("Processing...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        case .error(let message):
            return Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.red)
        case .idle:
            return Text("Ready")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.green)
        }
    }
    
    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
    }
}

#Preview {
    @Previewable @StateObject var state = RecordingState()
    
    FloatingPanelView(state: state)
        .frame(width: 280, height: 80)
        .onAppear {
            state.status = .recording
            state.transcription = "Hello, this is a test transcription..."
        }
}
