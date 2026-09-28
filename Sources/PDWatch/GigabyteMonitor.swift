import Foundation
import IOKit
import IOKit.hid
import Observation

/// OSD settings the Gigabyte M-series accepts over USB.
/// Codes come from the community projects gbmonctl, gbmonitor and m27q.
enum OSDSetting: String, CaseIterable {
    case brightness, contrast, sharpness, lowBlueLight, colorTemperature, volume, kvm

    var code: UInt16 {
        switch self {
        case .brightness:       return 0x10
        case .contrast:         return 0x12
        case .sharpness:        return 0x87
        case .volume:           return 0x62
        case .colorTemperature: return 0xE003   // 0 cool, 1 normal, 2 warm, 3 user
        case .lowBlueLight:     return 0xE00B
        case .kvm:              return 0xE069   // 0 or 1
        }
    }

    var range: ClosedRange<Int> {
        switch self {
        case .brightness, .contrast, .volume: return 0...100
        case .sharpness, .lowBlueLight:       return 0...10
        case .colorTemperature:               return 0...3
        case .kvm:                            return 0...1
        }
    }

    var defaultValue: Int {
        switch self {
        case .brightness, .contrast, .volume: return 50
        case .sharpness:                      return 5
        case .colorTemperature:               return 1
        case .lowBlueLight, .kvm:             return 0
        }
    }
}

struct USBDeviceInfo: Identifiable, Hashable {
    let name: String
    let vendorID: Int
    let productID: Int

    var id: String { "\(hex)-\(name)" }
    var hex: String { String(format: "%04x:%04x", vendorID, productID) }

    var note: String? {
        switch (vendorID, productID) {
        case (GigabyteMonitor.vendorID, GigabyteMonitor.productID):
            return "OSD controller, supported"
        case (0x2109, 0x8883):
            return "M27Q-style controller, needs a different protocol"
        default:
            return nil
        }
    }
}

/// Talks to the monitor's OSD controller through its built-in USB hub.
///
/// The protocol is write-only: the monitor accepts new values but this path
/// can't read the current ones back, so the app shows what it last set.
/// Only works from the computer that is currently the active KVM input.
@MainActor
@Observable
final class GigabyteMonitor {
    /// Realtek scaler used by the M27U / M32U / M34WQ family.
    /// If Diagnostics shows a different ID for your M27UP, change these.
    static let vendorID = 0x0BDA
    static let productID = 0x1100

    private(set) var isConnected = false
    private(set) var lastError: String?
    private(set) var values: [OSDSetting: Int] = [:]
    private(set) var dimmedFrom: Int?
    private(set) var usbDevices: [USBDeviceInfo] = []

    @ObservationIgnored private let manager: IOHIDManager
    @ObservationIgnored private var devices: [IOHIDDevice] = []
    @ObservationIgnored private var pending: [OSDSetting: DispatchWorkItem] = [:]
    @ObservationIgnored private var timer: Timer?

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            lastError = String(format: "Couldn't open USB devices (0x%08x).", UInt32(bitPattern: result))
        }

        for setting in OSDSetting.allCases where setting != .kvm {
            values[setting] = UserDefaults.standard.object(forKey: key(setting)) as? Int ?? setting.defaultValue
        }
        dimmedFrom = UserDefaults.standard.object(forKey: "osd.dimmedFrom") as? Int

        rescan()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.rescan() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Public API

    func value(_ setting: OSDSetting) -> Int {
        values[setting] ?? setting.defaultValue
    }

    /// Updates a setting. Rapid changes (slider drags) are coalesced so the
    /// monitor gets at most one command every 80 ms per setting.
    func set(_ setting: OSDSetting, to newValue: Int) {
        let clamped = min(max(newValue, setting.range.lowerBound), setting.range.upperBound)
        values[setting] = clamped
        UserDefaults.standard.set(clamped, forKey: key(setting))

        pending[setting]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.send(setting, clamped) }
        }
        pending[setting] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    /// Moves the monitor's picture and USB devices to KVM device 0 or 1.
    func switchKVM(to device: Int) {
        send(.kvm, device)
    }

    /// Drops brightness to free up the monitor's power budget, or restores it.
    func toggleDim(to dimLevel: Int = 25) {
        if let previous = dimmedFrom {
            set(.brightness, to: previous)
            dimmedFrom = nil
            UserDefaults.standard.removeObject(forKey: "osd.dimmedFrom")
        } else {
            let current = value(.brightness)
            dimmedFrom = current
            UserDefaults.standard.set(current, forKey: "osd.dimmedFrom")
            set(.brightness, to: min(current, dimLevel))
        }
    }

    func rescan() {
        devices = matchedDevices()
        isConnected = !devices.isEmpty
    }

    func refreshDiagnostics() {
        let interesting: Set<Int> = [Self.vendorID, 0x2109]
        usbDevices = Self.listUSBDevices()
            .filter { interesting.contains($0.vendorID) || $0.name.localizedCaseInsensitiveContains("gigabyte") }
            .sorted { $0.name < $1.name }
    }

    // MARK: Protocol

    /// Builds the 192-byte output report the monitor expects.
    /// Layout (from gbmonitor): a 64-byte header, then a DDC/CI-style
    /// "set VCP feature" message: 0x51, length, 0x03, code, 0x00, value.
    static func buildReport(code: UInt16, value: UInt8) -> [UInt8] {
        var report: [UInt8] = [0x40, 0xC6, 0x00, 0x00, 0x00, 0x00, 0x20, 0x00, 0x6E, 0x00, 0x80]
        report += Array(repeating: 0, count: 64 - report.count)

        var message: [UInt8] = code > 0xFF ? [UInt8(code >> 8)] : []
        message += [UInt8(code & 0xFF), 0x00, value]

        report += [0x51, UInt8(0x81 + message.count), 0x03] + message
        report += Array(repeating: 0, count: 192 - report.count)
        return report
    }

    private func send(_ setting: OSDSetting, _ value: Int) {
        guard !devices.isEmpty else {
            lastError = "Monitor not found. Make sure this Mac is the active KVM input."
            return
        }
        let report = Self.buildReport(code: setting.code, value: UInt8(clamping: value))

        // The hub can expose more than one HID interface; use the first that accepts it.
        var lastResult: IOReturn = kIOReturnSuccess
        for (index, device) in devices.enumerated() {
            lastResult = report.withUnsafeBufferPointer { buffer in
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, buffer.baseAddress!, buffer.count)
            }
            if lastResult == kIOReturnSuccess {
                if index != 0 { devices.swapAt(0, index) }
                lastError = nil
                return
            }
        }
        lastError = String(format: "The monitor didn't accept the command (0x%08x).", UInt32(bitPattern: lastResult))
    }

    private func matchedDevices() -> [IOHIDDevice] {
        guard let set = IOHIDManagerCopyDevices(manager) else { return [] }
        let count = CFSetGetCount(set)
        var pointers = [UnsafeRawPointer?](repeating: nil, count: count)
        CFSetGetValues(set, &pointers)
        return pointers.compactMap { pointer in
            pointer.map { Unmanaged<IOHIDDevice>.fromOpaque($0).takeUnretainedValue() }
        }
    }

    private static func listUSBDevices() -> [USBDeviceInfo] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var result: [USBDeviceInfo] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            result.append(USBDeviceInfo(
                name: (property("USB Product Name") as? String) ?? (property("kUSBProductString") as? String) ?? "Unnamed device",
                vendorID: property("idVendor") as? Int ?? 0,
                productID: property("idProduct") as? Int ?? 0
            ))
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    private func key(_ setting: OSDSetting) -> String { "osd.\(setting.rawValue)" }
}
