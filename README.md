# ModeruBakappu

ModeruBakappu is a native macOS app for managing local LLM model storage and backing selected models up to an external drive safely.

The previous Python/Textual implementation in this repository was a disposable mock and has been removed. The app is now being built as a SwiftUI/AppKit macOS utility with an Xcode project in this repository.

## Target Direction

- native macOS app
- SwiftUI-first UI
- AppKit for file panels and macOS-specific integration
- non-sandboxed distribution with direct filesystem access
- explicit handling for offline backup drives and missing permissions

## Current Status

This repository currently contains:

- the Xcode project
- Swift application source files
- product design documentation
- implementation planning
- repository instructions

## Documents

- [Design](docs/design.md)
- [Implementation Plan](docs/implementation-plan.md)

## Near-Term Build Order

1. create the macOS app skeleton
2. implement onboarding and provider detection
3. persist source and backup-folder settings
4. validate external drive state
5. add LM Studio discovery
6. implement safe backup and restore

## Requirements

- macOS
- Xcode for the upcoming native app implementation
