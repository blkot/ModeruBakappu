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
    @Published private(set) var suggestedLMStudioFolderURL: URL?
    @Published var errorMessage: String?

    private let bookmarkStore: BookmarkStore
    private let folderPicker: FolderPicker
    private let lmStudioSettingsService: LMStudioSettingsService
    private let fileManager: FileManager

    private var lmStudioBookmarkIsStale = false
    private var backupBookmarkIsStale = false

    convenience init() {
        self.init(
            bookmarkStore: UserDefaultsBookmarkStore(),
            folderPicker: OpenPanelFolderPicker(),
            lmStudioSettingsService: LMStudioSettingsService(),
            fileManager: .default
        )
    }

    init(
        bookmarkStore: BookmarkStore,
        folderPicker: FolderPicker,
        lmStudioSettingsService: LMStudioSettingsService,
        fileManager: FileManager
    ) {
        self.bookmarkStore = bookmarkStore
        self.folderPicker = folderPicker
        self.lmStudioSettingsService = lmStudioSettingsService
        self.fileManager = fileManager
    }

    var hasMinimumConfiguration: Bool {
        lmStudioFolderURL != nil && backupFolderURL != nil
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }

        suggestedLMStudioFolderURL = lmStudioSettingsService.suggestedModelsFolder()
        restoreBookmarks()
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
    }

    func clearError() {
        errorMessage = nil
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
            case .backupRoot:
                backupFolderURL = url
                backupBookmarkIsStale = false
            }
            refreshStatuses()
        } catch {
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
                return .offline
            }

            guard fileManager.isWritableFile(atPath: url.path) else {
                return .readOnly
            }

            return .online
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
