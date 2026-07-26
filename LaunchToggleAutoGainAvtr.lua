-- LaunchToggleAutoGainAvtr.lua
-- Registers the ToggleAutoGainAvtr behavior with Jester at launch.
-- Pattern mirrors the Heatblur example mod (mods/heatblur/example_mod/init/LaunchExampleMod.lua):
-- add an init function to the global mod_init table; Jester invokes it during launch.

local ToggleAutoGainAvtr = require 'ToggleAutoGainAvtr'

mod_init[#mod_init+1] = function(jester)
	jester.behaviors[ToggleAutoGainAvtr] = ToggleAutoGainAvtr:new()
end
