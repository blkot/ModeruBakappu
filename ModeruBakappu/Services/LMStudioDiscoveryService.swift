//
//  LMStudioDiscoveryService.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import Foundation

enum LMStudioDiscoveryError: LocalizedError {
    case inaccessibleRoot

    var errorDescription: String? {
        switch self {
        case .inaccessibleRoot:
            return "The selected models folder could not be scanned."
        }
    }
}

final class LMStudioDiscoveryService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func discoverModels(in rootURL: URL, source: ModelProvider) throws -> [DiscoveredModel] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LMStudioDiscoveryError.inaccessibleRoot
        }

        let topLevelDirectories = try visibleDirectories(in: rootURL)
        var models: [DiscoveredModel] = []

        for topLevelDirectory in topLevelDirectories {
            let nestedDirectories = try visibleDirectories(in: topLevelDirectory)
            var foundNestedModel = false

            for nestedDirectory in nestedDirectories {
                if let model = try makeModelCandidate(from: nestedDirectory, rootURL: rootURL, source: source) {
                    models.append(model)
                    foundNestedModel = true
                }
            }

            if !foundNestedModel, let directModel = try makeModelCandidate(from: topLevelDirectory, rootURL: rootURL, source: source) {
                models.append(directModel)
            }
        }

        return models.sorted {
            ($0.publisher ?? "", $0.displayName.localizedLowercase) < ($1.publisher ?? "", $1.displayName.localizedLowercase)
        }
    }

    private func makeModelCandidate(from directoryURL: URL, rootURL: URL, source: ModelProvider) throws -> DiscoveredModel? {
        let payload = try directoryPayload(in: directoryURL)
        guard payload.fileCount > 0 else {
            return nil
        }

        let relativePath = directoryURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        let pathComponents = relativePath.split(separator: "/").map(String.init)
        let publisher = pathComponents.count > 1 ? pathComponents.first : nil

        return DiscoveredModel(
            id: relativePath,
            source: source.rawValue,
            publisher: publisher,
            displayName: directoryURL.lastPathComponent,
            folderURL: directoryURL,
            relativePath: relativePath,
            sizeBytes: payload.sizeBytes,
            fileCount: payload.fileCount,
            lastModified: payload.lastModified
        )
    }

    private func visibleDirectories(in directoryURL: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private func directoryPayload(in directoryURL: URL) throws -> (sizeBytes: Int64, fileCount: Int, lastModified: Date?) {
        let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var sizeBytes: Int64 = 0
        var fileCount = 0
        var lastModified: Date?

        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true else {
                continue
            }

            fileCount += 1
            sizeBytes += Int64(values.fileSize ?? 0)

            if let modificationDate = values.contentModificationDate {
                if let currentLastModified = lastModified {
                    if modificationDate > currentLastModified {
                        lastModified = modificationDate
                    }
                } else {
                    lastModified = modificationDate
                }
            }
        }

        return (sizeBytes, fileCount, lastModified)
    }
}
