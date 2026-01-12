# Contributing to TalkToAI

Thanks for your interest in contributing to TalkToAI! This document provides guidelines for contributing to the project.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/talktoai.git`
3. Open the project in Xcode: `open talktoai.xcodeproj`
4. Create a new branch: `git checkout -b feature/your-feature-name`

## Development Setup

### Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Swift 5.9

### Building

```bash
# Build from command line
xcodebuild -scheme talktoai -configuration Debug build

# Or use Xcode
open talktoai.xcodeproj
# Then press Cmd+B to build
```

### Running

1. Build the project in Xcode
2. Run (Cmd+R)
3. Grant required permissions when prompted
4. Look for the microphone icon in the menu bar

## Code Style

### Swift Guidelines

- Use descriptive variable and function names
- Add comments for complex logic explaining "why", not "what"
- Use `// MARK: -` to organize code sections
- Prefer `guard` for early returns
- Use `async/await` over completion handlers where possible

### Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add new transcription provider
fix: resolve hotkey detection on macOS 14
docs: update installation instructions
refactor: simplify audio buffer handling
test: add unit tests for TextDispatcher
chore: update dependencies
```

### Pull Request Guidelines

1. **Keep PRs focused** - One feature or fix per PR
2. **Update documentation** - If you change behavior, update the README
3. **Test your changes** - Ensure the app works on your machine
4. **Describe your changes** - Explain what and why in the PR description

## Project Architecture

```
talktoai/
├── App/           # Application lifecycle, menu bar
├── Core/          # Core functionality (audio, transcription, text dispatch)
├── System/        # System integrations (accessibility, permissions)
├── UI/            # User interface components
└── Utils/         # Utilities and helpers
```

### Key Components

- **HotkeyManager** - Detects push-to-talk hotkey using CGEventTap
- **AudioRecorder** - Captures microphone input via AVAudioEngine
- **Transcriber** - Protocol for speech-to-text providers
- **TextDispatcher** - Types or pastes text into focused applications
- **AccessibilityManager** - Detects focused text fields

## Adding a New Transcription Provider

1. Create a new file in `Core/` (e.g., `WhisperTranscriber.swift`)
2. Implement the `Transcriber` protocol:

```swift
protocol Transcriber: AnyObject {
    var currentTranscription: String { get }
    var onPartialResult: ((String) -> Void)? { get set }
    var onFinalResult: ((String) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }

    func startRecognition() throws
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer)
    func finishRecognition()
    func reset()
}
```

3. Add the provider to `TranscriberProvider` enum in `Transcriber.swift`
4. Update `TranscriberConfig.createTranscriber()` to support the new provider
5. Add menu items in `AppDelegate.swift`

## Reporting Issues

When reporting issues, please include:

1. macOS version
2. Steps to reproduce
3. Expected behavior
4. Actual behavior
5. Any error messages or logs

## Feature Requests

Feature requests are welcome! Please open an issue describing:

1. The problem you're trying to solve
2. Your proposed solution
3. Any alternatives you've considered

## Questions?

Feel free to open an issue for any questions about contributing.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
