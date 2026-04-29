//
//  HFEndpointConfigStore.swift
//  ModeruBakappu
//

import Foundation

struct HFEndpointConfig: Equatable {
    var endpointURL: URL
    var isDefault: Bool

    static let defaultEndpoint = URL(string: "https://huggingface.co/api")!
    static let defaultsKey = "ModeruBakappu.hfEndpoint"
}

@MainActor
final class HFEndpointConfigStore {
    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.defaults = defaults
        self.fileManager = fileManager
    }

    func loadEndpointConfig() -> HFEndpointConfig {
        guard let stored = defaults.string(forKey: HFEndpointConfig.defaultsKey),
              let url = URL(string: stored)
        else {
            return HFEndpointConfig(endpointURL: HFEndpointConfig.defaultEndpoint, isDefault: true)
        }
        return HFEndpointConfig(endpointURL: url, isDefault: false)
    }

    func saveEndpointConfig(_ config: HFEndpointConfig) {
        defaults.set(config.endpointURL.absoluteString, forKey: HFEndpointConfig.defaultsKey)
    }

    func scanShellForHFEndpoint() -> String? {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".zshrc"),
            home.appendingPathComponent(".bashrc")
        ]
        let pattern = try? NSRegularExpression(
            pattern: #"export\s+HF_ENDPOINT\s*=\s*(.+)"#,
            options: []
        )

        for candidate in candidates {
            guard fileManager.fileExists(atPath: candidate.path) else { continue }
            guard let content = try? String(contentsOf: candidate, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) {
                guard let match = pattern?.firstMatch(
                    in: line,
                    options: [],
                    range: NSRange(line.startIndex..., in: line)
                ) else { continue }
                guard let range = Range(match.range(at: 1), in: line) else { continue }
                let value = String(line[range])
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "'", with: "")
                guard !value.isEmpty else { continue }
                print("[HFEndpointConfigStore] found HF_ENDPOINT in \(candidate.lastPathComponent): \(value)")
                return value
            }
        }
        return nil
    }

    func hasPromptedForShellImport() -> Bool {
        defaults.bool(forKey: "ModeruBakappu.hfEndpointShellPrompted")
    }

    func markShellImportPrompted() {
        defaults.set(true, forKey: "ModeruBakappu.hfEndpointShellPrompted")
    }
}
