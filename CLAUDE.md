# phantomjestermods — Maintainer Guide

Lua override mods for the DCS **F-4E Phantom "Jester"** AI backseater. The repo ships
several standalone mods as GitHub Releases; users drop a `mods/` folder into
`Saved Games/<DCS>/jester/`.

## Critical rules

- **Never override or add files under `base/`.** Overriding *any* `base/` file blocks
  **all** Jester mods from loading. Custom copies of base files live in `behaviors/`
  instead and are required from there:
  - `require('behaviors.Constants')` — never `base.Constants`
  - `require('behaviors.DbaseUtils')` — never `base.DbaseUtils`
  - Radar code (`Radar.lua`, `ReportMissiles.lua`) must use `behaviors.Constants`.
- **Keep the two trees in sync.** Editable source lives **flat in the repo root**
  (`Radar.lua`, `DbaseUtils.lua`, `DogfightAdvisory.lua`, …). `release/mods/` is a
  **deployment-structured mirror** of those same files. After editing any flat-root file,
  copy it to its `release/mods/<subpath>/` counterpart (matched by basename). **Release
  zips are built from `release/mods/`, so a stale mirror ships stale code.** Before
  building, `diff` every `release/mods` file against its flat-root basename — expect 0
  differences.

## Layout

- **Flat root** — authoritative source (edit here). Files are flat regardless of the
  subfolder they deploy to.
- **`release/mods/`** — deployment mirror: `behaviors/`, `radar/`, `conditions/`, `tasks/`.
  Must equal the flat-root sources.
- **`scripts/`** — maintainer tooling.

## Deploy & test — LOCAL MACHINE ONLY (not available in a cloud / phone session)

- Deploy target: `Saved Games/<DCS variant>/jester/mods/` (mirrors `release/mods/`).
- Syntax check: `luac -p <file>` (a local Lua parser; cloud sandboxes may not have Lua).
- In-sim: the mod's `Log()` prints only to the in-game **Jester Console** overlay
  (not persisted). A file logger `Config.ConsoleLog()` → `<writedir>/jester_console.log`
  is gated by `Config.JESTER_CONSOLE_LOG` in `radar/Config.lua` — **shipped `false`**.
  Flip to `true` to debug; set back to `false` before any release.

## Releases (GitHub, via `gh`)

Two releases carry the radar/combat work — keep **both** in step with `main`:

| Release | Tag | Asset | Contents |
|---|---|---|---|
| Jester Overhaul (Full) | `v0.9.x` | `phantomjestermods-vX.Y.Z.zip` | all **19** mod files |
| Jester Combat Core | `PhantomJesterRadarRwrBfm` | `Dawger.s.Phantom.Radar.RWR.BFM.zip` | **13** files (radar + combat) |

Other releases (*No Questions…*, *Jester Sounds*, *No INS…*) are independent — leave them
alone for radar/combat changes.

- **Combat Core (13):** `behaviors/{Constants, DbaseUtils, ObserveFuel, ObserveRWR,
  ReportMissiles, UpdateJesterWheel, NFO/WVR/DogfightAdvisory}`, `conditions/Merged`,
  `radar/{Config, Phases, Radar, State, UserActions}`.
- **Full (19):** the Combat Core 13 **plus** `behaviors/NFO/{ground_ops/TaxiAdvisory,
  landing/CommentOnLanding, takeoff/TakeOffAdvisory}`, `tasks/navigation/MinimumAltitudePlan`,
  `tasks/start/{SayReadyForInsAlignment, StartINS}`.

**Build:** stage the files under a top-level `mods/` folder, zip it (archive paths look
like `mods\radar\Radar.lua`), then `gh release upload <tag> <zip> --clobber`.
- On Windows: use PowerShell `Compress-Archive` — Git Bash has no `zip`, and `python` is
  the broken Microsoft Store alias.
- Always verify the built zip's file count (19 / 13), that there's **no bombing** content,
  and that `JESTER_CONSOLE_LOG = false`, before uploading. Re-download and grep to confirm.

## Discord announcements

```
scripts/announce-release.ps1 -Tag <tag> -Title "<title>" -DescriptionFile notes.txt
```
Webhook resolved from `$env:DISCORD_WEBHOOK`, else `scripts/.discord_webhook` (gitignored —
in a cloud session set the env var / secret instead).

## Key API notes

- **Observations:** `GetJester().awareness:GetObservation("<key>")`. Useful keys:
  `indicated_airspeed`, `TAS`, `barometric_altitude`, `velocity_ned` (Vector, `.x/.y/.z`
  in mps), `g_force` (unitless load factor), `gods_angular_velocity_ned` (`.z` = yaw /
  heading rate, rad/s), `gods_pitch`, `gods_roll`, `angle_of_attack`, `is_inverted`. Read a
  labeled value via `obs.value` (guard with `pcall` — it may be userdata).
- **Awareness threat queries are omniscient**, NOT visual-gated: `GetClosestAirThreat` /
  `GetAirThreats` come from the SixthSense sense and return hostiles regardless of radar or
  visual detection. Gate "actually engaged" on a signal like `g_force`, not proximity alone.
- **Radar** is a phase state machine: `radar/Radar.lua` (`FindNextPhase`, `Tick`) drives
  `radar/Phases.lua`; `radar/State.lua` holds state; `radar/Config.lua` holds tunables.
  `State.Reset()` clears scan/lock selections but NOT persistent flags
  (`is_auto_gain_allowed`, `gain_deferred_to_manual`, `recently_forgotten`, …).
- **Constants** (`behaviors/Constants.lua`): `dogfight_distance` (16 nm) is shared by
  `DogfightAdvisory` and `Merged` — do not repurpose it for radar-only behavior; add a
  dedicated `radar/Config.lua` value instead.
