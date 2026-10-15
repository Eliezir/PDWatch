import SwiftUI

@main
struct PDWatchApp: App {
    // Plain State storage instead of @State: on the macOS 27 SDK @State is a
    // macro whose plugin ships only with Xcode, not the Command Line Tools.
    private let powerState = State(initialValue: PowerMonitor())
    private let displayState: State<GigabyteMonitor>
    private let dualModeState: State<DualModeWatcher>
    private var power: PowerMonitor { powerState.wrappedValue }
    private var display: GigabyteMonitor { displayState.wrappedValue }
    private var dualMode: DualModeWatcher { dualModeState.wrappedValue }

    init() {
        let display = GigabyteMonitor()
        displayState = State(initialValue: display)
        dualModeState = State(initialValue: DualModeWatcher(display: display))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(power: power, display: display, dualMode: dualMode)
            .disclosureGroupStyle(RowDisclosureStyle())
            .shrinksMenuWindowToFit()
        } label: {
            MenuBarLabel(power: power, dualMode: dualMode)
        }
        .menuBarExtraStyle(.window)
    }
}

/// What shows in the menu bar: an icon plus the wattage the monitor is
/// offering, and a display warning while the monitor is stuck in Full HD.
struct MenuBarLabel: View {
    let power: PowerMonitor
    let dualMode: DualModeWatcher

    var body: some View {
        let icon: String = {
            guard power.offeredWatts != nil else { return "bolt.slash" }
            return power.isBelowTarget ? "exclamationmark.triangle.fill" : "bolt.fill"
        }()
        let text = power.offeredWatts.map { "\($0)W" } ?? "–"
        if dualMode.needsAttention {
            Text("\(Image(systemName: icon)) \(text) \(Image(systemName: "display.trianglebadge.exclamationmark"))")
        } else {
            Text("\(Image(systemName: icon)) \(text)")
        }
    }
}
