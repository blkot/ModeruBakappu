# ModeruBakappu Design

## Product Goal

ModeruBakappu is a native macOS app for managing local LLM model storage and backing selected models up to an external drive without losing track of what lives where.

The app should be designed around three constraints:

1. macOS file access is permission-driven and user-selected.
2. The backup destination may be offline for long periods.
3. Model discovery logic is service-specific and should not be mixed with backup orchestration.

## Product Principles

- Native macOS first: prefer SwiftUI, AppKit, and platform conventions over cross-platform abstractions.
- Safe by default: never remove local data until copy and verification succeed.
- Explicit states: permission errors, missing sources, and offline backup drives must be visible states, not silent failures.
- Source-aware discovery: each supported LLM app gets its own detection and indexing service.
- Backup index is local: the app should preserve model records even when the external drive is disconnected.

## Recommended Stack

- UI: SwiftUI
- Platform integration: AppKit where SwiftUI is insufficient
- Concurrency: Swift Concurrency
- Storage:
  - v1: JSON in the app support directory
  - later: SQLite if history, queueing, or richer indexing becomes necessary
- Packaging: standard macOS app bundle from Xcode

## App Modules

### App Layer

Responsible for app entry, window groups, navigation, app lifecycle, and dependency wiring.

Suggested files:

- `ModeruBakappuApp.swift`
- `AppContainer.swift`

### Domain Layer

Pure app types and state models with no filesystem side effects.

Suggested models:

- `ModelSource`
- `DetectedModel`
- `BackupRecord`
- `DriveState`
- `PermissionState`
- `BackupJob`

### Services Layer

Concrete logic for filesystem access, discovery, bookmarks, and backup execution.

Suggested services:

- `LMStudioService`
- `OllamaService`
- `BookmarkStore`
- `VolumeMonitor`
- `BackupCoordinator`
- `IndexStore`
- `SettingsStore`

### UI Layer

SwiftUI screens and view models for onboarding, settings, scanning, and backup operations.

Suggested screens:

- onboarding
- source access setup
- backup drive setup
- model browser
- model detail
- backup history
- settings

## Core Flows

### First Launch

1. Show onboarding.
2. Explain that the app needs access to model folders and a backup folder.
3. Let the user choose the LM Studio models folder or let the app prefill a detected candidate.
4. Let the user choose the backup root on an external drive.
5. Store both selections as security-scoped bookmarks.
6. Validate read/write access before completing onboarding.

### Startup Preflight

1. Resolve stored bookmarks.
2. Check whether the selected source folders are still reachable.
3. Check whether the selected backup volume is mounted.
4. Confirm that the backup root exists and is writable.
5. Publish explicit source and drive states to the UI.

### Model Discovery

1. Only scan sources that are in a ready state.
2. Keep each source-specific scanner independent.
3. Persist the last known index locally.
4. Show stale-but-known data if a source becomes temporarily unavailable.

### Backup

1. Ensure the backup drive is online and writable.
2. Create a backup plan for the selected model.
3. Copy data to the external drive.
4. Verify the copied result.
5. Update the local backup index.
6. Only then offer optional local removal if that behavior is enabled.

### Restore

1. Ensure the backup drive is online.
2. Confirm the original destination or let the user choose an alternative.
3. Copy the model back.
4. Verify the restored files.
5. Update the local backup index.

## Filesystem and Permissions

### User-Selected Access

The app should not rely on hardcoded paths for long-term access. Use user-selected folders and persist them through security-scoped bookmarks.

Hardcoded paths may still be useful as discovery hints, but they should never be the only source of truth.

### LM Studio

LM Studio should be treated as a configurable source. The app should:

1. inspect LM Studio settings for a likely models directory
2. let the user confirm or override it
3. persist the confirmed folder bookmark

### Ollama

Ollama should be implemented only after its current on-disk model representation is fully specified in code and tests.

## Data Model

### Suggested `DetectedModel`

- `id`
- `sourceID`
- `displayName`
- `relativePath`
- `kind`
- `sizeBytes`
- `lastModified`
- `status`

### Suggested `BackupRecord`

- `modelID`
- `sourceID`
- `backupRelativePath`
- `backupVolumeID`
- `copiedAt`
- `verifiedAt`
- `localState`
- `backupState`

### Suggested `DriveState`

- `unknown`
- `online`
- `offline`
- `missingPermission`
- `invalidBookmark`
- `readOnly`

## Error Handling

All filesystem operations should return typed errors and map cleanly into user-visible states.

Examples:

- source inaccessible
- source permission missing
- backup drive offline
- backup folder missing
- copy failed
- verification failed

## Out of Scope for v1

- cloud storage
- compression
- automatic scheduling
- menu bar mode
- background daemon helpers
- multi-user sync
