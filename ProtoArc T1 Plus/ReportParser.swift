//
//  ReportParser.swift
//  ProtoArc T1 Plus
//
//  Decodes the raw HID input report (Report ID 2) into a `TouchFrame`.
//
//  Layout was reverse-engineered from the device's actual HID report descriptor
//  (confirmed via `ioreg` Digitizer element dump). Report ID 2 carries a
//  Windows-Precision-Touchpad-style frame:
//
//      Finger[0..3]  (4 bytes each, 16 bytes total):
//          byte 0:  bit0 tipSwitch
//                   bit1 inRange
//                   bits2-3 padding
//                   bits4-7 contactID (4-bit, 0...15)
//          byte 1-3: X (12-bit) then Y (12-bit), little-endian bit packing
//                    v = b1 | (b2<<8) | (b3<<16);  X = v & 0xFFF;  Y = (v>>12)&0xFFF
//          (X max 3200, Y max 2000)
//      Scan time     (2 bytes, 16-bit little-endian)
//      Last byte:    bits0-6 contactCount (0...127)
//                    bit7     button (physical click)
//
//  Total payload = 19 bytes. The device's MaxInputReportSize is 20, which
//  includes the leading Report ID byte. `IOHIDManager` usually delivers the
//  payload with that Report ID byte stripped (so 19 bytes, ID passed
//  separately); `ReportLayout` lets the user flip this if needed.
//

import Foundation

enum ReportLayout: Int, CaseIterable, Identifiable {
    /// Buffer starts at finger 0 (Report ID already stripped). IOHIDManager default.
    case userspaceNoReportID = 0
    /// Buffer starts at the Report ID byte (raw 20-byte buffer).
    case rawWithReportID = 1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .userspaceNoReportID: return "Report ID stripped (default)"
        case .rawWithReportID: return "Report ID included"
        }
    }

    /// Byte offset of the first finger within the supplied buffer.
    var dataOffset: Int {
        switch self {
        case .userspaceNoReportID: return 0
        case .rawWithReportID: return 1
        }
    }
}

/// Left / right / middle state of the physical buttons.
struct MouseButtons: Equatable {
    var left: Bool
    var right: Bool
    var middle: Bool

    static let none = MouseButtons(left: false, right: false, middle: false)
}

enum ReportParser {
    static let reportID: UInt32 = 2
    /// The device also exposes a standard relative-mouse report; the physical
    /// left / right buttons are reported here as HID buttons.
    static let mouseReportID: UInt32 = 1
    static let maxContacts = 4
    static let bytesPerContact = 4
    /// fingers(16) + scanTime(2) + countByte(1)
    static let payloadLength = 19

    /// Parse a raw report buffer into a `TouchFrame`.
    /// - Returns: nil when the buffer is too short to decode safely.
    static func parse(_ bytes: UnsafePointer<UInt8>, length: Int, layout: ReportLayout) -> TouchFrame? {
        let base = layout.dataOffset
        guard length - base >= payloadLength else { return nil }

        var contacts: [TouchContact] = []
        contacts.reserveCapacity(maxContacts)

        var off = base
        for _ in 0..<maxContacts {
            let flags = bytes[off]
            let tip = (flags & 0x01) != 0
            let inRange = (flags & 0x02) != 0
            let cid = Int((flags >> 4) & 0x0F)

            // 12-bit X then 12-bit Y, packed LSB-first across 3 bytes.
            let b1 = UInt32(bytes[off + 1])
            let b2 = UInt32(bytes[off + 2])
            let b3 = UInt32(bytes[off + 3])
            let v = b1 | (b2 << 8) | (b3 << 16)
            let x = v & 0xFFF
            let y = (v >> 12) & 0xFFF

            if tip || inRange {
                contacts.append(TouchContact(
                    contactID: cid,
                    tipSwitch: tip,
                    inRange: inRange,
                    rawX: Double(x),
                    rawY: Double(y)
                ))
            }
            off += bytesPerContact
        }

        let scanTime = Int(bytes[base + 16]) | (Int(bytes[base + 17]) << 8)
        let countByte = bytes[base + 18]
        let count = Int(countByte & 0x7F)
        let button = (countByte & 0x80) != 0

        return TouchFrame(timestamp: scanTime, contacts: contacts, contactCount: count, button: button)
    }

    /// Decode the buttons from a standard mouse report (Report ID 1). In the
    /// HID boot-mouse layout the first payload byte holds the button bits
    /// (bit0 = left, bit1 = right, bit2 = middle).
    static func mouseButtons(_ bytes: UnsafePointer<UInt8>, length: Int, layout: ReportLayout) -> MouseButtons? {
        let base = layout.dataOffset
        guard length - base >= 1 else { return nil }
        let b = bytes[base]
        return MouseButtons(left: (b & 0x01) != 0,
                            right: (b & 0x02) != 0,
                            middle: (b & 0x04) != 0)
    }

    /// Hex dump for the calibration log.
    static func hexString(_ bytes: UnsafePointer<UInt8>, length: Int) -> String {
        var parts: [String] = []
        parts.reserveCapacity(length)
        for i in 0..<length {
            parts.append(String(format: "%02X", bytes[i]))
        }
        return parts.joined(separator: " ")
    }
}
