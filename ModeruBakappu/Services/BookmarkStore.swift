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
    private let pathStoragePrefix = "ModeruBakappu.path."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func saveBookmark(for url: URL, as key: BookmarkKey) throws {
        let bookmark = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        guard !bookmark.isEmpty else {
            throw BookmarkStoreError.failedToCreateBookmark
        }

        defaults.set(bookmark, forKey: storageKey(for: key))
        defaults.set(url.path, forKey: pathStorageKey(for: key))
    }

    func loadBookmark(for key: BookmarkKey) throws -> ResolvedBookmark? {
        guard let data = defaults.data(forKey: storageKey(for: key)) else {
            return pathFallback(for: key)
        }

        do {
            return try resolveBookmarkData(data, options: [.withSecurityScope])
        } catch {
            do {
                return try resolveBookmarkData(data, options: [])
            } catch {
                if let fallback = pathFallback(for: key) {
                    print("[BookmarkStore] bookmark resolution failed for \(key.rawValue), falling back to stored path: \(fallback.url.path)")
                    return fallback
                }
                throw error
            }
        }
    }

    func removeBookmark(for key: BookmarkKey) {
        defaults.removeObject(forKey: storageKey(for: key))
        defaults.removeObject(forKey: pathStorageKey(for: key))
    }

    private func resolveBookmarkData(_ data: Data, options: URL.BookmarkResolutionOptions) throws -> ResolvedBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        return ResolvedBookmark(url: url, isStale: isStale)
    }

    private func pathFallback(for key: BookmarkKey) -> ResolvedBookmark? {
        guard let path = defaults.string(forKey: pathStorageKey(for: key)), !path.isEmpty else {
            return nil
        }

        return ResolvedBookmark(url: URL(fileURLWithPath: path, isDirectory: true), isStale: false)
    }

    private func storageKey(for key: BookmarkKey) -> String {
        storagePrefix + key.rawValue
    }

    private func pathStorageKey(for key: BookmarkKey) -> String {
        pathStoragePrefix + key.rawValue
    }
}
