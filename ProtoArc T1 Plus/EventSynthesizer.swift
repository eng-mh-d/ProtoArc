//
//  EventSynthesizer.swift
//  ProtoArc T1 Plus
//
//  Posts CGEvents from the HID driver thread (never blocks the main/UI thread).
//

import Foundation
import CoreGraphics
import os.lock

enum SystemGesture {
    case missionControl
    case appExpose
    case spaceLeft
    case spaceRight
    case zoomIn
    case zoomOut
    case tabPrev
    case tabNext
    case windowPrev
    case windowNext
}

final class EventSynthesizer {
    private let source = CGEventSource(stateID: .combinedSessionState)
    private var lock = os_unfair_lock()
    private var leftButtonDown = false
    private var leftClickState: Int64 = 1
    private var trackedPos: CGPoint?

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body()
    }

    private func currentLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func screenBounds() -> CGRect {
        let maxDisplays: UInt32 = 16
        var active = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0
        CGGetActiveDisplayList(maxDisplays, &active, &count)
        guard count > 0 else {
            return CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
        var union = CGRect.null
        for i in 0..<Int(count) {
            union = union.union(CGDisplayBounds(active[i]))
        }
        return union
    }

    private func effectiveLocation() -> CGPoint {
        trackedPos ?? currentLocation()
    }

    private func post(_ event: CGEvent?) {
        event?.post(tap: .cgSessionEventTap)
    }

    private func postMouseNow(_ type: CGEventType, button: CGMouseButton, at loc: CGPoint, clickState: Int64) {
        let event = CGEvent(mouseEventSource: source, mouseType: type,
                            mouseCursorPosition: loc, mouseButton: button)
        event?.setIntegerValueField(.mouseEventClickState, value: clickState)
        post(event)
    }

    func syncPointer() {
        withLock { trackedPos = currentLocation() }
    }

    func endPointerSession() {
        withLock { trackedPos = nil }
    }

    func moveBy(dx: Double, dy: Double) {
        withLock {
            let bounds = screenBounds()
            var loc = trackedPos ?? currentLocation()
            loc.x = min(max(loc.x + dx, bounds.minX), bounds.maxX - 1)
            loc.y = min(max(loc.y + dy, bounds.minY), bounds.maxY - 1)
            trackedPos = loc

            let type: CGEventType = leftButtonDown ? .leftMouseDragged : .mouseMoved
            let event = CGEvent(mouseEventSource: source, mouseType: type,
                                mouseCursorPosition: loc, mouseButton: .left)
            post(event)
        }
    }

    func leftClick(clickState: Int64 = 1) {
        withLock {
            let loc = effectiveLocation()
            postMouseNow(.leftMouseDown, button: .left, at: loc, clickState: clickState)
            postMouseNow(.leftMouseUp, button: .left, at: loc, clickState: clickState)
        }
    }

    func doubleClick() {
        withLock {
            let loc = effectiveLocation()
            postMouseNow(.leftMouseDown, button: .left, at: loc, clickState: 1)
            postMouseNow(.leftMouseUp, button: .left, at: loc, clickState: 1)
            postMouseNow(.leftMouseDown, button: .left, at: loc, clickState: 2)
            postMouseNow(.leftMouseUp, button: .left, at: loc, clickState: 2)
        }
    }

    func rightClick() {
        withLock {
            let loc = effectiveLocation()
            postMouseNow(.rightMouseDown, button: .right, at: loc, clickState: 1)
            postMouseNow(.rightMouseUp, button: .right, at: loc, clickState: 1)
        }
    }

    func middleClick() {
        withLock {
            let loc = effectiveLocation()
            postMouseNow(.otherMouseDown, button: .center, at: loc, clickState: 1)
            postMouseNow(.otherMouseUp, button: .center, at: loc, clickState: 1)
        }
    }

    func pressLeft(clickState: Int64 = 1) {
        withLock {
            guard !leftButtonDown else { return }
            leftButtonDown = true
            leftClickState = clickState
            postMouseNow(.leftMouseDown, button: .left, at: effectiveLocation(), clickState: clickState)
        }
    }

    func releaseLeft() {
        withLock {
            guard leftButtonDown else { return }
            leftButtonDown = false
            postMouseNow(.leftMouseUp, button: .left, at: effectiveLocation(), clickState: leftClickState)
            leftClickState = 1
        }
    }

    func forceReleaseLeft() {
        withLock {
            guard leftButtonDown else { return }
            leftButtonDown = false
            postMouseNow(.leftMouseUp, button: .left, at: effectiveLocation(), clickState: leftClickState)
            leftClickState = 1
        }
    }

    func scroll(dx: Double, dy: Double) {
        let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel,
                            wheelCount: 2,
                            wheel1: Int32(dy.rounded()),
                            wheel2: Int32(dx.rounded()),
                            wheel3: 0)
        post(event)
    }

    func perform(_ gesture: SystemGesture) {
        switch gesture {
        case .missionControl: keyChordNow(keyCode: 0x7E, control: true)
        case .appExpose: keyChordNow(keyCode: 0x7D, control: true)
        case .spaceLeft: keyChordNow(keyCode: 0x7B, control: true)
        case .spaceRight: keyChordNow(keyCode: 0x7C, control: true)
        case .zoomIn: keyChordNow(keyCode: 0x18, command: true)
        case .zoomOut: keyChordNow(keyCode: 0x1B, command: true)
        case .tabNext: keyChordNow(keyCode: 0x30, control: true)
        case .tabPrev: keyChordNow(keyCode: 0x30, control: true, shift: true)
        case .windowNext: keyChordNow(keyCode: 0x32, command: true)
        case .windowPrev: keyChordNow(keyCode: 0x32, command: true, shift: true)
        }
    }

    private func keyChordNow(keyCode: CGKeyCode, command: Bool = false, control: Bool = false,
                             option: Bool = false, shift: Bool = false) {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if control { flags.insert(.maskControl) }
        if option { flags.insert(.maskAlternate) }
        if shift { flags.insert(.maskShift) }

        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        post(down)

        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags
        post(up)
    }
}
