//
//  OnboardingView.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set Up ModeruBakappu")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("The app will try to detect supported model folders automatically. You can still override any detected source or choose folders manually before backups begin.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                ForEach(appModel.sourceConfigurations) { configuration in
                    FolderStatusCard(
                        title: "\(configuration.provider.displayName) Models Folder",
                        path: configuration.folderURL?.path,
                        stateTitle: configuration.accessState.title,
                        summary: configuration.provider.disabledReason ?? configuration.accessState.summary,
                        accentColor: color(for: configuration.accessState),
                        primaryActionTitle: configuration.folderURL == nil ? "Choose Folder" : "Change Folder",
                        onPrimaryAction: { appModel.selectSourceFolder(for: configuration.provider) },
                        primaryActionDisabled: !configuration.provider.isEnabled,
                        secondaryActionTitle: nil,
                        onSecondaryAction: nil as (() -> Void)?
                    )
                    .opacity(configuration.provider.isEnabled ? 1 : 0.52)
                    .help(configuration.provider.disabledReason ?? configuration.accessState.summary)
                }

                FolderStatusCard(
                    title: "Backup Root",
                    path: appModel.backupFolderURL?.path,
                    stateTitle: appModel.backupDriveState.title,
                    summary: appModel.backupDriveSummary,
                    accentColor: color(for: appModel.backupDriveState),
                    primaryActionTitle: appModel.backupFolderURL == nil ? "Choose Backup Root" : "Change Backup Root",
                    onPrimaryAction: { appModel.selectBackupFolder() },
                    secondaryActionTitle: nil,
                    onSecondaryAction: nil as (() -> Void)?
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("What happens next")
                        .font(.headline)
                    Text("Once both folders are configured, the app will switch to the main shell. Source detection stays editable, and backup execution remains gated on the backup drive state.")
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(32)
        }
    }

    private func color(for state: SourceAccessState) -> Color {
        switch state {
        case .ready:
            return .green
        case .staleBookmark:
            return .orange
        case .notConfigured, .inaccessible:
            return .secondary
        }
    }

    private func color(for state: BackupDriveState) -> Color {
        switch state {
        case .online:
            return .green
        case .staleBookmark:
            return .orange
        case .readOnly:
            return .yellow
        case .permissionDenied:
            return .red
        case .notConfigured, .offline:
            return .secondary
        }
    }
}
