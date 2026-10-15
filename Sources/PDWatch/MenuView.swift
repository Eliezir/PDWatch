import Charts
import ServiceManagement
import SwiftUI

/// The menu, Control Center style: rounded modules, big sliders you drag
/// anywhere on, and round quick-action buttons. Picture settings and
/// preferences fold away below.
struct MenuView: View {
    let power: PowerMonitor
    let display: GigabyteMonitor
    let dualMode: DualModeWatcher

    private let showPicture = State(initialValue: false)
    private let showSettings = State(initialValue: false)

    var body: some View {
        VStack(spacing: 8) {
            powerModule
            HStack(spacing: 8) {
                batteryModule
                dualModeModule
            }
            monitorModule
            pictureModule
            settingsModule
            FooterSection(display: display, showsDevices: false)
                .padding(.horizontal, 4)
                .padding(.top, 2)
        }
        .padding(10)
        .frame(width: 330)
        .animation(.snappy, value: power.offeredWatts)
        .animation(.snappy, value: display.isConnected)
        .animation(.snappy, value: dualMode.mode)
    }

    private var powerModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconBadge(systemName: power.offeredWatts == nil ? "bolt.slash.fill" : "bolt.fill", color: power.statusColor)
                VStack(alignment: .leading, spacing: 1) {
                    if let watts = power.offeredWatts {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(watts)")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text("W offered").foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No USB-C power")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                if power.offeredWatts != nil {
                    Text(power.statusText)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(power.statusColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(power.statusColor)
                        .transition(.opacity)
                }
            }
            if power.offeredWatts != nil {
                BudgetBar(offered: power.offeredWatts, drawing: power.drawingWatts, target: power.targetWatts)
                    .transition(.opacity)
            }
            HistoryChart(samples: power.history, target: power.targetWatts, height: 40, showsCaption: false, showsAxis: false)
        }
        .module()
    }

    private var subtitle: String {
        var parts: [String] = []
        if let drawing = power.drawingWatts { parts.append(String(format: "Mac draws %.1f W", drawing)) }
        if let v = power.voltage, let a = power.current { parts.append(String(format: "%.0f V · %.1f A", v, a)) }
        if parts.isEmpty { return power.batteryPercent == nil ? "No power readings on this Mac" : "Running on battery" }
        return parts.joined(separator: " · ")
    }

    private var batteryModule: some View {
        HStack(spacing: 8) {
            IconBadge(systemName: power.isCharging ? "battery.100.bolt" : "battery.75", color: power.batteryPercent == nil ? .secondary : .green)
            VStack(alignment: .leading, spacing: 0) {
                Text(power.batteryPercent.map { "\($0)%" } ?? "–")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(power.batteryPercent == nil ? "No battery" : (power.isCharging ? "Charging" : "Not charging"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .module(padding: 10)
    }

    private var dualModeModule: some View {
        Button {
            dualMode.setEnabled(!dualMode.enabled)
        } label: {
            HStack(spacing: 8) {
                IconBadge(systemName: "4k.tv", color: dualMode.enabled ? .accentColor : .secondary, filled: dualMode.enabled)
                VStack(alignment: .leading, spacing: 0) {
                    Text(dualMode.mode?.label ?? "Unknown")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundStyle(dualMode.mode == .fhd ? Color.orange : Color.primary)
                        .contentTransition(.opacity)
                    Text(dualMode.enabled ? "Reminder on" : "Reminder off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .module(padding: 10, highlighted: dualMode.mode == .fhd)
        .help(dualMode.lastAction ?? "Remind me to switch to 4K when the monitor comes back to this Mac in Full HD")
    }

    private var monitorModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "display").foregroundStyle(.secondary)
                Text("Gigabyte M27UP").font(.subheadline.weight(.semibold))
                Spacer()
                StatusDot(on: display.isConnected, label: display.isConnected ? "Connected" : "Not found")
            }
            if !display.isConnected {
                HStack {
                    Text("Connect over USB-C and show this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Scan") { display.rescan() }.controlSize(.small)
                }
            }
            Group {
                BigSlider(systemImage: "sun.max.fill", value: binding(.brightness), range: OSDSetting.brightness.range)
                BigSlider(systemImage: "speaker.wave.2.fill", value: binding(.volume), range: OSDSetting.volume.range)
                HStack(spacing: 0) {
                    RoundAction(systemImage: display.dimmedFrom == nil ? "moon.fill" : "sun.max.fill",
                                label: display.dimmedFrom == nil ? "Dim" : "Restore",
                                active: display.dimmedFrom != nil,
                                tint: power.isBelowTarget && display.dimmedFrom == nil ? .orange : .accentColor) { display.toggleDim() }
                    RoundAction(systemImage: "arrow.left.arrow.right", label: "Switch KVM") { display.toggleKVM() }
                }
            }
            .disabled(!display.isConnected)
            .opacity(display.isConnected ? 1 : 0.5)

            if let action = dualMode.lastAction, dualMode.mode == .fhd {
                Label(action, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let error = display.lastError {
                Text(error).font(.caption).foregroundStyle(.red).transition(.opacity)
            }
        }
        .module()
    }

    private var pictureModule: some View {
        DisclosureGroup(isExpanded: showPicture.projectedValue.animation(.snappy)) {
            VStack(spacing: 8) {
                SliderRow(title: "Contrast", systemImage: "circle.lefthalf.filled", range: OSDSetting.contrast.range, value: binding(.contrast))
                SliderRow(title: "Sharpness", systemImage: "triangle", range: OSDSetting.sharpness.range, value: binding(.sharpness))
                SliderRow(title: "Blue light", systemImage: "moon", range: OSDSetting.lowBlueLight.range, value: binding(.lowBlueLight))
                Picker("Color", selection: binding(.colorTemperature)) {
                    Text("Cool").tag(0)
                    Text("Normal").tag(1)
                    Text("Warm").tag(2)
                    Text("User").tag(3)
                }
                .pickerStyle(.segmented)
            }
            .padding(.top, 8)
            .disabled(!display.isConnected)
        } label: {
            Label("Picture", systemImage: "slider.horizontal.3").font(.subheadline.weight(.medium))
        }
        .module()
    }

    private var settingsModule: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: showSettings.projectedValue.animation(.snappy)) {
                VStack(alignment: .leading, spacing: 6) {
                    Stepper("Alert below \(power.targetWatts) W",
                            value: Binding(get: { power.targetWatts }, set: { power.setTarget($0) }),
                            in: 15...100, step: 5)
                    Toggle("Notify when charging drops",
                           isOn: Binding(get: { power.notifyOnDrop }, set: { power.setNotifyOnDrop($0) }))
                }
                .padding(.top, 8)
            } label: {
                Label("Alerts", systemImage: "bell").font(.subheadline.weight(.medium))
            }
            FooterSection(display: display, showsLoginAndQuit: false)
                .font(.subheadline.weight(.medium))
        }
        .module()
    }

    private func binding(_ setting: OSDSetting) -> Binding<Int> {
        Binding(get: { display.value(setting) }, set: { display.set(setting, to: $0) })
    }
}

private struct IconBadge: View {
    let systemName: String
    let color: Color
    var filled = true

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(filled && color != .secondary ? Color.white : color)
            .frame(width: 28, height: 28)
            .background(filled && color != .secondary ? color : Color.primary.opacity(0.08), in: Circle())
            .contentTransition(.symbolEffect(.replace))
    }
}

/// A Control Center slider: the whole capsule is the hit area.
private struct BigSlider: View {
    let systemImage: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        GeometryReader { geo in
            let span = Double(range.upperBound - range.lowerBound)
            let fraction = Double(value - range.lowerBound) / max(span, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.primary.opacity(0.85))
                    .frame(width: max(geo.size.height, geo.size.width * fraction))
                    .animation(.snappy(duration: 0.18), value: value)
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                    .blendMode(.normal)
                    .padding(.leading, 10)
                HStack {
                    Spacer()
                    Text("\(value)")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .padding(.trailing, 10)
                }
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let f = min(max(drag.location.x / geo.size.width, 0), 1)
                value = range.lowerBound + Int((f * span).rounded())
            })
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 5, range.upperBound)
            case .decrement: value = max(value - 5, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

private struct RoundAction: View {
    let systemImage: String
    let label: String
    var active = false
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(active ? Color.white : Color.primary)
                    .frame(width: 38, height: 38)
                    .background(active ? tint : Color.primary.opacity(0.08), in: Circle())
                    .overlay(Circle().strokeBorder(tint.opacity(active ? 0 : (tint == .accentColor ? 0 : 0.8)), lineWidth: 1.5))
                    .contentTransition(.symbolEffect(.replace))
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: active)
    }
}

