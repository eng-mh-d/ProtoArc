//
//  AppDelegate.swift
//  ProtoArc T1 Plus
//
//  Keeps the driver running after the settings window is closed and starts
//  the touchpad driver at launch (MenuBarExtra onAppear alone is too late).
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set from the app entry point before the run loop starts.
    static weak var controller: TouchpadController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        DispatchQueue.main.async {
            guard let controller = Self.controller else { return }
            NSApp.activate(ignoringOtherApps: true)
            AppStartup.run(controller: controller)
            controller.unstickPointer()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
