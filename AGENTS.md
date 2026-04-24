# AGENTS.md

This file provides guidance to Codex and other coding agents working in this repository.

## Project Overview

ModeruBakappu is being rebuilt as a native macOS app for managing local LLM model storage and backing selected models up to an external drive safely.

The previous Python/Textual codebase was a throwaway mock and has been removed. Treat this repository as the clean planning baseline for the SwiftUI/AppKit implementation.

## Current Repository State

At the moment, the repository contains:

- the macOS Xcode project
- Swift source files for the app shell, discovery, and backup flow
- project guidance in this file
- a top-level `README.md`
- design and planning documents under `docs/`

The old Python structure no longer exists.

## Target Tech Stack

- **Platform**: macOS only
- **Primary UI**: SwiftUI
- **Platform Integration**: AppKit where SwiftUI is insufficient
- **Language**: Swift
- **Concurrency**: Swift Concurrency
- **Persistence**:
  - v1: JSON in the app support directory
  - later: SQLite if history and indexing needs outgrow JSON

## Intended Project Structure

Once scaffolding begins, prefer a structure similar to:

```text
ModeruBakappu/
├── ModeruBakappu.xcodeproj
├── ModeruBakappu/
│   ├── App/
│   ├── Domain/
│   ├── Services/
│   ├── UI/
│   └── Resources/
├── ModeruBakappuTests/
├── README.md
├── docs/
└── AGENTS.md
```

Until the Xcode project exists, keep repository changes focused on planning, scaffolding, and native macOS implementation work.

## Architecture Direction

The app should be organized around four layers:

1. **App**
   - app entry
   - dependency wiring
   - window and navigation setup

2. **Domain**
   - app state and domain models
   - no direct filesystem side effects

3. **Services**
   - source discovery
   - path/settings persistence
   - volume monitoring
   - backup coordination
   - index persistence

4. **UI**
   - onboarding
   - settings
   - source status
   - model browser
   - backup and restore flows

Keep filesystem access out of views.

## Key Product Constraints

### 1. macOS File Access

macOS access to model folders and external-drive locations should be treated as a first-class product concern.

- The app is intentionally distributed outside the App Store and does not rely on App Sandbox.
- Prefer automatic provider detection where practical, with user override when detection fails.
- Treat each provider as an independent source with its own folder, state, discovered models, and backup namespace.
- Model permission failures as explicit UI state.
- Do not silently convert permission problems into "empty folder" results.

### 2. External Backup Drive

The backup destination may be disconnected for long periods.

- Keep local records even when the drive is offline.
- Validate drive presence and writability before any backup or restore write.
- Track volume identity, not only mount path strings.
- Disable destructive operations while the drive is offline or unverified.

### 3. Safe Backup Semantics

Backup logic must be conservative.

- Copy first.
- Verify the copied result.
- Persist the backup record.
- Only then allow optional local removal if that feature exists.

Never implement "move first and hope" behavior.

## Service-Specific Guidance

### LM Studio

LM Studio should be treated as a configurable source.

- Read LM Studio settings for folder hints when useful.
- Auto-detect the configured folder when possible.
- Let the user confirm or override the folder if detection fails or looks ambiguous.
- Treat the resolved folder as the source of truth.

Do not hardcode one fixed LM Studio path as the only supported location.

### oMLX

oMLX should be treated as its own provider.

- Detect the default model root at `~/.omlx/models`.
- Do not use `~/.omlx/model_settings.json` as the model root source of truth.
- Back up oMLX models under their own provider namespace.

### Ollama

Ollama support should only be added after its current on-disk representation is specified with tests and fixtures.

- Do not guess manifest layout.
- Do not treat the entire Ollama models store as one model.
- Do not implement per-model backup until backup granularity is clearly safe.

## Persistence Guidance

For v1, keep persistence simple and local.

Suggested stored data:

- app settings
- provider path settings
- source status cache
- model index
- backup records

Prefer storing app data under the standard macOS application support location for the app once the bundle exists.

## UI Guidance

Use SwiftUI by default, but do not force everything through SwiftUI if AppKit is the better fit.

Use AppKit for cases such as:

- `NSOpenPanel` for folder selection
- macOS-specific file and volume interactions
- any integration where SwiftUI introduces unnecessary friction

The app should prioritize:

- explicit status
- low-friction onboarding
- safe destructive actions
- clear offline and permission messaging

## Development Priorities

Build in this order:

1. app skeleton
2. onboarding and settings
3. drive validation
4. provider detection and discovery for LM Studio and oMLX
5. backup and restore
6. later source support such as Ollama

Do not start with backup logic before permissions and drive state are implemented.

## Testing Guidance

When tests are added, prefer:

- unit tests for domain logic
- fixture-based tests for source discovery
- integration tests for backup planning and verification

Any service-layout assumptions should be covered by tests with realistic fixtures, not by constants that merely assert hardcoded paths back to themselves.

## Development Commands

There is no app target yet. Do not add commands here that assume the Xcode project already exists.

Once the native app is scaffolded, add and maintain the relevant `xcodebuild` commands for:

- building
- running tests
- linting or formatting, if adopted

## Documents to Keep in Sync

When architecture or scope changes, update these together:

- `AGENTS.md`
- `README.md`
- `docs/design.md`
- `docs/implementation-plan.md`

These files should describe the current intended direction, not an obsolete implementation.
