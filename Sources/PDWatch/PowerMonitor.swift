import Foundation
import IOKit
import IOKit.ps
import Observation
import UserNotifications

struct PowerSample: Identifiable {
    let id = UUID()
    let date: Date
    /// Watts the monitor is currently offering over USB-C PD.
    let offered: Int?
    /// Watts the Mac is actually pulling from the adapter.
    let drawing: Double?
}

/// Polls macOS for the current USB-C Power Delivery contract.
///
/// - Offered watts come from `IOPSCopyExternalPowerAdapterDetails()`, the same
///   number `system_profiler SPPowerDataType` shows. It changes when the monitor
///   renegotiates (its dynamic 18–45 W budget).
/// - Live draw comes from the `PowerTelemetryData` dictionary on
///   `AppleSmartBattery` (`SystemPowerIn`, in milliwatts). Only laptops have it.
@MainActor
@Observable
final class PowerMonitor {
    private(set) var offeredWatts: Int?
    private(set) var voltage: Double?          // volts
    private(set) var current: Double?          // amps
    private(set) var adapterName: String?
    private(set) var drawingWatts: Double?
    private(set) var batteryPercent: Int?
    private(set) var isCharging = false
    private(set) var lastChange: Date?
    private(set) var history: [PowerSample] = []

    private(set) var targetWatts: Int
    private(set) var notifyOnDrop: Bool

    /// How much history the chart keeps.
    let historyWindow: TimeInterval = 15 * 60
    let pollInterval: TimeInterval = 2

    @ObservationIgnored private var timer: Timer?

    /// Notifications only work from a real .app bundle (see build.sh).
    /// Under `swift run`, UNUserNotificationCenter would crash, so we skip it.
    static let canNotify = Bundle.main.bundlePath.hasSuffix(".app")

    var isBelowTarget: Bool {
        guard let offeredWatts else { return false }
        return offeredWatts < targetWatts
    }

    init() {
        let defaults = UserDefaults.standard
        targetWatts = defaults.object(forKey: Keys.target) as? Int ?? 45
        notifyOnDrop = defaults.object(forKey: Keys.notify) as? Bool ?? true

        if Self.canNotify && notifyOnDrop {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        refresh()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // .common keeps it ticking while the menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: Settings

    func setTarget(_ watts: Int) {
        targetWatts = watts
        UserDefaults.standard.set(watts, forKey: Keys.target)
    }

    func setNotifyOnDrop(_ enabled: Bool) {
        notifyOnDrop = enabled
        UserDefaults.standard.set(enabled, forKey: Keys.notify)
        if enabled && Self.canNotify {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    // MARK: Polling

    func refresh() {
        let previous = offeredWatts
        readAdapter()
        readTelemetry()
        readBattery()

        let now = Date()
        if offeredWatts != previous {
            lastChange = now
            checkThreshold(old: previous, new: offeredWatts)
        }

        history.append(PowerSample(date: now, offered: offeredWatts, drawing: drawingWatts))
        history.removeAll { now.timeIntervalSince($0.date) > historyWindow }
    }

    private func readAdapter() {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            offeredWatts = nil; voltage = nil; current = nil; adapterName = nil
            return
        }
        offeredWatts = details["Watts"] as? Int
        // Key names differ a little between macOS versions and adapters.
        let millivolts = (details["AdapterVoltage"] as? Int) ?? (details["Voltage"] as? Int)
        let milliamps = details["Current"] as? Int
        voltage = millivolts.map { Double($0) / 1000 }
        current = milliamps.map { Double($0) / 1000 }
        adapterName = (details["Name"] as? String) ?? (details["Description"] as? String)
    }

    private func readTelemetry() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { drawingWatts = nil; return }
        defer { IOObjectRelease(service) }

        guard
            let telemetry = IORegistryEntryCreateCFProperty(
                service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any],
            let milliwatts = telemetry["SystemPowerIn"] as? Int
        else { drawingWatts = nil; return }

        drawingWatts = Double(milliwatts) / 1000
    }

    private func readBattery() {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { batteryPercent = nil; return }

        for source in list {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description["Type"] as? String == "InternalBattery"
            else { continue }
            batteryPercent = description["Current Capacity"] as? Int
            isCharging = description["Is Charging"] as? Bool ?? false
            return
        }
        batteryPercent = nil
    }

    // MARK: Alerts

    private func checkThreshold(old: Int?, new: Int?) {
        guard notifyOnDrop, Self.canNotify, let new else { return }
        let wasAtTarget = (old ?? targetWatts) >= targetWatts

        if new < targetWatts && wasAtTarget {
            post(
                title: "Charging dropped to \(new) W",
                body: "The monitor is sharing its power budget. Unplug USB devices or lower brightness to get back to \(targetWatts) W."
            )
        } else if let old, old < targetWatts, new >= targetWatts {
            post(title: "Back to \(new) W", body: "The monitor is offering full power again.")
        }
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private enum Keys {
        static let target = "power.targetWatts"
        static let notify = "power.notifyOnDrop"
    }
}
