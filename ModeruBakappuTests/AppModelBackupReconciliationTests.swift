//
//  AppModelBackupReconciliationTests.swift
//  ModeruBakappuTests
//
//  Created by Codex on 2026/4/29.
//

import XCTest
@testable import ModeruBakappu

@MainActor
final class AppModelBackupReconciliationTests: XCTestCase {
    private var temporaryRoot: URL!
    private var sourceRoot: URL!
    private var backupRoot: URL!
    private var fileManager: FileManager!
    private var indexStore: MemoryBackupIndexStore!

    override func setUpWithError() throws {
        fileManager = FileManager()
        temporaryRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("ModeruBakappuAppModelTests-\(UUID().uuidString)", isDirectory: true)
        sourceRoot = temporaryRoot.appendingPathComponent("Sources", isDirectory: true)
        backupRoot = temporaryRoot.appendingPathComponent("BackupRoot", isDirectory: true)
        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        indexStore = MemoryBackupIndexStore()
    }

    override func tearDownWithError() throws {
        if let temporaryRoot, fileManager.fileExists(atPath: temporaryRoot.path) {
            try fileManager.removeItem(at: temporaryRoot)
        }
        indexStore = nil
        fileManager = nil
        temporaryRoot = nil
        sourceRoot = nil
        backupRoot = nil
    }

    func testLoadRepairsMissingBackupRecordWhenDestinationMatchesLocalModel() throws {
        try writeFile("publisher/model-a/weights.bin", contents: "same payload", under: sourceRoot)
        try writeFile("lm-studio/publisher/model-a/weights.bin", contents: "same payload", under: backupRoot)

        let appModel = makeAppModel()

        appModel.loadIfNeeded()

        let model = try XCTUnwrap(appModel.sourceConfigurations.first { $0.provider == .lmStudio }?.models.first)
        let record = try XCTUnwrap(appModel.backupRecords[model.id])
        XCTAssertEqual(record.backupRelativePath, "lm-studio/publisher/model-a")
        XCTAssertEqual(indexStore.savedIndex[model.id], record)

        let lifecycle = appModel.lifecycleStatus(for: model)
        guard case .backedUp = lifecycle.state else {
            return XCTFail("Expected backedUp lifecycle, got \(lifecycle.state)")
        }
    }

    func testLoadReportsBackupConflictWhenDestinationDoesNotMatchLocalModel() throws {
        try writeFile("publisher/model-b/weights.bin", contents: "local payload", under: sourceRoot)
        try writeFile("lm-studio/publisher/model-b/weights.bin", contents: "different backup payload", under: backupRoot)

        let appModel = makeAppModel()

        appModel.loadIfNeeded()

        let model = try XCTUnwrap(appModel.sourceConfigurations.first { $0.provider == .lmStudio }?.models.first)
        XCTAssertNil(appModel.backupRecords[model.id])

        let lifecycle = appModel.lifecycleStatus(for: model)
        guard case let .backupConflict(conflict) = lifecycle.state else {
            return XCTFail("Expected backupConflict lifecycle, got \(lifecycle.state)")
        }
        XCTAssertEqual(conflict.backupRelativePath, "lm-studio/publisher/model-b")
        XCTAssertFalse(lifecycle.backupState.canTriggerBackup)
    }

    private func makeAppModel() -> AppModel {
        let bookmarkStore = FixedBookmarkStore(sourceRoot: sourceRoot, backupRoot: backupRoot)
        let locator = ModelSourceLocator(adapters: [
            DirectoryModelProviderAdapter(
                provider: .lmStudio,
                candidates: [],
                pathMatchers: [],
                fileManager: fileManager
            )
        ])

        return AppModel(
            bookmarkStore: bookmarkStore,
            backupIndexStore: indexStore,
            folderPicker: NoopFolderPicker(),
            modelSourceLocator: locator,
            backupCoordinator: BackupCoordinator(fileManager: fileManager),
            fileManager: fileManager
        )
    }

    private func writeFile(_ path: String, contents: String, under root: URL) throws {
        let fileURL = root.appendingPathComponent(path, isDirectory: false)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.data(using: .utf8)?.write(to: fileURL)
    }
}

private final class FixedBookmarkStore: BookmarkStore {
    let sourceRoot: URL
    let backupRoot: URL

    init(sourceRoot: URL, backupRoot: URL) {
        self.sourceRoot = sourceRoot
        self.backupRoot = backupRoot
    }

    func saveBookmark(for url: URL, as key: BookmarkKey) throws {}

    func loadBookmark(for key: BookmarkKey) throws -> ResolvedBookmark? {
        switch key {
        case .lmStudioModels:
            return ResolvedBookmark(url: sourceRoot, isStale: false)
        case .backupRoot:
            return ResolvedBookmark(url: backupRoot, isStale: false)
        case .omlxModels, .ollamaModels:
            return nil
        }
    }

    func removeBookmark(for key: BookmarkKey) {}
}

private final class MemoryBackupIndexStore: BackupIndexStore {
    var savedIndex: [String: BackupRecord] = [:]

    func loadIndex() throws -> [String: BackupRecord] {
        savedIndex
    }

    func saveIndex(_ index: [String: BackupRecord]) throws {
        savedIndex = index
    }
}

private struct NoopFolderPicker: FolderPicker {
    func pickFolder(title: String, message: String, prompt: String, startingAt: URL?) -> URL? {
        nil
    }
}
