//
//  Logger.swift
//  talktoai
//
//  Created by TalkToAI Team.
//

import Foundation
import os.log

/// Centralized logging utility for the app
/// Logs are disabled in release builds for privacy and performance
enum Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.talktoai"
    
    private static let hotkeyLog = OSLog(subsystem: subsystem, category: "Hotkey")
    private static let audioLog = OSLog(subsystem: subsystem, category: "Audio")
    private static let speechLog = OSLog(subsystem: subsystem, category: "Speech")
    private static let textLog = OSLog(subsystem: subsystem, category: "Text")
    private static let permissionsLog = OSLog(subsystem: subsystem, category: "Permissions")
    private static let generalLog = OSLog(subsystem: subsystem, category: "General")
    
    enum Category {
        case hotkey
        case audio
        case speech
        case text
        case permissions
        case general
        
        var osLog: OSLog {
            switch self {
            case .hotkey: return Logger.hotkeyLog
            case .audio: return Logger.audioLog
            case .speech: return Logger.speechLog
            case .text: return Logger.textLog
            case .permissions: return Logger.permissionsLog
            case .general: return Logger.generalLog
            }
        }
    }
    
    static func debug(_ message: String, category: Category = .general) {
        #if DEBUG
        os_log(.debug, log: category.osLog, "%{public}@", message)
        #endif
    }
    
    static func info(_ message: String, category: Category = .general) {
        #if DEBUG
        os_log(.info, log: category.osLog, "%{public}@", message)
        #endif
    }
    
    static func warning(_ message: String, category: Category = .general) {
        #if DEBUG
        os_log(.default, log: category.osLog, "⚠️ %{public}@", message)
        #endif
    }
    
    static func error(_ message: String, category: Category = .general) {
        // Errors are logged in both debug and release for diagnostics
        os_log(.error, log: category.osLog, "❌ %{public}@", message)
    }
}
