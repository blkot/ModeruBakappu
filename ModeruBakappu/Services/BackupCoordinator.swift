//
//  BackupCoordinator.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import Foundation

enum BackupCoordinatorError: LocalizedError {
    case backupRootUnavailable
    case destinationAlreadyExists
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .backupRootUnavailable:
            return "The configured backup root is not currently available."
        case .destinationAlreadyExists:
            return "A backup already exists at the planned destination."
        case .verificationFailed:
            return "The copied backup did not match the source payload."
        }
    }
}

final class BackupCoordinator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func backup(model: DiscoveredModel, to backupRoot: URL) throws -> BackupRecord {
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
            backedUpAt: .now
        )
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
