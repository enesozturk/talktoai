//
//  TranscriberConfig.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import Foundation
import Security

/// Manages transcriber configuration including provider selection and API keys
/// Uses UserDefaults for preferences and Keychain for secure API key storage
final class TranscriberConfig {

    static let shared = TranscriberConfig()

    private let providerKey = "selectedTranscriberProvider"
    private let autoPasteKey = "autoPasteEnabled"
    private let elevenLabsKeychainService = "com.talktoai.elevenlabs"
    private let elevenLabsKeychainAccount = "api-key"

    private init() {}

    // MARK: - Auto-Paste Setting

    /// When enabled, transcribed text is typed directly into the focused field.
    /// When disabled, text is only copied to clipboard.
    var autoPasteEnabled: Bool {
        get {
            // Default to true for backwards compatibility
            if UserDefaults.standard.object(forKey: autoPasteKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: autoPasteKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoPasteKey)
            Logger.info("Auto-paste \(newValue ? "enabled" : "disabled")", category: .text)
        }
    }

    // MARK: - Auto-Submit Setting

    private let autoSubmitKey = "autoSubmitEnabled"

    /// When enabled, presses Enter after typing text to submit it.
    var autoSubmitEnabled: Bool {
        get {
            return UserDefaults.standard.bool(forKey: autoSubmitKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: autoSubmitKey)
            Logger.info("Auto-submit \(newValue ? "enabled" : "disabled")", category: .text)
        }
    }

    // MARK: - Provider Selection

    var selectedProvider: TranscriberProvider {
        get {
            let rawValue = UserDefaults.standard.string(forKey: providerKey) ?? TranscriberProvider.apple.rawValue
            return TranscriberProvider(rawValue: rawValue) ?? .apple
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: providerKey)
            Logger.info("Transcriber provider changed to: \(newValue.displayName)", category: .speech)
        }
    }

    // MARK: - ElevenLabs API Key

    var elevenLabsAPIKey: String? {
        get {
            return readKeychain(service: elevenLabsKeychainService, account: elevenLabsKeychainAccount)
        }
        set {
            if let key = newValue, !key.isEmpty {
                saveKeychain(service: elevenLabsKeychainService, account: elevenLabsKeychainAccount, value: key)
            } else {
                deleteKeychain(service: elevenLabsKeychainService, account: elevenLabsKeychainAccount)
            }
        }
    }

    var hasElevenLabsAPIKey: Bool {
        guard let key = elevenLabsAPIKey else { return false }
        return !key.isEmpty
    }

    // MARK: - Transcriber Factory

    func createTranscriber() -> any Transcriber {
        switch selectedProvider {
        case .apple:
            return SpeechTranscriber()
        case .elevenLabs:
            let apiKey = elevenLabsAPIKey ?? ""
            return ElevenLabsTranscriber(apiKey: apiKey)
        }
    }

    // MARK: - Keychain Helpers

    private func saveKeychain(service: String, account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first
        deleteKeychain(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Logger.error("Failed to save to keychain: \(status)", category: .general)
        }
    }

    private func readKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func deleteKeychain(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
