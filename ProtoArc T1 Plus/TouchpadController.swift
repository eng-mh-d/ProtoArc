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

    /// Only this device gets an input-report callback (avoids double pointer drive).
    private var primaryDevice: IOHIDDevice?
    /// Every matched interface we opened (for seize + teardown).
    private var openedDevices: [IOHIDDevice] = []
    /// Cached on start; read from HID thread.
    private var seizeEnabled = true

    private var reportCountHID = 0
    private let reportLock = NSLock()
    private var rateTimer: Timer?

    private let osLog = OSLog(subsystem: "proto.ProtoArc-T1-Plus", category: "Touchpad")

    // Cached on main, read from the HID thread (no main.sync).
    private var layoutRawValue: Int = ReportLayout.rawWithReportID.rawValue
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
        seizeEnabled = settings.seizeDevice

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

        // Open the manager without seize; we seize each interface at device level
        // below. Manager-level seize is unreliable for BLE composites on macOS 26+.
        hidLoop.perform { [weak self] in
            guard let self, let mgr = self.manager, let rl = self.hidLoop.runLoop else { return }
            IOHIDManagerScheduleWithRunLoop(mgr, rl, CFRunLoopMode.defaultMode.rawValue)
            let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
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

        if hidLoop.runLoop != nil {
            hidLoop.performAndWait {
                self.teardownDevicesOnHIDThread()
                if let mgr = self.manager, let rl = self.hidLoop.runLoop {
                    IOHIDManagerUnscheduleFromRunLoop(mgr, rl, CFRunLoopMode.defaultMode.rawValue)
                    IOHIDManagerClose(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
                }
            }
        }
        manager = nil
        primaryDevice = nil
        openedDevices.removeAll()

        if let buf = reportBuffer {
            buf.deinitialize(count: reportBufferSize)
            buf.deallocate()
        }
        reportBuffer = nil

        hidLoop.stop()
    }

    private func teardownDevicesOnHIDThread() {
        for device in openedDevices {
            // Closing the device drops its report callback; Swift's IOKit
            // binding does not allow a nil report buffer for unregister.
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        openedDevices.removeAll()
        primaryDevice = nil
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

    private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key as CFString) else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private func containsDevice(_ device: IOHIDDevice) -> Bool {
        openedDevices.contains { CFEqual($0, device) }
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        guard let buffer = reportBuffer else { return }

        let usagePage = intProperty(device, kIOHIDPrimaryUsagePageKey) ?? 0
        let usage = intProperty(device, kIOHIDPrimaryUsageKey) ?? 0
        let maxSize = intProperty(device, kIOHIDMaxInputReportSizeKey) ?? 0

        // Device-level seize blocks macOS from also driving the cursor from the
        // BLE mouse report (Report ID 1). Without it, system + app fight and the
        // pointer feels jumpy / “broken” — common after macOS 26 BLE HID changes.
        let options: IOOptionBits = seizeEnabled
            ? IOOptionBits(kIOHIDOptionsTypeSeizeDevice)
            : IOOptionBits(kIOHIDOptionsTypeNone)
        let openResult = IOHIDDeviceOpen(device, options)

        if !containsDevice(device) {
            openedDevices.append(device)
        }

        // Already listening on a primary device: keep companions seized only.
        if let primary = primaryDevice {
            if CFEqual(primary, device) { return }
            DispatchQueue.main.async { [weak self] in
                self?.uiState.appendLog(String(
                    format: "Companion HID open page=%d usage=%d size=%d result=0x%08X (seize=%d)",
                    usagePage, usage, maxSize, openResult, self?.seizeEnabled == true ? 1 : 0
                ))
            }
            return
        }

        // Prefer interfaces that can carry the 19-byte multitouch payload.
        // This device often reports PrimaryUsage=Mouse even for the composite
        // BLE HID node (MaxInputReportSize=20).
        let canCarryTouch = maxSize >= ReportParser.payloadLength || usagePage == 0x0D
        guard canCarryTouch || openResult == kIOReturnSuccess else { return }

        primaryDevice = device
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, reportBufferSize,
                                               Self.reportCallback, context)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state = .connected
            self.uiState.appendLog(String(
                format: "Device attached page=%d usage=%d size=%d seizeOpen=0x%08X",
                usagePage, usage, maxSize, openResult
            ))
            if self.seizeEnabled, openResult != kIOReturnSuccess {
                self.uiState.appendLog("Warning: exclusive seize failed — macOS may also move the cursor (jitter). Toggle Seize off/on or re-pair Bluetooth.")
            }
        }
        os_log("ProtoArc device matched page=%{public}d usage=%{public}d", log: osLog, type: .info, usagePage, usage)
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        openedDevices.removeAll { CFEqual($0, device) }

        if let primary = primaryDevice, CFEqual(primary, device) {
            primaryDevice = nil

            // Promote another opened interface if one remains.
            if let next = openedDevices.first {
                primaryDevice = next
                if let buffer = reportBuffer {
                    let context = Unmanaged.passUnretained(self).toOpaque()
                    IOHIDDeviceRegisterInputReportCallback(next, buffer, reportBufferSize,
                                                           Self.reportCallback, context)
                }
                DispatchQueue.main.async { [weak self] in
                    self?.state = .connected
                    self?.uiState.appendLog("Primary HID removed — switched to companion interface.")
                }
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.state = self.isRunning ? .waitingForDevice : .stopped
                self.uiState.clearDisplay()
                self.uiState.appendLog("Device removed.")
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.uiState.appendLog("Companion HID removed.")
        }
    }

    // MARK: - Report handling (HID thread)

    private func handleReport(reportID: UInt32, report: UnsafePointer<UInt8>, length: Int) {
        reportLock.lock()
        reportCountHID += 1
        reportLock.unlock()

        let preferred = ReportLayout(rawValue: layoutRawValue) ?? .rawWithReportID
        let layout = ReportParser.resolvedLayout(
            reportID: reportID, length: length, bytes: report, preferred: preferred
        )
        let logging = loggingEnabled
        let shouldPublish = publishDisplay

        if logging {
            let hex = (0..<length).map { String(format: "%02X", report[$0]) }.joined(separator: " ")
            Task { @MainActor [weak self] in
                self?.uiState.appendLog("id=\(reportID) len=\(length) layout=\(layout.label) [\(hex)]")
            }
        }

        if reportID == ReportParser.mouseReportID {
            // Buttons only — never apply relative mouse deltas (macOS/app would double-move).
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

    private static let removalCallback: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<TouchpadController>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
    }

    private static let reportCallback: IOHIDReportCallback = { context, _, _, _, reportID, report, reportLength in
        guard let context else { return }
        Unmanaged<TouchpadController>.fromOpaque(context).takeUnretainedValue()
            .handleReport(reportID: reportID, report: report, length: Int(reportLength))
    }
}
