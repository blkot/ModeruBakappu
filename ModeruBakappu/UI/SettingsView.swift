//
//  SettingsView.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Form {
            Section("Source Access") {
                LabeledContent("\(appModel.sourceDisplayName) Folder") {
                    Text(appModel.lmStudioFolderURL?.path ?? "Not configured")
                        .foregroundStyle(appModel.lmStudioFolderURL == nil ? .secondary : .primary)
                }

                LabeledContent("Source Status") {
                    Text(appModel.lmStudioAccessState.title)
                }

                HStack {
                    Button("Choose Models Folder") {
                        appModel.selectLMStudioFolder()
                    }
                }
            }

            Section("Backup Destination") {
                LabeledContent("Backup Root") {
                    Text(appModel.backupFolderURL?.path ?? "Not configured")
                        .foregroundStyle(appModel.backupFolderURL == nil ? .secondary : .primary)
                }

                LabeledContent("Drive Status") {
                    Text(appModel.backupDriveState.title)
                }

                HStack {
                    Button("Choose Backup Root") {
                        appModel.selectBackupFolder()
                    }
                    Button("Revalidate") {
                        appModel.refreshStatuses()
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 680)
    }
}
