//
//  ModelSourceLocatorTests.swift
//  ModeruBakappuTests
//
//  Created by Codex on 2026/4/29.
//

import XCTest
@testable import ModeruBakappu

final class ModelSourceLocatorTests: XCTestCase {
    func testDetectSourcesUsesProviderAdapters() {
        let lmStudioURL = URL(fileURLWithPath: "/tmp/lm-studio", isDirectory: true)
        let omlxURL = URL(fileURLWithPath: "/tmp/omlx", isDirectory: true)
        let locator = ModelSourceLocator(adapters: [
            StubModelProviderAdapter(provider: .lmStudio, detectedURL: lmStudioURL),
            StubModelProviderAdapter(provider: .omlx, detectedURL: omlxURL)
        ])

        let detected = locator.detectSources()

        XCTAssertEqual(detected, [
            DetectedSourceConfiguration(provider: .lmStudio, folderURL: lmStudioURL),
            DetectedSourceConfiguration(provider: .omlx, folderURL: omlxURL)
        ])
    }

    func testInferProviderUsesAdapterOwnership() {
        let omlxURL = URL(fileURLWithPath: "/Users/test/.omlx/models", isDirectory: true)
        let locator = ModelSourceLocator(adapters: [
            StubModelProviderAdapter(provider: .lmStudio, ownedURLs: []),
            StubModelProviderAdapter(provider: .omlx, ownedURLs: [omlxURL])
        ])

        XCTAssertEqual(locator.inferProvider(for: omlxURL), .omlx)
        XCTAssertEqual(locator.inferProvider(for: URL(fileURLWithPath: "/tmp/custom", isDirectory: true)), .custom)
    }

    func testDiscoveryAndReadinessAreDelegatedToAdapter() throws {
        let rootURL = URL(fileURLWithPath: "/tmp/source", isDirectory: true)
        let model = DiscoveredModel(
            id: "omlx:publisher/model",
            source: ModelProvider.omlx.rawValue,
            publisher: "publisher",
            displayName: "model",
            folderURL: rootURL.appendingPathComponent("publisher/model", isDirectory: true),
            relativePath: "publisher/model",
            sizeBytes: 128,
            fileCount: 2,
            lastModified: nil
        )
        let adapter = StubModelProviderAdapter(
            provider: .omlx,
            discoveredModels: [model],
            readinessState: .unknown("Provider-specific readiness is pending.")
        )
        let locator = ModelSourceLocator(adapters: [adapter])

        XCTAssertEqual(try locator.discoverModels(in: rootURL, source: .omlx), [model])
        XCTAssertEqual(locator.readiness(for: model), .unknown("Provider-specific readiness is pending."))
    }
}

private final class StubModelProviderAdapter: ModelProviderAdapter {
    let provider: ModelProvider

    private let detectedURL: URL?
    private let ownedURLs: Set<URL>
    private let discoveredModels: [DiscoveredModel]
    private let readinessState: ProviderReadinessState

    init(
        provider: ModelProvider,
        detectedURL: URL? = nil,
        ownedURLs: Set<URL> = [],
        discoveredModels: [DiscoveredModel] = [],
        readinessState: ProviderReadinessState = .ready
    ) {
        self.provider = provider
        self.detectedURL = detectedURL
        self.ownedURLs = ownedURLs
        self.discoveredModels = discoveredModels
        self.readinessState = readinessState
    }

    func detectSource() -> DetectedSourceConfiguration? {
        detectedURL.map { DetectedSourceConfiguration(provider: provider, folderURL: $0) }
    }

    func ownsSourceURL(_ url: URL) -> Bool {
        ownedURLs.contains(url)
    }

    func discoverModels(in rootURL: URL) throws -> [DiscoveredModel] {
        discoveredModels
    }

    func readiness(for model: DiscoveredModel) -> ProviderReadinessState {
        readinessState
    }
}
