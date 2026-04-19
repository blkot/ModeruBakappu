//
//  AppModel.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var hasLoaded = false
    @Published private(set) var sourceProvider: ModelProvider = .lmStudio
    @Published private(set) var lmStudioFolderURL: URL?
    @Published private(set) var backupFolderURL: URL?
    @Published private(set) var lmStudioAccessState: SourceAccessState = .notConfigured
    @Published private(set) var backupDriveState: BackupDriveState = .notConfigured
    @Published private(set) var lmStudioDiscoveryState: LMStudioDiscoveryState = .idle
    @Published private(set) var lmStudioModels: [DiscoveredModel] = []
    @Published private(set) var backupRecords: [String: BackupRecord] = [:]
    @Published var errorMessage: String?

    private let bookmarkStore: BookmarkStore
    private let backupIndexStore: BackupIndexStore
    private let folderPicker: FolderPicker
    private let modelSourceLocator: ModelSourceLocator
    private let lmStudioDiscoveryService: LMStudioDiscoveryService
    private let backupCoordinator: BackupCoordinator
    private let fileManager: FileManager

    private var lmStudioBookmarkIsStale = false
    private var backupBookmarkIsStale = false
    private var activeBackupIDs: Set<String> = []
    private var backupFailures: [String: String] = [:]
    private var lastBackupValidationFailure: String?

    convenience init() {
        self.init(
            bookmarkStore: UserDefaultsBookmarkStore(),
            backupIndexStore: JSONBackupIndexStore(),
            folderPicker: OpenPanelFolderPicker(),
            modelSourceLocator: ModelSourceLocator(),
            lmStudioDiscoveryService: LMStudioDiscoveryService(),
            backupCoordinator: BackupCoordinator(),
            fileManager: .default
        )
    }

    init(
        bookmarkStore: BookmarkStore,
        backupIndexStore: BackupIndexStore,
        folderPicker: FolderPicker,
        modelSourceLocator: ModelSourceLocator,
        lmStudioDiscoveryService: LMStudioDiscoveryService,
        backupCoordinator: BackupCoordinator,
        fileManager: FileManager
    ) {
        self.bookmarkStore = bookmarkStore
        self.backupIndexStore = backupIndexStore
        self.folderPicker = folderPicker
        self.modelSourceLocator = modelSourceLocator
        self.lmStudioDiscoveryService = lmStudioDiscoveryService
        self.backupCoordinator = backupCoordinator
        self.fileManager = fileManager
    }

    var hasMinimumConfiguration: Bool {
        lmStudioFolderURL != nil && backupFolderURL != nil
    }

    var sourceDisplayName: String {
        sourceProvider.displayName
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }

        print("[AppModel] loadIfNeeded")
        loadBackupIndex()
        restoreBookmarks()
        autoDetectLMStudioFolderIfNeeded()
        refreshStatuses()
        hasLoaded = true
    }

    func selectLMStudioFolder() {
        let picked = folderPicker.pickFolder(
            title: "Choose Models Folder",
            message: "Choose the models folder for the detected provider, or override it with a custom source.",
            prompt: "Use Folder",
            startingAt: lmStudioFolderURL
        )

        guard let picked else { return }
        sourceProvider = modelSourceLocator.inferProvider(for: picked)
        print("[AppModel] selected source folder provider=\(sourceProvider.displayName) path=\(picked.path)")
        saveSelection(picked, for: .lmStudioModels)
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
        saveSelection(picked, for: .backupRoot)
    }

    func refreshStatuses() {
        print("[AppModel] refreshStatuses")
        lmStudioAccessState = evaluateSourceFolder(url: lmStudioFolderURL, isStale: lmStudioBookmarkIsStale)
        backupDriveState = evaluateBackupFolder(url: backupFolderURL, isStale: backupBookmarkIsStale)
        refreshModelDiscovery()
        print("[AppModel] sourceState=\(lmStudioAccessState.title) backupState=\(backupDriveState.title)")
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

    func refreshModelDiscovery() {
        guard lmStudioAccessState == .ready, let lmStudioFolderURL else {
            lmStudioModels = []
            lmStudioDiscoveryState = .unavailable
            return
        }

        lmStudioDiscoveryState = .scanning

        let result: Result<[DiscoveredModel], Error> = withScopedAccess(to: lmStudioFolderURL) {
            Result { try lmStudioDiscoveryService.discoverModels(in: lmStudioFolderURL, source: sourceProvider) }
        }

        switch result {
        case let .success(models):
            lmStudioModels = models
            lmStudioDiscoveryState = models.isEmpty ? .empty : .ready(count: models.count)
        case let .failure(error):
            lmStudioModels = []
            lmStudioDiscoveryState = .failed(error.localizedDescription)
        }
    }

    var canAttemptBackup: Bool {
        backupDriveState == .online && !lmStudioModels.isEmpty
    }

    var backupDriveSummary: String {
        lastBackupValidationFailure ?? backupDriveState.summary
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
            if let lmStudioBookmark = try bookmarkStore.loadBookmark(for: .lmStudioModels) {
                lmStudioFolderURL = lmStudioBookmark.url
                sourceProvider = modelSourceLocator.inferProvider(for: lmStudioBookmark.url)
                lmStudioBookmarkIsStale = lmStudioBookmark.isStale
                print("[AppModel] restored source bookmark provider=\(sourceProvider.displayName) path=\(lmStudioBookmark.url.path) stale=\(lmStudioBookmark.isStale)")
            } else {
                print("[AppModel] no stored source bookmark")
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

    private func autoDetectLMStudioFolderIfNeeded() {
        guard lmStudioFolderURL == nil else { return }

        guard let detectedSource = modelSourceLocator.detectPreferredSource() else {
            print("[AppModel] no model source auto-detected")
            return
        }

        sourceProvider = detectedSource.provider
        print("[AppModel] auto-detected source provider=\(detectedSource.provider.displayName) path=\(detectedSource.folderURL.path)")
        saveSelection(detectedSource.folderURL, for: .lmStudioModels)
    }

    private func saveSelection(_ url: URL, for key: BookmarkKey) {
        do {
            try bookmarkStore.saveBookmark(for: url, as: key)
            print("[AppModel] saved bookmark for \(key.rawValue): \(url.path)")
            switch key {
            case .lmStudioModels:
                lmStudioFolderURL = url
                lmStudioBookmarkIsStale = false
                lmStudioModels = []
                lmStudioDiscoveryState = .idle
            case .backupRoot:
                backupFolderURL = url
                backupBookmarkIsStale = false
            }
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

    private func evaluateSourceFolder(url: URL?, isStale: Bool) -> SourceAccessState {
        guard let url else {
            print("[AppModel] LM Studio source not configured")
            return .notConfigured
        }

        if isStale {
            print("[AppModel] LM Studio bookmark stale: \(url.path)")
            return .staleBookmark
        }

        return withScopedAccess(to: url) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                print("[AppModel] LM Studio folder inaccessible or missing: \(url.path)")
                return .inaccessible
            }

            do {
                _ = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                print("[AppModel] LM Studio folder ready: \(url.path)")
                return .ready
            } catch {
                print("[AppModel] LM Studio contents read failed: \(url.path) error=\(error.localizedDescription)")
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

                if values.isWritable == true {
                    lastBackupValidationFailure = nil
                    print("[AppModel] backup root online via writable resource value")
                    return .online
                }

                guard try canWriteProbeFile(in: url) else {
                    lastBackupValidationFailure = "The app could not write inside the selected backup folder."
                    print("[AppModel] backup root read only after write probe failed")
                    return .permissionDenied
                }
            } catch let error as NSError {
                lastBackupValidationFailure = error.localizedDescription
                print("[AppModel] backup validation threw error: \(error.localizedDescription)")
                return .permissionDenied
            }

            lastBackupValidationFailure = nil
            print("[AppModel] backup root online after write probe succeeded")
            return .online
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
