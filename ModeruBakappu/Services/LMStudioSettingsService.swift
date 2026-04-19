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
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
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
}

private struct LMStudioSettings: Decodable {
    let downloadsFolder: String?
}
