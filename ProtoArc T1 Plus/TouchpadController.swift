//
//  TouchpadController.swift
//  ProtoArc T1 Plus
//

import Foundation
import IOKit.hid
import Combine
import QuartzCore
import os.log

enum ConnectionState: Equatable {
    case stopped
    case waitingForDevice
    case connected
    case error(String)

    var description: String {
        switch self {
        case .stopped: return "Stopped"
        case .waitingForDevice: return "Searching for ProtoArc T1 Plus…"
        case .connected: return "Connected"
        case .error(let m): return "Error: \(m)"
        }
    }
}

final class TouchpadController: ObservableObject {
    @Published private(set) var state: ConnectionState = .stopped
    @Published private(set) var isRunning = false
    @Published private(set) var reportRate: Int = 0

    let settings = TouchpadSettings()
    let uiState = TouchpadUIState()

    private let synth = EventSynthesizer()
    private lazy var engine = GestureEngine(synth: synth, settings: settings)
    private let hidLoop = HIDRunLoop()

    private var manager: IOHIDManager?
    private let reportBufferSize = 64
    private var reportBuffer: UnsafeMutablePointer<UInt8>?

    private var reportCountHID = 0
    private let reportLock = NSLock()
    private var rateTimer: Timer?

    private let osLog = OSLog(subsystem: "proto.ProtoArc-T1-Plus", category: "Touchpad")

    // Cached on main, read from the HID thread (no main.sync).
    private var layoutRawValue: Int = 0
    private var loggingEnabled = false
    private var publishDisplay = false

    // MARK: - Lifecycle

    @MainActor
    func start() {
        guard !isRunning else { return }

        guard SerialManager.shared.isLicensed else {
            state = .error("License required. Open Settings and enter a valid serial.")
            return
        }

        syncHIDCaches()

        engine.onLog = { [weak self] msg in
            Task { @MainActor [weak self] in
                self?.uiState.appendLog(msg)
            }
        }

        guard Permissions.hasInputMonitoring else {
            Permissions.requestInputMonitoring()
            state = .error("Input Monitoring permission required. Grant it, then press Start again.")
            return
        }
        guard Permissions.hasAccessibility else {
            Permissions.requestAccessibility()
            state = .error("Accessibility permission required. Grant it, then press Start again.")
            return
        }

        hidLoop.start()

        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr

        let matching: [String: Any] = [
            kIOHIDVendorIDKey: DeviceIDs.vendorID,
            kIOHIDProductIDKey: DeviceIDs.productID,
        ]
        IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, Self.matchCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, Self.removalCallback, context)

        reportBuffer = .allocate(capacity: reportBufferSize)
        reportBuffer?.initialize(repeating: 0, count: reportBufferSize)

        let openOptions: IOOptionBits = settings.seizeDevice
            ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
            : IOOptionBits(kIOHIDOptionsTypeNone)

