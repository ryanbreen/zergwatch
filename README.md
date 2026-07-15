# Zerg Watch

Zerg Watch is a macOS menu bar app that tracks StarCraft-style "APM"
(actions per minute) for your whole desktop — every keystroke and mouse
click, across every app. Alongside APM it tracks a second metric, "hotkey
chords": key downs held with Command, Option, or Control (Shift alone
doesn't count).

## Features

- Live ⚡APM readout right in the menu bar.
- Dashboard window with a per-hour Swift Charts view of actions vs. chords.
- Top Combos — your most-used hotkey chords, ranked.
- Top Apps — which apps you're most active in.
- A live Recent feed of the latest captured events.
- A playstyle tier based on your APM.

## Requirements

- macOS 14+
- Swift 6 toolchain

## Build

```sh
swift build -c release
```

Or build + assemble a signed `.app` bundle:

```sh
./build-app.sh
```

The release binary is `.build/release/ZergWatch`; the app bundle (via
`build-app.sh`) is `ZergWatch.app`.

## Permissions

Zerg Watch needs **both**:

- **Accessibility** — to install the session-level `CGEventTap` used to
  capture mouse clicks.
- **Input Monitoring** — to read keyboard HID events (needed to count
  keystrokes reliably, including when another app has grabbed the keyboard).

Grant both in **System Settings > Privacy & Security**. Zerg Watch polls
for these grants, so it starts tracking automatically once permission is
available — no relaunch needed.

## Privacy

Zerg Watch records **counts only**. It stores keycodes and modifier flags —
**never the characters you type**. It does not read event unicode strings,
and top hotkey combos are rendered locally through a fixed key-code name
table. Nothing leaves your machine; the app makes no network calls.

Data is plain JSON, one file per day, at:

```text
~/Library/Application Support/ZergWatch/YYYY-MM-DD.json
```

The app autosaves every 30 seconds, saves on normal termination, and rolls
over at local midnight.

## Known issue: Karabiner-Elements

If [Karabiner-Elements](https://karabiner-elements.pqrs.org/) is running, it
**seizes the keyboard HID device**, so a plain HID-level observer sees zero
keyboard events (mouse clicks still come through fine). Zerg Watch works
around this with a two-tier capture strategy: it first tries an IOKit HID
path, and falls back to an NSEvent global monitor at the session level
(Karabiner re-emits synthesized events there, so chords still get counted).

**Symptom:** mouse clicks count normally, but key presses and chords don't
move. **Usual cause:** Input Monitoring hasn't been granted — check that
first before assuming Karabiner is the problem; the fallback path generally
handles Karabiner fine once permission is granted.

## Signing tip

By default `build-app.sh` signs ad-hoc, which means macOS invalidates your
Accessibility/Input Monitoring grants on every rebuild (ad-hoc signing
changes the app's cdhash each time). To make grants persist across
rebuilds, create your own stable local signing certificate and point
`build-app.sh` at it:

```sh
# Generate a self-signed code signing cert
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem \
    -days 3650 -nodes -subj "/CN=Zerg Watch Local Signing"

# Package it as a .p12 (macOS's importer requires the legacy PBE format)
openssl pkcs12 -export -legacy -inkey key.pem -in cert.pem \
    -out zergwatch-signing.p12 -passout pass:changeme

# Create a dedicated keychain and import the cert
security create-keychain -p changeme zergwatch-signing.keychain-db
security import zergwatch-signing.p12 -k zergwatch-signing.keychain-db \
    -P changeme -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k changeme \
    zergwatch-signing.keychain-db

# Point build-app.sh at it
export ZERGWATCH_SIGN_IDENTITY="Zerg Watch Local Signing"
export ZERGWATCH_KEYCHAIN="$PWD/zergwatch-signing.keychain-db"
export ZERGWATCH_KEYCHAIN_PASSWORD="changeme"
./build-app.sh
```

## Launch at Login

A LaunchAgent template is at `packaging/com.wrb.apmmeter.plist`.
Edit it to point at your built `ZergWatch.app` (see the comment at the top
of the file), then install it:

```sh
./build-app.sh
cp packaging/com.wrb.apmmeter.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.wrb.apmmeter.plist
```

To remove it:

```sh
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.wrb.apmmeter.plist
rm ~/Library/LaunchAgents/com.wrb.apmmeter.plist
```

## License

MIT — see [LICENSE](LICENSE).
