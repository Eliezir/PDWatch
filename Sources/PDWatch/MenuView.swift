import Charts
import ServiceManagement
import SwiftUI

struct MenuView: View {
    let power: PowerMonitor
    let display: GigabyteMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PowerSection(power: power)
            Divider()
            DisplaySection(display: display, power: power)
            Divider()
            FooterSection(display: display)
        }
        .padding(14)
        .frame(width: 330)
    }
}

// MARK: - Power

private struct PowerSection: View {
    let power: PowerMonitor

    private var status: (text: String, color: Color) {
        guard power.offeredWatts != nil else { return ("Not on USB-C power", .secondary) }
        return power.isBelowTarget ? ("Reduced", .orange) : ("Full power", .green)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(power.offeredWatts.map(String.init) ?? "–")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: power.offeredWatts)
                Text("W offered")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(status.text)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(status.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(status.color)
            }

            BudgetBar(offered: power.offeredWatts, drawing: power.drawingWatts, target: power.targetWatts)

            VStack(alignment: .leading, spacing: 3) {
                if let drawing = power.drawingWatts {
                    Text("Mac is drawing \(drawing, format: .number.precision(.fractionLength(1))) W")
                }
                if let volts = power.voltage, let amps = power.current {
                    Text("Contract: \(volts, format: .number.precision(.fractionLength(1))) V at \(amps, format: .number.precision(.fractionLength(2))) A")
                }
                if let battery = power.batteryPercent {
                    Text("Battery \(battery)%\(power.isCharging ? ", charging" : "")")
                }
                if let changed = power.lastChange {
                    Text("Last renegotiated \(changed, style: .relative) ago")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            HistoryChart(samples: power.history, target: power.targetWatts)

            Stepper(
                "Alert below \(power.targetWatts) W",
                value: Binding(get: { power.targetWatts }, set: { power.setTarget($0) }),
                in: 15...100,
                step: 5
            )
            Toggle(
                "Notify when charging drops",
                isOn: Binding(get: { power.notifyOnDrop }, set: { power.setNotifyOnDrop($0) })
            )
            if !PowerMonitor.canNotify {
                Text("Notifications need the app bundle. Build it with build.sh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The monitor's budget at a glance: fill = what it offers,
/// thin tick = your target, dark marker = what the Mac actually draws.
private struct BudgetBar: View {
    let offered: Int?
    let drawing: Double?
    let target: Int

    var body: some View {
        let scale = Double(max(target, offered ?? 0, Int((drawing ?? 0).rounded(.up))))
        GeometryReader { geo in
            let width = geo.size.width
            let x = { (watts: Double) in width * min(max(watts / max(scale, 1), 0), 1) }
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 8)
                Capsule()
                    .fill(offered.map { $0 < target } == true ? Color.orange : Color.green)
                    .frame(width: x(Double(offered ?? 0)), height: 8)
                    .animation(.snappy, value: offered)
                Rectangle()
                    .fill(.secondary)
                    .frame(width: 1, height: 14)
                    .offset(x: x(Double(target)) - 1)
                if let drawing {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(.primary)
                        .frame(width: 3, height: 14)
                        .offset(x: x(drawing) - 1.5)
                }
            }
        }
        .frame(height: 14)
        .accessibilityElement()
        .accessibilityLabel("Offering \(offered ?? 0) of \(target) watts")
    }
}

private struct HistoryChart: View {
    let samples: [PowerSample]
    let target: Int

    var body: some View {
        let peak = samples.reduce(Double(target)) { result, sample in
            max(result, Double(sample.offered ?? 0), sample.drawing ?? 0)
        }
        Chart {
            RuleMark(y: .value("Target", Double(target)))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(.secondary)
            ForEach(samples) { sample in
                if let offered = sample.offered {
                    LineMark(x: .value("Time", sample.date), y: .value("Watts", Double(offered)), series: .value("Series", "Offered"))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(.green)
                }
                if let drawing = sample.drawing {
                    LineMark(x: .value("Time", sample.date), y: .value("Watts", drawing), series: .value("Series", "Drawing"))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.primary.opacity(0.6))
                }
            }
        }
        .chartYScale(domain: 0...(peak + 5))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, Double(target)]) { AxisValueLabel() }
        }
        .frame(height: 64)
        .overlay(alignment: .topLeading) {
            Text("Last 15 minutes").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Display

private struct DisplaySection: View {
    let display: GigabyteMonitor
    let power: PowerMonitor

    private func binding(_ setting: OSDSetting) -> Binding<Int> {
        Binding(get: { display.value(setting) }, set: { display.set(setting, to: $0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gigabyte M27UP").font(.headline)
                Spacer()
                Circle()
                    .fill(display.isConnected ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(display.isConnected ? "Connected" : "Not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !display.isConnected {
                Text("Connect the monitor to this Mac over USB-C, and make sure this Mac is the active KVM input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Scan again") { display.rescan() }
            }

            Group {
                SliderRow(title: "Brightness", systemImage: "sun.max", range: OSDSetting.brightness.range, value: binding(.brightness))
                SliderRow(title: "Contrast", systemImage: "circle.lefthalf.filled", range: OSDSetting.contrast.range, value: binding(.contrast))
                SliderRow(title: "Volume", systemImage: "speaker.wave.2", range: OSDSetting.volume.range, value: binding(.volume))
                SliderRow(title: "Sharpness", systemImage: "triangle", range: OSDSetting.sharpness.range, value: binding(.sharpness))
                SliderRow(title: "Blue light", systemImage: "moon", range: OSDSetting.lowBlueLight.range, value: binding(.lowBlueLight))

                Picker("Color", selection: binding(.colorTemperature)) {
                    Text("Cool").tag(0)
                    Text("Normal").tag(1)
                    Text("Warm").tag(2)
                    Text("User").tag(3)
                }
                .pickerStyle(.segmented)

                HStack {
                    Button(display.dimmedFrom == nil ? "Dim to save power" : "Restore brightness") {
                        display.toggleDim()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(power.isBelowTarget && display.dimmedFrom == nil ? .orange : .accentColor)
                    Spacer()
                    Text("KVM").foregroundStyle(.secondary)
                    Button("Device 1") { display.switchKVM(to: 0) }
                    Button("Device 2") { display.switchKVM(to: 1) }
                }
            }
            .disabled(!display.isConnected)

            if let error = display.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("Values show what this app last set. Changes made with the monitor's joystick won't appear here.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct SliderRow: View {
    let title: String
    let systemImage: String
    let range: ClosedRange<Int>
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(title).frame(width: 72, alignment: .leading)
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
            Text("\(value)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .font(.callout)
    }
}

// MARK: - Footer

private struct FooterSection: View {
    let display: GigabyteMonitor
    // See PDWatchApp.swift for why this isn't @State.
    private let showDevices = State(initialValue: false)
    private let launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup("USB devices", isExpanded: showDevices.projectedValue) {
                VStack(alignment: .leading, spacing: 4) {
                    if display.usbDevices.isEmpty {
                        Text("No Gigabyte-related USB devices found.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(display.usbDevices) { device in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(device.name)  \(device.hex)")
                            if let note = device.note {
                                Text(note).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .font(.caption)
                .textSelection(.enabled)
                .padding(.top, 4)
            }
            .onChange(of: showDevices.wrappedValue) { _, expanded in
                if expanded { display.refreshDiagnostics() }
            }

            HStack {
                Toggle("Open at login", isOn: launchAtLogin.projectedValue)
                    .onChange(of: launchAtLogin.wrappedValue) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin.wrappedValue = SMAppService.mainApp.status == .enabled
                        }
                    }
                    .disabled(!PowerMonitor.canNotify) // same requirement: a real .app bundle
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }
}
