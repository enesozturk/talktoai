//
//  ElevenLabsTranscriber.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import AVFoundation
import Foundation

/// Manages real-time speech-to-text transcription using ElevenLabs Scribe v2 Realtime
/// Uses WebSocket streaming for low-latency transcription (~150ms)
final class ElevenLabsTranscriber: NSObject, Transcriber {

    weak var delegate: TranscriberDelegate?

    var displayName: String { "ElevenLabs Scribe v2" }

    private(set) var currentTranscription = ""

    var isAvailable: Bool {
        !apiKey.isEmpty
    }

    // MARK: - Configuration

    private let apiKey: String
    private let modelId = "scribe_v2_realtime"
    private let targetSampleRate: Double = 16000

    // MARK: - WebSocket State

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var isStopping = false  // Flag to suppress errors during intentional close
    private var sessionId: String?
    private var pendingAudioBuffers: [Data] = []
    private let bufferQueue = DispatchQueue(label: "com.talktoai.elevenlabs.buffer")

    // MARK: - Audio Conversion

    private var audioConverter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let outputFormat: AVAudioFormat

    // MARK: - Initialization

    init(apiKey: String) {
        self.apiKey = apiKey

        // Create output format for ElevenLabs (16kHz mono PCM)
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        super.init()
    }

    deinit {
        stop()
    }

    // MARK: - Transcriber Protocol

    func startRecognition() throws {
        guard isAvailable else {
            throw ElevenLabsTranscriberError.apiKeyMissing
        }

        stop()
        isStopping = false  // Reset flag for new session
        currentTranscription = ""

        try connectWebSocket()
        Logger.info("ElevenLabs transcription started", category: .speech)
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Convert audio to ElevenLabs format
        guard let convertedData = convertAudioBuffer(buffer) else {
            Logger.warning("Failed to convert audio buffer", category: .speech)
            return
        }

        // If connected, send immediately. Otherwise, queue for later.
        if isConnected {
            sendAudioChunk(convertedData)
        } else {
            bufferQueue.sync {
                pendingAudioBuffers.append(convertedData)
                // Limit buffer size to prevent memory issues (keep ~5 seconds of audio)
                let maxBuffers = 250 // ~5 seconds at 4096 samples/buffer
                if pendingAudioBuffers.count > maxBuffers {
                    pendingAudioBuffers.removeFirst(pendingAudioBuffers.count - maxBuffers)
                }
            }
        }
    }

    /// Flush any buffered audio after connection is established
    private func flushPendingAudio() {
        bufferQueue.sync {
            Logger.info("Flushing \(pendingAudioBuffers.count) pending audio buffers", category: .speech)
            for audioData in pendingAudioBuffers {
                sendAudioChunk(audioData)
            }
            pendingAudioBuffers.removeAll()
        }
    }

