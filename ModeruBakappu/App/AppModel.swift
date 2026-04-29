//
//  AppModel.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var hasLoaded = false
    @Published private(set) var sourceConfigurations: [ModelSourceConfiguration]
    @Published private(set) var backupFolderURL: URL?
    @Published private(set) var backupDriveState: BackupDriveState = .notConfigured
    @Published private(set) var backupDriveSpaceInfo: BackupDriveSpaceInfo?
    @Published private(set) var mainDriveSpaceInfo: BackupDriveSpaceInfo?
    @Published private(set) var backupRecords: [String: BackupRecord] = [:]
    @Published var errorMessage: String?

    let catalogViewModel = CatalogViewModel()

    private let bookmarkStore: BookmarkStore
    private let backupIndexStore: BackupIndexStore
    private let folderPicker: FolderPicker
    private let modelSourceLocator: ModelSourceLocator
    private let backupCoordinator: BackupCoordinator
    private let fileManager: FileManager

    private var backupBookmarkIsStale = false
    private var activeBackupIDs: Set<String> = []
    private var activeArchiveIDs: Set<String> = []
    private var activeRestoreIDs: Set<String> = []
    private var activeDeleteLocalIDs: Set<String> = []
    private var activeDeleteBackupIDs: Set<String> = []
    private var backupFailures: [String: String] = [:]
    private var archiveFailures: [String: String] = [:]
    private var restoreFailures: [String: String] = [:]
    private var deleteLocalFailures: [String: String] = [:]
    private var deleteBackupFailures: [String: String] = [:]
    private var backupDestinationConflicts: [String: BackupDestinationConflict] = [:]
    private var lastBackupValidationFailure: String?
    private let backupRootIDDefaultsKey = "ModeruBakappu.backupRootID"

    private static let supportedProviders: [ModelProvider] = [.lmStudio, .omlx, .ollama]

    convenience init() {
        self.init(
            bookmarkStore: UserDefaultsBookmarkStore(),
            backupIndexStore: JSONBackupIndexStore(),
            folderPicker: OpenPanelFolderPicker(),
            modelSourceLocator: ModelSourceLocator(),
            backupCoordinator: BackupCoordinator(),
            fileManager: .default
        )
    }

    init(
        bookmarkStore: BookmarkStore,
        backupIndexStore: BackupIndexStore,
        folderPicker: FolderPicker,
        modelSourceLocator: ModelSourceLocator,
        backupCoordinator: BackupCoordinator,
        fileManager: FileManager
    ) {
        self.bookmarkStore = bookmarkStore
        self.backupIndexStore = backupIndexStore
        self.folderPicker = folderPicker
        self.modelSourceLocator = modelSourceLocator
        self.backupCoordinator = backupCoordinator
        self.fileManager = fileManager
        self.sourceConfigurations = Self.supportedProviders.map { provider in
            ModelSourceConfiguration(
                provider: provider,
                folderURL: nil,
                accessState: .notConfigured,
                discoveryState: .idle,
                models: [],
                bookmarkIsStale: false
            )
        }
    }

    var hasMinimumConfiguration: Bool {
        backupFolderURL != nil && sourceConfigurations.contains { $0.folderURL != nil }
    }

    var configuredSourceCount: Int {
        sourceConfigurations.filter { $0.folderURL != nil }.count
    }

    var discoveredModelCount: Int {
        sourceConfigurations.reduce(0) { $0 + $1.models.count }
    }

    var backupDriveSummary: String {
        lastBackupValidationFailure ?? backupDriveState.summary
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }

        print("[AppModel] loadIfNeeded")
        loadBackupIndex()
        restoreBookmarks()
        autoDetectSourceFolders()
        refreshStatuses()
        hasLoaded = true
    }

    func selectSourceFolder(for provider: ModelProvider) {
        guard provider.isEnabled else { return }

        let picked = folderPicker.pickFolder(
            title: "Choose \(provider.displayName) Models Folder",
            message: "Choose the folder where \(provider.displayName) stores local models.",
            prompt: "Use Folder",
            startingAt: configuration(for: provider)?.folderURL
        )

        guard let picked else { return }
        print("[AppModel] selected source folder provider=\(provider.displayName) path=\(picked.path)")
        saveSourceSelection(picked, for: provider)
    }

    func selectBackupFolder() {
        let picked = folderPicker.pickFolder(
            title: "Choose Backup Root",
            message: "Select the root folder on your external drive where backups should be stored.",
            prompt: "Use Backup Root",
            startingAt: backupFolderURL
        )

        guard let picked else { return }
        print("[AppModel] selected backup root: \(picked.path)")
        saveBackupSelection(picked)
    }

    func refreshStatuses() {
        print("[AppModel] refreshStatuses")
        for index in sourceConfigurations.indices {
            let configuration = sourceConfigurations[index]
            let state = evaluateSourceFolder(
                url: configuration.folderURL,
                isStale: configuration.bookmarkIsStale,
                provider: configuration.provider
            )
            sourceConfigurations[index].accessState = state
        }
        backupDriveState = evaluateBackupFolder(url: backupFolderURL, isStale: backupBookmarkIsStale)
        backupDriveSpaceInfo = readBackupDriveSpace(url: backupFolderURL)
        mainDriveSpaceInfo = readMainDriveSpace()
        refreshModelDiscovery()
        print("[AppModel] configuredSources=\(configuredSourceCount) backupState=\(backupDriveState.title)")
    }

    func refreshModelDiscovery() {
        for index in sourceConfigurations.indices {
            let configuration = sourceConfigurations[index]
            guard configuration.provider.isEnabled else {
                sourceConfigurations[index].models = []
                sourceConfigurations[index].discoveryState = .unavailable
                continue
            }

            guard configuration.accessState == .ready, let folderURL = configuration.folderURL else {
                sourceConfigurations[index].models = []
                sourceConfigurations[index].discoveryState = .unavailable
                continue
            }

            sourceConfigurations[index].discoveryState = .scanning

            let result: Result<[DiscoveredModel], Error> = withScopedAccess(to: folderURL) {
                Result {
                    try modelSourceLocator.discoverModels(in: folderURL, source: configuration.provider)
                }
            }

            switch result {
            case let .success(models):
                sourceConfigurations[index].models = models
                sourceConfigurations[index].discoveryState = models.isEmpty ? .empty : .ready(count: models.count)
            case let .failure(error):
                sourceConfigurations[index].models = []
                sourceConfigurations[index].discoveryState = .failed(error.localizedDescription)
            }
        }

        reconcileBackupDestinations()
    }

    func clearError() {
        errorMessage = nil
    }

    func displayModels(for configuration: ModelSourceConfiguration) -> [DiscoveredModel] {
        var models = configuration.models
        let localIDs = Set(models.map(\.id))

        let archivedModels = backupRecords.values.compactMap { record -> DiscoveredModel? in
            guard record.source == configuration.provider.rawValue,
                  record.effectiveLocalState == .archived,
                  backupRecordIsAvailable(record),
                  !localIDs.contains(record.modelID),
                  let folderURL = configuration.folderURL
            else {
                return nil
            }

            let pathComponents = record.relativePath.split(separator: "/").map(String.init)
            let publisher = pathComponents.count > 1 ? pathComponents.first : nil

            return DiscoveredModel(
                id: record.modelID,
                source: record.source,
                publisher: publisher,
                displayName: record.displayName,
                folderURL: folderURL.appendingPathComponent(record.relativePath, isDirectory: true),
                relativePath: record.relativePath,
                sizeBytes: record.sizeBytes,
                fileCount: record.fileCount,
                lastModified: record.archivedAt ?? record.backedUpAt
            )
        }

        models.append(contentsOf: archivedModels)
        return models.sorted {
            ($0.publisher ?? "", $0.displayName.localizedLowercase) < ($1.publisher ?? "", $1.displayName.localizedLowercase)
        }
    }

    func backupState(for model: DiscoveredModel) -> ModelBackupState {
        if let message = backupFailures[model.id] {
            return .failed(message)
        }

        if activeBackupIDs.contains(model.id) {
            return .inProgress
        }

        if let record = backupRecords[model.id] {
            if backupRecordIsAvailable(record) {
                return .backedUp(record)
            }

            if backupDriveState == .online {
                return .ready
            }
        }

        if let conflict = backupDestinationConflicts[model.id] {
            return .destinationConflict(conflict)
        }

        guard backupDriveState == .online else {
            return .unavailable
        }

        return .ready
    }

    private func backupRecordIsAvailable(_ record: BackupRecord) -> Bool {
        guard backupDriveState == .online,
              let backupFolderURL
        else {
            return false
        }

        let backupURL = backupFolderURL.appendingPathComponent(record.backupRelativePath, isDirectory: true)
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: backupURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func reconcileBackupDestinations() {
        guard backupDriveState == .online,
              let backupFolderURL
        else {
            backupDestinationConflicts = [:]
            return
        }

        var repairedRecords = false
        var latestConflicts: [String: BackupDestinationConflict] = [:]

        for model in sourceConfigurations.flatMap(\.models) {
            guard backupRecords[model.id] == nil else {
                continue
            }

            do {
                switch try backupCoordinator.inspectBackupDestination(for: model, in: backupFolderURL) {
                case .missing:
                    continue
                case let .matching(record):
                    backupRecords[model.id] = record
                    repairedRecords = true
                    print("[AppModel] repaired missing backup record model=\(model.id) path=\(record.backupRelativePath)")
                case let .conflict(conflict):
                    latestConflicts[model.id] = conflict
                    print("[AppModel] backup destination conflict model=\(model.id) path=\(conflict.backupRelativePath)")
                }
            } catch {
                print("[AppModel] backup destination inspection failed model=\(model.id) error=\(error.localizedDescription)")
            }
        }

        backupDestinationConflicts = latestConflicts

        if repairedRecords {
            do {
                try backupIndexStore.saveIndex(backupRecords)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func lifecycleStatus(for model: DiscoveredModel) -> ModelLifecycleStatus {
        let backupState = backupState(for: model)
        let lifecycleState: ModelLifecycleState

        if activeArchiveIDs.contains(model.id) {
            lifecycleState = .archiving
        } else if activeRestoreIDs.contains(model.id) {
            lifecycleState = .restoring
        } else if activeDeleteLocalIDs.contains(model.id) {
            lifecycleState = .deletingLocal
        } else if activeDeleteBackupIDs.contains(model.id) {
            lifecycleState = .deletingBackup
        } else if let message = archiveFailures[model.id] {
            lifecycleState = .archiveFailed(message)
        } else if let message = restoreFailures[model.id] {
            lifecycleState = .restoreFailed(message)
        } else if let message = deleteLocalFailures[model.id] {
            lifecycleState = .deleteLocalFailed(message)
        } else if let message = deleteBackupFailures[model.id] {
            lifecycleState = .deleteBackupFailed(message)
        } else {
            switch backupState {
            case .ready:
                lifecycleState = .localOnly
            case .unavailable:
                lifecycleState = .backupUnavailable
            case .inProgress:
                lifecycleState = .backingUp
            case let .backedUp(record):
                if record.effectiveLocalState == .archived {
                    if fileManager.fileExists(atPath: model.folderURL.path) {
                        lifecycleState = .restoreConflict("A local folder exists, but the backup index still marks this model archived.")
                    } else {
                        lifecycleState = backupDriveState == .online ? .restorable(record) : .missingBackupDrive(record)
                    }
                } else {
                    lifecycleState = .backedUp(record)
                }
            case let .destinationConflict(conflict):
                lifecycleState = .backupConflict(conflict)
            case let .failed(message):
                lifecycleState = .backupFailed(message)
            }
        }

        return ModelLifecycleStatus(
            state: lifecycleState,
            providerReadiness: modelSourceLocator.readiness(for: model),
            backupState: backupState
        )
    }

    func backup(model: DiscoveredModel) {
        guard backupState(for: model).canTriggerBackup, let backupFolderURL else {
            return
        }

        activeBackupIDs.insert(model.id)
        backupFailures[model.id] = nil
        objectWillChange.send()

        let backupCoordinator = self.backupCoordinator

        DispatchQueue.global(qos: .userInitiated).async {
            let sourceAccess = model.folderURL.startAccessingSecurityScopedResource()
            let backupAccess = backupFolderURL.startAccessingSecurityScopedResource()

            defer {
                if sourceAccess {
                    model.folderURL.stopAccessingSecurityScopedResource()
                }
                if backupAccess {
                    backupFolderURL.stopAccessingSecurityScopedResource()
                }
            }

            let result = Result { try backupCoordinator.backup(model: model, to: backupFolderURL) }

            Task { @MainActor in
                self.completeBackup(result, for: model.id)
            }
        }
    }

    func archive(model: DiscoveredModel) {
        guard backupDriveState == .online,
              let backupFolderURL,
              lifecycleStatus(for: model).canTriggerArchive
        else {
            return
        }

        activeArchiveIDs.insert(model.id)
        archiveFailures[model.id] = nil
        backupFailures[model.id] = nil
        restoreFailures[model.id] = nil
        deleteLocalFailures[model.id] = nil
        deleteBackupFailures[model.id] = nil
        objectWillChange.send()

        let backupCoordinator = self.backupCoordinator
        let existingRecord = backupRecords[model.id]

        DispatchQueue.global(qos: .userInitiated).async {
            let sourceAccess = model.folderURL.startAccessingSecurityScopedResource()
            let backupAccess = backupFolderURL.startAccessingSecurityScopedResource()

            defer {
                if sourceAccess {
                    model.folderURL.stopAccessingSecurityScopedResource()
                }
                if backupAccess {
                    backupFolderURL.stopAccessingSecurityScopedResource()
                }
            }

            let result = Result {
                try backupCoordinator.archive(
                    model: model,
                    to: backupFolderURL,
                    existingRecord: existingRecord
                )
            }

            Task { @MainActor in
                self.completeArchive(result, for: model.id)
            }
        }
    }

    func restore(model: DiscoveredModel) {
        guard backupDriveState == .online,
              let backupFolderURL,
              lifecycleStatus(for: model).canTriggerRestore,
              let record = backupRecords[model.id],
              let configuration = configuration(for: ModelProvider(rawValue: record.source) ?? .custom),
              let sourceFolderURL = configuration.folderURL
        else {
            return
        }

        activeRestoreIDs.insert(model.id)
        restoreFailures[model.id] = nil
        objectWillChange.send()

        let backupCoordinator = self.backupCoordinator

        DispatchQueue.global(qos: .userInitiated).async {
            let sourceAccess = sourceFolderURL.startAccessingSecurityScopedResource()
            let backupAccess = backupFolderURL.startAccessingSecurityScopedResource()

            defer {
                if sourceAccess {
                    sourceFolderURL.stopAccessingSecurityScopedResource()
                }
                if backupAccess {
                    backupFolderURL.stopAccessingSecurityScopedResource()
                }
            }

            let result = Result {
                try backupCoordinator.restore(
                    record: record,
                    from: backupFolderURL,
                    to: sourceFolderURL
                )
            }

            Task { @MainActor in
                self.completeRestore(result, for: model.id)
            }
        }
    }

    func deleteLocalCopy(model: DiscoveredModel) {
        guard backupDriveState == .online,
              let backupFolderURL,
              lifecycleStatus(for: model).canDeleteLocalCopy,
              let record = backupRecords[model.id]
        else {
            return
        }

        activeDeleteLocalIDs.insert(model.id)
        deleteLocalFailures[model.id] = nil
        objectWillChange.send()

        let backupCoordinator = self.backupCoordinator

        DispatchQueue.global(qos: .userInitiated).async {
            let sourceAccess = model.folderURL.startAccessingSecurityScopedResource()
            let backupAccess = backupFolderURL.startAccessingSecurityScopedResource()

            defer {
                if sourceAccess {
                    model.folderURL.stopAccessingSecurityScopedResource()
                }
                if backupAccess {
                    backupFolderURL.stopAccessingSecurityScopedResource()
                }
            }

            let result = Result {
                try backupCoordinator.deleteLocalCopy(
                    model: model,
                    to: backupFolderURL,
                    existingRecord: record
                )
            }

            Task { @MainActor in
                self.completeDeleteLocalCopy(result, for: model.id)
            }
        }
    }

    func deleteBackup(model: DiscoveredModel) {
        guard backupDriveState == .online,
              let backupFolderURL,
              lifecycleStatus(for: model).canDeleteBackup,
              let record = backupRecords[model.id]
        else {
            return
        }

        activeDeleteBackupIDs.insert(model.id)
        deleteBackupFailures[model.id] = nil
        objectWillChange.send()

        let backupCoordinator = self.backupCoordinator

        DispatchQueue.global(qos: .userInitiated).async {
            let backupAccess = backupFolderURL.startAccessingSecurityScopedResource()

            defer {
                if backupAccess {
                    backupFolderURL.stopAccessingSecurityScopedResource()
                }
            }

            let result = Result {
                try backupCoordinator.deleteBackup(record: record, from: backupFolderURL)
            }

            Task { @MainActor in
                self.completeDeleteBackup(result, for: model.id)
            }
        }
    }

    func revealLocalModel(_ model: DiscoveredModel) {
        NSWorkspace.shared.activateFileViewerSelecting([model.folderURL])
    }

    func revealBackup(for model: DiscoveredModel) {
        guard let backupFolderURL else {
            return
        }

        let backupRelativePath = backupRecords[model.id]?.backupRelativePath
            ?? backupDestinationConflicts[model.id]?.backupRelativePath
            ?? backupCoordinator.plannedBackupRelativePath(for: model)
        let backupURL = backupFolderURL.appendingPathComponent(backupRelativePath, isDirectory: true)
        withScopedAccess(to: backupFolderURL) {
            NSWorkspace.shared.activateFileViewerSelecting([backupURL])
        }
    }

    private func configuration(for provider: ModelProvider) -> ModelSourceConfiguration? {
        sourceConfigurations.first { $0.provider == provider }
    }

    private func updateSource(_ provider: ModelProvider, _ update: (inout ModelSourceConfiguration) -> Void) {
        guard let index = sourceConfigurations.firstIndex(where: { $0.provider == provider }) else { return }
        update(&sourceConfigurations[index])
    }

    private func loadBackupIndex() {
        do {
            backupRecords = try backupIndexStore.loadIndex()
            print("[AppModel] loaded backup index entries: \(backupRecords.count)")
        } catch {
            errorMessage = error.localizedDescription
            print("[AppModel] failed to load backup index: \(error.localizedDescription)")
        }
    }

    private func restoreBookmarks() {
        do {
            for provider in Self.supportedProviders {
                guard let key = provider.bookmarkKey else { continue }
                if let bookmark = try bookmarkStore.loadBookmark(for: key) {
                    updateSource(provider) { configuration in
                        configuration.folderURL = bookmark.url
                        configuration.bookmarkIsStale = bookmark.isStale
                    }
                    print("[AppModel] restored source bookmark provider=\(provider.displayName) path=\(bookmark.url.path) stale=\(bookmark.isStale)")
                } else {
                    print("[AppModel] no stored source bookmark provider=\(provider.displayName)")
                }
            }

            if let backupBookmark = try bookmarkStore.loadBookmark(for: .backupRoot) {
                backupFolderURL = backupBookmark.url
                backupBookmarkIsStale = backupBookmark.isStale
                print("[AppModel] restored backup bookmark: \(backupBookmark.url.path) stale=\(backupBookmark.isStale)")
            } else {
                print("[AppModel] no stored backup bookmark")
            }
        } catch {
            errorMessage = error.localizedDescription
            print("[AppModel] bookmark restore failed: \(error.localizedDescription)")
        }
    }

    private func autoDetectSourceFolders() {
        let detectedSources = modelSourceLocator.detectSources()
        guard !detectedSources.isEmpty else {
            print("[AppModel] no model sources auto-detected")
            return
        }

        for detectedSource in detectedSources {
            guard detectedSource.provider.isEnabled else { continue }

            guard configuration(for: detectedSource.provider)?.folderURL == nil else {
                print("[AppModel] source auto-detect skipped provider=\(detectedSource.provider.displayName) because it is already configured")
                continue
            }

            print("[AppModel] auto-detected source provider=\(detectedSource.provider.displayName) path=\(detectedSource.folderURL.path)")
            saveSourceSelection(detectedSource.folderURL, for: detectedSource.provider, refreshAfterSave: false)
        }
    }

    private func saveSourceSelection(_ url: URL, for provider: ModelProvider, refreshAfterSave: Bool = true) {
        guard provider.isEnabled else { return }
        guard let key = provider.bookmarkKey else { return }

        do {
            try bookmarkStore.saveBookmark(for: url, as: key)
            print("[AppModel] saved source bookmark provider=\(provider.displayName) path=\(url.path)")
            updateSource(provider) { configuration in
                configuration.folderURL = url
                configuration.bookmarkIsStale = false
                configuration.models = []
                configuration.discoveryState = .idle
            }
            if refreshAfterSave {
                refreshStatuses()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveBackupSelection(_ url: URL) {
        do {
            try bookmarkStore.saveBookmark(for: url, as: .backupRoot)
            try ensureBackupRootMarker(in: url)
            backupFolderURL = url
            backupBookmarkIsStale = false
            print("[AppModel] saved backup bookmark: \(url.path)")
            refreshStatuses()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func completeBackup(_ result: Result<BackupRecord, Error>, for modelID: String) {
        activeBackupIDs.remove(modelID)
        objectWillChange.send()

        switch result {
        case let .success(record):
            backupRecords[modelID] = record
            backupFailures[modelID] = nil
            do {
                try backupIndexStore.saveIndex(backupRecords)
            } catch {
                errorMessage = error.localizedDescription
            }
        case let .failure(error):
            backupFailures[modelID] = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func completeArchive(_ result: Result<BackupRecord, Error>, for modelID: String) {
        activeArchiveIDs.remove(modelID)
        objectWillChange.send()

        switch result {
        case let .success(record):
            backupRecords[modelID] = record
            backupFailures[modelID] = nil
            archiveFailures[modelID] = nil
            do {
                try backupIndexStore.saveIndex(backupRecords)
                refreshModelDiscovery()
            } catch {
                errorMessage = error.localizedDescription
            }
        case let .failure(error):
            archiveFailures[modelID] = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func completeRestore(_ result: Result<BackupRecord, Error>, for modelID: String) {
        activeRestoreIDs.remove(modelID)
        objectWillChange.send()

        switch result {
        case let .success(record):
            backupRecords[modelID] = record
            restoreFailures[modelID] = nil
            do {
                try backupIndexStore.saveIndex(backupRecords)
                refreshModelDiscovery()
            } catch {
                errorMessage = error.localizedDescription
            }
        case let .failure(error):
            restoreFailures[modelID] = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func completeDeleteLocalCopy(_ result: Result<BackupRecord, Error>, for modelID: String) {
        activeDeleteLocalIDs.remove(modelID)
        objectWillChange.send()

        switch result {
        case let .success(record):
            backupRecords[modelID] = record
            deleteLocalFailures[modelID] = nil
            do {
                try backupIndexStore.saveIndex(backupRecords)
                refreshModelDiscovery()
            } catch {
                errorMessage = error.localizedDescription
            }
        case let .failure(error):
            deleteLocalFailures[modelID] = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func completeDeleteBackup(_ result: Result<Void, Error>, for modelID: String) {
        activeDeleteBackupIDs.remove(modelID)
        objectWillChange.send()

        switch result {
        case .success:
            backupRecords[modelID] = nil
            backupFailures[modelID] = nil
            archiveFailures[modelID] = nil
            restoreFailures[modelID] = nil
            deleteLocalFailures[modelID] = nil
            deleteBackupFailures[modelID] = nil
            do {
                try backupIndexStore.saveIndex(backupRecords)
                refreshModelDiscovery()
            } catch {
                errorMessage = error.localizedDescription
            }
        case let .failure(error):
            deleteBackupFailures[modelID] = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    private func evaluateSourceFolder(url: URL?, isStale: Bool, provider: ModelProvider) -> SourceAccessState {
        guard provider.isEnabled else {
            print("[AppModel] source disabled provider=\(provider.displayName)")
            return .notConfigured
        }

        guard let url else {
            print("[AppModel] source not configured provider=\(provider.displayName)")
            return .notConfigured
        }

        if isStale {
            print("[AppModel] source bookmark stale provider=\(provider.displayName) path=\(url.path)")
            return .staleBookmark
        }

        return withScopedAccess(to: url) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                print("[AppModel] source folder inaccessible or missing provider=\(provider.displayName) path=\(url.path)")
                return .inaccessible
            }

            do {
                _ = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                print("[AppModel] source folder ready provider=\(provider.displayName) path=\(url.path)")
                return .ready
            } catch {
                print("[AppModel] source contents read failed provider=\(provider.displayName) path=\(url.path) error=\(error.localizedDescription)")
                return .inaccessible
            }
        }
    }

    private func evaluateBackupFolder(url: URL?, isStale: Bool) -> BackupDriveState {
        guard let url else {
            print("[AppModel] backup root not configured")
            return .notConfigured
        }

        if isStale {
            print("[AppModel] backup bookmark stale: \(url.path)")
            return .staleBookmark
        }

        return withScopedAccess(to: url) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                lastBackupValidationFailure = "The selected backup folder no longer exists."
                print("[AppModel] backup root offline: \(url.path)")
                return .offline
            }

            do {
                let values = try url.resourceValues(forKeys: [.volumeIsReadOnlyKey, .isWritableKey])
                print("[AppModel] backup resource values path=\(url.path) volumeIsReadOnly=\(String(describing: values.volumeIsReadOnly)) isWritable=\(String(describing: values.isWritable))")
                if values.volumeIsReadOnly == true {
                    lastBackupValidationFailure = "The selected volume is mounted read only."
                    print("[AppModel] backup root read only due to volume flag")
                    return .readOnly
                }

                if values.isWritable != true {
                    guard try canWriteProbeFile(in: url) else {
                        lastBackupValidationFailure = "The app could not write inside the selected backup folder."
                        print("[AppModel] backup root permission denied after write probe failed")
                        return .permissionDenied
                    }
                }

                try ensureBackupRootMarker(in: url)
            } catch let error as NSError {
                lastBackupValidationFailure = error.localizedDescription
                print("[AppModel] backup validation threw error: \(error.localizedDescription)")
                return .permissionDenied
            }

            lastBackupValidationFailure = nil
            print("[AppModel] backup root online")
            return .online
        }
    }

    private func ensureBackupRootMarker(in directoryURL: URL) throws {
        let markerURL = directoryURL.appendingPathComponent(".moderubakappu-backup.json", isDirectory: false)
        if fileManager.fileExists(atPath: markerURL.path) {
            let data = try Data(contentsOf: markerURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let marker = try decoder.decode(BackupRootMarker.self, from: data)
            rememberSelectedBackupRootID(marker.backupRootID)
            print("[AppModel] backup marker present: \(markerURL.path) id=\(marker.backupRootID.uuidString)")
            return
        }

        let marker = BackupRootMarker(
            schemaVersion: 1,
            backupRootID: UUID(),
            appName: "ModeruBakappu",
            createdAt: .now
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(marker)
        try data.write(to: markerURL, options: .atomic)
        rememberSelectedBackupRootID(marker.backupRootID)
        print("[AppModel] created backup marker: \(markerURL.path) id=\(marker.backupRootID.uuidString)")
    }

    private func rememberSelectedBackupRootID(_ backupRootID: UUID) {
        UserDefaults.standard.set(backupRootID.uuidString, forKey: backupRootIDDefaultsKey)
    }

    private func canWriteProbeFile(in directoryURL: URL) throws -> Bool {
        let probeURL = directoryURL.appendingPathComponent(
            "moderubakappu-write-probe-\(UUID().uuidString).tmp",
            isDirectory: false
        )

        let created = fileManager.createFile(
            atPath: probeURL.path,
            contents: Data("probe".utf8),
            attributes: nil
        )

        guard created else {
            print("[AppModel] write probe failed to create file: \(probeURL.path)")
            return false
        }

        do {
            try fileManager.removeItem(at: probeURL)
            print("[AppModel] write probe succeeded: \(probeURL.path)")
            return true
        } catch {
            print("[AppModel] write probe cleanup failed: \(probeURL.path) error=\(error.localizedDescription)")
            return false
        }
    }

    private func readBackupDriveSpace(url: URL?) -> BackupDriveSpaceInfo? {
        guard let url else { return nil }

        return withScopedAccess(to: url) {
            readDriveSpace(at: url, logContext: "backup drive")
        }
    }

    private func readMainDriveSpace() -> BackupDriveSpaceInfo? {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        return readDriveSpace(at: homeURL, logContext: "main drive")
    }

    private func readDriveSpace(at url: URL, logContext: String) -> BackupDriveSpaceInfo? {
        do {
            let values = try url.resourceValues(forKeys: [.volumeNameKey])
            let attributes = try fileManager.attributesOfFileSystem(forPath: url.path)

            guard let freeSize = attributes[.systemFreeSize] as? NSNumber,
                  let totalSize = attributes[.systemSize] as? NSNumber,
                  freeSize.int64Value >= 0,
                  totalSize.int64Value > 0
            else {
                return nil
            }

            return BackupDriveSpaceInfo(
                volumeName: values.volumeName,
                volumePath: url.path,
                availableBytes: freeSize.int64Value,
                totalBytes: totalSize.int64Value
            )
        } catch {
            print("[AppModel] failed to read \(logContext) space: \(error.localizedDescription)")
            return nil
        }
    }

    private func withScopedAccess<T>(to url: URL, perform: () -> T) -> T {
        let started = url.startAccessingSecurityScopedResource()
        print("[AppModel] startAccessingSecurityScopedResource path=\(url.path) started=\(started)")
        defer {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return perform()
    }
}
