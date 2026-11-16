# BTSleepGuard

Stops Bluetooth headphones from connecting to your MacBook while it's asleep.

If you use multipoint headphones (Soundcore, Sony, Bose, etc.), you've probably had this happen: you take your headphones out of the case, and instead of your phone, they connect to the MacBook sitting closed in your bag. BTSleepGuard watches for that and immediately disconnects them, but only while the Mac is asleep. When you open the lid, everything works as normal.

## How it works

It's a tiny native background program (~95 KB) that macOS wakes only when something relevant happens. It runs no polling loops and no shell scripts, and uses no CPU when idle.

| Event | What it does |
|---|---|
| Mac is about to sleep | Starts the "asleep" window and disconnects your headphones if they're still connected |
| Any Bluetooth device connects | If the Mac is asleep and it's one of your headphones, disconnects it immediately |
| Display turns on (you open the lid) | Ends the "asleep" window |

- **Dark wakes / Power Nap** (the Mac briefly waking with the screen off) count as asleep, so connections during those are caught too.
- **Screen off while you're using the Mac** (idle display sleep) doesn't count, so listening with the screen off still works.
- **It never reconnects your headphones on wake**, so it won't steal them from your phone.
- **It only affects the devices you choose.** Your keyboard, mouse, etc. are left alone.

## Install

Requires macOS 12+ and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/Yahya565/BTSleepGuard.git
cd BTSleepGuard
./install.sh "Soundcore P3i"
```

Use your headphones' name exactly as shown in **System Settings → Bluetooth** (they must be paired), or pass their address (`AA:BB:CC:DD:EE:FF`). You can list several devices.

When macOS asks for Bluetooth access for **BTSleepGuard**, click **Allow**. You can check it later under System Settings → Privacy & Security → Bluetooth.

It starts automatically at login and restarts if it crashes.

## Check it's working

```bash
log stream --predicate 'subsystem == "local.btsleepguard"'
```

Close the lid, take your headphones out of the case, then open the lid. You should see:

```
disconnected Soundcore P3i: connected while asleep
```

You may see a few of these in quick succession. That's normal: after a link drops, most headphones retry the last device a few times before giving up. macOS accepts the connection before any app is told about it, and there's no public API to refuse a paired device, so each retry is cut within milliseconds until the headphones stop trying (usually within a few seconds).

## Uninstall

```bash
./uninstall.sh
```

## Why not sleepwatcher + blueutil?

Those are great tools, but neither tells you when a device *connects*. The common workaround is a shell loop that runs `blueutil --disconnect` every few seconds while the Mac sleeps. That loop is frozen during real sleep, can miss short dark wakes, and starts several processes every cycle. BTSleepGuard uses macOS's own Bluetooth connection notification instead, so it reacts the moment the headphones connect and costs nothing in between.

## Notes

- Builds are ad-hoc signed, so macOS will ask for Bluetooth permission again after each reinstall.
- With the lid closed and an external display connected (clamshell mode) the Mac isn't asleep, so nothing is disconnected. This is intended.

## License

MIT
