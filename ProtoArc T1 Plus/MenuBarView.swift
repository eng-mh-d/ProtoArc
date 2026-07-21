//
//  MenuBarView.swift
//  ProtoArc T1 Plus
//
//  Menu bar status item and quick controls.
//

import AppKit
import SwiftUI

enum AppStartup {
    private static var didRun = false

    static func run(controller: TouchpadController) {
        guard !didRun else { return }
        didRun = true

        _ = Permissions.requestInputMonitoring()
        LaunchAtLogin.sync(with: controller.settings.launchAtLogin)
        if controller.settings.autoStartDriver, !controller.isRunning {
            Task { @MainActor in
                guard SerialManager.shared.isLicensed else { return }
                controller.start()
            }
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var controller: TouchpadController
    @ObservedObject private var serials = SerialManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Text("ProtoArc T1 Plus")
                .font(.headline)

            Text(controller.state.description)
                .foregroundStyle(.secondary)

            if serials.isLicensed {
                Text(serials.status.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("License required")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()

            Button(controller.isRunning ? "Stop Driver" : "Start Driver") {
                if controller.isRunning {
                    controller.stop()
                } else if serials.isLicensed {
                    controller.start()
                } else {
                    openWindow(id: "welcome")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }

            if !serials.isLicensed {
                Button("Welcome & License…") {
                    openWindow(id: "welcome")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }

            Button("User guide (browser)…") {
                if let url = Bundle.main.url(forResource: "UserGuide", withExtension: "html") {
                    NSWorkspace.shared.open(url)
                }
            }

            Button("Settings…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }

            Divider()

            Button("Quit") {
                if controller.isRunning { controller.stop() }
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            controller.unstickPointer()
            if !serials.isLicensed {
                openWindow(id: "welcome")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .onDisappear { controller.unstickPointer() }
    }
}

struct MenuBarIcon: View {
    let state: ConnectionState

    var body: some View {
        Image(systemName: "rectangle.and.hand.point.up.left.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(iconColor, .primary)
    }

    private var iconColor: Color {
        switch state {
        case .connected: return .green
        case .waitingForDevice: return .orange
        case .error: return .red
        case .stopped: return .gray
        }
    }
}
