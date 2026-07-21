//
//  WelcomeOnboardingView.swift
//  ProtoArc T1 Plus
//
//  First-launch welcome slides + activation. "More" opens usage help and
//  cross-platform notes (macOS app vs iOS / Android / web guide).
//

import AppKit
import SwiftUI

/// Welcome / license window: intro slides on first launch, then defaults to activation page.
struct WelcomeFlowView: View {
    @ObservedObject private var serials = SerialManager.shared
    @AppStorage("hasSeenWelcomeIntro") private var hasSeenWelcomeIntro = false
    /// 0...2 = intro, 3 = activation
    @State private var page: Int = 0
    @State private var showHowToUse = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("More") { showHowToUse = true }
                    .buttonStyle(.bordered)
                if !hasSeenWelcomeIntro {
                    Button("Skip intro") {
                        hasSeenWelcomeIntro = true
                        page = 3
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Group {
                switch page {
                case 0: introWhatItIs
                case 1: introPermissions
                case 2: introConnect
                default: activationPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            pagerChrome
        }
        .frame(minWidth: 520, minHeight: 440)
        .onAppear {
            page = hasSeenWelcomeIntro ? 3 : 0
        }
        .sheet(isPresented: $showHowToUse) {
            HowToUseSheet(onOpenUserGuide: openUserGuideInBrowser)
        }
    }

    private var pagerChrome: some View {
        HStack(spacing: 16) {
            Button("Back") {
                page = max(0, page - 1)
            }
            .disabled(page == 0)

            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer(minLength: 8)

            if page < 3 {
                Button("Next") {
                    page += 1
                    if page == 3 { hasSeenWelcomeIntro = true }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Color.clear.frame(width: 72, height: 28)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var activationPage: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "key.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)

                Text("Activate ProtoArc T1 Plus")
                    .font(.title2.bold())

                Text("Enter a valid **weekly** or **active** serial (from SerialNumbers.txt).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                SerialActivationForm()

                VStack(spacing: 10) {
                    Button("Open user guide in browser (Mac, iPhone, Android, web)") {
                        openUserGuideInBrowser()
                    }
                    .buttonStyle(.bordered)

                    if hasSeenWelcomeIntro {
                        Button("See intro slides again") {
                            hasSeenWelcomeIntro = false
                            page = 0
                        }
                        .buttonStyle(.borderless)
                    }
                }

                if serials.isLicensed {
                    Label("Licensed — close this window and start the driver from the menu bar icon.", systemImage: "checkmark.seal.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private var introWhatItIs: some View {
        introSlide(
            systemImage: "rectangle.and.hand.point.up.left.fill",
            title: "Welcome to ProtoArc T1 Plus",
            body: "This is a **menu bar app for macOS** that turns your ProtoArc T1 Plus Bluetooth touchpad into a full pointer: move, tap, scroll, and system gestures — **without** installing a kernel extension or turning off System Integrity Protection.\n\nThe app reads touch data in **user space** and synthesizes mouse and keyboard events so your Mac behaves like you expect from a precision touchpad."
        )
    }

    private var introPermissions: some View {
        introSlide(
            systemImage: "lock.shield.fill",
            title: "Permissions on your Mac",
            body: "The first time you start the driver, macOS will ask for two permissions in **System Settings → Privacy & Security**:\n\n• **Input Monitoring** — so the app can read the touchpad’s HID reports.\n\n• **Accessibility** — so the app can move the cursor and send clicks and shortcuts.\n\nGrant both, then press **Start Driver** again if needed."
        )
    }

    private var introConnect: some View {
        introSlide(
            systemImage: "antenna.radiowaves.left.and.right",
            title: "Connect & run",
            body: "**Bluetooth** — pair the ProtoArc T1 Plus like any accessory.\n\n**Menu bar** — click the hand icon: **Start Driver** begins listening to the pad; green means connected.\n\n**Settings** — open the window to tune pointer speed, scroll, gestures, optional raw report logging, and “seize device” so only this app handles the pad (recommended).\n\nTap **More** (top right) anytime for step-by-step usage and a guide you can open on **phone, tablet, or web**."
        )
    }

    private func introSlide(systemImage: String, title: String, body: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                    Text(title)
                        .font(.title2.bold())
                }
                Text(.init(body))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(28)
        }
    }

    private func openUserGuideInBrowser() {
        guard let url = Bundle.main.url(forResource: "UserGuide", withExtension: "html") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - How to use (sheet)

struct HowToUseSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onOpenUserGuide: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Group {
                        Text("How to use the app (macOS)")
                            .font(.headline)
                        Text(.init("1. Open the **menu bar** icon (hand + rectangle)."))
                        Text(.init("2. Choose **Start Driver** after your license is active and permissions are granted."))
                        Text(.init("3. Use **Settings…** for pointer speed, scroll speed, gestures, and troubleshooting (report layout, raw log)."))
                        Text(.init("4. Use **Stop Driver** if you want the system to handle the pad again."))
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    Text("Gestures (defaults)")
                        .font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(.init("• **1 finger move** → move pointer"))
                        Text(.init("• **1 finger tap** → left click"))
                        Text(.init("• **2 fingers move** → scroll"))
                        Text(.init("• **2 finger tap** → right click (touch)"))
                        Text(.init("• **3 finger swipes** → Spaces / Mission Control / App Exposé (as configured)"))
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    Text("All platforms: iOS, Android, web")
                        .font(.headline)
                    Text(
                        "The **driver runs only on macOS** (this app). iOS and Android cannot run the same kind of system touchpad driver for this device.\n\nYou can still read the full **User guide** in **Safari, Chrome, or any browser** on iPhone, iPad, Android, or desktop: use the button below on your Mac, or copy **UserGuide.html** from the app bundle to iCloud Drive / your website and open the link on any device."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        onOpenUserGuide()
                    } label: {
                        Label("Open UserGuide.html in your default browser", systemImage: "safari")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("How to use")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 520)
    }
}
