//
//  ProtoArc_T1_PlusApp.swift
//  ProtoArc T1 Plus
//
//  Created by Mohammad Hassan  on 5/30/26.
//

import SwiftUI

@main
struct ProtoArc_T1_PlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller: TouchpadController

    init() {
        let c = TouchpadController()
        _controller = StateObject(wrappedValue: c)
        AppDelegate.controller = c
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(controller: controller)
        } label: {
            MenuBarIcon(state: controller.state)
        }
        .menuBarExtraStyle(.menu)

        Window("ProtoArc T1 Plus", id: "settings") {
            ContentView(controller: controller)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 880, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Window("Welcome & License", id: "welcome") {
            WelcomeFlowView()
        }
        .defaultSize(width: 540, height: 480)
    }
}
