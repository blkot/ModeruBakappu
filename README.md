# ModeruBakappu

ModeruBakappu is being rebuilt as a native macOS app for managing local LLM model storage and backing selected models up to an external drive safely.

The previous Python/Textual implementation in this repository was a disposable mock and has been removed. The repository is now the clean planning baseline for the SwiftUI/AppKit rewrite.

## Target Direction

- native macOS app
- SwiftUI-first UI
- AppKit for file panels and macOS-specific integration
- persistent folder access via security-scoped bookmarks
- explicit handling for offline backup drives and missing permissions

## Current Status

This repository currently contains:

- product design documentation
- implementation planning
- repository instructions

It does not yet contain the Xcode project or application source files.

## Documents

- [Design](docs/design.md)
- [Implementation Plan](docs/implementation-plan.md)

## Near-Term Build Order

1. create the macOS app skeleton
2. implement onboarding and folder selection
3. persist source and backup-folder access
4. validate external drive state
5. add LM Studio discovery
6. implement safe backup and restore

## Requirements

- macOS
- Xcode for the upcoming native app implementation
