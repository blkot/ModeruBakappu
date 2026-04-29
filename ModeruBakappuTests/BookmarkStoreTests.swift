//
//  BookmarkStoreTests.swift
//  ModeruBakappuTests
//
//  Created by Codex on 2026/4/29.
//

import XCTest
@testable import ModeruBakappu

final class BookmarkStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "ModeruBakappuTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    func testLoadBookmarkFallsBackToStoredPathWhenBookmarkDataCannotResolve() throws {
        let expectedURL = URL(fileURLWithPath: "/Volumes/TestDrive/ModeruBackups", isDirectory: true)
        defaults.set(Data("not a bookmark".utf8), forKey: "ModeruBakappu.bookmark.backupRoot")
        defaults.set(expectedURL.path, forKey: "ModeruBakappu.path.backupRoot")

        let store = UserDefaultsBookmarkStore(defaults: defaults)
        let bookmark = try store.loadBookmark(for: .backupRoot)

        XCTAssertEqual(bookmark?.url, expectedURL)
        XCTAssertEqual(bookmark?.isStale, false)
    }

    func testRemoveBookmarkClearsStoredPathFallback() {
        defaults.set(Data("not a bookmark".utf8), forKey: "ModeruBakappu.bookmark.backupRoot")
        defaults.set("/Volumes/TestDrive/ModeruBackups", forKey: "ModeruBakappu.path.backupRoot")

        let store = UserDefaultsBookmarkStore(defaults: defaults)
        store.removeBookmark(for: .backupRoot)

        XCTAssertNil(defaults.object(forKey: "ModeruBakappu.bookmark.backupRoot"))
        XCTAssertNil(defaults.object(forKey: "ModeruBakappu.path.backupRoot"))
    }
}
