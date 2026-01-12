//
//  RecordingState.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import Foundation
import Combine

/// The current state of the recording/transcription process
enum RecordingStatus: Equatable {
    case idle
    case recording
    case processing
    case error(String)
}

/// Observable state container for the recording session
@MainActor
final class RecordingState: ObservableObject {
    
    /// Current recording status
    @Published var status: RecordingStatus = .idle
    
    /// The current/latest transcription text (partial or final)
    @Published var transcription: String = ""
    
    /// Whether the recording indicator should be visible
    @Published var showIndicator: Bool = false
    
    /// Last error message, if any
    @Published var lastError: String?
    
    /// Whether we're currently recording
    var isRecording: Bool {
        status == .recording
    }
    
    /// Whether we're processing (waiting for final transcription)
    var isProcessing: Bool {
        status == .processing
    }
    
    /// Whether we're idle
    var isIdle: Bool {
        status == .idle
    }
    
    /// Start a new recording session
    func startRecording() {
        status = .recording
        transcription = ""
        lastError = nil
        showIndicator = true
        Logger.debug("RecordingState: started recording", category: .general)
    }
    
    /// Stop recording and begin processing
    func stopRecording() {
        status = .processing
        Logger.debug("RecordingState: stopped recording, processing", category: .general)
    }
    
    /// Update with partial transcription
    func updateTranscription(_ text: String) {
        transcription = text
    }
    
    /// Complete the session with final transcription
    func complete(with text: String) {
        transcription = text
        status = .idle
        
        // Hide indicator after a brief delay to show completion
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showIndicator = false
        }
        
        Logger.debug("RecordingState: completed with \(text.count) characters", category: .general)
    }
    
    /// Complete the session with an error
    func fail(with error: String) {
        status = .error(error)
        lastError = error
        showIndicator = false
        
        // Return to idle after showing error
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            if case .error = self?.status {
                self?.status = .idle
            }
        }
        
        Logger.error("RecordingState: failed with error: \(error)", category: .general)
    }
    
    /// Reset to idle state
    func reset() {
        status = .idle
        transcription = ""
        lastError = nil
        showIndicator = false
    }
}
