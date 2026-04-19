//
//  ContentView.swift
//  ModeruBakappu
//
//  Created by wangshenhao on 2026/4/19.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        Group {
            if !appModel.hasLoaded {
                ProgressView("Loading configuration…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if appModel.hasMinimumConfiguration {
                DashboardView()
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .alert("Configuration Error", isPresented: alertBinding) {
            Button("OK") {
                appModel.clearError()
            }
        } message: {
            Text(appModel.errorMessage ?? "")
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
