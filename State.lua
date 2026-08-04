---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.

local Config = require('radar.Config')
local MoveRadarCursor = require('radar.MoveRadarCursor')
local MoveRadarAntenna = require('radar.MoveRadarAntenna')

-- State for Radar.lua. Jester-Radar is mostly a state machine.
-- Changes in the state will influence what he will execute in the next cycle.
-- For example, locking a target can be achieved by calling State.Reset() and setting a State.target_to_lock.
local State = {}

State.task = nil -- current task within the phase cycle, Jester only executes one task and then waits before proceeding
State.event_task = nil -- parallel task spawned via user actions like context-action, only one at a time. Use :SetEventTask.

State.current_phase = nil -- influences which phase is next to pick within the cycle, essentially the current state in the state-machine
State.is_active = nil -- whether Jester Radar is active or not. can be used externally to shut it off completely (for example when using the Pave Spike, see PrepareDscg.lua)
State.current_context_mode = Config.context_mode.A2A -- controlled by PrepareDscg.lua to tell the radar which context mode it is in, so it can interpret the action correctly

State.scan_screen_timer = s(0) -- how long Jester looked at the screen to interpret it (one of his phases), in order to proceed to the next phase eventually
State.current_scan_zone = nil -- table (name, range, altitude, is_relative) - influences which scan zone will be next, or Config.scan_zone.TARGET_FOCUS to scan a target instead
State.time_spent_scanning_zone_no_bandits = s(0) -- how long the current zone is already scanned and no new bandits have been spotted anymore, in order to eventually proceed to the next
State.max_scan_time_for_zone_no_bandits = Config.MAX_ZONE_SCAN_TIME -- the max time to spend scanning the current zone; can be adjusted based on the situation to scan longer

State.pilot_requested_scan_zone = nil -- table (name, range, altitude, is_relative) - set to a zone if the user requested special attention at a given zone; will be scanned longer than normally
State.pilot_requested_range = Config.range.nm_50 -- the display range to use during a regular scan pattern, ignored when a target is under focus
State.pilot_requested_scan_type = Config.scan_type.wide -- the scan type to use during a regular scan pattern, ignored when a target is under focus
State.is_auto_focus_allowed = true -- whether Jester is allowed to auto-highlight and focus targets within threat range
State.is_auto_gain_allowed = true -- whether Jester is allowed to auto-adjust radar gain / clutter interest range (see Phases.AdjustGain). Set to false to have Jester leave gain alone by default. Toggled via the "radar_auto_gain" event / Radar wheel. NOT reset by State.Reset() (survives locks/scans), like is_auto_focus_allowed.

-- External coarse-gain override detection (see Phases.DetectGainOverride / Config.GAIN_OVERRIDE_*).
-- All persist across State.Reset() (a per-session/binding fact, like is_auto_gain_allowed).
State.gain_last_commanded = nil     -- coarse gain value Jester last commanded (baseline for override detection)
State.gain_last_command_time = nil  -- mission_time of that command (for the settle grace)
State.gain_override_value = nil     -- the stable foreign value the knob keeps returning to while overridden
State.gain_override_strikes = 0     -- consecutive confirmed-override cycles
State.gain_deferred_to_manual = false -- once set, Jester stops driving coarse gain and defers to the player's axis/knob

State.target_to_highlight = nil -- if set, the given target will be highlighted, or "selected"; this also includes automatic cursor movement
State.pilot_requested_target_to_highlight = nil -- if set, Jester will stop automatically selecting high priority targets for highlight and stick to the selected target
State.target_to_focus_on = nil -- if set, the given target will be focused (must be set with State.target_to_highlight); aborts scan, points antenna at target, goes narrow view, adjusts display range
State.target_to_lock = nil -- if set, the given target will be locked (must be set with State.target_to_highlight and State.target_to_focus_on)
State.target_currently_locked = nil -- if set, Jester knows that a target is currently locked; controls if he will still attempt locking or instead hold the lock

