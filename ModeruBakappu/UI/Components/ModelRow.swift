//
//  ModelRow.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import SwiftUI

struct ModelRow: View {
    let model: DiscoveredModel
    let backupEnabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(model.displayName)
                        .font(.headline)
                    if let publisher = model.publisher {
                        Text(publisher)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }

                Text(model.relativePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 12) {
                    Text(model.sizeDescription)
                    Text(model.fileCountDescription)
                    if let lastModified = model.lastModified {
                        Text(lastModified, style: .date)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Backup") {}
                .disabled(true || !backupEnabled)
                .help(backupEnabled ? "Backup actions are not implemented yet." : "Backup remains unavailable until the backup drive is online.")
        }
        .padding(.vertical, 4)
    }
}
