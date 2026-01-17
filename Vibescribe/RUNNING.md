# Running Vibescribe

## Prerequisites

- macOS 15.0 or later
- Apple Silicon Mac

## Build & Run (CLI)

```bash
cd /Users/kevin/Code/vibescribe/Vibescribe

# Build the app bundle
xcodebuild -scheme Vibescribe -configuration Debug \
  -derivedDataPath .build/xcode \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

# Run
open .build/xcode/Build/Products/Debug/Vibescribe.app
```

## First Launch

On first launch, Vibescribe will:

1. **Request microphone permission** - Required for transcription
2. **Download the Parakeet v3 model** (~650MB) - One-time download

The app will show a setup screen until both are complete.

## Troubleshooting

### App doesn't appear
- Check if it's running: `pgrep -l Vibescribe`
- Kill and retry: `pkill Vibescribe`
- Try running from Xcode to see console output

### Permission issues
- Go to **System Settings > Privacy & Security > Microphone**
- Ensure Vibescribe is allowed
- For screen recording (system audio): **System Settings > Privacy & Security > Screen Recording**
