//
//  BookmarkStore.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import Foundation

protocol BookmarkStore {
    func saveBookmark(for url: URL, as key: BookmarkKey) throws
    func loadBookmark(for key: BookmarkKey) throws -> ResolvedBookmark?
    func removeBookmark(for key: BookmarkKey)
}

enum BookmarkStoreError: LocalizedError {
    case failedToCreateBookmark

    var errorDescription: String? {
        switch self {
        case .failedToCreateBookmark:
            return "The app could not create a persistent folder bookmark."
        }
    }
}

final class UserDefaultsBookmarkStore: BookmarkStore {
    private let defaults: UserDefaults
    private let storagePrefix = "ModeruBakappu.bookmark."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func saveBookmark(for url: URL, as key: BookmarkKey) throws {
        let bookmark = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        guard !bookmark.isEmpty else {
            throw BookmarkStoreError.failedToCreateBookmark
        }

        defaults.set(bookmark, forKey: storageKey(for: key))
    }

    func loadBookmark(for key: BookmarkKey) throws -> ResolvedBookmark? {
        guard let data = defaults.data(forKey: storageKey(for: key)) else {
            return nil
        }

        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        return ResolvedBookmark(url: url, isStale: isStale)
    }

    func removeBookmark(for key: BookmarkKey) {
        defaults.removeObject(forKey: storageKey(for: key))
    }

    private func storageKey(for key: BookmarkKey) -> String {
        storagePrefix + key.rawValue
    }
}
