//
//  DashboardView.swift
//  ModeruBakappu
//
//  Created by Codex on 2026/4/19.
//

import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedProvider: ModelProvider = .lmStudio
    @State private var pendingActionSheet: ModelActionSheet?

    private var selectedConfiguration: ModelSourceConfiguration? {
        appModel.sourceConfigurations.first { $0.provider == selectedProvider }
            ?? appModel.sourceConfigurations.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                providerSidebar
                    .frame(width: 260)
                    .background(Color(nsColor: .underPageBackgroundColor))

                Divider()

                selectedProviderContent
            }
        }
        .onAppear {
            if !appModel.sourceConfigurations.contains(where: { $0.provider == selectedProvider }),
               let firstProvider = appModel.sourceConfigurations.first?.provider {
                selectedProvider = firstProvider
            }
        }
        .sheet(item: $pendingActionSheet) { sheet in
            switch sheet {
            case let .backup(request):
                ModelActionPlanSheet(
                    preview: planPreview(for: .backup, request: request),
                    onCancel: { pendingActionSheet = nil },
                    onConfirm: {
                        pendingActionSheet = nil
                        appModel.backup(model: request.model)
                    }
                )
            case let .archive(request):
                ModelActionPlanSheet(
                    preview: planPreview(for: .archive, request: request),
                    onCancel: { pendingActionSheet = nil },
                    onConfirm: {
                        pendingActionSheet = nil
                        appModel.archive(model: request.model)
                    }
                )
            case let .restore(request):
                ModelActionPlanSheet(
                    preview: planPreview(for: .restore, request: request),
                    onCancel: { pendingActionSheet = nil },
                    onConfirm: {
                        pendingActionSheet = nil
                        appModel.restore(model: request.model)
                    }
                )
            case let .deleteLocal(request):
                ModelActionPlanSheet(
                    preview: planPreview(for: .deleteLocal, request: request),
                    onCancel: { pendingActionSheet = nil },
                    onConfirm: {
                        pendingActionSheet = nil
                        appModel.deleteLocalCopy(model: request.model)
                    }
                )
            case let .deleteBackup(request):
                ModelActionPlanSheet(
                    preview: planPreview(for: .deleteBackup, request: request),
                    onCancel: { pendingActionSheet = nil },
                    onConfirm: {
                        pendingActionSheet = nil
                        appModel.deleteBackup(model: request.model)
                    }
                )
            }
        }
    }

    private var providerSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sources")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 18)

            VStack(spacing: 8) {
                ForEach(appModel.sourceConfigurations) { configuration in
                    ProviderSidebarRow(
                        configuration: configuration,
                        isSelected: selectedProvider == configuration.provider,
                        accessColor: color(for: configuration.accessState),
                        onSelect: {
                            guard configuration.provider.isEnabled else { return }
                            selectedProvider = configuration.provider
                        },
                        onChooseFolder: {
                            guard configuration.provider.isEnabled else { return }
                            selectedProvider = configuration.provider
                            appModel.selectSourceFolder(for: configuration.provider)
                        }
                    )
                }
            }
            .padding(.horizontal, 10)

            Spacer()
        }
    }

    @ViewBuilder
    private var selectedProviderContent: some View {
        if let configuration = selectedConfiguration {
            VStack(alignment: .leading, spacing: 0) {
                ProviderDetailHeader(
                    configuration: configuration,
                    accessColor: color(for: configuration.accessState),
                    backupRootPath: appModel.backupFolderURL?.path,
                    onChooseFolder: { appModel.selectSourceFolder(for: configuration.provider) },
                    onRefresh: { appModel.refreshModelDiscovery() }
                )
                .padding(24)

                Divider()

                ModelListView(
                    configuration: configuration,
                    models: appModel.displayModels(for: configuration),
                    lifecycleStatus: { appModel.lifecycleStatus(for: $0) },
                    onBackup: { pendingActionSheet = .backup(ModelActionRequest(provider: configuration.provider, model: $0)) },
                    onArchive: { pendingActionSheet = .archive(ModelActionRequest(provider: configuration.provider, model: $0)) },
                    onRestore: { pendingActionSheet = .restore(ModelActionRequest(provider: configuration.provider, model: $0)) },
                    onDeleteLocal: { pendingActionSheet = .deleteLocal(ModelActionRequest(provider: configuration.provider, model: $0)) },
                    onDeleteBackup: { model in
                        let record = appModel.backupRecords[model.id]
                        pendingActionSheet = .deleteBackup(
                            ModelActionRequest(
                                provider: configuration.provider,
                                model: model,
                                backupRelativePath: record?.backupRelativePath,
                                requiresTypedConfirmation: record?.effectiveLocalState == .archived
                            )
                        )
                    },
                    onRevealLocal: { appModel.revealLocalModel($0) },
                    onRevealBackup: { appModel.revealBackup(for: $0) }
                )
            }
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

    private func planPreview(for kind: ModelActionKind, request: ModelActionRequest) -> ModelActionPlanPreview {
        let model = request.model
        let backupRootPath = appModel.backupFolderURL?.path
        let backupRelativePath = request.backupRelativePath
            ?? appModel.backupRecords[model.id]?.backupRelativePath
            ?? "\(request.provider.backupDirectoryName)/\(model.relativePath)"
        let backupPath = backupRootPath.map { "\($0)/\(backupRelativePath)" } ?? backupRelativePath
        let existingRecord = appModel.backupRecords[model.id]
        let sizeDescription = existingRecord.map {
            ByteCountFormatter.string(fromByteCount: $0.sizeBytes, countStyle: .file)
        } ?? model.sizeDescription
        let fileCountDescription = existingRecord.map {
            $0.fileCount == 1 ? "1 file" : "\($0.fileCount) files"
        } ?? model.fileCountDescription

        switch kind {
        case .backup:
            return ModelActionPlanPreview(
                kind: kind,
                provider: request.provider,
                model: model,
                sourcePath: model.folderURL.path,
                destinationPath: backupPath,
                sizeDescription: sizeDescription,
                fileCountDescription: fileCountDescription,
                note: "The provider-usable model stays on this Mac.",
                steps: [
                    "Copy the model folder to the backup drive.",
                    "Verify copied file count and size.",
                    "Save the backup record.",
                    "Keep the local runtime model in place."
                ]
            )
        case .archive:
            let firstStep = existingRecord == nil
                ? "Copy the model folder to the backup drive."
                : "Verify the existing backup payload on the backup drive."
            return ModelActionPlanPreview(
                kind: kind,
                provider: request.provider,
                model: model,
                sourcePath: model.folderURL.path,
                destinationPath: backupPath,
                sizeDescription: sizeDescription,
                fileCountDescription: fileCountDescription,
                note: "The local runtime model will be removed only after backup verification.",
                steps: [
                    firstStep,
                    "Verify file count and size.",
                    "Save the backup record.",
                    "Remove the local runtime model from this Mac."
                ]
            )
        case .restore:
            return ModelActionPlanPreview(
                kind: kind,
                provider: request.provider,
                model: model,
                sourcePath: backupPath,
                destinationPath: model.folderURL.path,
                sizeDescription: sizeDescription,
                fileCountDescription: fileCountDescription,
                note: "The archived backup remains on the backup drive.",
                steps: [
                    "Verify the backup payload on the backup drive.",
                    "Copy the model back into the provider model folder.",
                    "Verify restored file count and size.",
                    "Mark the model as available locally."
                ]
            )
        case .deleteLocal:
            return ModelActionPlanPreview(
                kind: kind,
                provider: request.provider,
                model: model,
                sourcePath: model.folderURL.path,
                destinationPath: backupPath,
                sizeDescription: sizeDescription,
                fileCountDescription: fileCountDescription,
                note: "The verified backup remains available on the backup drive.",
                steps: [
                    "Verify the backup payload on the backup drive.",
                    "Remove the local runtime model folder from this Mac.",
                    "Update the backup record as archived."
                ]
            )
        case .deleteBackup:
            return ModelActionPlanPreview(
                kind: kind,
                provider: request.provider,
                model: model,
                sourcePath: backupPath,
                destinationPath: "Removed from backup drive",
                sizeDescription: sizeDescription,
                fileCountDescription: fileCountDescription,
                note: request.requiresTypedConfirmation ? "This may remove the only known copy." : "The local runtime model remains on this Mac.",
                steps: [
                    "Verify the backup payload on the backup drive.",
                    "Remove the backup payload from the selected backup root.",
                    "Remove the backup record from the local index."
                ],
                requiresTypedConfirmation: request.requiresTypedConfirmation
            )
        }
    }
}

private struct ModelActionRequest: Identifiable {
    let provider: ModelProvider
    let model: DiscoveredModel
    var backupRelativePath: String?
    var requiresTypedConfirmation = false

    var id: String {
        "\(provider.rawValue):\(model.id):\(requiresTypedConfirmation)"
    }
}

private enum ModelActionKind {
    case backup
    case archive
    case restore
    case deleteLocal
    case deleteBackup

    var title: String {
        switch self {
        case .backup:
            return "Back Up Model?"
        case .archive:
            return "Archive Model?"
        case .restore:
            return "Restore Model?"
        case .deleteLocal:
            return "Delete Local Model?"
        case .deleteBackup:
            return "Delete Backup?"
        }
    }

    var subtitle: String {
        switch self {
        case .backup:
            return "Create a verified duplicate on the backup drive."
        case .archive:
            return "Free space on this Mac after backup verification."
        case .restore:
            return "Copy the archived model back to this Mac."
        case .deleteLocal:
            return "Remove provider-usable files from this Mac."
        case .deleteBackup:
            return "Remove the backup payload from the backup drive."
        }
    }

    var confirmTitle: String {
        switch self {
        case .backup:
            return "Back Up"
        case .archive:
            return "Archive"
        case .restore:
            return "Restore"
        case .deleteLocal:
            return "Delete Local Model"
        case .deleteBackup:
            return "Delete Backup"
        }
    }

    var systemImage: String {
        switch self {
        case .backup:
            return "externaldrive.badge.plus"
        case .archive:
            return "archivebox"
        case .restore:
            return "arrow.down.doc"
        case .deleteLocal:
            return "trash"
        case .deleteBackup:
            return "externaldrive.badge.minus"
        }
    }

    var tint: Color {
        switch self {
        case .backup, .restore:
            return .blue
        case .archive, .deleteLocal, .deleteBackup:
            return .red
        }
    }

    var isDestructive: Bool {
        switch self {
        case .archive, .deleteLocal, .deleteBackup:
            return true
        case .backup, .restore:
            return false
        }
    }
}

private struct ModelActionPlanPreview {
    let kind: ModelActionKind
    let provider: ModelProvider
    let model: DiscoveredModel
    let sourcePath: String
    let destinationPath: String
    let sizeDescription: String
    let fileCountDescription: String
    let note: String
    let steps: [String]
    var requiresTypedConfirmation = false
}

private enum ModelActionSheet: Identifiable {
    case backup(ModelActionRequest)
    case archive(ModelActionRequest)
    case restore(ModelActionRequest)
    case deleteLocal(ModelActionRequest)
    case deleteBackup(ModelActionRequest)

    var id: String {
        switch self {
        case let .backup(request):
            return "backup:\(request.id)"
        case let .archive(request):
            return "archive:\(request.id)"
        case let .restore(request):
            return "restore:\(request.id)"
        case let .deleteLocal(request):
            return "delete-local:\(request.id)"
        case let .deleteBackup(request):
            return "delete-backup:\(request.id)"
        }
    }
}

private struct ModelActionPlanSheet: View {
    let preview: ModelActionPlanPreview
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var confirmationText = ""

    private var canConfirm: Bool {
        !preview.requiresTypedConfirmation || confirmationText == "DELETE"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: preview.kind.systemImage)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(preview.kind.tint.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.kind.title)
                        .font(.title3.weight(.semibold))
                    Text(preview.kind.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ModelActionInfoFrame(provider: preview.provider, model: preview.model)

            PlanPathGrid(preview: preview)

            VStack(alignment: .leading, spacing: 8) {
                Text("Plan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(preview.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(preview.kind.tint.opacity(0.85), in: Circle())
                            Text(step)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(preview.note)
                .font(.callout)
                .foregroundStyle(preview.kind.isDestructive ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            if preview.requiresTypedConfirmation {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type DELETE to confirm.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("DELETE", text: $confirmationText)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                if preview.kind.isDestructive {
                    Button(preview.kind.confirmTitle, role: .destructive, action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canConfirm)
                } else {
                    Button(preview.kind.confirmTitle, action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canConfirm)
                }
            }
        }
        .padding(24)
        .frame(width: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PlanPathGrid: View {
    let preview: ModelActionPlanPreview

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 9) {
            PlanRow(title: "Source", value: preview.sourcePath)
            PlanRow(title: "Destination", value: preview.destinationPath)
            PlanRow(title: "Size", value: preview.sizeDescription)
            PlanRow(title: "Files", value: preview.fileCountDescription)
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PlanRow: View {
    let title: String
    let value: String

    var body: some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct ModelActionInfoFrame: View {
    let provider: ModelProvider
    let model: DiscoveredModel
    var pathTitle = "Path"
    var pathValue: String?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 9) {
            GridRow {
                Text("Provider")
                    .foregroundStyle(.secondary)
                Text(provider.displayName)
                    .fontWeight(.semibold)
            }

            GridRow {
                Text("Model")
                    .foregroundStyle(.secondary)
                Text(model.displayName)
                    .fontWeight(.semibold)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            GridRow {
                Text(pathTitle)
                    .foregroundStyle(.secondary)
                Text(pathValue ?? model.relativePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.24))
            )
    }
}

private struct ProviderSidebarRow: View {
    let configuration: ModelSourceConfiguration
    let isSelected: Bool
    let accessColor: Color
    let onSelect: () -> Void
    let onChooseFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                ProviderBadge(provider: configuration.provider, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(configuration.provider.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(configuration.provider.isEnabled ? .primary : .secondary)
                    Text(statusTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(accessColor)
                    .frame(width: 7, height: 7)
                Text(configuration.accessState.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Folder", action: onChooseFolder)
                    .font(.caption)
                    .buttonStyle(.link)
                    .disabled(!configuration.provider.isEnabled)
            }

            Text(folderSummary)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.32) : Color.primary.opacity(0.08))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .opacity(configuration.provider.isEnabled ? 1 : 0.48)
        .help(configuration.provider.disabledReason ?? configuration.accessState.summary)
    }

    private var statusTitle: String {
        configuration.provider.disabledReason ?? configuration.discoveryState.title
    }

    private var folderSummary: String {
        if let disabledReason = configuration.provider.disabledReason {
            return disabledReason
        }
        return configuration.folderURL?.lastPathComponent ?? "No folder selected"
    }
}

private struct ProviderDetailHeader: View {
    let configuration: ModelSourceConfiguration
    let accessColor: Color
    let backupRootPath: String?
    let onChooseFolder: () -> Void
    let onRefresh: () -> Void

    var providerBackupPath: String {
        guard let backupRootPath else {
            return "Backup root not configured"
        }
        return "\(backupRootPath)/\(configuration.provider.backupDirectoryName)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                HStack(spacing: 16) {
                    ProviderBadge(provider: configuration.provider, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(configuration.provider.displayName)
                            .font(.title2.weight(.semibold))
                        Text(configuration.accessState.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Choose Folder", action: onChooseFolder)
                    .disabled(!configuration.provider.isEnabled)
                Button("Refresh Scan", action: onRefresh)
                    .disabled(!configuration.provider.isEnabled || configuration.discoveryState == .scanning || configuration.discoveryState == .unavailable)
            }

            HStack(spacing: 12) {
                PathSummary(
                    title: "Model Folder",
                    value: configuration.folderURL?.path ?? "Not configured",
                    color: accessColor
                )
                PathSummary(
                    title: "Backup Namespace",
                    value: providerBackupPath,
                    color: .blue
                )
            }
        }
    }
}

private struct ModelListView: View {
    let configuration: ModelSourceConfiguration
    let models: [DiscoveredModel]
    let lifecycleStatus: (DiscoveredModel) -> ModelLifecycleStatus
    let onBackup: (DiscoveredModel) -> Void
    let onArchive: (DiscoveredModel) -> Void
    let onRestore: (DiscoveredModel) -> Void
    let onDeleteLocal: (DiscoveredModel) -> Void
    let onDeleteBackup: (DiscoveredModel) -> Void
    let onRevealLocal: (DiscoveredModel) -> Void
    let onRevealBackup: (DiscoveredModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Model")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Local")
                    .frame(width: 150, alignment: .leading)
                Text("Lifecycle")
                    .frame(width: 210, alignment: .leading)
                Text("Action")
                    .frame(width: 120, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)

            Divider()

            if models.isEmpty {
                switch configuration.discoveryState {
                case .idle, .scanning, .unavailable, .empty:
                    EmptyModelState(message: configuration.discoveryState.summary)
                case let .failed(message):
                    EmptyModelState(message: message)
                case .ready:
                    EmptyModelState(message: configuration.discoveryState.summary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(models) { model in
                            ProviderModelRow(
                                model: model,
                                provider: configuration.provider,
                                lifecycleStatus: lifecycleStatus(model),
                                onBackup: { onBackup(model) },
                                onArchive: { onArchive(model) },
                                onRestore: { onRestore(model) },
                                onDeleteLocal: { onDeleteLocal(model) },
                                onDeleteBackup: { onDeleteBackup(model) },
                                onRevealLocal: { onRevealLocal(model) },
                                onRevealBackup: { onRevealBackup(model) }
                            )
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct ProviderModelRow: View {
    let model: DiscoveredModel
    let provider: ModelProvider
    let lifecycleStatus: ModelLifecycleStatus
    let onBackup: () -> Void
    let onArchive: () -> Void
    let onRestore: () -> Void
    let onDeleteLocal: () -> Void
    let onDeleteBackup: () -> Void
    let onRevealLocal: () -> Void
    let onRevealBackup: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.subheadline.weight(.semibold))
                    if let publisher = model.publisher {
                        Text(publisher)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }

                Text(model.relativePath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.sizeDescription)
                Text(model.fileCountDescription)
                if let lastModified = model.lastModified {
                    Text(lastModified, style: .date)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 150, alignment: .leading)

            LifecycleStatusSummary(provider: provider, status: lifecycleStatus)
                .frame(width: 210, alignment: .leading)

            ModelActionMenu(
                status: lifecycleStatus,
                onBackup: onBackup,
                onArchive: onArchive,
                onRestore: onRestore,
                onDeleteLocal: onDeleteLocal,
                onDeleteBackup: onDeleteBackup,
                onRevealLocal: onRevealLocal,
                onRevealBackup: onRevealBackup
            )
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

private struct ModelActionMenu: View {
    let status: ModelLifecycleStatus
    let onBackup: () -> Void
    let onArchive: () -> Void
    let onRestore: () -> Void
    let onDeleteLocal: () -> Void
    let onDeleteBackup: () -> Void
    let onRevealLocal: () -> Void
    let onRevealBackup: () -> Void

    var body: some View {
        Menu {
            Button(status.backupState.buttonTitle, action: onBackup)
                .disabled(!status.backupState.canTriggerBackup)
                .help("Copy this model to the backup drive. The local model stays on this Mac.")

            Divider()

            Button("Reveal Local", action: onRevealLocal)
                .help("Open the local model folder in Finder.")
            Button("Reveal Backup", action: onRevealBackup)
                .disabled(!status.hasBackupDestination)
                .help("Open this model's backup folder in Finder.")

            Divider()

            Button("Archive", action: onArchive)
                .disabled(!status.canTriggerArchive)
                .help("Copy and verify this model on the backup drive, then remove the local model to free space.")
            Button("Restore", action: onRestore)
                .disabled(!status.canTriggerRestore)
                .help("Copy the archived model back to this Mac from the backup drive.")

            Divider()

            Button("Delete Local Model", role: .destructive, action: onDeleteLocal)
                .disabled(!status.canDeleteLocalCopy)
                .help("Remove the provider-usable model files from this Mac. The verified backup remains available.")
            Button("Delete Backup", role: .destructive, action: onDeleteBackup)
                .disabled(!status.canDeleteBackup)
                .help("Remove only the backup copy from the selected backup drive.")
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
    }
}

private struct LifecycleStatusSummary: View {
    let provider: ModelProvider
    let status: ModelLifecycleStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if status.providerReadiness != .ready {
                HStack(spacing: 5) {
                    Image(systemName: providerReadinessIcon)
                        .font(.caption2.weight(.semibold))
                    Text(status.providerReadiness.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(providerReadinessColor)
                .help(providerReadinessHelpText)
            }
        }
        .help(helpText)
    }

    private var title: String {
        status.state.title
    }

    private var subtitle: String {
        switch status.state {
        case .localOnly:
            return "Maps to /\(provider.backupDirectoryName)"
        default:
            return status.state.summary
        }
    }

    private var helpText: String {
        let readinessSuffix: String
        if status.providerReadiness == .ready {
            readinessSuffix = ""
        } else {
            readinessSuffix = "\n\n\(providerReadinessHelpText)"
        }

        switch status.state {
        case .localOnly:
            return "This model exists only on this Mac. Back Up creates a duplicate on the backup drive." + readinessSuffix
        case .backedUp:
            return "A verified backup exists, and the model is still available locally." + readinessSuffix
        case let .backupConflict(conflict):
            return "A folder already exists at the planned backup destination, but it does not match this local model.\n\n\(conflict.summary)" + readinessSuffix
        case .backupUnavailable:
            return "Backup and archive actions require a reachable writable backup drive." + readinessSuffix
        case .backingUp:
            return "ModeruBakappu is copying and verifying the backup. The local model remains in place." + readinessSuffix
        case let .backupFailed(message):
            return "Backup failed: \(message)" + readinessSuffix
        case .archiving:
            return "ModeruBakappu is ensuring a verified backup exists, then it will remove the local model." + readinessSuffix
        case let .archiveFailed(message):
            return "Archive failed: \(message)" + readinessSuffix
        case .archived:
            return "The local model was removed after backup verification." + readinessSuffix
        case .restoring:
            return "ModeruBakappu is copying the archived model back to this Mac and verifying it." + readinessSuffix
        case let .restoreFailed(message):
            return "Restore failed: \(message)" + readinessSuffix
        case .deletingLocal:
            return "ModeruBakappu is removing the local model folder. The verified backup remains available." + readinessSuffix
        case let .deleteLocalFailed(message):
            return "Delete local model failed: \(message)" + readinessSuffix
        case .deletingBackup:
            return "ModeruBakappu is removing the backup payload from the selected backup drive." + readinessSuffix
        case let .deleteBackupFailed(message):
            return "Delete backup failed: \(message)" + readinessSuffix
        case .restorable:
            return "This model is archived: the local model was removed, and Restore copies it back from the backup drive." + readinessSuffix
        case .missingBackupDrive:
            return "This model is archived, but the backup drive is not currently available." + readinessSuffix
        case let .restoreConflict(message):
            return "Restore conflict: \(message)" + readinessSuffix
        case let .providerNotReady(message):
            return "Provider is not ready: \(message)" + readinessSuffix
        case let .unknown(message):
            return message + readinessSuffix
        }
    }

    private var providerReadinessHelpText: String {
        switch status.providerReadiness {
        case .ready:
            return "Provider readiness is confirmed."
        case let .notReady(message):
            return "Provider is not ready: \(message)"
        case let .unknown(message):
            return "Provider readiness is unknown: \(message)"
        }
    }

    private var providerReadinessIcon: String {
        switch status.providerReadiness {
        case .ready:
            return "checkmark.circle"
        case .notReady:
            return "exclamationmark.triangle"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var providerReadinessColor: Color {
        switch status.providerReadiness {
        case .ready:
            return .green
        case .notReady:
            return .red
        case .unknown:
            return .orange
        }
    }

    private var color: Color {
        switch status.state {
        case .backupConflict, .backupFailed, .archiveFailed, .restoreFailed, .deleteLocalFailed, .deleteBackupFailed, .restoreConflict, .providerNotReady:
            return .red
        case .backingUp, .archiving, .restoring, .deletingLocal, .deletingBackup:
            return .orange
        case .backedUp:
            return .green
        case .archived, .restorable:
            return .blue
        case .localOnly, .backupUnavailable, .missingBackupDrive, .unknown:
            return .secondary
        }
    }
}

private struct EmptyModelState: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

private struct PathSummary: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct ProviderBadge: View {
    let provider: ModelProvider
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color)

            if let assetName {
                Image(assetName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFill()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous))
                    .accessibilityLabel(provider.displayName)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }

    private var cornerRadius: CGFloat {
        size * 0.24
    }

    private var iconSize: CGFloat {
        switch provider {
        case .lmStudio, .omlx:
            return size
        case .ollama, .custom:
            return size * 0.62
        }
    }

    private var iconCornerRadius: CGFloat {
        switch provider {
        case .lmStudio, .omlx:
            return cornerRadius
        case .ollama, .custom:
            return 0
        }
    }

    private var assetName: String? {
        switch provider {
        case .lmStudio:
            return "ProviderLMStudio"
        case .omlx:
            return "ProviderOMLX"
        case .ollama:
            return "ProviderOllama"
        case .custom:
            return nil
        }
    }

    private var initials: String {
        switch provider {
        case .lmStudio:
            return "LM"
        case .omlx:
            return "OX"
        case .ollama:
            return "OL"
        case .custom:
            return "CS"
        }
    }

    private var color: Color {
        switch provider {
        case .lmStudio, .omlx:
            return .clear
        case .ollama:
            return .gray
        case .custom:
            return .gray
        }
    }
}
