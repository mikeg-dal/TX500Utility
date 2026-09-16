# TX500 Utility — Developer Guide

A native macOS utility for the **Lab599 Discovery TX-500**: CAT control, memory channels,
settings backup, clock sync and firmware updates. It is a *utility*, not an SDR/panadapter.
Keep the UI simple and task-focused.

## Quick start

```bash
cd TX500Utility
swift build                     # builds library, app and CLI
swift test                      # unit tests (no radio needed)
swift run TX500Utility          # launches the app
swift run tx500 status          # CLI: talk to the radio from the terminal
open Package.swift              # opens the package in Xcode
```

Requirements: macOS 14+, Xcode 16+ (Swift 5.10 tools). The TX-500 CAT cable (FTDI FT232 or
Prolific PL2303) uses Apple's built-in drivers; it shows up as `/dev/cu.usbserial-*`.

## Layout

```
TX500Utility/
├── Package.swift
├── DEVELOPER.md                 ← this file
├── Sources/
│   ├── TX500Kit/                ← protocol library. No UI, no SwiftUI imports.
│   │   ├── TX500Protocol.swift  ← ALL protocol constants (baud rates, timeouts, field layouts)
│   │   ├── SerialPort.swift     ← termios transport + SerialTransport protocol
│   │   ├── PortDiscovery.swift  ← IOKit enumeration of serial ports
│   │   ├── KenwoodCAT.swift     ← CAT session actor (query/send/typed getters & setters)
│   │   ├── RigState.swift       ← response parsers and value types
│   │   ├── SettingsBackup.swift ← XL/XS 1024-byte settings table, .set files
│   │   ├── BackupLibrary.swift  ← folder of .set backups: save/import/export/delete (Trash), source from file name
│   │   ├── SettingsField.swift  ← one decoded field (offset, kind, scale, unit, confidence)
│   │   ├── BackupComparison.swift ← which bytes ever change across a set of backups
│   │   ├── SettingsLayout.swift ← decoded field map of the settings table + FilterTable (confidence-tagged)
│   │   ├── LevelScale.swift     ← raw CAT value ↔ front-panel units (%, dB, CPM)
│   │   ├── MemoryChannel.swift  ← MR/MW channels, TRXMem-compatible .mem files
│   │   ├── TimeSync.swift       ← TM clock set/read
│   │   ├── FirmwareImage.swift  ← .fw validation (BL20 header, size, SHA-256)
│   │   └── Bootloader.swift     ← firmware transfer actor (57600, header → OK → payload → OK)
│   ├── TX500Utility/            ← SwiftUI app
│   │   ├── App/                 ← entry point, RootView, AppSection (sidebar)
│   │   ├── Theme/Theme.swift    ← ALL styling tokens (spacing, fonts, colors, sizes)
│   │   ├── Components/          ← reusable views (Card, LabeledValue, MeterBar, StatusBadge, ErrorBanner)
│   │   ├── Services/            ← app-wide state: RadioConnection (owns the port), RadioLoader (connect-time
│   │   │                          load + cached memories/settings/clock), BackupStore, AppPreferences, FilePanels
│   │   ├── Resources/           ← bundled assets (SplashLogo.png for the loading screen)
│   │   └── Features/<Name>/     ← one folder per sidebar section (views + feature logic)
│   └── tx500cli/                ← terminal tool for testing TX500Kit against a real radio
└── Tests/TX500KitTests/         ← unit tests using MockTransport, captured responses and Fixtures/*.set
```

**Dependency direction:** `Features → Components/Theme/Services → TX500Kit`. TX500Kit never
imports the app. Features never import each other; shared behavior goes in `Services` or `Components`.

## Standards

### No magic numbers
- **Protocol values** (baud rates, timeouts, command names, field offsets, value ranges) live in
  `TX500Protocol` (`TX500Kit/TX500Protocol.swift`), grouped by subsystem (`CAT`, `Bootloader`,
  `Settings`, `Memory`, `Clock`). Each has a doc comment saying where the value came from.
- **Visual values** (spacing, radii, fonts, colors, opacities, fixed sizes, animations) live in
  `Theme` (`TX500Utility/Theme/Theme.swift`). Views use `Theme.Spacing.md`, never `12`.
- The only literals allowed inline are `0`, `1`, and string command mnemonics like `"FA"` that
  *are* the protocol.

### Theme
| Token group | Use for |
|---|---|
| `Theme.Spacing.xxs…xxl` | padding & stack spacing (4-pt scale: 2, 4, 8, 12, 16, 24, 32) |
| `Theme.Radius.sm/md/lg` | corner radii |
| `Theme.Typography.*` | every `.font(...)` (frequency, value, label, sectionTitle, mono…) |
| `Theme.Palette.*` | every color; semantic names (`receive`, `transmit`, `warning`), never `.red` in a view |
| `Theme.Opacity.*` | tints and disabled states |
| `Theme.Metrics.*` | fixed component sizes (meter height, field width, min window size) |
| `Theme.Motion.*` | animations |

