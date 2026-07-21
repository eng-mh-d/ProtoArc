//
//  TouchModels.swift
//  ProtoArc T1 Plus
//
//  Data models for parsed multi-touch reports and tunable settings.
//

import Foundation
import CoreGraphics
import Combine

/// Hardware identifiers for the ProtoArc T1 Plus touchpad.
enum DeviceIDs {
    static let vendorID: Int = 1256      // 0x04E8
    static let productID: Int = 28705    // 0x7021

    /// Logical maximums reported by the digitizer (see README / HID descriptor).
    static let maxX: Double = 3200
    static let maxY: Double = 2000
}

/// A single finger (transducer) within one report frame.
struct TouchContact: Identifiable, Equatable {
    var id: Int { contactID }

    /// 6-bit identifier the hardware keeps stable while a finger stays down.
    var contactID: Int
    /// True while the finger is physically touching the surface.
    var tipSwitch: Bool
    /// True while the finger is detected hovering (if supported).
    var inRange: Bool
    /// Raw absolute coordinates (0...maxX, 0...maxY).
    var rawX: Double
    var rawY: Double

    /// Normalized position in 0...1 with the origin at the top-left.
    var normalized: CGPoint {
        CGPoint(x: rawX / DeviceIDs.maxX, y: rawY / DeviceIDs.maxY)
    }
}

/// One fully parsed report frame: the set of fingers currently on the pad.
struct TouchFrame: Equatable {
    /// Hardware scan-time counter (wraps around; only useful for deltas).
    var timestamp: Int
    /// Active contacts (those with `tipSwitch` or `inRange` set).
    var contacts: [TouchContact]
    /// Number of fingers the hardware reports as active.
    var contactCount: Int
    /// Physical click button state (clickpad press).
    var button: Bool = false

    static let empty = TouchFrame(timestamp: 0, contacts: [], contactCount: 0, button: false)

    /// Fingers actually touching the surface.
    var touching: [TouchContact] { contacts.filter { $0.tipSwitch } }

    /// Fingers firmly on the pad — used by the gesture engine (matches live UI).
    var activeTouching: [TouchContact] { contacts.filter { $0.tipSwitch && $0.inRange } }

    /// Frame for the live UI: only fingers firmly on the pad (`tipSwitch` + `inRange`).
    static func displayFrame(from frame: TouchFrame) -> TouchFrame {
        let visible = frame.activeTouching
        return TouchFrame(
            timestamp: frame.timestamp,
            contacts: visible,
            contactCount: visible.count,
            button: frame.button
        )
    }
}

/// What a one-finger tap maps to (clicks only).
enum TapAction: Int, CaseIterable, Identifiable {
    case none = 0
    case leftClick = 1
    case rightClick = 2
    case middleClick = 3
    case doubleClick = 4

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "Do nothing"
        case .leftClick: return "Left click"
        case .rightClick: return "Right click"
        case .middleClick: return "Middle click"
        case .doubleClick: return "Double left click"
        }
    }
}

/// Touch-only gesture assigned to a 2- or 3-finger tap (not the physical button).
/// Placing two or three fingers on the pad and lifting without swiping triggers
/// the selected action anywhere on the surface.
enum TouchGestureAction: Int, CaseIterable, Identifiable {
    case none = 0

    // Mouse clicks
    case leftClick = 1
    case rightClick = 2
    case middleClick = 3
    case doubleClick = 4

    // System gestures (keyboard shortcuts)
    case missionControl = 10
    case appExpose = 11
    case spaceLeft = 12
    case spaceRight = 13
    case zoomIn = 14
    case zoomOut = 15
    case tabPrev = 16
    case tabNext = 17
    case windowPrev = 18
    case windowNext = 19

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "Do nothing"
        case .leftClick: return "Left click"
        case .rightClick: return "Right click"
        case .middleClick: return "Middle click"
        case .doubleClick: return "Double left click"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .spaceLeft: return "Previous Space / desktop"
        case .spaceRight: return "Next Space / desktop"
        case .zoomIn: return "Zoom in (⌘ +)"
        case .zoomOut: return "Zoom out (⌘ −)"
        case .tabPrev: return "Previous tab"
        case .tabNext: return "Next tab"
        case .windowPrev: return "Previous app window"
        case .windowNext: return "Next app window"
        }
    }

    /// Grouping label for the settings picker.
    var section: String {
        switch self {
        case .none: return "None"
        case .leftClick, .rightClick, .middleClick, .doubleClick: return "Clicks"
        default: return "System gestures"
        }
    }

    static var clickCases: [TouchGestureAction] {
        [.none, .leftClick, .rightClick, .middleClick, .doubleClick]
    }

    static var systemCases: [TouchGestureAction] {
        [.missionControl, .appExpose, .spaceLeft, .spaceRight,
         .zoomIn, .zoomOut, .tabPrev, .tabNext, .windowPrev, .windowNext]
    }
}

/// What a three-finger horizontal swipe maps to.
enum HorizontalSwipeAction: Int, CaseIterable, Identifiable {
    case spaces = 0     // move between desktops / full-screen apps
    case tabs = 1       // previous / next tab (Ctrl+Tab)
    case windows = 2    // cycle windows of the current app (Cmd+`)

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .spaces: return "Switch Spaces / full-screen apps"
        case .tabs: return "Switch tabs (Ctrl+Tab)"
        case .windows: return "Switch app windows (⌘ `)"
        }
    }
}

