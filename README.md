# TX500 Utility

A native macOS utility for the **Lab599 Discovery TX-500**: CAT control, memory channels, settings
backup and restore, clock sync and firmware updates.

**Independent software by Mike (KF5O). Not affiliated with or endorsed by Lab599.**
Lab599, TX-500 and the 599lab logo are their trademarks.

[**Download the latest release**](https://mikeg-dal.github.io/TX500Utility) — signed and notarised.

## What it does

| | |
|---|---|
| **Radio** | Live frequency, mode, S-meter, supply voltage, filter and function badges |
| **Memories** | Read, edit and write all 100 channels; import/export `.mem` files |
| **Settings Backups** | Full 1024-byte backup and restore, with a decoded viewer and backup comparison |
| **Clock** | Set the radio's clock from the Mac |
| **Firmware** | Signed `.fw` transfer to the bootloader, with the steps spelled out |

Backups are written as `.set` files and memory files as `.mem` — the same formats Lab599's own
TRXSettings and TRXMem use. A backup taken by this app has been compared byte-for-byte against one
taken by TRXSettings from the same radio minutes apart: identical.

## Requirements

- macOS 14 or later
- A TX-500 CAT cable (FTDI FT232 or Prolific PL2303 — both use Apple's built-in drivers and appear
  as `/dev/cu.usbserial-*`)
- The radio set to **LAB599** CAT protocol (menu 35). TS-2000 compatibility mode does not implement
  the `XL`/`XS` commands that settings backup relies on.

## Building it yourself

```bash
swift build                     # library, app and CLI
swift test                      # unit tests, no radio needed
swift run TX500Utility          # run the app
swift run tx500 status          # CLI: talk to the radio from a terminal
./Scripts/build-app.sh          # produces build/TX500 Utility.app
```

Requires Xcode 16 or later (Swift 5.10 tools). `Scripts/build-app.sh` assembles a normal
double-clickable `.app`; releases are additionally signed and notarised by CI.

## Layout

```
Sources/
  TX500Kit/        protocol library — no UI, no SwiftUI imports
  TX500Utility/    the SwiftUI app
  tx500cli/        terminal tool for testing against a real radio
Tests/             unit tests using a mock transport and captured responses
Scripts/           build-app.sh
```

`DEVELOPER.md` is the guide for working on it: house rules (no magic numbers, everything styled from
`Theme`), the concurrency model, the safety rules around transmitting and firmware, and what has been
verified on hardware.

## Safety

The radio can transmit, and firmware updates erase the running firmware. Two rules are enforced in
code rather than left to care:

- **`TransmitGuard`** refuses `TX`, `CG010`–`CG100` and tuner-start unless a caller explicitly asks
  for it. `CG` is not obviously a transmit command — it sets the tune carrier level *and keys the
  transmitter*.
- **Firmware**: the loader erases the application firmware as soon as it accepts the 16-byte header,
  so there is no safe "test the link" step. An interrupted update is recoverable — the radio stays in
  loader mode and the update is simply re-run.

Settings restore takes a fresh backup of the radio first, writes only the bytes that differ, and
reads each one back to verify it.

## Contributing

Issues and pull requests welcome. Please read `DEVELOPER.md` first — it explains the conventions the
codebase follows and, more usefully, which parts of the protocol are *verified on hardware* versus
inferred. The Settings Viewer labels every decoded field confirmed / inferred / unknown for the same
reason.

## Licence

GPL-3.0. See `LICENSE`.
