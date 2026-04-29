//
//  FolderStatusCard.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import SwiftUI

struct FolderStatusCard: View {
    let title: String
    let path: String?
    let stateTitle: String
    let summary: String
    let accentColor: Color
    let primaryActionTitle: String
    let onPrimaryAction: () -> Void
    var primaryActionDisabled = false
    let secondaryActionTitle: String?
    let onSecondaryAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(stateTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accentColor.opacity(0.12), in: Capsule())
            }

            Text(path ?? "No folder selected")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(path == nil ? .secondary : .primary)
                .textSelection(.enabled)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Button(primaryActionTitle, action: onPrimaryAction)
                    .disabled(primaryActionDisabled)

                if let secondaryActionTitle, let onSecondaryAction {
                    Button(secondaryActionTitle, action: onSecondaryAction)
                        .buttonStyle(.link)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}
