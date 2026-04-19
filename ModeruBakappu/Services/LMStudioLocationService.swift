//
//  LMStudioLocationService.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/20.
//

import Foundation

final class LMStudioLocationService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func detectModelsFolder() -> URL? {
        let candidates = candidatePaths()
        print("[LMStudioLocationService] checking candidates:")

        for candidate in candidates {
            let exists = isLikelyModelsRoot(candidate)
            print("[LMStudioLocationService] candidate=\(candidate.path) valid=\(exists)")
            if exists {
                return candidate
            }
        }

        return nil
    }

    private func candidatePaths() -> [URL] {
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)

        return [
            homeDirectory.appendingPathComponent(".cache/lm-studio/models", isDirectory: true),
            homeDirectory.appendingPathComponent(".lmstudio/models", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Application Support/LM Studio/Models", isDirectory: true)
        ]
    }

    private func isLikelyModelsRoot(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return false
        }

        guard let children = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        return !children.isEmpty
    }
}
