# TalkToAI

A lightweight macOS menu bar app for hands-free voice input. Press a hotkey, speak, and your words are instantly typed into any app.

![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Push-to-talk hotkey** - Hold Right Option key to record, release to transcribe
- **Universal text input** - Types directly into any focused text field
- **Terminal app support** - Smart clipboard+paste for Terminal, iTerm2, Warp, and other terminal apps
- **Auto-submit option** - Automatically press Enter after typing (great for CLI tools)
- **Dual transcription engines**:
  - **Apple Speech** - Free, on-device, works offline
  - **ElevenLabs Scribe** - Cloud-based, higher accuracy (requires API key)
- **Real-time feedback** - Floating panel shows live transcription
- **Menu bar app** - Runs quietly in the background

## Installation

### Option 1: Download Release

1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the DMG and drag TalkToAI to Applications
3. Launch TalkToAI from Applications

### Option 2: Build from Source

```bash
# Clone the repository
git clone https://github.com/enesozturk/talktoai.git
cd talktoai

# Build with Xcode
xcodebuild -scheme talktoai -configuration Release build

# Or open in Xcode
open talktoai.xcodeproj
```

## Setup

### 1. Enable System Dictation (for Apple Speech)

TalkToAI uses Apple's Speech Recognition which requires Dictation:

1. Open **System Settings**
2. Go to **Keyboard**
3. Scroll to **Dictation**
4. Turn **Dictation ON**

### 2. Grant Permissions

On first launch, grant these permissions:

| Permission | Purpose |
|------------|---------|
| **Microphone** | Capture your voice |
| **Speech Recognition** | Convert speech to text (Apple provider) |
| **Accessibility** | Type into apps & detect hotkey |

For Accessibility: **System Settings > Privacy & Security > Accessibility** > Enable TalkToAI

### 3. Configure Provider (Optional)

Click the menu bar icon to:
- Switch between Apple Speech and ElevenLabs
- Enter your ElevenLabs API key (if using cloud transcription)
- Toggle auto-submit (press Enter after typing)

## Usage

1. **Start the app** - Look for the microphone icon in the menu bar
2. **Focus a text field** - Click into any input field in any app
3. **Hold Right Option (⌥)** - Begin speaking
4. **Release the key** - Text is typed into the focused field

### Menu Bar Options

- **Apple Speech / ElevenLabs** - Switch transcription provider
- **Auto-Submit (Press Enter)** - Automatically submit after typing
- **Set ElevenLabs API Key** - Configure cloud transcription

## Terminal App Support

TalkToAI automatically detects terminal applications and uses a clipboard+paste approach for better compatibility. Supported terminals:

- Terminal.app
- iTerm2
- Warp
- Alacritty
- Kitty
- WezTerm
- Hyper
- Panic Prompt

This ensures reliable text input in CLI tools like Claude Code, vim, and other terminal applications.

## Project Structure

```
talktoai/
├── App/
│   └── AppDelegate.swift          # Main coordinator, menu bar setup
├── Core/
│   ├── AudioRecorder.swift        # Microphone capture via AVAudioEngine
│   ├── HotkeyManager.swift        # Global push-to-talk detection
│   ├── RecordingState.swift       # Observable state management
│   ├── SpeechTranscriber.swift    # Apple Speech Recognition
│   ├── ElevenLabsTranscriber.swift# ElevenLabs WebSocket API
│   ├── Transcriber.swift          # Transcriber protocol
│   ├── TranscriberConfig.swift    # Settings & API key storage
│   └── TextDispatcher.swift       # Type/paste text into apps
├── System/
│   ├── AccessibilityManager.swift # Detect focused inputs
│   └── PermissionsManager.swift   # Handle system permissions
├── UI/
│   └── FloatingPanel.swift        # Recording indicator overlay
├── Utils/
│   ├── KeyCodes.swift             # macOS key code mappings
│   └── Logger.swift               # Debug logging
├── Info.plist
├── talktoai.entitlements
└── talktoaiApp.swift
```

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0+ (for building from source)
- ElevenLabs API key (optional, for cloud transcription)

## Troubleshooting

### "Siri and Dictation are disabled"
Enable Dictation in **System Settings > Keyboard > Dictation**

### Hotkey not working
1. Grant Accessibility permission in **System Settings > Privacy & Security > Accessibility**
2. Try removing and re-adding TalkToAI from the list
3. Restart the app

### No transcription output
1. Check microphone permission is granted
2. Check Speech Recognition permission is granted
3. Ensure Dictation is enabled in system settings
4. Try switching to ElevenLabs provider

### App not appearing
The app runs as a menu bar utility. Look for the microphone icon (🎙) in the menu bar, not the Dock.

### Text not submitting in terminal
TalkToAI should auto-detect terminals. If auto-submit isn't working:
1. Ensure "Auto-Submit" is enabled in the menu
2. Try increasing the delay in `TextDispatcher.swift` (currently 1000ms)

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Apple Speech Recognition framework
- [ElevenLabs](https://elevenlabs.io) for cloud transcription API
