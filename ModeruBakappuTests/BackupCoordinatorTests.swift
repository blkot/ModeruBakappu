//
//  BackupCoordinatorTests.swift
//  ModeruBakappuTests
//
//  Created by Codex on 2026/4/29.
//

import XCTest
@testable import ModeruBakappu

final class BackupCoordinatorTests: XCTestCase {
    private var temporaryRoot: URL!
    private var sourceRoot: URL!
    private var backupRoot: URL!
    private var fileManager: FileManager!
    private var coordinator: BackupCoordinator!

    override func setUpWithError() throws {
        fileManager = FileManager()
        temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ModeruBakappuTests-\(UUID().uuidString)", isDirectory: true)
        sourceRoot = temporaryRoot.appendingPathComponent("Sources", isDirectory: true)
        backupRoot = temporaryRoot.appendingPathComponent("BackupRoot", isDirectory: true)
        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        coordinator = BackupCoordinator(fileManager: fileManager)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot, fileManager.fileExists(atPath: temporaryRoot.path) {
            try fileManager.removeItem(at: temporaryRoot)
        }
        coordinator = nil
        fileManager = nil
        temporaryRoot = nil
        sourceRoot = nil
        backupRoot = nil
    }

    func testBackupCreatesVerifiedProviderNamespacedRecord() throws {
        let model = try makeModel(relativePath: "publisher/model-a", files: [
            "config.json": "{}",
            "weights/model.safetensors": "123456789"
        ])

        let record = try coordinator.backup(model: model, to: backupRoot)

        XCTAssertEqual(record.modelID, model.id)
        XCTAssertEqual(record.backupRelativePath, "lm-studio/publisher/model-a")
        XCTAssertEqual(record.effectiveLocalState, .present)
        XCTAssertNil(record.archivedAt)
        XCTAssertNil(record.restoredAt)
        XCTAssertTrue(fileManager.fileExists(atPath: backupRoot.appendingPathComponent(record.backupRelativePath).path))
        XCTAssertTrue(fileManager.fileExists(atPath: model.folderURL.path))
    }

    func testArchiveDoesNotRemoveLocalModelWhenExistingBackupVerificationFails() throws {
        let model = try makeModel(relativePath: "publisher/model-b", files: [
            "weights.bin": "original payload"
        ])
        let staleRecord = backupRecord(for: model, backupRelativePath: "lm-studio/publisher/model-b")
        let staleBackupURL = backupRoot.appendingPathComponent(staleRecord.backupRelativePath, isDirectory: true)
        try writeFile("weights.bin", contents: "wrong", under: staleBackupURL)

        XCTAssertThrowsError(
            try coordinator.archive(model: model, to: backupRoot, existingRecord: staleRecord)
        ) { error in
            guard case BackupCoordinatorError.verificationFailed = error else {
                return XCTFail("Expected verificationFailed, got \(error)")
            }
        }
        XCTAssertTrue(fileManager.fileExists(atPath: model.folderURL.path))
    }

    func testDeleteLocalModelVerifiesBackupBeforeRemoval() throws {
        let model = try makeModel(relativePath: "publisher/model-c", files: [
            "weights.bin": "local payload"
        ])
        let record = backupRecord(for: model, backupRelativePath: "lm-studio/publisher/model-c")
        let staleBackupURL = backupRoot.appendingPathComponent(record.backupRelativePath, isDirectory: true)
        try writeFile("weights.bin", contents: "bad backup payload", under: staleBackupURL)

        XCTAssertThrowsError(
            try coordinator.deleteLocalCopy(model: model, to: backupRoot, existingRecord: record)
        ) { error in
            guard case BackupCoordinatorError.verificationFailed = error else {
                return XCTFail("Expected verificationFailed, got \(error)")
            }
        }
        XCTAssertTrue(fileManager.fileExists(atPath: model.folderURL.path))
    }

    func testRestoreRejectsExistingLocalFolderWithoutOverwriting() throws {
        let archivedModel = try makeModel(relativePath: "publisher/model-d", files: [
            "weights.bin": "backup payload"
        ])
        let record = try coordinator.archive(model: archivedModel, to: backupRoot, existingRecord: nil)
        let conflictingModelURL = sourceRoot.appendingPathComponent(record.relativePath, isDirectory: true)
        try writeFile("weights.bin", contents: "existing local payload", under: conflictingModelURL)

        XCTAssertThrowsError(
            try coordinator.restore(record: record, from: backupRoot, to: sourceRoot)
        ) { error in
            guard case BackupCoordinatorError.restoreDestinationAlreadyExists = error else {
                return XCTFail("Expected restoreDestinationAlreadyExists, got \(error)")
            }
        }
        let localPayload = try String(contentsOf: conflictingModelURL.appendingPathComponent("weights.bin"), encoding: .utf8)
        XCTAssertEqual(localPayload, "existing local payload")
    }

    func testDeleteBackupRemovesPayloadAfterVerification() throws {
        let model = try makeModel(relativePath: "publisher/model-e", files: [
            "weights.bin": "payload"
        ])
        let record = try coordinator.backup(model: model, to: backupRoot)
        let backupURL = backupRoot.appendingPathComponent(record.backupRelativePath, isDirectory: true)

        try coordinator.deleteBackup(record: record, from: backupRoot)

        XCTAssertFalse(fileManager.fileExists(atPath: backupURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: model.folderURL.path))
    }

    private func makeModel(relativePath: String, files: [String: String]) throws -> DiscoveredModel {
        let modelURL = sourceRoot.appendingPathComponent(relativePath, isDirectory: true)
        for (path, contents) in files {
            try writeFile(path, contents: contents, under: modelURL)
        }

        let payload = try directoryPayload(in: modelURL)
        return DiscoveredModel(
            id: "lm_studio:\(relativePath)",
            source: ModelProvider.lmStudio.rawValue,
            publisher: relativePath.split(separator: "/").dropLast().last.map(String.init),
            displayName: modelURL.lastPathComponent,
            folderURL: modelURL,
            relativePath: relativePath,
            sizeBytes: payload.sizeBytes,
            fileCount: payload.fileCount,
            lastModified: nil
        )
    }

    private func backupRecord(for model: DiscoveredModel, backupRelativePath: String) -> BackupRecord {
        BackupRecord(
            modelID: model.id,
            source: model.source,
            displayName: model.displayName,
            relativePath: model.relativePath,
            backupRelativePath: backupRelativePath,
            sizeBytes: model.sizeBytes,
            fileCount: model.fileCount,
            backedUpAt: Date(),
            localState: .present,
            archivedAt: nil,
            restoredAt: nil
        )
    }

    private func writeFile(_ path: String, contents: String, under root: URL) throws {
        let fileURL = root.appendingPathComponent(path, isDirectory: false)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.data(using: .utf8)?.write(to: fileURL)
    }

    private func directoryPayload(in directoryURL: URL) throws -> (sizeBytes: Int64, fileCount: Int) {
        let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var sizeBytes: Int64 = 0
        var fileCount = 0

        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else {
                continue
            }

            fileCount += 1
            sizeBytes += Int64(values.fileSize ?? 0)
        }

        return (sizeBytes, fileCount)
    }
}