extension View {
    func module(padding: CGFloat = 12, highlighted: Bool = false) -> some View {
        self
            .padding(padding)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(highlighted ? Color.orange.opacity(0.7) : Color.primary.opacity(0.05), lineWidth: highlighted ? 1.5 : 1)
            )
    }
}

// MARK: - Shared pieces

extension PowerMonitor {
    var statusText: String {
        guard offeredWatts != nil else { return "Not on USB-C power" }
        return isBelowTarget ? "Reduced" : "Full power"
    }

    var statusColor: Color {
        guard offeredWatts != nil else { return .secondary }
        return isBelowTarget ? .orange : .green
    }
}

/// The monitor's budget at a glance: fill = what it offers,
/// thin tick = your target, dark marker = what the Mac actually draws.
struct BudgetBar: View {
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

struct HistoryChart: View {
    let samples: [PowerSample]
    let target: Int
    var height: CGFloat = 64
    var showsCaption = true
    var showsAxis = true

    var body: some View {
        let peak = samples.reduce(Double(target)) { result, sample in
            max(result, Double(sample.offered ?? 0), sample.drawing ?? 0)
        }
        let hasData = samples.contains { $0.offered != nil || $0.drawing != nil }
        VStack(alignment: .leading, spacing: 2) {
            if showsCaption {
                Text("Last 15 minutes").font(.caption2).foregroundStyle(.tertiary)
            }
            chart(peak: peak)
                .frame(height: height)
                .overlay {
                    if !hasData {
                        Text("No power readings")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .transition(.opacity)
                    }
                }
        }
    }

