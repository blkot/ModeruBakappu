# ModeruBakappu Implementation Plan

## Objective

Replace the discarded Python mock with a native SwiftUI/AppKit macOS application that handles provider auto-detection, removable backup drives, and model indexing safely.

## Phase 0: Repository Baseline

- remove mock Python implementation
- keep repository instructions and project-level documentation
- add native-app design and implementation planning docs
- initialize git and create the first baseline commit

## Phase 1: App Skeleton

Deliverable: a runnable macOS app shell with no backup logic yet.

Tasks:

- create Xcode project
- add SwiftUI app entry
- add basic navigation structure
- add app support directory utilities
- add settings persistence

Exit criteria:

- app launches
- settings window exists
- app can persist simple local settings

## Phase 2: Onboarding and Path Settings

Deliverable: onboarding plus persisted source and backup paths.

Tasks:

- implement onboarding flow
- add provider auto-detection for likely source folders
- add folder selection using native macOS panels as fallback
- persist resolved selections in app settings
- keep each provider's source path and status independent
- restore settings on relaunch
- surface access failures as UI state

Exit criteria:

- app can auto-detect LM Studio and oMLX when their folders are available
- user can override each provider folder
- user can select backup root
- selections persist across relaunch
- invalid selections are reported cleanly

## Phase 3: Drive Validation

Deliverable: reliable backup destination state handling.

Tasks:

- identify selected backup volume
- detect online/offline state
- validate backup root existence and writability
- disable write operations while offline
- keep existing index records available when the drive is absent

Exit criteria:

- app distinguishes offline drive from missing permission
- backup actions are gated by drive state
- records remain visible when drive is disconnected

## Phase 4: Provider Discovery

Deliverable: correct provider-separated model indexing.

Tasks:

- route detection and discovery through provider adapters
- read LM Studio settings for likely folder hints
- resolve the current configured folder automatically when possible
- detect oMLX at `~/.omlx/models`
- support user override per provider as the source of truth
- scan each selected provider folder
- build local model index
- show scan errors per source

Exit criteria:

- app lists models from confirmed provider directories
- app keeps LM Studio and oMLX records separate
- provider-specific readiness can be surfaced without changing backup logic
- index survives relaunch
- permission and path failures are visible

## Phase 5: Backup and Restore

Deliverable: safe copy-based backup and restore flow.

Tasks:

- plan copy destinations
- namespace copy destinations by provider
- perform backup copy jobs
- verify copied output
- write backup records locally
- implement restore flow
- optionally support local removal only after verified backup

Exit criteria:

- model backup succeeds to external drive
- restore succeeds back to local storage
- failed copies do not remove local originals

## Phase 6: Ollama Support

Deliverable: verified Ollama indexing strategy.

Tasks:

- specify current Ollama storage representation in code comments and tests
- implement manifest-aware discovery
- decide how backup granularity should work for Ollama
- ship only after per-model safety is demonstrated

Exit criteria:

- Ollama discovery is backed by fixture-based tests
- backup behavior does not operate on the whole store by mistake

## Testing Strategy

- unit tests for path/settings handling and index persistence
- fixture-based tests for source discovery
- integration tests for backup planning and verification
- manual QA for removable drive behavior on macOS

## Initial Directory Target

Planned post-scaffold structure:

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
```

## Immediate Next Step

Implement backup-root identity tracking and restore behavior before adding more providers.
