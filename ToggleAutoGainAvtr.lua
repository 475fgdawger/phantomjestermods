---// ToggleAutoGainAvtr.lua
-- Uses the WSO "AVTR Mode" switch as a stand-in keybind for the radar auto-gain
-- toggle. Bind a key to the AVTR Mode switch in DCS controls; each time the
-- switch changes position this behavior dispatches the "radar_auto_gain" toggle
-- event, which is handled in UserActions.lua (flips State.is_auto_gain_allowed).
--
-- Why the AVTR switch: it is a rear-cockpit (WSO) manipulator Jester can read,
-- it is discrete/stable (OFF / STANDBY / RECORD), it is bindable, and Jester
-- never operates it EXCEPT ObserveAvtr.lua sets it to OFF once when a recording
-- tape runs out. If you never record AVTR video that never happens, so there are
-- no spurious toggles. (If it ever matters, ignore transitions to "OFF" below.)
--
-- This is a NEW behavior, so it must be registered - see LaunchToggleAutoGainAvtr.lua.

local Class = require('base.Class')
local Behavior = require('base.Behavior')
require('base.Interactions') -- provides the Dispatch / ListenTo globals

local ToggleAutoGainAvtr = Class(Behavior)

ToggleAutoGainAvtr.initialized = false
ToggleAutoGainAvtr.last_avtr_state = nil

function ToggleAutoGainAvtr:Constructor()
	Behavior.Constructor(self)
end

local function GetAvtrState()
	local cockpit = GetJester():GetCockpit()
	if not cockpit then
		return nil
	end
	local manipulator = cockpit:GetManipulator("AVTR Mode")
	if not manipulator then
		return nil
	end
	return manipulator:GetState()
end

function ToggleAutoGainAvtr:Tick()
	local state = GetAvtrState()
	if state == nil then
		return
	end

	-- First valid read: remember it without firing, so spawning in doesn't toggle.
	if not self.initialized then
		self.last_avtr_state = state
		self.initialized = true
		return
	end

	if state ~= self.last_avtr_state then
		self.last_avtr_state = state
		Log("Jester Radar | AVTR Mode switch moved to '" .. tostring(state) .. "' -> toggling auto gain")
		Dispatch("radar_auto_gain", "toggle")
	end
end

ToggleAutoGainAvtr:Seal()
return ToggleAutoGainAvtr
