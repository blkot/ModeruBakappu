//
//  ContentView.swift
//  ModeruBakappu
//

import SwiftUI

enum AppMode: String, CaseIterable {
    case backup = "Backup"
    case discover = "Discover"

    var systemImage: String {
        switch self {
        case .backup: return "externaldrive"
        case .discover: return "magnifyingglass"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedMode: AppMode = .backup

    var body: some View {
        Group {
            if !appModel.hasLoaded {
                ProgressView("Loading configuration…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appModel.hasMinimumConfiguration {
                VStack(spacing: 0) {
                    appChrome
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.bar)

                    Divider()

                    switch selectedMode {
                    case .backup:
                        DashboardView()
                    case .discover:
                        CatalogView(viewModel: appModel.catalogViewModel)
                    }
                }
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .alert("Configuration Error", isPresented: alertBinding) {
            Button("OK") {
                appModel.clearError()
            }
        } message: {
            Text(appModel.errorMessage ?? "")
        }
    }

    private var appChrome: some View {
        HStack(alignment: .center, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ModeruBakappu")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("\(appModel.configuredSourceCount) sources, \(appModel.discoveredModelCount) models")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 190, alignment: .leading)

                modeSwitcher
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                CompactDriveStatus(
                    title: "Backup",
                    iconName: "externaldrive",
                    statusTitle: appModel.backupDriveState.title,
                    path: appModel.backupFolderURL?.path,
                    spaceInfo: appModel.backupDriveSpaceInfo,
                    unavailableSpaceText: appModel.backupDriveState == .notConfigured ? "No root" : "Unavailable",
                    accentColor: color(for: appModel.backupDriveState),
                    onChange: { appModel.selectBackupFolder() }
                )

                CompactDriveStatus(
                    title: "Mac",
                    iconName: "internaldrive",
                    statusTitle: appModel.mainDriveSpaceInfo == nil ? "Unavailable" : "Online",
                    path: appModel.mainDriveSpaceInfo?.volumePath,
                    spaceInfo: appModel.mainDriveSpaceInfo,
                    unavailableSpaceText: "Unavailable",
                    accentColor: appModel.mainDriveSpaceInfo == nil ? .secondary : .blue,
                    onChange: nil
                )

                Button {
                    appModel.refreshStatuses()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Refresh")
            }
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(AppMode.allCases, id: \.self) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.systemImage)
                            .font(.caption)
                        Text(mode.rawValue)
                            .font(.caption.weight(.medium))
                    }
                    .frame(width: 116, height: 38)
                    .background(
                        selectedMode == mode
                            ? Color.accentColor.opacity(0.16)
                            : Color.clear
                    )
                    .foregroundStyle(
                        selectedMode == mode
                            ? Color.accentColor
                            : Color.secondary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
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

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { appModel.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appModel.clearError()
                }
            }
        )
    }
}

private struct CompactDriveStatus: View {
    let title: String
    let iconName: String
    let statusTitle: String
    let path: String?
    let spaceInfo: BackupDriveSpaceInfo?
    let unavailableSpaceText: String
    let accentColor: Color
    let onChange: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accentColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Text(statusTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accentColor)
                        .lineLimit(1)
                }

                HStack(spacing: 7) {
                    if let spaceInfo {
                        ProgressView(value: spaceInfo.usedFraction)
                            .tint(spaceTint)
                            .frame(width: 58)
                        Text("\(spaceInfo.availableDescription) free")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text(unavailableSpaceText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            if let onChange {
                Button(action: onChange) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Change backup root")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 210, alignment: .leading)
        .frame(minHeight: 48)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .help(path ?? "No folder selected")
    }

    private var spaceTint: Color {
        guard let usedFraction = spaceInfo?.usedFraction else { return .secondary }
        if usedFraction > 0.9 {
            return .red
        }
        if usedFraction > 0.75 {
            return .orange
        }
        return .green
    }
}
