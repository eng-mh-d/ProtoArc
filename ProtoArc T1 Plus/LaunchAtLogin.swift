//
//  LaunchAtLogin.swift
//  ProtoArc T1 Plus
//
//  Registers the app in System Settings → Login Items so it starts at macOS login.
//

import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status != .notRegistered else { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    /// Applies the saved preference when it differs from the system login-item state.
    static func sync(with preference: Bool) {
        if preference != isEnabled {
            _ = setEnabled(preference)
        }
    }
}
