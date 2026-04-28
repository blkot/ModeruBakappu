# Model Lifecycle Roadmap

## Objective

ModeruBakappu should evolve from a copy-only backup utility into a model lifecycle manager for local LLM storage.

The goal is to help users keep model data available when needed while freeing space on the Mac's main drive when models are not actively in use.

## Product Direction

Model management should be explicit, reversible, and provider-aware.

The app should not silently treat a copied backup as complete lifecycle management. A copied model and an archived model are different states:

- copied backup: local model remains usable
- archived model: verified backup exists and local model data has been removed
- restored model: archived model has been copied back to the provider source path

Every destructive step must remain gated behind a verified external-drive copy.

## Model Lifecycle States

Suggested model states:

- `localOnly`: the model exists on the Mac, with no verified backup record
- `backedUp`: the model exists locally and has a verified backup copy
- `archived`: the model has a verified backup copy and local model data was removed by the app
- `restorable`: the backup drive is online and an archived model can be restored
- `missingBackupDrive`: the app knows about an archived model, but the backup drive is offline
- `restoreConflict`: the original local destination already contains different data
- `providerNotReady`: model files exist, but the provider does not currently consider the model usable
- `unknown`: the app cannot safely determine local or backup state

The UI should show these states per model, not only per provider.

## Model Actions

Suggested first-class model actions:

- `Back Up`: copy local model data to the external backup namespace and verify it
- `Archive`: copy, verify, persist the record, then remove local model data
- `Restore`: copy archived model data back to its provider source path and verify it
- `Reveal Local`: open the provider source folder for the selected model
- `Reveal Backup`: open the backup folder for the selected model
- `Delete Backup`: remove backup data only after explicit confirmation
- `Forget Record`: remove the app's local index record without deleting files

`Archive` should not be a default action. It should require a confirmation dialog that names the local path and backup path.

## Safe Archive Semantics

Archive must follow this order:

1. Validate source folder exists and is readable.
2. Validate backup drive is online, writable, and matches the stored backup-root identity.
3. Copy model data to a provider-specific backup namespace.
4. Verify copied size, file count, and optionally file hashes for high-risk operations.
5. Persist backup and lifecycle records.
6. Remove local model data.
7. Verify local removal.
8. Refresh provider discovery.

If any step before local removal fails, leave the local model untouched.

If local removal fails after a verified backup exists, preserve the backup record and surface a partial archive state.

## Restore Semantics

Restore must follow this order:

1. Validate backup drive is online and matches the stored backup-root identity.
2. Validate the backup record and backup files.
3. Check whether the target provider folder is configured and writable.
4. Detect destination conflicts.
5. Copy backup data back to the local provider path.
6. Verify restored size and file count.
7. Refresh provider discovery.
8. Mark the model as restored while preserving the backup record.

The first version should not overwrite an existing local model folder automatically.

## Provider Adapter Model

Different providers do not have the same model readiness rules. The app should introduce a provider adapter boundary before implementing deeper provider-specific management.

Suggested protocol responsibilities:

- discover configured source folder hints
- scan model folders
- produce stable model IDs
- classify provider readiness
- return provider-specific warnings
- map model IDs to provider backup namespaces
- optionally refresh provider indexes
- optionally register restored models with the provider

Suggested capability flags:

- `canDiscoverModels`
- `canValidateReadiness`
- `canRefreshProviderIndex`
- `canRegisterRestoredModel`
- `canEditProviderConfig`
- `requiresManifestForModelUse`

The app should display unsupported capabilities rather than guessing behavior.

## Provider-Specific Guidance

### LM Studio

Treat LM Studio as configurable and folder-based at first.

Initial support:

- detect configured model folder hints
- scan model directories
- back up and restore files under `lm-studio/`
- validate that restored files appear in discovery

Avoid editing LM Studio config until its settings format and refresh behavior are covered by fixtures or manual verification notes.

### oMLX

Treat oMLX as a provider where files on disk may not be enough for usability.

Initial support:

- detect `~/.omlx/models`
- scan top-level model directories
- back up and restore files under `omlx/`
- mark manually copied models as `providerNotReady` when files are present but readiness cannot be confirmed

Do not assume that placing a folder under `~/.omlx/models` is equivalent to a provider-managed installation.

### Ollama

Do not add model lifecycle actions for Ollama until its manifest and blob layout are specified with fixtures.

Ollama should remain blocked for per-model archive and restore until the app can prove it will not treat the whole model store as one model.

## Provider Config Editing

Provider config editing should be a later capability, not a first implementation step.

Before editing any provider config, the app needs:

- documented config file locations
- fixture files for each supported provider version
- backup and rollback of config edits
- typed parser/writer logic, not ad hoc string replacement
- clear UI explaining what will be changed

Until then, the app should operate on files and show provider readiness status.

## Download and Import Roadmap

The app should eventually support provider-neutral model download and import flows, especially for users with poor Hugging Face connectivity.

The flow should target higher-level model storage, not one provider's UI clone:

