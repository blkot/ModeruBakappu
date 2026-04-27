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

    private let bookmarkStore: BookmarkStore
    private let backupIndexStore: BackupIndexStore
    private let folderPicker: FolderPicker
    private let modelSourceLocator: ModelSourceLocator
    private let modelDiscoveryService: LMStudioDiscoveryService
    private let backupCoordinator: BackupCoordinator
    private let fileManager: FileManager

    private var backupBookmarkIsStale = false
    private var activeBackupIDs: Set<String> = []
    private var backupFailures: [String: String] = [:]
    private var lastBackupValidationFailure: String?
    private let backupRootIDDefaultsKey = "ModeruBakappu.backupRootID"

    private static let supportedProviders: [ModelProvider] = [.lmStudio, .omlx]

    convenience init() {
        self.init(
            bookmarkStore: UserDefaultsBookmarkStore(),
            backupIndexStore: JSONBackupIndexStore(),
            folderPicker: OpenPanelFolderPicker(),
            modelSourceLocator: ModelSourceLocator(),
            modelDiscoveryService: LMStudioDiscoveryService(),
            backupCoordinator: BackupCoordinator(),
            fileManager: .default
        )
    }

    init(
        bookmarkStore: BookmarkStore,
        backupIndexStore: BackupIndexStore,
        folderPicker: FolderPicker,
        modelSourceLocator: ModelSourceLocator,
        modelDiscoveryService: LMStudioDiscoveryService,
        backupCoordinator: BackupCoordinator,
        fileManager: FileManager
    ) {
        self.bookmarkStore = bookmarkStore
        self.backupIndexStore = backupIndexStore
        self.folderPicker = folderPicker
        self.modelSourceLocator = modelSourceLocator
        self.modelDiscoveryService = modelDiscoveryService
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
            guard configuration.accessState == .ready, let folderURL = configuration.folderURL else {
                sourceConfigurations[index].models = []
                sourceConfigurations[index].discoveryState = .unavailable
                continue
            }

            sourceConfigurations[index].discoveryState = .scanning

            let result: Result<[DiscoveredModel], Error> = withScopedAccess(to: folderURL) {
                Result {
                    try modelDiscoveryService.discoverModels(in: folderURL, source: configuration.provider)
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
    }

    func clearError() {
        errorMessage = nil
    }

    func backupState(for model: DiscoveredModel) -> ModelBackupState {
        if let message = backupFailures[model.id] {
            return .failed(message)
        }

        if activeBackupIDs.contains(model.id) {
            return .inProgress
        }

        if let record = backupRecords[model.id] {
            return .backedUp(record)
        }

        guard backupDriveState == .online else {
            return .unavailable
        }

        return .ready
    }

    func lifecycleStatus(for model: DiscoveredModel) -> ModelLifecycleStatus {
        let backupState = backupState(for: model)
        let lifecycleState: ModelLifecycleState

        switch backupState {
        case .ready:
            lifecycleState = .localOnly
        case .unavailable:
            lifecycleState = .backupUnavailable
        case .inProgress:
            lifecycleState = .backingUp
        case let .backedUp(record):
            lifecycleState = .backedUp(record)
        case let .failed(message):
            lifecycleState = .backupFailed(message)
        }

        return ModelLifecycleStatus(
            state: lifecycleState,
            providerReadiness: .ready,
            backupState: backupState
        )
    }

    func backup(model: DiscoveredModel) {
        guard backupState(for: model).canTriggerBackup, let backupFolderURL else {
            return
        }

        activeBackupIDs.insert(model.id)
        backupFailures[model.id] = nil

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

    func revealLocalModel(_ model: DiscoveredModel) {
        NSWorkspace.shared.activateFileViewerSelecting([model.folderURL])
    }

    func revealBackup(for model: DiscoveredModel) {
        guard let backupFolderURL,
              let record = backupRecords[model.id]
        else {
            return
        }

        let backupURL = backupFolderURL.appendingPathComponent(record.backupRelativePath, isDirectory: true)
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
            guard configuration(for: detectedSource.provider)?.folderURL == nil else {
                print("[AppModel] source auto-detect skipped provider=\(detectedSource.provider.displayName) because it is already configured")
                continue
            }

            print("[AppModel] auto-detected source provider=\(detectedSource.provider.displayName) path=\(detectedSource.folderURL.path)")
            saveSourceSelection(detectedSource.folderURL, for: detectedSource.provider, refreshAfterSave: false)
        }
    }

    private func saveSourceSelection(_ url: URL, for provider: ModelProvider, refreshAfterSave: Bool = true) {
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

    private func evaluateSourceFolder(url: URL?, isStale: Bool, provider: ModelProvider) -> SourceAccessState {
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
            try validateBackupRootID(marker.backupRootID)
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
        UserDefaults.standard.set(marker.backupRootID.uuidString, forKey: backupRootIDDefaultsKey)
        print("[AppModel] created backup marker: \(markerURL.path) id=\(marker.backupRootID.uuidString)")
    }

    private func validateBackupRootID(_ backupRootID: UUID) throws {
        let defaults = UserDefaults.standard
        guard let storedID = defaults.string(forKey: backupRootIDDefaultsKey) else {
            defaults.set(backupRootID.uuidString, forKey: backupRootIDDefaultsKey)
            return
        }

        guard storedID == backupRootID.uuidString else {
            throw NSError(
                domain: "ModeruBakappu.BackupRoot",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "The selected folder belongs to a different ModeruBakappu backup root."
                ]
            )
        }
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
