//
//  SerialManager.swift
//  ProtoArc T1 Plus
//
//  Validates serial numbers from SerialNumbers.txt (weekly + active licenses).
//

import Foundation
import Combine

enum SerialType: String, Codable {
    case weekly
    case active
}

struct LicenseStatus: Equatable {
    var isValid: Bool
    var serial: String
    var type: SerialType
    var expiresAt: Date?
    var message: String

    static let invalid = LicenseStatus(isValid: false, serial: "", type: .weekly,
                                       expiresAt: nil, message: "No license activated")
}

@MainActor
final class SerialManager: ObservableObject {
    static let shared = SerialManager()

    @Published private(set) var status: LicenseStatus = .invalid

    private let activatedSerialKey = "activatedSerial"
    private let activatedTypeKey = "activatedSerialType"
    private let activatedAtKey = "activatedAt"
    private let weeklyDuration: TimeInterval = 7 * 24 * 60 * 60

    private var weeklySerials: Set<String> = []
    private var activeSerials: Set<String> = []

    private init() {
        loadCatalog()
        restoreActivation()
    }

    var isLicensed: Bool { status.isValid }

    func activate(serial raw: String) -> LicenseStatus {
        let serial = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !serial.isEmpty else {
            status = LicenseStatus(isValid: false, serial: "", type: .weekly,
                                   expiresAt: nil, message: "Enter a serial number")
            return status
        }

        if activeSerials.contains(serial) {
            saveActivation(serial: serial, type: .active, activatedAt: Date())
            status = makeStatus(serial: serial, type: .active, activatedAt: Date())
            return status
        }

        if weeklySerials.contains(serial) {
            let now = Date()
            saveActivation(serial: serial, type: .weekly, activatedAt: now)
            status = makeStatus(serial: serial, type: .weekly, activatedAt: now)
            return status
        }

        status = LicenseStatus(isValid: false, serial: serial, type: .weekly,
                               expiresAt: nil, message: "Invalid serial number")
        return status
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: activatedSerialKey)
        UserDefaults.standard.removeObject(forKey: activatedTypeKey)
        UserDefaults.standard.removeObject(forKey: activatedAtKey)
        status = .invalid
    }

    func reloadCatalog() {
        loadCatalog()
        restoreActivation()
    }

    // MARK: - Catalog

    private func loadCatalog() {
        weeklySerials = []
        activeSerials = []

        guard let url = Bundle.main.url(forResource: "SerialNumbers", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }

        var section: SerialType?
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed == "[weekly]" { section = .weekly; continue }
            if trimmed == "[active]" { section = .active; continue }

            if let eq = trimmed.firstIndex(of: "=") {
                let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
                let value = trimmed[trimmed.index(after: eq)...]
                    .trimmingCharacters(in: .whitespaces).uppercased()
                switch key {
                case "weekly": weeklySerials.insert(value)
                case "active": activeSerials.insert(value)
                default: break
                }
                continue
            }

            let code = trimmed.uppercased()
            switch section {
            case .weekly: weeklySerials.insert(code)
            case .active: activeSerials.insert(code)
            case nil: break
            }
        }
    }

    private func restoreActivation() {
        let defaults = UserDefaults.standard
        guard let serial = defaults.string(forKey: activatedSerialKey),
              let typeRaw = defaults.string(forKey: activatedTypeKey),
              let type = SerialType(rawValue: typeRaw),
              let activatedAt = defaults.object(forKey: activatedAtKey) as? Date
        else {
            status = .invalid
            return
        }
        status = validate(serial: serial, type: type, activatedAt: activatedAt)
        if !status.isValid {
            deactivate()
        }
    }

    private func validate(serial: String, type: SerialType, activatedAt: Date) -> LicenseStatus {
        switch type {
        case .active:
            guard activeSerials.contains(serial) else {
                return LicenseStatus(isValid: false, serial: serial, type: type,
                                   expiresAt: nil, message: "Serial revoked or not in catalog")
            }
            return makeStatus(serial: serial, type: .active, activatedAt: activatedAt)

        case .weekly:
            guard weeklySerials.contains(serial) else {
                return LicenseStatus(isValid: false, serial: serial, type: type,
                                   expiresAt: nil, message: "Serial revoked or not in catalog")
            }
            let expires = activatedAt.addingTimeInterval(weeklyDuration)
            if Date() > expires {
                return LicenseStatus(isValid: false, serial: serial, type: type,
                                   expiresAt: expires, message: "Weekly license expired")
            }
            return makeStatus(serial: serial, type: .weekly, activatedAt: activatedAt)
        }
    }

    private func makeStatus(serial: String, type: SerialType, activatedAt: Date) -> LicenseStatus {
        switch type {
        case .active:
            return LicenseStatus(isValid: true, serial: serial, type: .active,
                                 expiresAt: nil, message: "Active license")
        case .weekly:
            let expires = activatedAt.addingTimeInterval(weeklyDuration)
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return LicenseStatus(isValid: true, serial: serial, type: .weekly,
                                 expiresAt: expires,
                                 message: "Weekly license — expires \(formatter.string(from: expires))")
        }
    }

    private func saveActivation(serial: String, type: SerialType, activatedAt: Date) {
        let defaults = UserDefaults.standard
        defaults.set(serial, forKey: activatedSerialKey)
        defaults.set(type.rawValue, forKey: activatedTypeKey)
        defaults.set(activatedAt, forKey: activatedAtKey)
    }
}
