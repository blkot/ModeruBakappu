//
//  BackupCoordinator.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import Foundation

enum BackupCoordinatorError: LocalizedError {
    case backupRootUnavailable
    case sourceRootUnavailable
    case destinationAlreadyExists
    case restoreDestinationAlreadyExists
    case verificationFailed
    case sourceRemovalFailed(String)
    case backupRemovalFailed(String)

    var errorDescription: String? {
        switch self {
        case .backupRootUnavailable:
            return "The configured backup root is not currently available."
        case .sourceRootUnavailable:
            return "The configured source folder is not currently available."
        case .destinationAlreadyExists:
            return "A backup already exists at the planned destination."
        case .restoreDestinationAlreadyExists:
            return "A local folder already exists at the restore destination."
        case .verificationFailed:
            return "The copied backup did not match the source payload."
        case let .sourceRemovalFailed(message):
            return message
        case let .backupRemovalFailed(message):
            return message
        }
    }
}

final class BackupCoordinator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func backup(model: DiscoveredModel, to backupRoot: URL) throws -> BackupRecord {
        try copyAndVerifyBackup(model: model, to: backupRoot)
    }

    func archive(model: DiscoveredModel, to backupRoot: URL, existingRecord: BackupRecord?) throws -> BackupRecord {
        let backupRecord: BackupRecord

        if let existingRecord {
            try verifyBackup(record: existingRecord, in: backupRoot)
            backupRecord = existingRecord
        } else {
            backupRecord = try copyAndVerifyBackup(model: model, to: backupRoot)
        }

        do {
            try fileManager.removeItem(at: model.folderURL)
        } catch {
            throw BackupCoordinatorError.sourceRemovalFailed(
                "The backup was verified, but the local model could not be removed: \(error.localizedDescription)"
            )
        }

        return BackupRecord(
            modelID: backupRecord.modelID,
            source: backupRecord.source,
            displayName: backupRecord.displayName,
            relativePath: backupRecord.relativePath,
            backupRelativePath: backupRecord.backupRelativePath,
            sizeBytes: backupRecord.sizeBytes,
            fileCount: backupRecord.fileCount,
            backedUpAt: backupRecord.backedUpAt,
            localState: .archived,
            archivedAt: .now,
            restoredAt: backupRecord.restoredAt
        )
    }

    func restore(record: BackupRecord, from backupRoot: URL, to sourceRoot: URL) throws -> BackupRecord {
        try verifyBackup(record: record, in: backupRoot)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BackupCoordinatorError.sourceRootUnavailable
        }

        let backupURL = backupRoot.appendingPathComponent(record.backupRelativePath, isDirectory: true)
        let restoreURL = sourceRoot.appendingPathComponent(record.relativePath, isDirectory: true)

        if fileManager.fileExists(atPath: restoreURL.path) {
            throw BackupCoordinatorError.restoreDestinationAlreadyExists
        }

        let parentURL = restoreURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: backupURL, to: restoreURL)

        let payload = try directoryPayload(in: restoreURL)
        guard payload.fileCount == record.fileCount,
              payload.sizeBytes == record.sizeBytes
        else {
            throw BackupCoordinatorError.verificationFailed
        }

        return BackupRecord(
            modelID: record.modelID,
            source: record.source,
            displayName: record.displayName,
            relativePath: record.relativePath,
            backupRelativePath: record.backupRelativePath,
            sizeBytes: record.sizeBytes,
            fileCount: record.fileCount,
            backedUpAt: record.backedUpAt,
            localState: .present,
            archivedAt: record.archivedAt,
            restoredAt: .now
        )
    }

    func deleteLocalCopy(model: DiscoveredModel, to backupRoot: URL, existingRecord: BackupRecord) throws -> BackupRecord {
        try verifyBackup(record: existingRecord, in: backupRoot)

        do {
            try fileManager.removeItem(at: model.folderURL)
        } catch {
            throw BackupCoordinatorError.sourceRemovalFailed(
                "The backup was verified, but the local model could not be removed: \(error.localizedDescription)"
            )
        }

        return BackupRecord(
            modelID: existingRecord.modelID,
            source: existingRecord.source,
            displayName: existingRecord.displayName,
            relativePath: existingRecord.relativePath,
            backupRelativePath: existingRecord.backupRelativePath,
            sizeBytes: existingRecord.sizeBytes,
            fileCount: existingRecord.fileCount,
            backedUpAt: existingRecord.backedUpAt,
            localState: .archived,
            archivedAt: .now,
            restoredAt: existingRecord.restoredAt
        )
    }

    func deleteBackup(record: BackupRecord, from backupRoot: URL) throws {
        try verifyBackup(record: record, in: backupRoot)

        let backupURL = backupRoot.appendingPathComponent(record.backupRelativePath, isDirectory: true)
        do {
            try fileManager.removeItem(at: backupURL)
        } catch {
            throw BackupCoordinatorError.backupRemovalFailed(
                "The backup payload could not be removed: \(error.localizedDescription)"
            )
        }
    }

    private func copyAndVerifyBackup(model: DiscoveredModel, to backupRoot: URL) throws -> BackupRecord {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: backupRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BackupCoordinatorError.backupRootUnavailable
        }

        let sourceDirectory = model.source.replacingOccurrences(of: "_", with: "-")
        let backupRelativePath = "\(sourceDirectory)/\(model.relativePath)"
        let destinationURL = backupRoot.appendingPathComponent(backupRelativePath, isDirectory: true)

        if fileManager.fileExists(atPath: destinationURL.path) {
            throw BackupCoordinatorError.destinationAlreadyExists
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: model.folderURL, to: destinationURL)

        let copiedPayload = try directoryPayload(in: destinationURL)
        guard copiedPayload.fileCount == model.fileCount,
              copiedPayload.sizeBytes == model.sizeBytes
        else {
            try? fileManager.removeItem(at: destinationURL)
            throw BackupCoordinatorError.verificationFailed
        }

        return BackupRecord(
            modelID: model.id,
            source: model.source,
            displayName: model.displayName,
            relativePath: model.relativePath,
            backupRelativePath: backupRelativePath,
            sizeBytes: model.sizeBytes,
            fileCount: model.fileCount,
            backedUpAt: .now,
            localState: .present,
            archivedAt: nil,
            restoredAt: nil
        )
    }

    private func verifyBackup(record: BackupRecord, in backupRoot: URL) throws {
        let backupURL = backupRoot.appendingPathComponent(record.backupRelativePath, isDirectory: true)
        let payload = try directoryPayload(in: backupURL)
        guard payload.fileCount == record.fileCount,
              payload.sizeBytes == record.sizeBytes
        else {
            throw BackupCoordinatorError.verificationFailed
        }
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
