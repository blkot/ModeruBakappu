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
                    Text("Choose the folders this app is allowed to use before model discovery or backups begin. The app does not inspect other apps' Library data automatically.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                FolderStatusCard(
                    title: "LM Studio Models Folder",
                    path: appModel.lmStudioFolderURL?.path,
                    stateTitle: appModel.lmStudioAccessState.title,
                    summary: appModel.lmStudioAccessState.summary,
                    accentColor: color(for: appModel.lmStudioAccessState),
                    primaryActionTitle: appModel.lmStudioFolderURL == nil ? "Choose Folder" : "Change Folder",
                    onPrimaryAction: { appModel.selectLMStudioFolder() },
                    secondaryActionTitle: nil,
                    onSecondaryAction: nil as (() -> Void)?
                )

                FolderStatusCard(
                    title: "Backup Root",
                    path: appModel.backupFolderURL?.path,
                    stateTitle: appModel.backupDriveState.title,
                    summary: appModel.backupDriveState.summary,
                    accentColor: color(for: appModel.backupDriveState),
                    primaryActionTitle: appModel.backupFolderURL == nil ? "Choose Backup Root" : "Change Backup Root",
                    onPrimaryAction: { appModel.selectBackupFolder() },
                    secondaryActionTitle: nil,
                    onSecondaryAction: nil as (() -> Void)?
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("What happens next")
                        .font(.headline)
                    Text("Once both folders are configured, the app will switch to the main shell. Model discovery and backup execution will be added in the next phase.")
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
