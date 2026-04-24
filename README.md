# ModeruBakappu

A native macOS utility for managing local LLM model storage and backing selected models up to an external drive.

ModeruBakappu is built for local-first model workflows: detect where provider apps keep their models, show what is installed, and copy selected models to a trusted backup root without losing track of provider boundaries.

## Status

This project is an early native macOS rewrite. The old Python/Textual prototype was removed and replaced with a SwiftUI/AppKit Xcode project.

Current implementation:

- SwiftUI macOS app shell
- provider-separated source configuration
- LM Studio source detection
- oMLX source detection via `~/.omlx/models`
- external backup root validation
- backup-root marker file: `.moderubakappu-backup.json`
- local backup index stored under Application Support
- copy-and-verify backup flow for discovered model folders

Still in progress:

- restore workflow
- richer backup history UI
- Ollama support
- fixture-based discovery tests
- volume identity tracking beyond the current backup marker ID

## Supported Providers

| Provider | Detection | Backup Namespace |
| --- | --- | --- |
| LM Studio | known local model roots | `lm-studio/` |
| oMLX | `~/.omlx/models` | `omlx/` |

Providers are intentionally independent. You can use LM Studio, oMLX, or multiple providers at the same time; their source folders, scan state, discovered models, and backup paths are kept separate.

## Backup Model

ModeruBakappu treats the selected external-drive folder as a registered backup root.

When a backup root is selected, the app creates or validates:

```text
.moderubakappu-backup.json
```

The marker contains a generated backup-root ID. The app also stores that ID locally, so future launches can distinguish the expected backup folder from a different folder at a similar path.

Backups are conservative:

1. Validate that the backup root exists and is writable.
2. Copy the model folder into a provider-specific namespace.
3. Verify copied file count and total size.
4. Record the backup locally.
5. Leave the original model files untouched.

## Project Structure

```text
ModeruBakappu/
  ModeruBakappu.xcodeproj
  ModeruBakappu/
    App/
    Domain/
    Services/
    UI/
    Resources/
  ModeruBakappuTests/
  ModeruBakappuUITests/
  docs/
```

Key areas:

- `App/`: app state and lifecycle wiring
- `Domain/`: provider, model, backup, and status types
- `Services/`: source detection, folder picking, backup coordination, index persistence
- `UI/`: onboarding, dashboard, settings, and reusable SwiftUI components

## Development

Requirements:

- macOS
- Xcode

Open the project:

```bash
open ModeruBakappu.xcodeproj
```

Build from the command line:

```bash
xcodebuild \
  -project ModeruBakappu.xcodeproj \
  -scheme ModeruBakappu \
  -derivedDataPath /tmp/ModeruBakappuDerived \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

## Design Notes

ModeruBakappu is intentionally distributed outside the App Store and currently runs without App Sandbox. That lets it inspect local provider model folders directly, while still keeping backup behavior explicit and conservative.

The app should continue to prioritize:

- provider-specific discovery instead of generic directory guesses
- clear offline, missing, and permission states
- copy-first backup behavior
- verified backups before any future local-removal feature
- local records that remain useful when the external drive is disconnected

## Documentation

- [Design](docs/design.md)
- [Implementation Plan](docs/implementation-plan.md)