    func finishRecognition() {
        guard isConnected else { return }

        // Send final commit to get remaining transcription
        sendCommit()

        Logger.info("ElevenLabs transcription finishing, waiting for final result", category: .speech)

        // Timeout fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self, self.isConnected else { return }

            Logger.warning("ElevenLabs timeout - using last transcription", category: .speech)
            let finalText = self.currentTranscription
            self.delegate?.transcriber(self, didFinishWithResult: finalText)
            self.stop()
        }
    }

    func stop() {
        isStopping = true  // Suppress errors during intentional close
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        sessionId = nil
        audioConverter = nil
        inputFormat = nil
        bufferQueue.sync {
            pendingAudioBuffers.removeAll()
        }

        Logger.info("ElevenLabs transcription stopped", category: .speech)
    }

    // MARK: - WebSocket Connection

    private func connectWebSocket() throws {
        var components = URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!

        components.queryItems = [
            URLQueryItem(name: "model_id", value: modelId),
            URLQueryItem(name: "audio_format", value: "pcm_16000"),
            URLQueryItem(name: "include_timestamps", value: "false"),
            URLQueryItem(name: "commit_strategy", value: "manual")
        ]

        guard let url = components.url else {
            throw ElevenLabsTranscriberError.invalidURL
        }

        Logger.info("Connecting to ElevenLabs WebSocket...", category: .speech)

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.timeoutInterval = 30

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        // Use main queue for delegate callbacks to avoid threading issues
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()

        // receiveMessage() is called from didOpenWithProtocol delegate

        // Send periodic pings to keep connection alive
        schedulePing()
    }

    private func schedulePing() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, self.webSocketTask?.state == .running else { return }
            self.webSocketTask?.sendPing { error in
                if let error = error {
                    Logger.warning("Ping failed: \(error.localizedDescription)", category: .speech)
                } else {
                    self.schedulePing()
                }
            }
        }
    }

    private func receiveMessage() {
        guard let task = webSocketTask else {
            Logger.error("receiveMessage called but webSocketTask is nil", category: .speech)
            return
        }

        Logger.info("Starting to receive messages, task state: \(task.state.rawValue)", category: .speech)

        task.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                Logger.debug("Received WebSocket message", category: .speech)
                self.handleMessage(message)
                self.receiveMessage() // Continue listening
            case .failure(let error):
                // Don't report errors if we're intentionally stopping
                guard !self.isStopping else {
                    Logger.debug("WebSocket closed during stop - ignoring error", category: .speech)
                    return
                }
                let nsError = error as NSError
                Logger.error("WebSocket receive error: \(error.localizedDescription) (domain: \(nsError.domain), code: \(nsError.code))", category: .speech)
                DispatchQueue.main.async {
                    self.delegate?.transcriber(self, didFailWithError: error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseResponse(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseResponse(text)
            }
        @unknown default:
            break
        }
    }

    private func parseResponse(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageType = json["message_type"] as? String else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            switch messageType {
            case "session_started":
                self.sessionId = json["session_id"] as? String
                self.isConnected = true
                Logger.info("ElevenLabs session started: \(self.sessionId ?? "unknown")", category: .speech)
                self.flushPendingAudio()

            case "partial_transcript":
                if let text = json["text"] as? String {
                    self.currentTranscription = text
                    Logger.debug("Partial transcription: \(text)", category: .speech)
                    self.delegate?.transcriber(self, didReceivePartialResult: text)
                }

            case "committed_transcript", "committed_transcript_with_timestamps":
                if let text = json["text"] as? String {
                    self.currentTranscription = text
                    Logger.info("Final transcription: \(text)", category: .speech)
                    self.delegate?.transcriber(self, didFinishWithResult: text)
                }

            case "error", "auth_error", "quota_exceeded", "rate_limited":
                let errorMessage = json["error"] as? String ?? "Unknown error"
                Logger.error("ElevenLabs error (\(messageType)): \(errorMessage)", category: .speech)
                self.delegate?.transcriber(self, didFailWithError: ElevenLabsTranscriberError.serverError(errorMessage))

            default:
                Logger.debug("Unhandled message type: \(messageType)", category: .speech)
            }
        }
    }

    // MARK: - Audio Processing

    private func convertAudioBuffer(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let bufferFormat = buffer.format as AVAudioFormat? else { return nil }

        // Setup converter if needed or format changed
        if inputFormat != bufferFormat {
            inputFormat = bufferFormat
            audioConverter = AVAudioConverter(from: bufferFormat, to: outputFormat)
        }

        guard let converter = audioConverter else {
            Logger.warning("No audio converter available", category: .audio)
            return nil
        }

        // Calculate output frame capacity
        let ratio = outputFormat.sampleRate / bufferFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return nil
        }

        var error: NSError?
        var hasData = false

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasData {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasData = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            Logger.warning("Audio conversion error: \(error.localizedDescription)", category: .audio)
            return nil
        }

        // Extract int16 samples as Data
        guard let int16Data = outputBuffer.int16ChannelData else { return nil }
        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: int16Data[0], count: byteCount)
    }

    // MARK: - WebSocket Messages

    private func sendAudioChunk(_ audioData: Data) {
        let base64Audio = audioData.base64EncodedString()

        let message: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": base64Audio,
            "commit": false,
            "sample_rate": Int(targetSampleRate)
        ]

        sendJSON(message)
    }

    private func sendCommit() {
        let message: [String: Any] = [
            "message_type": "input_audio_chunk",
            "audio_base_64": "",
            "commit": true,
            "sample_rate": Int(targetSampleRate)
        ]

        sendJSON(message)
    }

    private func sendJSON(_ dict: [String: Any]) {
        guard let task = webSocketTask,
              task.state == .running else {
            Logger.warning("WebSocket not ready, skipping send", category: .speech)
            return
        }

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: data, encoding: .utf8) else {
            return
        }

        task.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                Logger.warning("WebSocket send error: \(error.localizedDescription)", category: .speech)
                // If socket closed unexpectedly, notify delegate
                if (error as NSError).code == 57 { // Socket is not connected
                    DispatchQueue.main.async {
                        self?.isConnected = false
                    }
                }
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate

extension ElevenLabsTranscriber: URLSessionWebSocketDelegate {
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Logger.info("✅ WebSocket didOpenWithProtocol called", category: .speech)
        // Start receiving messages now that connection is open
        receiveMessage()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
        Logger.info("WebSocket didCloseWith: code=\(closeCode.rawValue), reason=\(reasonString)", category: .speech)
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            // Don't report errors if we're intentionally stopping
            guard !isStopping else {
                Logger.debug("WebSocket task ended during stop - ignoring", category: .speech)
                return
            }
            let nsError = error as NSError
            Logger.error("WebSocket didCompleteWithError: \(error.localizedDescription) (domain: \(nsError.domain), code: \(nsError.code))", category: .speech)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isConnected = false
                self.delegate?.transcriber(self, didFailWithError: error)
            }
        }
    }

    // Called when WebSocket receives a challenge (for debugging SSL issues)
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        Logger.info("WebSocket received auth challenge: \(challenge.protectionSpace.authenticationMethod)", category: .speech)
        completionHandler(.performDefaultHandling, nil)
    }
}

// MARK: - Errors

enum ElevenLabsTranscriberError: Error, LocalizedError {
    case apiKeyMissing
    case invalidURL
    case connectionFailed
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "ElevenLabs API key is not configured"
        case .invalidURL:
            return "Failed to construct WebSocket URL"
        case .connectionFailed:
            return "Failed to connect to ElevenLabs"
        case .serverError(let message):
            return "ElevenLabs error: \(message)"
        }
    }
}
