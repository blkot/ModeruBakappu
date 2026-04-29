//
//  ModelProviderAdapter.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/29.
//

import Foundation

protocol ModelProviderAdapter {
    var provider: ModelProvider { get }

    func detectSource() -> DetectedSourceConfiguration?
    func ownsSourceURL(_ url: URL) -> Bool
    func discoverModels(in rootURL: URL) throws -> [DiscoveredModel]
    func readiness(for model: DiscoveredModel) -> ProviderReadinessState
}

final class DirectoryModelProviderAdapter: ModelProviderAdapter {
    let provider: ModelProvider

    private let fileManager: FileManager
    private let candidates: [URL]
    private let pathMatchers: [(String) -> Bool]
    private let readinessState: ProviderReadinessState
    private let discoveryService: LMStudioDiscoveryService

    init(
        provider: ModelProvider,
        candidates: [URL],
        pathMatchers: [(String) -> Bool],
        readinessState: ProviderReadinessState = .ready,
        fileManager: FileManager = .default
    ) {
        self.provider = provider
        self.fileManager = fileManager
        self.candidates = candidates
        self.pathMatchers = pathMatchers
        self.readinessState = readinessState
        self.discoveryService = LMStudioDiscoveryService(fileManager: fileManager)
    }

    func detectSource() -> DetectedSourceConfiguration? {
        for candidate in candidates {
            let valid = isLikelyModelsRoot(candidate)
            print("[ModelProviderAdapter] candidate provider=\(provider.displayName) path=\(candidate.path) valid=\(valid)")
            if valid {
                return DetectedSourceConfiguration(provider: provider, folderURL: candidate)
            }
        }
        return nil
    }

    func ownsSourceURL(_ url: URL) -> Bool {
        let path = url.path
        return pathMatchers.contains { matcher in matcher(path) }
    }

    func discoverModels(in rootURL: URL) throws -> [DiscoveredModel] {
        try discoveryService.discoverModels(in: rootURL, source: provider)
    }

    func readiness(for model: DiscoveredModel) -> ProviderReadinessState {
        readinessState
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

extension DirectoryModelProviderAdapter {
    static func defaultAdapters(fileManager: FileManager = .default) -> [any ModelProviderAdapter] {
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)

        return [
            DirectoryModelProviderAdapter(
                provider: .lmStudio,
                candidates: [
                    homeDirectory.appendingPathComponent(".cache/lm-studio/models", isDirectory: true),
                    homeDirectory.appendingPathComponent(".lmstudio/models", isDirectory: true),
                    homeDirectory.appendingPathComponent("Library/Application Support/LM Studio/Models", isDirectory: true)
                ],
                pathMatchers: [
                    { $0.contains("/LM Studio/") },
                    { $0.contains("/.cache/lm-studio/") },
                    { $0.contains("/.lmstudio/") }
                ],
                fileManager: fileManager
            ),
            DirectoryModelProviderAdapter(
                provider: .omlx,
                candidates: [
                    homeDirectory.appendingPathComponent(".omlx/models", isDirectory: true)
                ],
                pathMatchers: [
                    { $0.contains("/.omlx/") },
                    { $0.hasSuffix("/.omlx/models") }
                ],
                readinessState: .unknown("oMLX readiness cannot be confirmed from files alone yet."),
                fileManager: fileManager
            )
        ]
    }
}