Need a new value? Add a token to `Theme`, then use it. Build screens from the shared `Components`
(e.g. wrap every panel in `Card`) so all sections look the same.

### Naming conventions
- Types `UpperCamelCase`; properties/functions `lowerCamelCase`; no prefixes like `TX5`.
- Views end in `View` (`RadioView`); reusable pieces are named by what they are (`Card`, `MeterBar`).
- Feature folders match the `AppSection` case: `Features/Radio/RadioView.swift` ↔ `AppSection.radio`.
- Protocol commands keep their radio mnemonic in comments/strings (`"XL"`, `"MR"`), but APIs use
  plain English (`readSettings()`, `memoryChannel(_:)`).
- Errors: one `enum …Error: LocalizedError` per subsystem with user-readable `errorDescription`.
- Files hold one primary type, named after the file.

### Scope
The app does five things: CAT control, memory channels, settings backup/restore/compare, clock sync and
firmware updates. Reverse-engineering tools do **not** belong in it — put them in `tools/`.

### Connect-time loading
`RadioLoader.connectAndLoad()` connects, then reads status → filters → clock → memories → settings and applies
the automatic-backup preference. Features show `loader.memories` / `loader.settings` / `loader.clockSupported`
immediately and push fresh data back (`updateMemories`, `updateSettings`) after their own reads or writes.
Long reads loop over small actor calls (one memory, one 16-byte `XL` batch) so live polling keeps running.
Preferences (⌘,) are defined in `AppPreferences`; add new keys there, bind with `@AppStorage` in `PreferencesView`.

### Concurrency
- All serial I/O runs inside an **actor** (`KenwoodCAT`, `Bootloader`), so commands never interleave.
- UI state is `@MainActor @Observable` (`RadioConnection`). Views get it via `@Environment`.
- Only **one owner** of the port at a time. Anything needing exclusive access (firmware update)
  calls `RadioConnection.releasePort()` first.

### Safety rules (non-negotiable)
- Never send `TX;`, settings writes (`XS`), memory writes (`MW`) or firmware data without an explicit
  user action and confirmation in the UI.
- Take an automatic settings backup before restore or firmware update.
- Open ports with DTR/RTS cleared (already done in `SerialPort.open()`).

### Firmware update facts (verified on hardware)
- The loader erases the application firmware as soon as it accepts the 16-byte header. There is no
  "safe handshake test": after `OK` the radio boots into the loader until a full update completes.
- An interrupted update is recoverable: the bootloader survives, so the update can simply be re-run.

### Verified on hardware (2026-09-16, firmware 1.30.00)
- **Backup** matches Lab599's own Windows TRXSettings tool byte for byte, same radio minutes apart.
  Both files are test fixtures; `SettingsLayoutTests` compares them on every build.
- **Restore** works end to end: factory reset the radio, restored a backup through the app, and all
  the settings in that backup came back. Memory channels and CW messages are not in the `.set` file
  and are unaffected, as expected.
- A factory-reset radio left `0x2B1` = 161 inside the otherwise-zero reserved region. Every other
  backup has it at zero.
- **Memory channels hold only frequency, mode and PRE/ATT.** Four sources agree: the CAT protocol
  tables mark everything after PRE/ATT "always 0", the `.mem` record is 6 bytes, a real `MR` answer
  is zeros and spaces past PRE/ATT, and Lab599's TRXMem UI offers exactly Freq / Mode / PreAtt.
  PRE/ATT has no level because the radio's preamp and attenuator are fixed (`PA` and `RA` are
  binary) — it is the same three-state setting stored per band at record byte 6, bits 2-3.
- **`.mem` files store mode and PRE/ATT as ASCII digits**, not raw values: CW is `0x33`, empty is
  `'0'`. The frequency is a binary Int32 LE. We wrote raw binary until this was checked against a
  TRXMem-exported file, which made our exports unreadable by the vendor tool and dropped the mode
  when importing theirs.

### Firmware page behaviour
Opening Firmware **disconnects CAT immediately** (`FirmwareModel.prepare`). A radio in loader mode
does not answer CAT, so a connection left open polls a silent radio and buries the instructions in
errors. Disconnecting on open makes that state unreachable rather than merely discouraged; the port
is remembered in `FirmwareModel.portPath` for the loader to use at 57600 baud.

The card order is deliberate: disconnect → file → **back up** → loader mode → update. Backing up has
to come before loader mode, because a radio already in loader mode cannot be backed up.

The radio does not report its firmware version over CAT (`ID` gives model and protocol only), so
after an update the app asks the user to read the version from the radio's own startup screen and
offers **Reconnect** to resume control.

### Testing gap
`FirmwareModel` and the other app-side models live in an executable target, which the test target
cannot import. Their logic is deliberately thin for that reason; anything worth testing belongs in
`TX500Kit`. Splitting the app into a library target would make them testable if that changes.

