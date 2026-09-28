# PDWatch

A macOS menu bar app for a USB-C monitor with dynamic Power Delivery. It shows
how many watts the monitor is offering your Mac right now, and controls the
Gigabyte M27UP's OSD from the menu bar.

## What it does

- Shows the negotiated PD wattage in the menu bar, with a warning icon when it
  falls below your target (45 W by default).
- Shows what the Mac is actually drawing, the voltage and current of the
  contract, battery state, and a 15-minute history chart.
- Sends a notification when charging drops below the target and when it recovers.
- Controls brightness, contrast, volume, sharpness, blue light filter, color
  temperature and the KVM switch over USB.
- "Dim to save power" lowers brightness to free up the monitor's power budget,
  then restores it.

## Build

Requires macOS 14 or later and Xcode or the Command Line Tools
(`xcode-select --install`).

```sh
./build.sh
open build/PDWatch.app
```

For quick iteration, `swift run` works too, but notifications and
"Open at login" need the .app bundle.

The app builds with just the Command Line Tools. It avoids the `@State`
macro, whose plugin ships only with Xcode on the macOS 27 SDK, and stores
`State(initialValue:)` directly instead.

## Checking the monitor connection

Open **USB devices** at the bottom of the menu. The app expects the monitor's
OSD controller at `0bda:1100` (the Realtek chip in the M27U, M32U and M34WQ).

- If you see `0bda:1100`, you're set.
- If you see a different ID for the monitor, change `vendorID` and `productID`
  in `GigabyteMonitor.swift`.
- If you see `2109:8883`, your unit uses the older M27Q-style protocol
  (USB control transfers instead of HID), which this app doesn't implement yet.

On recent macOS, list USB devices with `system_profiler SPUSBHostDataType`
(`SPUSBDataType` prints nothing).

If the monitor isn't found, check how it's connected. A USB-C dock that
feeds the monitor over HDMI carries no USB, so the OSD controller never
reaches the Mac. The M27UP shows up as a hub (`0bda:5411`) with the HID
controller (`0bda:1100`) behind it, but only when the Mac is connected to the
monitor's USB-C port (or its USB-B upstream port) and KVM routes USB to that input.

## Limits

- The M27UP's USB-C port tops out at 18 W. Its manual lists 5V/3A, 9V/2A,
  12V/1.5A and 15V/1.2A. Gigabyte's "Smart PD (dynamic 45W)" is an OSD
  setting (Settings → Other Settings → Smart PD) described only as adjusting
  wattage between standby and power-on.

- The M27UP isn't confirmed to use this protocol. It's the same family as the
  M27U, which is.
- Commands are write-only, so the sliders show what the app last set, not what
  the monitor's joystick changed.
- OSD control only works from the computer that is the active KVM input.
- There's no known code for the monitor's Power Delivery setting. If you
  find one (for example by capturing OSD Sidekick's USB traffic on Windows with
  Wireshark and USBPcap), add it to `OSDSetting`.

## Credits

The OSD protocol comes from
[kelvie/gbmonctl](https://github.com/kelvie/gbmonctl),
[WildFireFlum/gbmonitor](https://github.com/WildFireFlum/gbmonitor) and
[P403n1x87/m27q](https://github.com/P403n1x87/m27q).
