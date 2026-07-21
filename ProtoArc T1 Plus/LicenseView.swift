//
//  LicenseView.swift
//  ProtoArc T1 Plus
//

import SwiftUI

/// Shared serial entry + activate (Settings sidebar + welcome window).
struct SerialActivationForm: View {
    @ObservedObject private var serials = SerialManager.shared
    @State private var input = ""
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Serial number", text: $input)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())

            HStack {
                Button("Activate") { activate() }
                    .buttonStyle(.borderedProminent)
                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(serials.isLicensed ? .green : .orange)
                }
            }
        }
        .frame(maxWidth: 360)
        .onChange(of: serials.isLicensed) { _, licensed in
            if licensed { message = "" }
        }
    }

    private func activate() {
        let result = serials.activate(serial: input)
        message = result.message
        if result.isValid {
            input = ""
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct LicenseSection: View {
    @ObservedObject private var serials = SerialManager.shared
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("License")
                .font(.headline)

            if serials.isLicensed {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(serials.status.serial)
                            .font(.caption.monospaced())
                        Text(serials.status.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Deactivate") {
                    serials.deactivate()
                    message = "License removed"
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text("Enter a serial from SerialNumbers.txt to use the driver.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SerialActivationForm()

                if !message.isEmpty {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

/// Compact gate (e.g. previews). Prefer `WelcomeFlowView` in the app window.
struct LicenseGateView: View {
    @ObservedObject private var serials = SerialManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Activate ProtoArc T1 Plus")
                .font(.title2.bold())

            Text("A valid weekly or active serial is required.")
                .foregroundStyle(.secondary)

            SerialActivationForm()

            if serials.isLicensed {
                Text("Licensed — you can close this window.")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(32)
        .frame(width: 420, height: 280)
    }
}
