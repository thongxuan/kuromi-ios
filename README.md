# kuromi-ios

Kuromi iOS voice chat app — real-time voice conversation with AI.

Supports two modes:
- **Relay mode** (default): streams raw PCM audio to a Node.js relay server which handles STT, gateway, and TTS
- **On-device mode**: uses iOS `SFSpeechRecognizer` for STT, `AVSpeechSynthesizer` for TTS, connects directly to OpenClaw gateway via WebSocket

## Requirements

- iOS 16+
- Xcode 15+
- An OpenClaw gateway URL and token
- (Relay mode) Running `kuromi/relay` Node.js server

## Setup

1. Open `KuromiApp.xcodeproj` in Xcode
2. Build and run on device
3. On first launch, enter your Gateway URL and token in Settings

## Architecture

See `CLAUDE.md` for full architecture, state machine, and protocol documentation.
