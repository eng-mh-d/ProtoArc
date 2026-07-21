//
//  TouchpadManager.swift
//  ProtoArc T1 Plus
//
//  Detects single vs. double taps coming from the Bluetooth touchpad and turns
//  them into native macOS left clicks using Quartz Event Services (CGEvent).
//
//  Detection strategy — "deferred single click":
//   1. The Bluetooth/HID layer reports a one-finger tap by calling `handleTap`.
//   2. On the FIRST tap we do NOT click immediately. Instead we schedule a
//      single-click `DispatchWorkItem` to run after the double-tap interval.
//   3. If a SECOND tap arrives before that work item runs, we cancel it and
//      emit a native DOUBLE click instead (click state 1 then 2).
//   4. If the interval expires with no second tap, the deferred single click
//      fires.
//
//  This guarantees:
//   • One tap                    → one left click.
//   • Two taps within interval   → one native double click.
//   • Two taps outside interval  → two separate single clicks.
//
//  Thread safety: all tap state is mutated on a private serial queue, so taps
//  arriving from the HID callback (any thread) can never race, and we never
//  emit duplicate click events.
//

import Foundation
import CoreGraphics

final class TouchpadManager {

    // MARK: - Configuration

    /// Maximum gap between two taps for them to count as a double tap.
    /// Defaults to 300 ms as required; can be overridden per tap.
    private let defaultDoubleTapInterval: TimeInterval

    // MARK: - Thread-safety / state

    /// Serial queue that guards all pending-tap state. Using one queue means
    /// `handleTap` calls and the scheduled work item are fully serialized.
    private let queue = DispatchQueue(label: "com.protoarc.TouchpadManager.taps")

    /// The single-click action waiting for the double-tap timeout. Non-nil only
    /// while we are inside the double-tap window after the first tap.
    private var pendingSingleClick: DispatchWorkItem?

    private let eventSource = CGEventSource(stateID: .hidSystemState)

    /// Optional human-readable log sink (mirrors the app's on-screen log).
    var onLog: ((String) -> Void)?

    init(defaultDoubleTapInterval: TimeInterval = 0.300) {
        self.defaultDoubleTapInterval = defaultDoubleTapInterval
    }

    // MARK: - Public API (call this from the Bluetooth tap callback)

    /// Register a one-finger tap from the touchpad. Safe to call from any
    /// thread. `interval` is the double-tap window (defaults to 300 ms).
    func handleTap(interval: TimeInterval? = nil) {
        let window = interval ?? defaultDoubleTapInterval

        queue.async { [weak self] in
            guard let self else { return }

            if let pending = self.pendingSingleClick {
                // ── Second tap inside the window → DOUBLE click ──
                // Cancel the deferred single click and emit a real double click.
                pending.cancel()
                self.pendingSingleClick = nil
                self.performDoubleClick()
                self.onLog?("TouchpadManager: double tap → double click")
            } else {
                // ── First tap → defer the single click ──
                // Schedule it; a second tap arriving in time will cancel it.
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    // Runs on `queue`; if it wasn't cancelled, the window
                    // expired with no second tap, so this is a single click.
                    self.pendingSingleClick = nil
                    self.performSingleClick()
                    self.onLog?("TouchpadManager: single tap → single click")
                }
                self.pendingSingleClick = work
                self.queue.asyncAfter(deadline: .now() + window, execute: work)
            }
        }
    }

    /// Cancel any pending single click (e.g. when the gesture turned into a
    /// drag or the device disconnected).
    func cancelPending() {
        queue.async { [weak self] in
            self?.pendingSingleClick?.cancel()
            self?.pendingSingleClick = nil
        }
    }

    // MARK: - CGEvent generation

    private func performSingleClick() {
        let pos = currentCursor()
        postClick(at: pos, clickState: 1)
    }

    /// A native macOS double click: two presses at the same point, the second
    /// carrying click state 2 so the system recognizes it as a double click.
    private func performDoubleClick() {
        let pos = currentCursor()
        postClick(at: pos, clickState: 1)
        postClick(at: pos, clickState: 2)
    }

    /// Emit a single left mouse down + up pair with the given click state.
    private func postClick(at pos: CGPoint, clickState: Int64) {
        let down = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown,
                           mouseCursorPosition: pos, mouseButton: .left)
        down?.setIntegerValueField(.mouseEventClickState, value: clickState)
        down?.post(tap: .cgSessionEventTap)

        let up = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp,
                         mouseCursorPosition: pos, mouseButton: .left)
        up?.setIntegerValueField(.mouseEventClickState, value: clickState)
        up?.post(tap: .cgSessionEventTap)
    }

    private func currentCursor() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}
