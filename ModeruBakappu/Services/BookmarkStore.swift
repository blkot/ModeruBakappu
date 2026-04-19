//
//  BookmarkStore.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import Foundation

protocol BookmarkStore {
    func saveBookmark(for url: URL) throws
}
