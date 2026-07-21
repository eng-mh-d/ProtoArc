# ProtoArc T1 Plus — macOS Touchpad App

A native SwiftUI macOS app that drives the **ProtoArc T1 Plus** Bluetooth
multi-touch touchpad entirely from **user space** — no DriverKit, no special
Apple entitlement, and no need to disable SIP.

The app opens the device with `IOHIDManager`, parses its raw multi-touch
reports (Report ID 2), and synthesizes cursor movement, clicks, scrolling, and
gestures using `CGEvent` (Quartz Event Services).

* Device matched: **VID 1256 (0x04E8) / PID 28705 (0x7021)**.
* Coordinate space: 0…3200 × 0…2000.

## Features

| Gesture | Action |
| --- | --- |
| 1 finger move | Move cursor (with acceleration) |
| 1 finger tap | Left click |
| Tap, then hold & move | Click-and-drag (tap-and-a-half) |
| 2 finger move | Scroll (natural or standard) |
| 2 finger tap | Right click |
| 2 finger pinch | Zoom in / out (⌘ +, ⌘ −) |
| 3 finger swipe ← / → | Move one Space left / right |
| 3 finger swipe ↑ | Mission Control |
| 3 finger swipe ↓ | App Exposé |

All behaviors are toggleable, with pointer/scroll speed sliders, in the app UI.

## Project layout (build target: `ProtoArc T1 Plus/`)

| File | Responsibility |
| --- | --- |
| `ProtoArc_T1_PlusApp.swift` | App entry point |
| `ContentView.swift` | UI: status, permissions, settings, live touch view, raw report log |
| `TouchpadController.swift` | `IOHIDManager` connection + report dispatch (`ObservableObject`) |
| `ReportParser.swift` | Decodes Report ID 2 into a `TouchFrame` |
| `GestureEngine.swift` | Touch → intent state machine (tap, scroll, pinch, swipe) |
| `EventSynthesizer.swift` | Posts `CGEvent`s (mouse, scroll, keyboard chords) |
| `Permissions.swift` | Accessibility + Input Monitoring checks/prompts |
| `TouchModels.swift` | Data models + persisted `TouchpadSettings` |

## Permissions

The app is **not sandboxed** (required to read HID input and inject events).
On first launch it will ask for two permissions in
**System Settings → Privacy & Security**:

1. **Input Monitoring** — to read the touchpad's reports.
2. **Accessibility** — to move the cursor and post clicks/keystrokes.

After granting either permission you may need to quit and relaunch the app.

## First launch & help

- The **Welcome & License** window shows **intro slides** (what the app does, macOS permissions, Bluetooth & menu bar), then **serial activation**. Use **Skip intro** or **Next** to move through; after the first visit, the window opens on the activation page (use **See intro slides again** to replay).
- **More** opens an in-app **How to use** sheet (steps, gestures, and how to open the guide on other devices).
- **User guide (browser)** — `UserGuide.html` is bundled with the app. The menu bar includes **User guide (browser)…**; Settings includes **Open user guide in browser**. The HTML is responsive and can be copied to iCloud or a web server and opened on **iPhone, iPad, or Android** in Safari / Chrome (the touchpad **driver** itself remains **macOS-only**). For Android **native** splash behavior (no logo), see `android/no-logo-splash/README.md`.

## Developer guide (PDF, English + Arabic)

- **PDF:** `docs/ProtoArc_T1_Plus_Developer_Guide.pdf` — how to build the app and what each source file does (English first, then Arabic).
- **HTML (printable):** `docs/ProtoArc_T1_Plus_Developer_Guide.html` — open in Safari and use **File → Print → Save as PDF** if you want a PDF without Python.
- **Regenerate the PDF** (requires `reportlab`, `arabic-reshaper`, `python-bidi`, and `docs/fonts/NotoSansArabic-Regular.ttf`):

  ```bash
  python3 -m pip install --user reportlab arabic-reshaper python-bidi
  python3 docs/build_guide_pdf.py
  ```

## Building & running

1. Open `ProtoArc T1 Plus.xcodeproj` in Xcode 26+.
2. Select the **ProtoArc T1 Plus** scheme and press Run (⌘R).
   (Signing can be left as "Sign to Run Locally" / automatic.)
3. Grant Input Monitoring and Accessibility when prompted.
4. Pair the ProtoArc T1 Plus over Bluetooth.
5. Press **Start** in the app. The status dot turns green when the device attaches.

Or from the command line:

```bash
xcodebuild -project "ProtoArc T1 Plus.xcodeproj" \
  -scheme "ProtoArc T1 Plus" -configuration Debug build
```

## Calibrating the report layout

The exact on-the-wire byte layout can vary by how macOS delivers the report.
If touches don't track correctly:

1. Toggle **Log raw reports** in the app to see live hex dumps.
2. Confirm reports arrive with `id=2`.
3. Flip the **Report layout** picker between *Report ID stripped* (default for
   `IOHIDManager`) and *Report ID included*, watching the live touch view.
4. If coordinates look swapped/scaled, adjust the maximums in
   `DeviceIDs` (`TouchModels.swift`) or the parsing in `ReportParser.swift`.

The report format (decoded from the device's actual HID descriptor, confirmed
via `ioreg`) is a Windows-Precision-Touchpad-style frame, **19 bytes** of
payload (the device's `MaxInputReportSize` of 20 includes the Report ID byte,
which `IOHIDManager` strips):

```
Finger[0..3]   // 4 bytes each = 16 bytes
  byte 0:  bit0     tipSwitch
           bit1     inRange
           bits2-3  padding
           bits4-7  contactID (4-bit, 0..15)
  byte 1-3: X (12-bit) then Y (12-bit), little-endian bit packing
            v = b1 | (b2<<8) | (b3<<16);  X = v & 0xFFF;  Y = (v>>12) & 0xFFF
            (X max 3200, Y max 2000)
uint16  scanTime        // little-endian
uint8   bits0-6 contactCount (0..127)
        bit7    button (physical clickpad press)
```

The device also exposes **Report ID 1** as a standard relative mouse, which is
why macOS moves the cursor on its own. Because `IOHIDManager` is opened with
`kIOHIDOptionsTypeSeizeDevice` (the "Seize device" toggle, on by default), the
app takes exclusive control so the system and this app don't both process input.

## Note on the DriverKit files

The repository also contains an earlier DriverKit attempt at the project root
(`ProtoArcTouchpadDriver.cpp`, `.iig`, `.entitlements`, `ExtensionManager.swift`).
These are **not part of the app target** and are kept only for reference. The
DriverKit route requires Apple's `com.apple.developer.driverkit.transport.hid`
entitlement (granted by special request) and disabling SIP for local testing,
which is why this app uses the user-space approach instead.
