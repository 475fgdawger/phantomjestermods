# phantomjestermods
mods for DCS F-4E Phantom Jester



### Jester Radar (A2A search)
- **Range + gain sweep** during normal search: works down from your selected display range to 25 nm, Gain is .62783 Coarse Knob for all searched, adjusting down to .5 when ground clutter is detected. There are three operational options.
  1. Full pilot control of COARSE GAIN by binding a COARSE GAIN Axis. Auto Gain on or off will not matter
  2. Bind COARSE GAIN buttons (Inc and Dec) and turn Auto Gain off in the Jester Wheel for pilot control of gain.
  3. Auto Gain On for Jester Gain control (If no pilot COARSE GAIN AXIS exists) 
- ***NOTE: If you bind a COARSE GAIN AXIS from the pilot seat, you will have control of the Radar Gain at all times. This will override all Jester Gain functions. Unbind and restart if you do not want this behavior***
- **25 nm manual bar scan**: elevation bars from +30,000 ft down to −5,000 ft (referenced at 30 nm); Jester completes the full vertical sweep before ranging out, and stops at CENTER when flying low.
- **Low-altitude cutoff**: skips the below-level elevation zones at/below 5,000 ft MSL so he doesn't scan into the ground.
- **Auto-gain toggle** via the Radar wheel "Auto Gain" item / `radar_auto_gain` event — gates all Jester gain adjustment (including the cage/boresight reset).
- **Auto-focus forced on** at startup (no pilot action needed; still toggleable).
- **Nails-triggered directed search**: a forward-arc (10–2 o'clock) RWR nails makes Jester dwell on the bearing, sweep elevation, and walk gain to resolve and auto-lock a contact. Jester will also initiate a nails bearing search when an existing nail enters the forward quarter and aircraft heading stabilises.

### RWR (AN/ALR-46) call-outs
- Fixed the friendly filter, phrase ordering/priorities, and duplicate same-clock call suppression.

### BFM
- **Dogfight Advisory**: Calls visual contacts by clock/type/distance. Eliminates all Jester 'cheerleading'. He concentrates on calling out ALL visual targets by aircraft type. He doesn't tell you if they are friend or foe. The pilot must decide. He will also give occasional fuel remaining callouts if he can see a bandit AND you are in Afterburner.

This mod is best used with the Jester Sounds mod, which abbreviates the relevant Jester sound files.

Known issues:

Jester no longer repeats call like he used to but he will talk a lot in a fight.

Some aircraft do not have type sound files. Jester will call these as "bogey". I am using the "Hawk" sound file as a stand in for "Skyhawk". Be careful, it might be a Hawk or a Skyhawk. I am using "Sabre" Sound file for both the F-86 and the F-100 until there is a Super Sabre sound file as well.

There are no plural type sound files so 2 aircraft of the same type in the same clock will come out as "Two Phantom," for example.

Jester will also call fuel state occasionally if he sees a bandit and you are in afterburner.

This mod is installed in your Saved Games Jester mods path.


Jester Radar AUTO Gain Toggle

This mod gives the player the ability to stop Jester from adjusting Radar Gain to allow player gain control. Toggle is available via Jester Wheel. This is only functional for Pilot button/Key Coarse Gain. Binding a COARSE GAIN Axis makes Auto Gain irrelevant. Pilot Gain Axis gives pilot sole control of GAIN

### Startup
-**No INS Alignment Question** You MUST tell Jester to start alignment yourself. There is a keybind for that. He will automatically do a Stored Heading Alignment if available, BATH if not. He will NEVER do a full alignment.

### Taxi
-**No Minimum Altitude Plan Question** Yay

-**No obscenities on fast taxi or takeoff on non-runway** Also, Yay.

### Takeoff
-**Takeoff Callouts** Slight improvement to accuracy of callouts. Jester anticipates acceleration so if you are doing slow throttle he might call speeds early.