-- Nails Search state (see Phases.HandleNailsSearch). Set by the "radar_nails_search"
-- event handler in UserActions.lua when a forward-arc nails is detected while free-scanning.
State.nails_search_active = false -- whether a directed nails-search is currently running
State.nails_search_azimuth = nil -- antenna azimuth (deg) of the nails bearing being searched
State.nails_search_start = nil -- mission_time the directed nails-search began (nil until setup runs); gates the timeout
State.nails_search_sweep_up = true -- elevation sweep direction toggle, flipped each dwell step
State.nails_search_scans_completed = 0 -- count of full up+down elevation scans done this search; the timeout won't fire until this is >= 1

State.search_range = nil -- current display range (set to pilot_requested_range by Phases.GetSearchRange; no sweep)

State.last_iff_timestamp = s(0) -- timestamp the last IFF was executed, in order to not spam it

State.time_spent_trying_to_lock_bandit = s(0) -- in order to eventually give up if a bandit dropped from the screen
State.wrong_lock_attempts = 0 -- when Jester locks a contact but the lock is faulty, he will repeat and increase this counter; eventually he will abort

State.has_single_unidentified_contact = false -- whether, when spotted a new contact, it is only a single or multiple contacts; used to adjust the voice-flow

State.time_left_trying_to_lock_cage_target = s(0)
State.is_locking_cage_target = false

State.unidentified_new_targets = {} -- temporarily holds contacts just spotted but not yet identified, usually empty
State.identified_targets = {} -- all contacts that were IFFed, identification is stable
State.processed_targets = {} -- all contacts that were called out (BRA), contact is fully processed
State.all_targets = {} -- contains all contacts, from the moment they were spotted
State.recently_forgotten = {} -- id -> mission_time a contact was forgotten (dropped lock); re-detections within FORGOTTEN_TARGET_QUIET_TIME are absorbed silently (no repeat callout). Persists across Reset; purged lazily on expiry.

State.bandits_by_priority_desc = {} -- view of State.all_targets, filtered by bandits (HOSTILE or UNKNOWN), sorted (highest priority first)
State.not_bandits_by_priority_desc = {} -- view of State.all_targets, filtered by non-bandits (FRIENDLY, NEUTRAL), sorted (highest priority first)

-- Resets Jester Radar back to a standard scan pattern, dropping all locks, target selections or focus.
function State.Reset()
	if State.task then
		State.task:Cancel()
	end
	if State.event_task then
		State.event_task:Cancel()
	end
	State.task = nil
	State.event_task = nil

	State.current_phase = nil

	State.scan_screen_timer = s(0)
	State.current_scan_zone = nil
	State.time_spent_scanning_zone_no_bandits = s(0)
	State.max_scan_time_for_zone_no_bandits = Config.MAX_ZONE_SCAN_TIME

	State.pilot_requested_scan_zone = nil

	State.target_to_highlight = nil
	State.pilot_requested_target_to_highlight = nil
	State.target_to_focus_on = nil
	State.target_to_lock = nil
	State.target_currently_locked = nil

	-- Abort any directed nails-search on reset.
	State.nails_search_active = false
	State.nails_search_azimuth = nil
	State.nails_search_start = nil
	State.nails_search_sweep_up = true
	State.nails_search_scans_completed = 0
	State.search_range = nil

	State.time_spent_trying_to_lock_bandit = s(0)
	State.wrong_lock_attempts = 0

	State.has_single_unidentified_contact = 0

	State.time_left_trying_to_lock_cage_target = s(0)
	State.is_locking_cage_target = false

	local move_radar_cursor = GetJester().behaviors[MoveRadarCursor]
	if move_radar_cursor then
		move_radar_cursor:ClearTarget()
	end
	local move_antenna_cursor = GetJester().behaviors[MoveRadarAntenna]
	if move_antenna_cursor then
		move_antenna_cursor:ClearTarget()
	end
end

function State.SetEventTask(task)
	if State.event_task then
		State.event_task:Cancel()
	end
	State.event_task = task
end

return State
