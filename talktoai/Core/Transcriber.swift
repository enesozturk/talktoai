//
//  Transcriber.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import AVFoundation

/// Protocol for receiving transcription results from any speech-to-text provider
protocol TranscriberDelegate: AnyObject {
    /// Called with interim transcription results while user is speaking
    func transcriber(_ transcriber: any Transcriber, didReceivePartialResult text: String)
    /// Called when transcription is complete
    func transcriber(_ transcriber: any Transcriber, didFinishWithResult text: String)
    /// Called when an error occurs
    func transcriber(_ transcriber: any Transcriber, didFailWithError error: Error)
}

/// Unified protocol for speech-to-text transcription providers
/// Supports both local (Apple) and remote (ElevenLabs) implementations
protocol Transcriber: AnyObject {
    /// Delegate for receiving transcription callbacks
    var delegate: TranscriberDelegate? { get set }

    /// The latest partial transcription result
    var currentTranscription: String { get }

    /// Whether the transcriber is available and ready to use
    var isAvailable: Bool { get }

    /// Human-readable name for this transcriber
    var displayName: String { get }

    /// Start a new recognition session
    func startRecognition() throws

    /// Append an audio buffer to the recognition request
    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer)

    /// Signal that audio input has ended and wait for final result
    func finishRecognition()

    /// Stop recognition immediately and clean up resources
    func stop()
}

/// Available transcription providers
enum TranscriberProvider: String, CaseIterable {
    case apple = "apple"
    case elevenLabs = "elevenlabs"

    var displayName: String {
        switch self {
        case .apple:
            return "Apple (On-Device)"
        case .elevenLabs:
            return "ElevenLabs Scribe v2"
        }
    }
}
