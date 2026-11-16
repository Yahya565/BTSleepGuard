// BTSleepGuard — keeps specific Bluetooth devices (e.g. headphones) off the Mac while it sleeps.
//
// Fully event-driven: no polling, no timers, no child processes. Between events the process
// is blocked in its run loop (0% CPU). It only runs code when:
//   • the system is about to sleep        → mark "asleep", drop the target if it's connected
//   • any Bluetooth device connects       → if asleep and it's a target, drop it immediately
//   • the display turns back on           → mark "awake" (a real, user-visible wake)
//
// Dark wakes / Power Nap keep the display off, so they stay inside the "asleep" window.
// Idle display sleep alone does NOT count, so listening with the screen off is unaffected.
//
// Usage: BTSleepGuard <address> [address ...]   e.g. BTSleepGuard AA:BB:CC:DD:EE:FF
// Logs:  log stream --predicate 'subsystem == "local.btsleepguard"'

import AppKit
import CoreBluetooth
import IOBluetooth
import os

private let log = Logger(subsystem: "local.btsleepguard", category: "guard")

/// "AA:BB:CC:DD:EE:FF" / "aa-bb-cc-dd-ee-ff" → IOBluetooth's "aa-bb-cc-dd-ee-ff".
private func normalize(_ s: String) -> String {
    s.lowercased().replacingOccurrences(of: ":", with: "-")
}

final class SleepGuard: NSObject {
    private let targets: Set<String>
    private var asleep = false
    private var connectToken: IOBluetoothUserNotification?

    init(targets: Set<String>) {
        self.targets = targets
        super.init()
    }

    func start() {
        // Read-only check (doesn't prompt). The installer reads this line to confirm setup.
        let access: String
        switch CBManager.authorization {
        case .allowedAlways: access = "granted"
        case .notDetermined: access = "pending"   // macOS shows the Allow prompt during registration below
        default:             access = "denied"
        }
        log.notice("bluetooth access: \(access, privacy: .public)")

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(willSleep(_:)),
                       name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(screensDidWake(_:)),
                       name: NSWorkspace.screensDidWakeNotification, object: nil)

        // One system-wide callback per connection. It also fires for already-connected
        // devices at registration; those are ignored because we start awake.
        connectToken = IOBluetoothDevice.register(forConnectNotifications: self,
                                                  selector: #selector(deviceConnected(_:device:)))
        log.notice("started, guarding \(self.targets.sorted().joined(separator: ", "), privacy: .public)")
    }

    @objc private func willSleep(_: Notification) {
        asleep = true
        // Headphones can stay linked through a lid close; cut them before the system sleeps.
        for addr in targets {
            if let device = IOBluetoothDevice(addressString: addr), device.isConnected() {
                disconnect(device, why: "system going to sleep")
            }
        }
    }

    @objc private func screensDidWake(_: Notification) {
        asleep = false
    }

    @objc private func deviceConnected(_: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard asleep,
              let addr = device.addressString,
              targets.contains(normalize(addr)) else { return }
        disconnect(device, why: "connected while asleep")
    }

    private func disconnect(_ device: IOBluetoothDevice, why: String) {
        let rc = device.closeConnection()
        let name = device.nameOrAddress ?? "device"
        if rc == kIOReturnSuccess {
            log.notice("disconnected \(name, privacy: .public): \(why, privacy: .public)")
        } else {
            log.error("could not disconnect \(name, privacy: .public) (IOReturn \(rc, privacy: .public))")
        }
    }
}

let targets = Set(CommandLine.arguments.dropFirst().map(normalize))
guard !targets.isEmpty else {
    FileHandle.standardError.write(Data("usage: BTSleepGuard <bluetooth-address> [...]\n".utf8))
    exit(64)
}

let sleepGuard = SleepGuard(targets: targets)
sleepGuard.start()
RunLoop.main.run()
