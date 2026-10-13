import Foundation
import IOKit
import IOKit.ps
import Observation

struct PowerSample: Identifiable {
    let id = UUID()
    let date: Date
    /// Watts the monitor is currently offering over USB-C PD.
    let offered: Int?
    /// Watts the Mac is actually pulling from the adapter.
    let drawing: Double?
}

/// One poll of the Mac's power state.
struct PowerReading {
    var offeredWatts: Int?
    var voltage: Double?
    var current: Double?
    var adapterName: String?
    var drawingWatts: Double?
    var batteryPercent: Int?
    var isCharging = false
}

/// Polls macOS for the current USB-C Power Delivery contract.
///
/// - Offered watts come from `IOPSCopyExternalPowerAdapterDetails()`, the same
///   number `system_profiler SPPowerDataType` shows. It changes when the monitor
///   renegotiates.
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
    @ObservationIgnored private let read: () -> PowerReading
    @ObservationIgnored private let services: Services

    /// Notifications only work from a real .app bundle (see build.sh).
    static var canNotify: Bool { Notifier.isAvailable }

    var isBelowTarget: Bool {
        guard let offeredWatts else { return false }
        return offeredWatts < targetWatts
    }

    /// - Parameters:
    ///   - read: where readings come from. The real one asks IOKit.
    ///   - history: samples to start the chart with. The last one counts as
    ///     the previous reading, so a seeded history doesn't look like a change.
    init(
        read: @escaping () -> PowerReading = SystemPower.read,
        services: Services = .live,
        history: [PowerSample] = []
    ) {
        self.read = read
        self.services = services
        targetWatts = services.defaults.object(forKey: Keys.target) as? Int ?? 45
        notifyOnDrop = services.defaults.object(forKey: Keys.notify) as? Bool ?? true

        self.history = history
        offeredWatts = history.last?.offered
        lastChange = Array(zip(history, history.dropFirst())).last { $0.offered != $1.offered }?.1.date

        if notifyOnDrop { services.requestNotificationPermission() }

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
        services.defaults.set(watts, forKey: Keys.target)
    }

    func setNotifyOnDrop(_ enabled: Bool) {
        notifyOnDrop = enabled
        services.defaults.set(enabled, forKey: Keys.notify)
        if enabled { services.requestNotificationPermission() }
    }

    // MARK: Polling

    func refresh() {
        let previous = offeredWatts
        let reading = read()
        offeredWatts = reading.offeredWatts
        voltage = reading.voltage
        current = reading.current
        adapterName = reading.adapterName
        drawingWatts = reading.drawingWatts
        batteryPercent = reading.batteryPercent
        isCharging = reading.isCharging

        let now = Date()
        if offeredWatts != previous {
            lastChange = now
            checkThreshold(old: previous, new: offeredWatts)
        }

        history.append(PowerSample(date: now, offered: offeredWatts, drawing: drawingWatts))
        history.removeAll { now.timeIntervalSince($0.date) > historyWindow }
    }

    // MARK: Alerts

    private func checkThreshold(old: Int?, new: Int?) {
        guard notifyOnDrop, let new else { return }
        let wasAtTarget = (old ?? targetWatts) >= targetWatts

        if new < targetWatts && wasAtTarget {
            services.notify(
                "Charging dropped to \(new) W",
                "The monitor is sharing its power budget. Unplug USB devices or lower brightness to get back to \(targetWatts) W."
            )
        } else if let old, old < targetWatts, new >= targetWatts {
            services.notify("Back to \(new) W", "The monitor is offering full power again.")
        }
    }

    private enum Keys {
        static let target = "power.targetWatts"
        static let notify = "power.notifyOnDrop"
    }
}

/// Reads the Mac's real power state from IOKit.
enum SystemPower {
    static func read() -> PowerReading {
        var reading = PowerReading()
        readAdapter(into: &reading)
        readTelemetry(into: &reading)
        readBattery(into: &reading)
        return reading
    }

    private static func readAdapter(into reading: inout PowerReading) {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else { return }
        reading.offeredWatts = details["Watts"] as? Int
        // Key names differ a little between macOS versions and adapters.
        let millivolts = (details["AdapterVoltage"] as? Int) ?? (details["Voltage"] as? Int)
        let milliamps = details["Current"] as? Int
        reading.voltage = millivolts.map { Double($0) / 1000 }
        reading.current = milliamps.map { Double($0) / 1000 }
        reading.adapterName = (details["Name"] as? String) ?? (details["Description"] as? String)
    }

    private static func readTelemetry(into reading: inout PowerReading) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        guard
            let telemetry = IORegistryEntryCreateCFProperty(
                service, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any],
            let milliwatts = telemetry["SystemPowerIn"] as? Int
        else { return }

        reading.drawingWatts = Double(milliwatts) / 1000
    }

    private static func readBattery(into reading: inout PowerReading) {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in list {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description["Type"] as? String == "InternalBattery"
            else { continue }
            reading.batteryPercent = description["Current Capacity"] as? Int
            reading.isCharging = description["Is Charging"] as? Bool ?? false
            return
        }
    }
}