/// User-tunable behavior. Persisted via `UserDefaults`.
final class TouchpadSettings: ObservableObject {
    @Published var pointerSpeed: Double { didSet { save("pointerSpeed", pointerSpeed) } }
    @Published var scrollSpeed: Double { didSet { save("scrollSpeed", scrollSpeed) } }
    @Published var naturalScrolling: Bool { didSet { save("naturalScrolling", naturalScrolling) } }
    @Published var oneFingerTapRawValue: Int { didSet { save("oneFingerTapRawValue", oneFingerTapRawValue) } }
    /// Touch-only 2-finger tap gesture (not the physical clickpad button).
    @Published var twoFingerTouchGestureRawValue: Int { didSet { save("twoFingerTouchGestureRawValue", twoFingerTouchGestureRawValue) } }
    /// Touch-only 3-finger tap gesture (not the physical clickpad button).
    @Published var threeFingerTouchGestureRawValue: Int { didSet { save("threeFingerTouchGestureRawValue", threeFingerTouchGestureRawValue) } }
    @Published var doubleTapDrag: Bool { didSet { save("doubleTapDrag2", doubleTapDrag) } }
    @Published var twoFingerScroll: Bool { didSet { save("twoFingerScroll", twoFingerScroll) } }
    @Published var enableGestures: Bool { didSet { save("enableGestures", enableGestures) } }
    @Published var seizeDevice: Bool { didSet { save("seizeDevice", seizeDevice) } }

    /// What a 3-finger horizontal swipe does (see `HorizontalSwipeAction`).
    @Published var horizontalSwipeRawValue: Int { didSet { save("horizontalSwipeRawValue", horizontalSwipeRawValue) } }

    /// Index of the byte layout assumed when parsing (see `ReportLayout`).
    @Published var layoutRawValue: Int { didSet { save("layoutRawValue", layoutRawValue) } }

    /// Start reading the touchpad as soon as the app opens.
    @Published var autoStartDriver: Bool { didSet { save("autoStartDriver", autoStartDriver) } }
    /// Register in Login Items so the app launches at macOS startup.
    @Published var launchAtLogin: Bool {
        didSet {
            save("launchAtLogin", launchAtLogin)
            LaunchAtLogin.setEnabled(launchAtLogin)
        }
    }

    private let defaults = UserDefaults.standard

    init() {
        let store = UserDefaults.standard
        func dbl(_ key: String, _ fallback: Double) -> Double {
            store.object(forKey: key) == nil ? fallback : store.double(forKey: key)
        }
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            store.object(forKey: key) == nil ? fallback : store.bool(forKey: key)
        }
        func int(_ key: String, _ fallback: Int) -> Int {
            store.object(forKey: key) == nil ? fallback : store.integer(forKey: key)
        }

        pointerSpeed = dbl("pointerSpeed", 1.6)
        scrollSpeed = dbl("scrollSpeed", 1.0)
        naturalScrolling = bool("naturalScrolling", true)
        oneFingerTapRawValue = int("oneFingerTapRawValue", TapAction.leftClick.rawValue)
        twoFingerTouchGestureRawValue = int("twoFingerTouchGestureRawValue", TouchGestureAction.doubleClick.rawValue)
        threeFingerTouchGestureRawValue = int("threeFingerTouchGestureRawValue", TouchGestureAction.rightClick.rawValue)
        doubleTapDrag = bool("doubleTapDrag2", false)
        twoFingerScroll = bool("twoFingerScroll", true)
        enableGestures = bool("enableGestures", true)
        seizeDevice = bool("seizeDevice", true)
        horizontalSwipeRawValue = int("horizontalSwipeRawValue", HorizontalSwipeAction.spaces.rawValue)
        layoutRawValue = int("layoutRawValue", ReportLayout.userspaceNoReportID.rawValue)
        autoStartDriver = bool("autoStartDriver", true)
        launchAtLogin = bool("launchAtLogin", true)
    }

    var layout: ReportLayout {
        get { ReportLayout(rawValue: layoutRawValue) ?? .userspaceNoReportID }
        set { layoutRawValue = newValue.rawValue }
    }

    var horizontalSwipe: HorizontalSwipeAction {
        get { HorizontalSwipeAction(rawValue: horizontalSwipeRawValue) ?? .spaces }
        set { horizontalSwipeRawValue = newValue.rawValue }
    }

    var oneFingerTap: TapAction {
        get { TapAction(rawValue: oneFingerTapRawValue) ?? .leftClick }
        set { oneFingerTapRawValue = newValue.rawValue }
    }

    var twoFingerTouchGesture: TouchGestureAction {
        get { TouchGestureAction(rawValue: twoFingerTouchGestureRawValue) ?? .doubleClick }
        set { twoFingerTouchGestureRawValue = newValue.rawValue }
    }

    var threeFingerTouchGesture: TouchGestureAction {
        get { TouchGestureAction(rawValue: threeFingerTouchGestureRawValue) ?? .rightClick }
        set { threeFingerTouchGestureRawValue = newValue.rawValue }
    }

    private func save<T>(_ key: String, _ value: T) {
        defaults.set(value, forKey: key)
    }
}
