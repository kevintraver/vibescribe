# CLAUDE.md

This file provides guidance to coding agents when working with code in this repository.

# Vibescribe Development Guide

## Build & Test Commands

- Build: `swift build`
- Build and bundle: `./scripts/bundle.sh`
- Run: `open .build/debug/Vibescribe.app`
- Kill app: `pkill Vibescribe`

## Architecture Overview

Vibescribe is a macOS application for live transcription of collaborative conversations using FluidAudio/Parakeet v3.

**Key Components:**

- `VibescribeApp`: Application entry point, window configuration, hotkey setup
- `AppState`: Central observable state management for recording, sessions, permissions
- `TranscriptionService`: Orchestrates audio capture and transcription pipeline
- `FluidAudioProvider`: Wraps FluidAudio SDK for speech-to-text
- `DatabaseManager`: SQLite persistence for sessions and transcript lines
- `SettingsManager`: UserDefaults persistence for app settings

**Audio Capture:**

- `MicCapture`: AVAudioEngine-based microphone capture at 16kHz mono
- `AppAudioCapture`: ScreenCaptureKit-based system audio capture from specific apps
- `ThreadSafeAudioBuffer`: Lock-protected buffer for audio samples

**Services:**

- `PermissionsManager`: Handles mic and screen recording permissions
- `HotkeyManager`: Global hotkey registration using Carbon API
- `EventLogger`: Structured JSONL logging for crash recovery
- `AudioDeviceManager`: CoreAudio device enumeration
- `AppListManager`: ScreenCaptureKit app listing

**Views:**

- `SetupView`: Initial setup flow (permissions, model download)
- `SidebarView`: Session list with selection
- `TranscriptView`: Displays transcript lines with speaker labels
- `ControlsView`: Recording controls (record, pause, stop)
- `SettingsView`: App preferences (hotkey, storage, silence duration)

**Data Flow:**

1. Audio captured via MicCapture/AppAudioCapture → ThreadSafeAudioBuffer
2. TranscriptionService processes chunks every 1.5s
3. FluidAudioProvider transcribes samples → TranscriptionResult
4. Results added to Session via AppState
5. DatabaseManager persists lines immediately

## Code Style Guidelines

- **Imports**: Group Foundation/SwiftUI imports first, then frameworks (AVFoundation, ScreenCaptureKit)
- **Naming**: Use descriptive camelCase for variables/functions, PascalCase for types
- **Types**: Use explicit type annotations for public properties and parameters
- **Error Handling**: Use do/catch blocks, log errors via `Log` utility
- **Logging**: Use `Log.info/debug/warning/error()` with appropriate categories
- **State Management**: Use @Observable and @Environment for reactive UI
- **Access Control**: Use appropriate access modifiers (private, internal)
- **Concurrency**: Use async/await, actors for thread safety, @MainActor for UI code

Follow Swift idioms and default formatting (4-space indentation, spaces around operators).

## After Making Changes

Step 1: Build and bundle the app

```bash
./scripts/bundle.sh
```

Step 2: Check if build succeeded

- If you see "Build complete!", proceed to step 3
- If you see errors, stop here and fix them

Step 3: Kill the running app (if any)

```bash
pkill Vibescribe
```

Step 4: Launch the app

```bash
open .build/debug/Vibescribe.app
```

## Key Paths

- App data: `~/Library/Application Support/Vibescribe/`
- Database: `~/Library/Application Support/Vibescribe/vibescribe.db`
- Event logs: `~/Library/Application Support/Vibescribe/events.jsonl`
- Speech model: `~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml/`

## Dependencies

- FluidAudio (SPM): `https://github.com/FluidInference/FluidAudio` from `0.8.0`
- Requires macOS 15.0+, Apple Silicon
