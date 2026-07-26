# phantomjestermods — release (nails-search branch)

Drop-in Jester mod files, already arranged in the correct `mods/` folder
structure. This snapshot is the **`nails-search`** branch: everything on `main`
plus the nails-triggered directed radar search.

## Install

Copy the **contents of `mods/`** in this release into your Jester mods folder,
letting the folders merge:

```
<Saved Games>\<DCS variant>\jester\mods\
```

For this machine that is:

```
C:\Users\Patrick\Saved Games\DCS_F4E\jester\mods\
```

Each file overrides the stock Jester file at the same relative path (e.g.
`radar/Phases.lua` overrides Jester's `radar/Phases.lua`). Nothing here is a
core-game file, so it is integrity-check safe.

## What's included

| Path | Purpose |
|---|---|
| `radar/Config.lua` | `HANDLE_NAILS_SEARCH` phase + nails-search tunables |
| `radar/State.lua` | radar state incl. auto-gain toggle + nails-search fields |
| `radar/Phases.lua` | `AdjustGain` gate + `HandleNailsSearch` |
| `radar/Radar.lua` | phase entry for nails-search + gated cage gain reset |
| `radar/UserActions.lua` | `radar_auto_gain` + `radar_nails_search` handlers |
| `behaviors/ObserveRWR.lua` | RWR call-outs + dispatches the nails search |
| `behaviors/ReportMissiles.lua`, `UpdateJesterWheel.lua`, `ObserveFuel.lua`, `Constants.lua`, `DbaseUtils.lua` | other mod behaviors |
| `behaviors/NFO/**` | dogfight / takeoff / taxi / landing advisories |
| `conditions/Merged.lua`, `tasks/**` | supporting conditions and tasks |

## Not included

- The **AVTR-switch auto-gain keybind** lives on the separate `avtr-gain-keybind`
  branch (adds `ToggleAutoGainAvtr.lua` at `mods/` root + `init/LaunchToggleAutoGainAvtr.lua`).

## Notes

- The nails-search feature (`Config.NAILS_SEARCH_*`) is a first cut; the gain
  step, dwell, elevation amplitude and azimuth tolerance are meant to be tuned
  in-sim. Azimuth hold in search and the auto-lock hand-off still need validation
  in the jet. Filter the Jester console on `Jester Radar |` to watch it run.