        hidLoop.perform { [weak self] in
            guard let self, let mgr = self.manager, let rl = self.hidLoop.runLoop else { return }
            IOHIDManagerScheduleWithRunLoop(mgr, rl, CFRunLoopMode.defaultMode.rawValue)
            let result = IOHIDManagerOpen(mgr, openOptions)
            DispatchQueue.main.async {
                guard result == kIOReturnSuccess else {
                    self.state = .error(String(format: "IOHIDManagerOpen failed (0x%08X). Check Input Monitoring permission.", result))
                    self.cleanup()
                    return
                }
                self.isRunning = true
                self.state = .waitingForDevice
                self.startRateTimer()
                self.uiState.appendLog("Started. Seize=\(self.settings.seizeDevice), layout=\(self.settings.layout.label)")
            }
        }
    }

    @MainActor
    func stop() {
        guard isRunning else { return }
        synth.forceReleaseLeft()
        cleanup()
        isRunning = false
        state = .stopped
        reportRate = 0
        uiState.clearDisplay()
        uiState.appendLog("Stopped.")
    }

    @MainActor
    private func cleanup() {
        rateTimer?.invalidate()
        rateTimer = nil

        if let mgr = manager, hidLoop.runLoop != nil {
            hidLoop.performAndWait {
                if let rl = self.hidLoop.runLoop {
                    IOHIDManagerUnscheduleFromRunLoop(mgr, rl, CFRunLoopMode.defaultMode.rawValue)
                }
                IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
            }
        }
        manager = nil

        if let buf = reportBuffer {
            buf.deinitialize(count: reportBufferSize)
            buf.deallocate()
        }
        reportBuffer = nil

        hidLoop.stop()
    }

    @MainActor
    private func startRateTimer() {
        rateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.reportLock.lock()
            self.reportRate = self.reportCountHID
            self.reportCountHID = 0
            self.reportLock.unlock()
        }
    }

    @MainActor
    private func syncHIDCaches() {
        layoutRawValue = settings.layoutRawValue
        loggingEnabled = uiState.logging
        publishDisplay = uiState.isOpen
    }

    // MARK: - Device attach / detach

    private func deviceMatched(_ device: IOHIDDevice) {
        guard let buffer = reportBuffer else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, reportBufferSize,
                                               Self.reportCallback, context)
        DispatchQueue.main.async { [weak self] in
            self?.state = .connected
            self?.uiState.appendLog("Device attached.")
        }
        os_log("ProtoArc device matched", log: osLog, type: .info)
    }

    private func deviceRemoved() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state = self.isRunning ? .waitingForDevice : .stopped
            self.uiState.clearDisplay()
            self.uiState.appendLog("Device removed.")
        }
    }

    // MARK: - Report handling (HID thread)

    private func handleReport(reportID: UInt32, report: UnsafePointer<UInt8>, length: Int) {
        reportLock.lock()
        reportCountHID += 1
        reportLock.unlock()

        let layout = ReportLayout(rawValue: layoutRawValue) ?? .userspaceNoReportID
        let logging = loggingEnabled
        let shouldPublish = publishDisplay

        if logging {
            let hex = (0..<length).map { String(format: "%02X", report[$0]) }.joined(separator: " ")
            Task { @MainActor [weak self] in
                self?.uiState.appendLog("id=\(reportID) len=\(length) [\(hex)]")
            }
        }

        if reportID == ReportParser.mouseReportID {
            if let buttons = ReportParser.mouseButtons(report, length: length, layout: layout) {
                engine.physicalMouseButtons(buttons)
            }
            return
        }

        guard reportID == ReportParser.reportID else { return }
        guard let frame = ReportParser.parse(report, length: length, layout: layout) else { return }

        engine.process(frame: frame)

        if shouldPublish {
            Task { @MainActor [weak self] in
                self?.uiState.publishFrame(frame)
            }
        }
    }

    @MainActor
    func settingsWindowDidOpen() {
        uiState.windowDidOpen()
        syncHIDCaches()
    }

    @MainActor
    func settingsWindowDidClose() {
        uiState.windowDidClose()
        syncHIDCaches()
    }

    @MainActor
    func hidCachesDidChange() {
        syncHIDCaches()
    }

    /// Release stuck drag after menu-bar interaction (no cross-thread deadlock).
    func unstickPointer() {
        guard isRunning else { return }
        engine.unstickPointer()
        synth.forceReleaseLeft()
    }

    // MARK: - C callbacks (HID run loop thread)

    private static let matchCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<TouchpadController>.fromOpaque(context).takeUnretainedValue().deviceMatched(device)
    }

    private static let removalCallback: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        Unmanaged<TouchpadController>.fromOpaque(context).takeUnretainedValue().deviceRemoved()
    }

    private static let reportCallback: IOHIDReportCallback = { context, _, _, _, reportID, report, reportLength in
        guard let context else { return }
        Unmanaged<TouchpadController>.fromOpaque(context).takeUnretainedValue()
            .handleReport(reportID: reportID, report: report, length: Int(reportLength))
    }
}
