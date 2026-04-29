//
//  ModelSourceLocator.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/20.
//

import Foundation

final class ModelSourceLocator {
    private let adapters: [any ModelProviderAdapter]

    init(adapters: [any ModelProviderAdapter] = DirectoryModelProviderAdapter.defaultAdapters()) {
        self.adapters = adapters
    }

    func detectSources() -> [DetectedSourceConfiguration] {
        let detected = adapters.compactMap { adapter in
            adapter.detectSource()
        }

        for result in detected {
            print("[ModelSourceLocator] detected provider=\(result.provider.displayName) path=\(result.folderURL.path)")
        }

        return detected
    }

    func inferProvider(for url: URL) -> ModelProvider {
        adapters.first { $0.ownsSourceURL(url) }?.provider ?? .custom
    }

    func discoverModels(in rootURL: URL, source: ModelProvider) throws -> [DiscoveredModel] {
        guard let adapter = adapter(for: source) else {
            throw LMStudioDiscoveryError.inaccessibleRoot
        }
        return try adapter.discoverModels(in: rootURL)
    }

    func readiness(for model: DiscoveredModel) -> ProviderReadinessState {
        guard let provider = ModelProvider(rawValue: model.source),
              let adapter = adapter(for: provider)
        else {
            return .unknown("No provider adapter is available for this model.")
        }
        return adapter.readiness(for: model)
    }

    private func adapter(for provider: ModelProvider) -> (any ModelProviderAdapter)? {
        adapters.first { $0.provider == provider }
    }
}
