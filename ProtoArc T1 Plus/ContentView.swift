//
//  ContentView.swift
//  ProtoArc T1 Plus
//
//  User-space touchpad driver UI.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: TouchpadController
    @State private var refreshTick = false

    init(controller: TouchpadController) {
        self.controller = controller
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(controller: controller, refreshTick: refreshTick, toggle: toggle, bump: bump)
                .frame(width: 320)
                .background(.regularMaterial)

            Divider()

            TouchPanel(ui: controller.uiState)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 880, minHeight: 600)
        .onAppear { controller.settingsWindowDidOpen() }
        .onDisappear { controller.settingsWindowDidClose() }
        .onChange(of: controller.uiState.logging) { controller.hidCachesDidChange() }
        .onChange(of: controller.settings.layoutRawValue) { controller.hidCachesDidChange() }
    }

    private func toggle() {
        controller.isRunning ? controller.stop() : controller.start()
        bump()
    }

    private func bump() { refreshTick.toggle() }
}

// MARK: - Sidebar (does not observe touch UI — avoids re-render on every report)

private struct SidebarView: View {
    @ObservedObject var controller: TouchpadController
    let refreshTick: Bool
    let toggle: () -> Void
    let bump: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statusCard
                permissionsSection
                userGuideRow
                LicenseSection()
                SettingsSection(settings: controller.settings)
            }
            .padding(20)
        }
        .id(refreshTick)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.and.hand.point.up.left.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("ProtoArc T1 Plus")
                    .font(.title2.bold())
                Text("User-space touchpad driver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(controller.state.description)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Spacer()
            }

            HStack {
                Label("\(controller.reportRate) rep/s", systemImage: "waveform.path.ecg")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button(action: toggle) {
                Label(controller.isRunning ? "Stop" : "Start",
                      systemImage: controller.isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(controller.isRunning ? .red : .accentColor)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions")
                .font(.headline)

            PermissionRow(
                title: "Input Monitoring",
                granted: Permissions.hasInputMonitoring,
                hint: "Needed to read the touchpad",
                action: {
                    Permissions.requestInputMonitoring()
                    Permissions.openInputMonitoringSettings()
                    bump()
                }
            )
            PermissionRow(
                title: "Accessibility",
                granted: Permissions.hasAccessibility,
                hint: "Needed to move the cursor & click",
                action: {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                    bump()
                }
            )
            Text("After granting a permission you may need to quit and relaunch the app.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .id(refreshTick)
    }

    private var userGuideRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Help")
                .font(.headline)
            Button("Open user guide in browser") {
                if let url = Bundle.main.url(forResource: "UserGuide", withExtension: "html") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            Text("Readable on Mac, iPhone, iPad, or Android in Safari / Chrome. Copy UserGuide.html from the app bundle to iCloud or a website to open it elsewhere.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch controller.state {
        case .connected: return .green
        case .waitingForDevice: return .orange
        case .error: return .red
        case .stopped: return .gray
        }
    }
}

// MARK: - Touch panel (high-frequency updates isolated here)

private struct TouchPanel: View {
    @ObservedObject var ui: TouchpadUIState

    var body: some View {
        VStack(spacing: 16) {
            TouchVisualizer(frame: ui.displayFrame)
                .frame(maxWidth: .infinity)
                .frame(height: 260)

            CalibrationLog(ui: ui)
        }
    }
}

// MARK: - Behavior settings

private struct SettingsSection: View {
    @ObservedObject var settings: TouchpadSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Behavior")
                .font(.headline)

            sliderRow("Pointer speed", value: $settings.pointerSpeed, range: 0.3...4.0)
            sliderRow("Scroll speed", value: $settings.scrollSpeed, range: 0.2...3.0)

            Toggle("Natural scrolling", isOn: $settings.naturalScrolling)

            Text("One-finger touch (tap)")
                .font(.subheadline.bold())
            tapActionRow("Action", selection: $settings.oneFingerTapRawValue)

            Text("Two-finger touch (tap, not physical button)")
                .font(.subheadline.bold())
            touchGestureRow("Action", selection: $settings.twoFingerTouchGestureRawValue)

            Text("Three-finger touch (tap, not physical button)")
                .font(.subheadline.bold())
            touchGestureRow("Action", selection: $settings.threeFingerTouchGestureRawValue)

            Text("Place fingers on the pad and lift without swiping. Physical clickpad presses are separate.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle("Double-tap & slide drag-and-drop", isOn: $settings.doubleTapDrag)
                .help("Tap twice quickly (100–250 ms), then slide on the second touch to drag files. Turn off to disable.")

            Text("Double click (select ×2): 100–250 ms between taps — quick second tap without sliding")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle("Two-finger scroll", isOn: $settings.twoFingerScroll)
            Toggle("Advanced gestures (swipe / pinch)", isOn: $settings.enableGestures)

            VStack(alignment: .leading, spacing: 4) {
                Text("3-finger horizontal swipe")
                    .font(.subheadline)
                Picker("3-finger horizontal swipe", selection: $settings.horizontalSwipeRawValue) {
                    ForEach(HorizontalSwipeAction.allCases) { action in
                        Text(action.label).tag(action.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            Divider()

            Text("Startup")
                .font(.headline)

            Toggle("Start driver when app opens", isOn: $settings.autoStartDriver)
            Toggle("Open at login", isOn: $settings.launchAtLogin)
                .help("Adds ProtoArc T1 Plus to System Settings → General → Login Items.")

            Divider()

            Toggle("Seize device (exclusive access)", isOn: $settings.seizeDevice)
                .help("Prevents macOS from also processing the device. Re-press Start to apply.")

            VStack(alignment: .leading, spacing: 4) {
                Text("Report layout")
                    .font(.subheadline)
                Picker("Report layout", selection: $settings.layoutRawValue) {
                    ForEach(ReportLayout.allCases) { layout in
                        Text(layout.label).tag(layout.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                Text("If touches don't track, switch this and watch the log.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: "%.1f×", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func tapActionRow(_ title: String, selection: Binding<Int>) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(TapAction.allCases) { action in
                    Text(action.label).tag(action.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 180)
        }
    }

    private func touchGestureRow(_ title: String, selection: Binding<Int>) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Picker(title, selection: selection) {
                Section("None") {
                    Text(TouchGestureAction.none.label).tag(TouchGestureAction.none.rawValue)
                }
                Section("Clicks") {
                    ForEach(TouchGestureAction.clickCases.filter { $0 != .none }) { action in
                        Text(action.label).tag(action.rawValue)
                    }
                }
                Section("System gestures") {
                    ForEach(TouchGestureAction.systemCases) { action in
                        Text(action.label).tag(action.rawValue)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 220)
        }
    }
}

// MARK: - Permission row

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let hint: String
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                Text(hint).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Live touch visualizer

private struct TouchVisualizer: View {
    let frame: TouchFrame

    private let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Live touches")
                    .font(.headline)
                Spacer()
                if let p = frame.touching.first?.normalized {
                    Text(String(format: "%.0f, %.0f",
                                p.x * DeviceIDs.maxX, p.y * DeviceIDs.maxY))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.secondary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)

                    ForEach(frame.touching) { c in
                        let p = c.normalized
                        Circle()
                            .fill(color(for: c.contactID).opacity(0.85))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Text("\(c.contactID)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            )
                            .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                    }

                    if frame.touching.isEmpty {
                        Text("No fingers detected")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func color(for id: Int) -> Color {
        palette[((id % palette.count) + palette.count) % palette.count]
    }
}

// MARK: - Calibration log

private struct CalibrationLog: View {
    @ObservedObject var ui: TouchpadUIState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Raw report log")
                    .font(.headline)
                Spacer()
                Toggle("Log raw reports", isOn: $ui.logging)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Button("Clear") { ui.clearLog() }
                    .controlSize(.small)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(ui.log.enumerated()), id: \.offset) { idx, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(idx)
                        }
                    }
                    .padding(8)
                }
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onChange(of: ui.log.count) { old, new in
                    guard new > old, let last = ui.log.indices.last else { return }
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

#Preview {
    ContentView(controller: TouchpadController())
}
