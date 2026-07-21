//
//  Permissions.swift
//  ProtoArc T1 Plus
//
//  Helpers for the two TCC permissions this app needs:
//   * Accessibility  - to post synthetic mouse/keyboard CGEvents.
//   * Input Monitoring - to open the HID device and read its input reports.
//

import Foundation
import ApplicationServices
import IOKit.hid
import AppKit

enum Permissions {

    // MARK: - Accessibility (post events)

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system prompt and adds the app to the Accessibility list.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Input Monitoring (read HID)

    static var hasInputMonitoring: Bool {
        if #available(macOS 10.15, *) {
            return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        }
        return true
    }

    /// Triggers the Input Monitoring prompt the first time it is called.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        if #available(macOS 10.15, *) {
            return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        return true
    }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
