//
//  SpeechTranscriber.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import Speech
import AVFoundation

/// Manages speech-to-text transcription using Apple's SFSpeechRecognizer
/// Supports streaming recognition for real-time feedback
final class SpeechTranscriber: Transcriber {

    weak var delegate: TranscriberDelegate?

    var displayName: String { "Apple (On-Device)" }
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    /// Current locale for speech recognition
    var locale: Locale {
        didSet {
            speechRecognizer = SFSpeechRecognizer(locale: locale)
            Logger.info("Speech locale changed to: \(locale.identifier)", category: .speech)
        }
    }
    
    /// Whether the speech recognizer is available
    var isAvailable: Bool {
        speechRecognizer?.isAvailable ?? false
    }
    
    /// The latest partial transcription result
    private(set) var currentTranscription = ""
    
    init(locale: Locale = .current) {
        self.locale = locale
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
        
        Logger.info("Speech transcriber initialized with locale: \(locale.identifier)", category: .speech)
    }
    
    deinit {
        stop()
    }
    
    /// Start a new recognition session
    /// Must be called before appending audio buffers
    func startRecognition() throws {
        // Cancel any existing task
        stop()
        
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            Logger.error("Speech recognizer not available", category: .speech)
            throw SpeechTranscriberError.recognizerNotAvailable
        }
        
        // Create recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        // Don't require on-device - let the system decide
        // Setting requiresOnDeviceRecognition = true can cause failures if not available
        if #available(macOS 13, *) {
            request.requiresOnDeviceRecognition = false
            request.addsPunctuation = true
            Logger.info("On-device recognition available: \(recognizer.supportsOnDeviceRecognition)", category: .speech)
        }
        
        recognitionRequest = request
        currentTranscription = ""
        
        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                // Check if this is just a cancellation
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                    // User cancelled - not an error
                    Logger.debug("Recognition cancelled by user", category: .speech)
                    return
                }
                
                Logger.error("Recognition error: \(error.localizedDescription)", category: .speech)
                self.delegate?.transcriber(self, didFailWithError: error)
                return
            }
            
            guard let result = result else { return }
            
            let transcription = result.bestTranscription.formattedString
            self.currentTranscription = transcription
            
            if result.isFinal {
                Logger.info("Final transcription: \(transcription)", category: .speech)
                self.delegate?.transcriber(self, didFinishWithResult: transcription)
            } else {
                Logger.debug("Partial transcription: \(transcription)", category: .speech)
                self.delegate?.transcriber(self, didReceivePartialResult: transcription)
            }
        }
        
        Logger.info("Speech recognition started", category: .speech)
    }
    
    /// Append an audio buffer to the recognition request
    /// Call this with buffers from AudioRecorder
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }
    
    /// Stop recognition and get final result
    func stop() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        
        Logger.info("Speech recognition stopped", category: .speech)
    }
    
    /// Finish recognition and wait for final result
    /// The result will be delivered via delegate
    func finishRecognition() {
        recognitionRequest?.endAudio()
        Logger.info("Speech recognition finishing, waiting for final result", category: .speech)
        
        // Set a timeout - if we don't get a final result within 2 seconds,
        // use the current transcription (last partial result)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            
            // If we still have an active task, it means we didn't get a final result
            if self.recognitionTask != nil && self.recognitionTask?.state == .running {
                Logger.warning("Recognition timeout - using last partial result", category: .speech)

                let finalText = self.currentTranscription
                self.delegate?.transcriber(self, didFinishWithResult: finalText)
                
                // Clean up
                self.recognitionTask?.cancel()
                self.recognitionRequest = nil
                self.recognitionTask = nil
            }
        }
    }
}

/// Errors that can occur during speech transcription
enum SpeechTranscriberError: Error, LocalizedError {
    case recognizerNotAvailable
    case recognitionFailed
    
    var errorDescription: String? {
        switch self {
        case .recognizerNotAvailable:
            return "Speech recognizer is not available for the current locale"
        case .recognitionFailed:
            return "Speech recognition failed"
        }
    }
}
