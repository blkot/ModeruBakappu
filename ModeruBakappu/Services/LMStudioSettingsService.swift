//
//  LMStudioSettingsService.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import Foundation

final class LMStudioSettingsService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func suggestedModelsFolder() -> URL? {
        for candidate in settingsCandidates() {
            guard let data = try? Data(contentsOf: candidate),
                  let settings = try? JSONDecoder().decode(LMStudioSettings.self, from: data),
                  let path = settings.downloadsFolder
            else {
                continue
            }

            let url = URL(fileURLWithPath: path, isDirectory: true)
            if isExistingDirectory(url) {
                return url
            }
        }

        for fallback in fallbackCandidates() {
            if isExistingDirectory(fallback) {
                return fallback
            }
        }

        return nil
    }

    private func settingsCandidates() -> [URL] {
        let supportDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("LM Studio", isDirectory: true)

        return [
            supportDirectory.appendingPathComponent("settings.json", isDirectory: false),
            supportDirectory.appendingPathComponent("settings.json.lmstudio-temp", isDirectory: false),
        ]
    }

    private func fallbackCandidates() -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser

        return [
            home.appendingPathComponent(".cache", isDirectory: true)
                .appendingPathComponent("lm-studio", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true),
            home.appendingPathComponent(".lmstudio", isDirectory: true)
                .appendingPathComponent("models", isDirectory: true),
            home.appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("LM Studio", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true),
        ]
    }

    private func isExistingDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private struct LMStudioSettings: Decodable {
    let downloadsFolder: String?
}
