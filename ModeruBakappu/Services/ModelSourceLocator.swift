//
//  ModelSourceLocator.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/20.
//

import Foundation

final class ModelSourceLocator {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func detectPreferredSource() -> DetectedSourceConfiguration? {
        let detectors: [() -> DetectedSourceConfiguration?] = [
            detectLMStudio,
            detectOMLX
        ]

        for detector in detectors {
            if let result = detector() {
                print("[ModelSourceLocator] detected provider=\(result.provider.displayName) path=\(result.folderURL.path)")
                return result
            }
        }

        return nil
    }

    func inferProvider(for url: URL) -> ModelProvider {
        let path = url.path
        if path.contains("/.omlx/") || path.hasSuffix("/.omlx/models") {
            return .omlx
        }
        if path.contains("/LM Studio/") || path.contains("/.cache/lm-studio/") || path.contains("/.lmstudio/") {
            return .lmStudio
        }
        return .custom
    }

    private func detectLMStudio() -> DetectedSourceConfiguration? {
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let candidates = [
            homeDirectory.appendingPathComponent(".cache/lm-studio/models", isDirectory: true),
            homeDirectory.appendingPathComponent(".lmstudio/models", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Application Support/LM Studio/Models", isDirectory: true)
        ]

        print("[ModelSourceLocator] checking LM Studio candidates:")
        return firstValidCandidate(in: candidates, provider: .lmStudio)
    }

    private func detectOMLX() -> DetectedSourceConfiguration? {
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let fallback = homeDirectory.appendingPathComponent(".omlx/models", isDirectory: true)
        print("[ModelSourceLocator] checking oMLX models root:")
        return firstValidCandidate(in: [fallback], provider: .omlx)
    }

    private func firstValidCandidate(in candidates: [URL], provider: ModelProvider) -> DetectedSourceConfiguration? {
        for candidate in candidates {
            let valid = isLikelyModelsRoot(candidate)
            print("[ModelSourceLocator] candidate=\(candidate.path) valid=\(valid)")
            if valid {
                return DetectedSourceConfiguration(provider: provider, folderURL: candidate)
            }
        }
        return nil
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
