//
//  AudioRecorder.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import AVFoundation
import CoreAudio

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

    private var audioEngine: AVAudioEngine?
    private var isRecording = false

    /// The audio format being captured
    var audioFormat: AVAudioFormat? {
        audioEngine?.inputNode.outputFormat(forBus: 0)
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

        // Create a fresh audio engine to ensure clean state with current device
        // This is critical for external microphones like Blue Yeti that may have
        // different formats than the previously cached engine state
        audioEngine = AVAudioEngine()

        guard let audioEngine = audioEngine else {
            throw AudioRecorderError.engineStartFailed
        }

        let inputNode = audioEngine.inputNode

        // Get the hardware input format - this is what the device actually provides
        // Using inputFormat(forBus:) ensures we get the actual hardware format
        let hardwareFormat = inputNode.inputFormat(forBus: 0)

        Logger.info("Hardware input format: \(hardwareFormat.sampleRate)Hz, \(hardwareFormat.channelCount) channels", category: .audio)

        // Get the output format that AVAudioEngine will provide after any necessary conversion
        let outputFormat = inputNode.outputFormat(forBus: 0)

        Logger.info("Output format: \(outputFormat.sampleRate)Hz, \(outputFormat.channelCount) channels", category: .audio)

        // Verify we have a valid format
        guard outputFormat.sampleRate > 0 else {
            Logger.error("Invalid audio format - sample rate is 0", category: .audio)
            throw AudioRecorderError.invalidFormat
        }

        // For external microphones, we need to handle potential format mismatches
        // by using nil format which lets AVAudioEngine handle the conversion automatically
        let tapFormat: AVAudioFormat?

        if hardwareFormat.sampleRate != outputFormat.sampleRate ||
           hardwareFormat.channelCount != outputFormat.channelCount {
            // Format mismatch detected - let AVAudioEngine handle conversion
            Logger.info("Format mismatch detected, using automatic conversion", category: .audio)
            tapFormat = nil
        } else {
            tapFormat = outputFormat
        }

        // Install tap on input node to receive audio buffers
        // Use larger buffer size (4096) for better audio quality and recognition
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: tapFormat
        ) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.delegate?.audioRecorder(self, didReceiveBuffer: buffer)
        }

        // Prepare and start the engine
        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            // Clean up the tap if engine fails to start
            inputNode.removeTap(onBus: 0)
            Logger.error("Failed to start audio engine: \(error.localizedDescription)", category: .audio)
            throw AudioRecorderError.engineStartFailed
        }

        isRecording = true
        Logger.info("Audio recording started", category: .audio)

        delegate?.audioRecorderDidStartRecording(self)
    }

    /// Stop recording audio
    func stop() {
        guard isRecording else { return }

        if let audioEngine = audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioEngine = nil

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
    case deviceNotFound

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid audio format - microphone may not be available"
        case .engineStartFailed:
            return "Failed to start audio engine"
        case .deviceNotFound:
            return "Selected audio device not found"
        }
    }
}
