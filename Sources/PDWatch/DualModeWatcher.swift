import CoreGraphics
import Foundation
import IOKit
import Observation

/// The M27UP's Dual Mode: 4K up to 160 Hz, or Full HD up to 320 Hz.
/// It's a monitor-wide setting, shared by every input.
enum DualMode: Equatable {
    case uhd, fhd

    var label: String {
        switch self {
        case .uhd: return "4K"
        case .fhd: return "Full HD"
        }
    }
}

/// Reminds you to switch the monitor back to 4K when it comes back to this
/// Mac in Full HD mode.
///
/// The monitor reports its current mode through its EDID: in Full HD mode it
/// stops listing any 4K timing. PDWatch can't change the mode itself: the
/// monitor exposes Dual Mode only as a read-only status (vendor code 0xE053),
/// so the reminder asks you to press Tactical Switch.
///
/// The notification goes out when the monitor *becomes* this Mac's input
/// (its USB controller appeared, or macOS added the display), so picking
/// 320 Hz on another computer doesn't nag you there. While the reminder is on
/// and the monitor is in Full HD, the menu bar icon shows it too.
@MainActor
@Observable
final class DualModeWatcher {
    private(set) var mode: DualMode?
    private(set) var lastAction: String?
    private(set) var enabled: Bool

    /// The reminder is on and the monitor is in Full HD mode.
    var needsAttention: Bool { enabled && mode == .fhd }

    @ObservationIgnored private let display: GigabyteMonitor
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let readEDIDs: () -> [[UInt8]]
    @ObservationIgnored private let services: Services

    /// - Parameters:
    ///   - readEDIDs: where EDIDs come from. The real one reads IOKit.
    ///   - watchesDisplays: also react to macOS adding a display. Only the
    ///     app-lifetime watcher should, since the callback can't be removed safely.
    init(
        display: GigabyteMonitor,
        readEDIDs: @escaping () -> [[UInt8]] = DualModeWatcher.systemEDIDs,
        watchesDisplays: Bool = true,
        services: Services = .live
    ) {
        self.display = display
        self.readEDIDs = readEDIDs
        self.services = services
        enabled = services.defaults.object(forKey: Self.enabledKey) as? Bool ?? true

        if enabled { services.requestNotificationPermission() }
        refreshMode()
        display.onConnect = { [weak self] in self?.becameActive(reason: "monitor's USB connected") }
        if watchesDisplays {
            CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
                guard flags.contains(.addFlag), let userInfo else { return }
                let watcher = Unmanaged<DualModeWatcher>.fromOpaque(userInfo).takeUnretainedValue()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { watcher.becameActive(reason: "display added") }
                }
            }, Unmanaged.passUnretained(self).toOpaque())
        }

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMode() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        if display.isConnected { becameActive(reason: "launch") }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        services.defaults.set(value, forKey: Self.enabledKey)
        if value { services.requestNotificationPermission() }
        if value && display.isConnected { becameActive(reason: "turned on") }
    }

    func refreshMode() {
        let newMode = readEDIDs().compactMap(EDIDInfo.init).first { $0.isM27UP }?.mode
        if newMode != mode { mode = newMode }
        if mode != .fhd { lastAction = nil }
    }

    private func becameActive(reason: String) {
        refreshMode()
        guard needsAttention else { return }
        lastAction = "Monitor is in Full HD mode. Press Tactical Switch for 4K."
        services.notify(
            "Monitor is in Full HD mode",
            "Press the Tactical Switch button on the M27UP to go back to 4K."
        )
    }

    /// EDIDs of external displays, from the DisplayPort transport metadata.
    /// This covers both a direct USB-C connection and a dock's DP-to-HDMI output.
    nonisolated static func systemEDIDs() -> [[UInt8]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPortTransportStateDisplayPort"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var result: [[UInt8]] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let metadata = IORegistryEntryCreateCFProperty(service, "Metadata" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
               let edid = metadata["EDID"] as? Data {
                result.append([UInt8](edid))
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return result
    }

    private static let enabledKey = "dualMode.keep4K"
}

/// The parts of an EDID needed to tell the M27UP's two modes apart.
struct EDIDInfo {
    let name: String?
    let maxWidth: Int

    var isM27UP: Bool { name?.hasPrefix("M27U") == true }

    /// In 4K mode the EDID lists 3840-wide timings; in Full HD mode the widest is 1920.
    var mode: DualMode? {
        if maxWidth >= 3840 { return .uhd }
        if maxWidth > 0 && maxWidth <= 1920 { return .fhd }
        return nil
    }

    init?(_ bytes: [UInt8]) {
        guard bytes.count >= 128, bytes[0..<8] == [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00] else { return nil }
        var name: String?
        var maxWidth = 0

        func descriptor(at offset: Int) {
            let pixelClock = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
            if pixelClock != 0 {
                maxWidth = max(maxWidth, Int(bytes[offset + 2]) | Int(bytes[offset + 4] >> 4) << 8)
            } else if bytes[offset + 3] == 0xFC {
                name = String(bytes: bytes[(offset + 5)..<(offset + 18)], encoding: .ascii)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        for offset in stride(from: 54, through: 108, by: 18) { descriptor(at: offset) }

        // CTA-861 extension blocks: 4K video codes plus more detailed timings.
        for start in stride(from: 128, to: bytes.count - 127, by: 128) where bytes[start] == 0x02 {
            let dtdStart = Int(bytes[start + 2])
            var index = start + 4
            while dtdStart > 4, index < start + dtdStart {
                let tag = bytes[index] >> 5
                let length = Int(bytes[index] & 0x1F)
                if tag == 2 {
                    for vic in bytes[(index + 1)..<min(index + 1 + length, start + dtdStart)] {
                        let code = vic & 0x7F
                        if (93...107).contains(code) || (114...127).contains(code) { maxWidth = max(maxWidth, 3840) }
                    }
                }
                index += 1 + length
            }
            if dtdStart >= 4 {
                for offset in stride(from: start + dtdStart, through: start + 127 - 18, by: 18) { descriptor(at: offset) }
            }
        }

        self.name = name
        self.maxWidth = maxWidth
    }
}
