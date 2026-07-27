# phantomjestermods
mods for DCS F-4E Phantom Jester

Jester Combat Core

### Jester Radar (A2A search)
- **Range + gain sweep** during normal search: works down from your selected display range to 25 nm, walking coarse gain 0.8 → 0.5 at each range to surface weak/distant returns.
- **25 nm manual bar scan**: elevation bars from +30,000 ft down to −5,000 ft (referenced at 30 nm); Jester completes the full vertical sweep before ranging out, and stops at CENTER when flying low.
- **Low-altitude cutoff**: skips the below-level elevation zones at/below 5,000 ft MSL so he doesn't scan into the ground.
- **Auto-gain toggle** via the Radar wheel "Auto Gain" item / `radar_auto_gain` event — gates all Jester gain adjustment (including the cage/boresight reset).
- **Auto-focus forced on** at startup (no pilot action needed; still toggleable).
- **Nails-triggered directed search**: a forward-arc (10–2 o'clock) RWR nails makes Jester dwell on the bearing, sweep elevation, and walk gain to resolve and auto-lock a contact.

### RWR (AN/ALR-46) call-outs
- Fixed the friendly filter, phrase ordering/priorities, and duplicate same-clock call suppression.

### BFM
- **Dogfight Advisory**: Calls visual contacts by clock/type/distance. Eliminates all Jester 'cheerleading'. He concentrates on calling out ALL visual targets by aircraft type. He doesn't tell you if they are friend or foe. The pilot must decide. He will also give occasional fuel remaining callouts if he can see a bandit AND you are in Afterburner.

This mod is best used with the Jester Sounds mod, which abbreviates the relevant Jester sound files.

Known issues:

Jester talks constantly during a multiple target dogfight. This is both good and bad.

Some aircraft do not have type sound files. Jester will call these as "bogey". I am using the "Hawk" sound file as a stand in for "Skyhawk". Be careful, it might be a Hawk or a Skyhawk. I am using "Sabre" Sound file for both the F-86 and the F-100 until there is a Super Sabre sound file as well.

There are no plural type sound files so 2 aircraft of the same type in the same clock will come out as "Two Phantom," for example.

Jester will also call fuel state occasionally if he sees a bandit and you are in afterburner.

This mod is install in your Saved Games Jester mods path.


Jester Radar Gain Toggle

This mod gives the player the ability to stop Jester from adjusting Radar Gain to allow player gain control. Toggle is available via Jester Wheel.


