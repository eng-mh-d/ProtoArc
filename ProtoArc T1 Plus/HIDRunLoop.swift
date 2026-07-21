//
//  HIDRunLoop.swift
//  ProtoArc T1 Plus
//
//  Dedicated thread + run loop for IOHIDManager so touch reports never block the UI.
//

import Foundation
import CoreFoundation

/// Runs IOHID callbacks on a background run loop (not the main thread).
final class HIDRunLoop {
    private var thread: Thread?
    private var cfRunLoop: CFRunLoop?
    private let ready = DispatchSemaphore(value: 0)

    func start() {
        guard thread == nil else { return }
        let t = Thread { [weak self] in
            guard let self else { return }
            self.cfRunLoop = CFRunLoopGetCurrent()
            self.ready.signal()
            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.25, true)
            }
        }
        t.name = "ProtoArc HID"
        t.start()
        thread = t
        ready.wait()
    }

    func stop() {
        guard let rl = cfRunLoop else { return }
        perform {
            CFRunLoopStop(rl)
        }
        thread?.cancel()
        thread = nil
        cfRunLoop = nil
    }

    var runLoop: CFRunLoop? { cfRunLoop }

    func perform(_ block: @escaping () -> Void) {
        guard let rl = cfRunLoop else { return }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(rl)
    }

    /// Runs `block` on the HID run loop and waits until it finishes (for teardown).
    func performAndWait(_ block: @escaping () -> Void) {
        guard let rl = cfRunLoop else { return }
        let done = DispatchSemaphore(value: 0)
        CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue) {
            block()
            done.signal()
        }
        CFRunLoopWakeUp(rl)
        done.wait()
    }
}
