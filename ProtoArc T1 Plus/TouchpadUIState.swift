//
//  TouchpadUIState.swift
//  ProtoArc T1 Plus
//
//  Settings-window UI state, isolated so touch updates don't re-render the menu bar app.
//

import Foundation
import Combine
import QuartzCore

@MainActor
final class TouchpadUIState: ObservableObject {
    @Published private(set) var displayFrame: TouchFrame = .empty
    @Published var logging = false
    @Published private(set) var log: [String] = []

    private(set) var isOpen = false
    private var lastDisplayUpdate: CFTimeInterval = 0
    private let displayMinInterval: CFTimeInterval = 1.0 / 20.0

    func windowDidOpen() {
        isOpen = true
        displayFrame = .empty
        lastDisplayUpdate = 0
    }

    func windowDidClose() {
        isOpen = false
        displayFrame = .empty
    }

    /// Only contacts actively on the surface; lift-off artifacts are hidden in the UI.
    func publishFrame(_ frame: TouchFrame) {
        guard isOpen else { return }

        let visible = TouchFrame.displayFrame(from: frame)
        if visible.touching.isEmpty {
            if !displayFrame.touching.isEmpty {
                displayFrame = .empty
            }
            return
        }

        let now = CACurrentMediaTime()
        guard now - lastDisplayUpdate >= displayMinInterval else { return }
        lastDisplayUpdate = now
        displayFrame = visible
    }

    func appendLog(_ line: String) {
        guard isOpen else { return }
        guard logging || !line.hasPrefix("id=") else { return }
        let stamp = String(format: "%.3f", CACurrentMediaTime().truncatingRemainder(dividingBy: 1000))
        log.append("[\(stamp)] \(line)")
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }

    func clearLog() { log.removeAll() }

    func clearDisplay() { displayFrame = .empty }
}
