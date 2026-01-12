//
//  talktoaiApp.swift
//  talktoai
//
//  Created by Enes on 12.01.2026.
//

import SwiftUI

@main
struct TalkToAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty settings scene - we're a menu bar app
        Settings {
            EmptyView()
        }
    }
}
