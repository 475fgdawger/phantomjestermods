# phantomjestermods
mods for DCS F-4E Phantom Jester

Jester Combat Core

A rewrite of the Heatblur F-4E Phantom Dogfight Advisory. This mod makes Jester much more useful in a visual dogfight. He will call out what he sees providing clock position, aircraft type and distance. Be advised he does not discriminate between friend or foe here. It is up to the pilot to decide based upon provided aircraft type.

This mod is best used with the Jester Sounds mod, which abbreviates the relevant Jester sound files.

Known issues:

Jester talks constantly during a multiple target dogfight. This is both good and bad.

Some aircraft do not have type sound files. Jester will call these as "bogey". I am using the "Hawk" sound file as a stand in for "Skyhawk". Be careful, it might be a Hawk or a Skyhawk.

There are no plural type sound files so 2 aircraft of the same type in the same clock will come out as "Two Phantom," for example.

Jester will also call fuel state occasionally if he sees a bandit and you are in afterburner.

This mod is install in your Saved Games Jester mods path.


Jester Radar Gain Toggle

This mod gives the player the ability to stop Jester from adjusting Radar Gain to allow player gain control. Toggle is available via Jester Wheel.

Files jester/mods/radar/Phases.lua
      jester/mods/radar/UserActions.lua
      jester/mods/radar/State.lua
      jester/mods/behaviors/UpdateJesterWheel.lua