1. User chooses a model source such as Hugging Face repo ID or direct URL.
2. User chooses a destination:
   - local provider folder
   - backup drive archive namespace
   - download cache for later import
3. User chooses provider target metadata when needed.
4. App downloads with resume support.
5. App verifies file size and optional checksums.
6. App imports files into the selected provider folder or backup namespace.
7. App runs provider readiness validation.

## Hugging Face Connectivity Support

The app should not rely only on `HF_ENDPOINT` environment variables.

Suggested settings:

- Hugging Face base endpoint
- mirror endpoint
- token, stored in Keychain
- proxy settings if needed
- max concurrent downloads
- resume partial downloads
- retry policy

The download service should pass endpoint settings directly into requests.

China-focused connectivity support should be explicit in the UI:

- default Hugging Face endpoint
- custom mirror endpoint
- connection test
- per-download error messages

## Shared Model Store

Status: deferred. Do not implement in the current lifecycle refinement work.

A future version may support one physical model copy being exposed to multiple providers.

The safer design is not to symlink provider folders directly to each other. Instead, ModeruBakappu should own a canonical shared model store and expose models into provider-specific locations as views or registrations.

Suggested layout:

```text
BackupRoot/
  shared-models/
    huggingface--org--model/
      ...
  providers/
    lm-studio/
    omlx/
```

Possible exposure mechanisms:

- symlink provider model folder to the shared model
- provider-supported external path registration
- provider config entry pointing at shared storage
- local copy fallback when linking is unsupported
- APFS clone where the source and destination are on the same APFS volume

Each mechanism has constraints:

- symlinks may be ignored, rejected, or mishandled by provider apps
- hardlinks are not useful for directory-level model sharing and usually require the same filesystem
- APFS clones do not solve sharing across different volumes
- provider config editing is powerful but fragile across provider versions

Provider adapters should eventually expose capability flags:

- `canUseSymlinkedModel`
- `canUseExternalModelPath`
- `requiresLocalCopy`
- `requiresProviderRegistration`
- `canValidateSharedModelReadiness`

The UI should present this as provider-specific linking, not as a guaranteed universal feature:

- `Link to LM Studio`
- `Link to oMLX`
- `Provider requires local copy`
- `Shared model available`

Before implementation, the app needs provider-specific experiments and fixtures proving that each provider can safely load a linked or externally referenced model.

## Data Model Additions

Suggested stored records:

- model lifecycle state
- local path
- backup relative path
- provider namespace
- backup root ID
- archived date
- restored date
- last verified date
- verification summary
- provider readiness state
- provider readiness message

The existing backup index can evolve into a lifecycle index, but migration should be explicit.

## UI Changes

The model list should expose actions through a compact action menu instead of a single backup button.

Suggested row actions:

- Back Up
- Archive
- Restore
- Reveal Local
- Reveal Backup
- More...

Model rows should show:

- local state
- backup state
- provider readiness
- size on Mac
- size on backup drive

Provider detail should show capability warnings when a provider cannot confirm readiness or registration.

## Implementation Phases

### Phase 1: Lifecycle Model

- Add lifecycle state types.
- Extend backup records into lifecycle records.
- Show lifecycle status in the model list.
- Keep current backup behavior unchanged.

### Phase 2: Archive and Restore

- Add archive action with copy-verify-remove semantics.
- Add restore action with conflict detection.
- Add focused tests for backup planning, archive safety, and restore conflicts.

### Phase 3: Provider Adapter Boundary

- Introduce provider adapters for LM Studio and oMLX.
- Move provider-specific discovery into adapters.
- Add provider readiness output.
- Mark unknown readiness explicitly.

### Phase 4: oMLX Readiness

- Investigate oMLX's installation and readiness rules.
- Add fixtures or documented sample states.
- Surface `providerNotReady` where appropriate.
- Avoid config edits until behavior is verified.

### Phase 5: Download and Import

- Add download settings for endpoint, mirror, and token.
- Implement resumable downloads.
- Add import destination selection.
- Verify downloads before exposing model actions.

### Phase 6: Provider Config Editing

- Add parser/writer support only where provider formats are documented and tested.
- Back up config files before edits.
- Add rollback path.

## Testing Requirements

Minimum tests before archive ships:

- archive never removes local files before verified backup
- archive preserves backup record if local deletion fails
- restore refuses destination conflicts by default
- lifecycle index survives backup drive offline state
- provider namespace mapping is stable

Minimum tests before provider config editing ships:

- fixture parse/write roundtrip
- rollback on failed write
- version mismatch handling

Minimum tests before download ships:

- endpoint selection
- failed download retry
- partial download resume
- checksum mismatch handling
- destination conflict handling

## Open Questions

- Should archived models remain visible when both local source and backup drive are offline?
- Should archive remove empty parent directories after local deletion?
- Should restore support alternate destination paths?
- Should downloads target backup storage first, then restore into providers?
- Which Hugging Face mirror endpoints should be presented as examples, if any?