### Tearing down the connection
`RadioConnection.disconnect()` cancels the poll task and closes the port, but a poll already awaiting
a reply still resumes and throws `EBADF` ("Bad write failed: Bad file descriptor"). The poll loop
therefore checks `Task.isCancelled` and `port != nil` **in its catch**, not only at the top of the
loop, and `disconnect()` clears `lastError`. Without both, a deliberate disconnect left an error
banner that appeared later on whichever page the user opened next — which is how it was found, after
the Firmware page's Back Up Radio Now released the port.

### Radio write verification
Set commands (`MW`, `XS`, `FA`…) get no answer from the TX-500. Never treat silence as failure;
verify writes by reading the value back (see `writeMemories`).

### Testing
- Every parser/encoder gets a unit test using **real captured responses** (see `CATTests.captured`).
- Protocol flows are tested with `MockTransport`, which maps a written command to a scripted reply.
- Hardware checks use the CLI: `swift run tx500 status | watch | probe | settings [file] | memories | fw-info f.fw | fw-test f.fw (erases firmware!) | raw "FA;"`.
  Disconnect in the app first, because the port is opened exclusively.

## Adding a feature (checklist)
1. Protocol: add constants to `TX500Protocol`, logic to a new file in `TX500Kit`, tests in `Tests/`.
2. UI: add a case to `AppSection` (title + SF Symbol), create `Features/<Name>/<Name>View.swift`,
   and route it in `RootView.detail(for:)`.
3. Compose with `Card`, `LabeledValue`, `StatusBadge`, `ErrorBanner`; style only with `Theme` tokens.
4. Talk to the radio through `RadioConnection.perform { cat in … }` (errors surface automatically).

## Decoding the settings table
The app only *shows* decoded settings — no discovery UI. Fields ship in
`SettingsLayout.builtInFields` with a `confidence`: **confirmed** (verified on hardware by changing the
setting and watching the byte), **inferred** (matches manual defaults or a single CAT reading) or
**unknown**. `BackupComparison` marks undecoded bytes that never differ across the user's backups, so the
viewer can hide inert padding.

Discovery is a developer job and lives in **`../tools/`** (Python, not shipped):

```bash
cd tools
./discover.py constants '*.set'   # which bytes ever change (no radio needed)
./discover.py locate              # every CAT-settable value at once (~25 s)
./discover.py toggles             # on/off settings, one at a time
./discover.py modes               # per-mode copies (RF gain, AGC, VOX…), AM/FM retried on 6 m
./discover.py menu 12-17          # guided: change each unmapped item in that menu range, name it
./discover.py check 06-11         # re-measure items already mapped; a match promotes them to confirmed
./discover.py noise              # which bytes move just from using the radio
./discover.py doctor             # run first: is the radio answering, and are reads aligned?
./discover.py watch              # leave the radio alone; find bytes that move by themselves
./discover.py panel              # guided: front-panel settings with no CAT command
./discover.py bits 0x276         # watch one byte, report which bits ever move
./discover.py dump 0x224 0x244   # live table bytes with their 16-bit values
./discover.py swift map.json      # emit Swift lines for SettingsLayout.discovered
```

`menu` and `check` take a menu number (`13`), a range (`06-11`) or part of a name (`contrast`). We walk
the menu in order, one small block at a time — see **`tools/MAPPING.md`** for progress, the validation
log and open questions.

Results accumulate in `tools/map.json`; paste the generated lines into `SettingsLayout.discovered`, add an
offset constant in `TX500Protocol.Settings.Layout`, and assert the value in `SettingsLayoutTests`.
Then refresh the parity fixture so the two stay in step:

```bash
cp tools/map.json TX500Utility/Tests/TX500KitTests/Fixtures/map.json && swift test
```

`SettingsLayoutTests.testMapJSONMatchesLayout` fails if a field the tools call *confirmed* is missing
from `SettingsLayout`, has a different width, or is not confirmed there. It matches by offset, not name.
`tools/tx500.py` refuses commands that transmit (`TX`, `CG010`–`CG100`, tuner start) unless the caller
passes `allow_transmit=True` — the app enforces the same rule through `TransmitGuard`.

## Protocol reference (summary)
Full details and sources are in the doc comments of `TX500Protocol.swift`.

| Function | Link | Commands |
|---|---|---|
| CAT control | 9600 8N1 | Kenwood set: `ID IF FA FB MD PC SM0 AG0 RG …`. Unsupported commands are echoed back. |
| Memories | 9600 | `MR00cc;` read, `MW00cc…;` write, channels 00–99 |
| Settings backup | 9600 | `XL1000;`…`XL2023;` → `XLnnn;` (1024 bytes); `XS` writes |
| Clock | 9600 | `TMhh:mm:ss;` set, `TM;` read (newer firmware only) |
| Firmware | 57600 8N1 | radio in loader mode (hold the 3rd button from the left in the row above the LCD + POWER); host sends 16-byte header → `OK` → streams payload → `OK` |

External reference for rig-control architecture: <https://github.com/rigplane/rigplane-core>.
