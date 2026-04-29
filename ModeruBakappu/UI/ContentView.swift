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
                    modeSwitcher
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .underPageBackgroundColor))

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

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        selectedMode == mode
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                    .foregroundStyle(
                        selectedMode == mode
                            ? Color.accentColor
                            : Color.secondary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
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
