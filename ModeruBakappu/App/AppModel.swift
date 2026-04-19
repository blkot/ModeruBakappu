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
    @Published private(set) var lmStudioFolderURL: URL?
    @Published private(set) var backupFolderURL: URL?
    @Published private(set) var lmStudioAccessState: SourceAccessState = .notConfigured
    @Published private(set) var backupDriveState: BackupDriveState = .notConfigured
    @Published private(set) var lmStudioDiscoveryState: LMStudioDiscoveryState = .idle
    @Published private(set) var lmStudioModels: [DiscoveredModel] = []
    @Published private(set) var backupRecords: [String: BackupRecord] = [:]
    @Published private(set) var suggestedLMStudioFolderURL: URL?
    @Published var errorMessage: String?

    private let bookmarkStore: BookmarkStore
    private let backupIndexStore: BackupIndexStore
    private let folderPicker: FolderPicker
    private let lmStudioSettingsService: LMStudioSettingsService
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
            lmStudioSettingsService: LMStudioSettingsService(),
            lmStudioDiscoveryService: LMStudioDiscoveryService(),
            backupCoordinator: BackupCoordinator(),
            fileManager: .default
        )
    }

    init(
        bookmarkStore: BookmarkStore,
        backupIndexStore: BackupIndexStore,
        folderPicker: FolderPicker,
        lmStudioSettingsService: LMStudioSettingsService,
        lmStudioDiscoveryService: LMStudioDiscoveryService,
        backupCoordinator: BackupCoordinator,
        fileManager: FileManager
    ) {
        self.bookmarkStore = bookmarkStore
        self.backupIndexStore = backupIndexStore
        self.folderPicker = folderPicker
        self.lmStudioSettingsService = lmStudioSettingsService
        self.lmStudioDiscoveryService = lmStudioDiscoveryService
        self.backupCoordinator = backupCoordinator
        self.fileManager = fileManager
    }

    var hasMinimumConfiguration: Bool {
        lmStudioFolderURL != nil && backupFolderURL != nil
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }

        suggestedLMStudioFolderURL = lmStudioSettingsService.suggestedModelsFolder()
        loadBackupIndex()
        restoreBookmarks()
        adoptSuggestedLMStudioFolderIfNeeded()
        refreshStatuses()
        hasLoaded = true
    }

    func selectLMStudioFolder() {
        let picked = folderPicker.pickFolder(
            title: "Choose LM Studio Models Folder",
            message: "Select the folder that LM Studio uses to store downloaded models.",
            prompt: "Use Folder",
            startingAt: lmStudioFolderURL ?? suggestedLMStudioFolderURL
        )

        guard let picked else { return }
        saveSelection(picked, for: .lmStudioModels)
    }

    func useSuggestedLMStudioFolder() {
        guard let suggestedLMStudioFolderURL else { return }
        saveSelection(suggestedLMStudioFolderURL, for: .lmStudioModels)
    }

    func selectBackupFolder() {
        let picked = folderPicker.pickFolder(
            title: "Choose Backup Root",
            message: "Select the root folder on your external drive where backups should be stored.",
            prompt: "Use Backup Root",
            startingAt: backupFolderURL
        )

        guard let picked else { return }
        saveSelection(picked, for: .backupRoot)
    }

    func refreshStatuses() {
        lmStudioAccessState = evaluateSourceFolder(url: lmStudioFolderURL, isStale: lmStudioBookmarkIsStale)
        backupDriveState = evaluateBackupFolder(url: backupFolderURL, isStale: backupBookmarkIsStale)
        refreshModelDiscovery()
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
            Result { try lmStudioDiscoveryService.discoverModels(in: lmStudioFolderURL) }
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

    private func loadBackupIndex() {
        do {
            backupRecords = try backupIndexStore.loadIndex()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func adoptSuggestedLMStudioFolderIfNeeded() {
        guard lmStudioFolderURL == nil, let suggestedLMStudioFolderURL else {
            return
        }

        lmStudioFolderURL = suggestedLMStudioFolderURL
        lmStudioBookmarkIsStale = false
    }

    private func restoreBookmarks() {
        do {
            if let lmStudioBookmark = try bookmarkStore.loadBookmark(for: .lmStudioModels) {
                lmStudioFolderURL = lmStudioBookmark.url
                lmStudioBookmarkIsStale = lmStudioBookmark.isStale
            }

            if let backupBookmark = try bookmarkStore.loadBookmark(for: .backupRoot) {
                backupFolderURL = backupBookmark.url
                backupBookmarkIsStale = backupBookmark.isStale
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveSelection(_ url: URL, for key: BookmarkKey) {
        do {
            try bookmarkStore.saveBookmark(for: url, as: key)
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
            return .notConfigured
        }

        if isStale {
            return .staleBookmark
        }

        return withScopedAccess(to: url) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                return .inaccessible
            }

            do {
                _ = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                return .ready
            } catch {
                return .inaccessible
            }
        }
    }

    private func evaluateBackupFolder(url: URL?, isStale: Bool) -> BackupDriveState {
        guard let url else {
            return .notConfigured
        }

        if isStale {
            return .staleBookmark
        }

        return withScopedAccess(to: url) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                lastBackupValidationFailure = "The selected backup folder no longer exists."
                return .offline
            }

            do {
                let values = try url.resourceValues(forKeys: [.volumeIsReadOnlyKey, .isWritableKey])
                if values.volumeIsReadOnly == true {
                    lastBackupValidationFailure = "The selected volume is mounted read only."
                    return .readOnly
                }

                if values.isWritable == true {
                    lastBackupValidationFailure = nil
                    return .online
                }

                guard try canWriteProbeFile(in: url) else {
                    lastBackupValidationFailure = "The app could not write inside the selected backup folder."
                    return .readOnly
                }
            } catch let error as NSError {
                lastBackupValidationFailure = error.localizedDescription
                return .readOnly
            }

            lastBackupValidationFailure = nil
            return .online
        }
    }

    private func canWriteProbeFile(in directoryURL: URL) throws -> Bool {
        let probeURL = directoryURL.appendingPathComponent(
            ".moderubakappu-write-probe-\(UUID().uuidString).tmp",
            isDirectory: false
        )

        do {
            try Data("probe".utf8).write(to: probeURL, options: .atomic)
            try fileManager.removeItem(at: probeURL)
            return true
        } catch {
            return false
        }
    }

    private func withScopedAccess<T>(to url: URL, perform: () -> T) -> T {
        let started = url.startAccessingSecurityScopedResource()
        defer {
            if started {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return perform()
    }
}
