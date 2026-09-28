import SwiftUI

@main
struct PDWatchApp: App {
    // Plain State storage instead of @State: on the macOS 27 SDK @State is a
    // macro whose plugin ships only with Xcode, not the Command Line Tools.
    private let powerState = State(initialValue: PowerMonitor())
    private let displayState = State(initialValue: GigabyteMonitor())
    private var power: PowerMonitor { powerState.wrappedValue }
    private var display: GigabyteMonitor { displayState.wrappedValue }

    var body: some Scene {
        MenuBarExtra {
            MenuView(power: power, display: display)
        } label: {
            MenuBarLabel(power: power)
        }
        .menuBarExtraStyle(.window)
    }
}

/// What shows in the menu bar: an icon plus the wattage the monitor is offering.
struct MenuBarLabel: View {
    let power: PowerMonitor

    var body: some View {
        let icon: String = {
            guard power.offeredWatts != nil else { return "bolt.slash" }
            return power.isBelowTarget ? "exclamationmark.triangle.fill" : "bolt.fill"
        }()
        let text = power.offeredWatts.map { "\($0)W" } ?? "–"
        Text("\(Image(systemName: icon)) \(text)")
    }
}
