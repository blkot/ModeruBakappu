//
//  FolderPicker.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import AppKit
import Foundation

protocol FolderPicker {
    func pickFolder(title: String, message: String, prompt: String, startingAt: URL?) -> URL?
}

final class OpenPanelFolderPicker: FolderPicker {
    func pickFolder(title: String, message: String, prompt: String, startingAt: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = startingAt

        return panel.runModal() == .OK ? panel.url : nil
    }
}
