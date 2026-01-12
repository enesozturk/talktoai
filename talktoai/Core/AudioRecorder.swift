//
//  AudioRecorder.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import AVFoundation

/// Protocol for receiving audio buffers
protocol AudioRecorderDelegate: AnyObject {
    func audioRecorder(_ recorder: AudioRecorder, didReceiveBuffer buffer: AVAudioPCMBuffer)
    func audioRecorderDidStartRecording(_ recorder: AudioRecorder)
    func audioRecorderDidStopRecording(_ recorder: AudioRecorder)
}

/// Manages microphone audio capture using AVAudioEngine
/// Provides audio buffers for speech recognition
final class AudioRecorder {
    
    weak var delegate: AudioRecorderDelegate?
    
    private let audioEngine = AVAudioEngine()
    private var isRecording = false
    
    /// The audio format being captured
    var audioFormat: AVAudioFormat? {
        audioEngine.inputNode.outputFormat(forBus: 0)
    }
    
    init() {}
    
    deinit {
        stop()
    }
    
    /// Start recording audio from the microphone
    /// - Throws: Error if audio engine cannot be started
    func start() throws {
        guard !isRecording else {
            Logger.warning("Audio recorder already recording", category: .audio)
            return
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Verify we have a valid format
        guard recordingFormat.sampleRate > 0 else {
            Logger.error("Invalid audio format - sample rate is 0", category: .audio)
            throw AudioRecorderError.invalidFormat
        }
        
        Logger.info("Audio format: \(recordingFormat.sampleRate)Hz, \(recordingFormat.channelCount) channels", category: .audio)
        
        // Install tap on input node to receive audio buffers
        // Use larger buffer size (4096) for better audio quality and recognition
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: recordingFormat
        ) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.delegate?.audioRecorder(self, didReceiveBuffer: buffer)
        }
        
        // Prepare and start the engine
        audioEngine.prepare()
        try audioEngine.start()
        
        isRecording = true
        Logger.info("Audio recording started", category: .audio)
        
        delegate?.audioRecorderDidStartRecording(self)
    }
    
    /// Stop recording audio
    func stop() {
        guard isRecording else { return }
        
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
        isRecording = false
        Logger.info("Audio recording stopped", category: .audio)
        
        delegate?.audioRecorderDidStopRecording(self)
    }
    
    /// Check if currently recording
    var recording: Bool {
        isRecording
    }
}

/// Errors that can occur during audio recording
enum AudioRecorderError: Error, LocalizedError {
    case invalidFormat
    case engineStartFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid audio format - microphone may not be available"
        case .engineStartFailed:
            return "Failed to start audio engine"
        }
    }
}