    private func chart(peak: Double) -> some View {
        Chart {
            RuleMark(y: .value("Target", Double(target)))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary)
            ForEach(samples) { sample in
                if let offered = sample.offered {
                    LineMark(x: .value("Time", sample.date), y: .value("Watts", Double(offered)), series: .value("Series", "Offered"))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(.green)
                }
                if let drawing = sample.drawing {
                    LineMark(x: .value("Time", sample.date), y: .value("Watts", drawing), series: .value("Series", "Drawing"))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.primary.opacity(0.55))
                }
            }
        }
        .chartYScale(domain: 0...(peak + 5))
        .chartXAxis(.hidden)
        .chartYAxis {
            if showsAxis {
                AxisMarks(position: .trailing, values: [0, Double(target)]) { AxisValueLabel() }
            }
        }
    }
}

struct SliderRow: View {
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

struct StatusDot: View {
    let on: Bool
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(on ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct FooterSection: View {
    let display: GigabyteMonitor
    var showsDevices = true
    var showsLoginAndQuit = true
    // See PDWatchApp.swift for why this isn't @State.
    private let showDevices = State(initialValue: false)
    private let launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsDevices {
                DisclosureGroup(isExpanded: showDevices.projectedValue) {
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
                } label: {
                    Label("USB devices", systemImage: "cable.connector")
                }
                .onChange(of: showDevices.wrappedValue) { _, expanded in
                    if expanded { display.refreshDiagnostics() }
                }
            }

            if showsLoginAndQuit {
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
}

// MARK: - Accordion

/// The macOS default only toggles on the chevron. This makes the whole
/// header row clickable and animates the chevron and content.
struct RowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 12)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }
}
