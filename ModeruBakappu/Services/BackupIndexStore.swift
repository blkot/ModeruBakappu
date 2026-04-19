//
//  BackupIndexStore.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import Foundation

protocol BackupIndexStore {
    func loadIndex() throws -> [String: BackupRecord]
    func saveIndex(_ index: [String: BackupRecord]) throws
}

final class JSONBackupIndexStore: BackupIndexStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func loadIndex() throws -> [String: BackupRecord] {
        let fileURL = try indexFileURL()
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([String: BackupRecord].self, from: data)
    }

    func saveIndex(_ index: [String: BackupRecord]) throws {
        let fileURL = try indexFileURL()
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(index)
        try data.write(to: fileURL, options: .atomic)
    }

    private func indexFileURL() throws -> URL {
        let appSupportRoot = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupportRoot
            .appendingPathComponent("ModeruBakappu", isDirectory: true)
            .appendingPathComponent("backup-index.json", isDirectory: false)
    }
}
