//
//  LMStudioSettingsService.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import Foundation
import Darwin

final class LMStudioSettingsService {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func suggestedModelsFolder() -> URL? {
        let candidates = settingsCandidates()
        print("[LMStudioSettingsService] settingsCandidates:")
        for candidate in candidates {
            print("  - \(candidate.path) exists=\(fileManager.fileExists(atPath: candidate.path))")
        }

        for candidate in candidates {
            guard let data = try? Data(contentsOf: candidate),
                  let settings = try? JSONDecoder().decode(LMStudioSettings.self, from: data),
                  let path = settings.downloadsFolder
            else {
                continue
            }

            let url = URL(fileURLWithPath: path, isDirectory: true)
            print("[LMStudioSettingsService] downloadsFolder from \(candidate.lastPathComponent): \(url.path)")
            if isExistingDirectory(url) {
                print("[LMStudioSettingsService] using settings-derived models folder: \(url.path)")
                return url
            }
        }

        for fallback in fallbackCandidates() {
            print("  fallback: \(fallback.path) exists=\(isExistingDirectory(fallback))")
            if isExistingDirectory(fallback) {
                print("[LMStudioSettingsService] using fallback models folder: \(fallback.path)")
                return fallback
            }
        }

        print("[LMStudioSettingsService] no models folder candidate resolved")
        return nil
    }

    private func settingsCandidates() -> [URL] {
        let supportDirectory = realUserHomeDirectory()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("LM Studio", isDirectory: true)

        return [
            supportDirectory.appendingPathComponent("settings.json", isDirectory: false),
            supportDirectory.appendingPathComponent("settings.json.lmstudio-temp", isDirectory: false),
        ]
    }

    private func fallbackCandidates() -> [URL] {
        let home = realUserHomeDirectory()

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

    private func realUserHomeDirectory() -> URL {
        let uid = getuid()
        guard let passwd = getpwuid(uid), let homeDirectory = passwd.pointee.pw_dir else {
            return fileManager.homeDirectoryForCurrentUser
        }

        return URL(fileURLWithPath: String(cString: homeDirectory), isDirectory: true)
    }
}

private struct LMStudioSettings: Decodable {
    let downloadsFolder: String?
}
