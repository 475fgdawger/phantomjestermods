---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.

require('base.Interactions')
local Task = require('base.Task')
local Math = require('base.Math')
local Utilities = require('base.Utilities')
local Config = require('radar.Config')
local State = require('radar.State')
local Api = require('radar.Api')
local Phases = require('radar.Phases')
local Routines = require('radar.Routines')
require('radar.UserActions') -- must be included so that its ListenTo are registered
local MoveRadarCursor = require('radar.MoveRadarCursor')
local MoveRadarAntenna = require('radar.MoveRadarAntenna')
local Constants = require('base.Constants')

-- Mostly a state-machine that enqueues a single task per :Tick.
-- General preparation for operating the Radar system and deactivating it while
-- for example the Pave Spike is used, is handled by PrepareDscg.lua.
-- The behavior that distributes the Radars tick can be found in OperateRadar.lua.
-- The tasks depend on the current phase/state, decided in :FindNextPhase.
-- In general, Jester differentiates between:
--   * A2A mode (BVR)
--   * A2G mode (DT/DL)
-- The ticking system is only active for A2A, as A2G is operated via PrepareDscg.lua and context actions instead.
-- For the A2A mode, Jester generally operates between:
--   * scan (either regular scan pattern or focused on a target)
--   * target locked
-- Within this flow, Jesters switches between several phases, where the two scan modes go through:
--   * preparing for a scan
--   * selecting a zone/area to scan (could also be focused at a target)
--   * adjusting screen settings like range and scan type
--   * interpreting the screen
--   * identifying any new targets by pressing the IFF button
--   * calling out any new contact groups
--   * adjusting the gain setting
-- Steps for having a target locked are all handled in a single HANDLE_TARGET_LOCKING phase.
-- Cursor movement is handled in MoveRadarCursor.lua and steered from here in each tick via :UpdateTargetHighlight.
-- Antenna movement is handled in MoveRadarAntenna.lua.
-- Jesters behavior can be steered by manipulating the states and phases. For example, locking a
-- target can be achieved by calling State.Reset() and setting a State.target_to_lock.
-- Jester will the naturally pick this up in his next tick and enqueue the correct tasks.
-- This is also what most context actions do, they usually call State.Reset() and then slightly change the state
-- to force Jester picking the appropriate task based on the current state.
-- Targets go through several collections throughout the phases:
--   * unidentified_new_targets - new contact spotted
--   * identified_targets - contact was IFFed, identification is stable
--   * processed_targets - contact was called out (BRA), contact is fully processed
--   * all_targets - contains all contacts, from the moment they were spotted
-- All contact data is constantly updated with the master data from radar_targets in each tick.
local Radar = {}

-- One-shot: guarantee auto-focus is enabled when the radar starts, so the pilot
-- never has to turn it on. Applied once in Radar.Tick; the pilot can still toggle
-- it off afterwards via the Radar wheel / radar_auto_focus.
local forced_auto_focus_on = false

function Radar.UpdateDiveToss()
	local move_radar_cursor = GetJester().behaviors[MoveRadarCursor]

	if Api.IsInTrackState() then
		move_radar_cursor:ClearTarget()
		return
	end

	local ground_return_range = GetRadarMlcRange()
	if not ground_return_range then
		return
	end

	move_radar_cursor:MoveCursorTo(deg(0), ground_return_range)
end

function Radar.UpdateBoresightOrCageMode()
	local move_radar_cursor = GetJester().behaviors[MoveRadarCursor]

	if Api.IsInTrackState() then
		State.is_locking_cage_target = false
		move_radar_cursor:ClearTarget()
		return
	end
	if State.is_locking_cage_target then
		return
	end

	if State.time_left_trying_to_lock_cage_target > s(0) then
		State.time_left_trying_to_lock_cage_target = State.time_left_trying_to_lock_cage_target - Utilities.GetTime().dt

		if State.time_left_trying_to_lock_cage_target <= s(0) then
			State.is_locking_cage_target = false
			GetJester():AddTask(Task:new():Say("contacts_iff/contactdropped"))
		end
	end

	-- Cage/boresight gain reset is a separate gain path from Phases.AdjustGain;
	-- gate it behind the same toggle so "auto gain off" means Jester never forces
	-- the gain (and stops the recurring "--Click 'Radar Gain Coarse': 0.5" log).
	local gain_diff = Math.Abs(Api.GetCurrentGainCoarse() - 0.5)
	if State.is_auto_gain_allowed and gain_diff > 0.05 then
		local task = Task:new()
				:ClickFast("Radar Gain Coarse", 0.5)
		GetJester():AddTask(task)
	end

	local target = Api.GetTargetForBoresightCageOrNil()
	if not target then
		return
	end

	move_radar_cursor:FollowTarget(target, true, true)

	if State.time_left_trying_to_lock_cage_target > s(0) then
		State.time_left_trying_to_lock_cage_target = s(0)
		State.is_locking_cage_target = true
		local task = Task:new()
		task:SetPriority(1)
		task:WaitUntil(function()
			return move_radar_cursor:IsCursorOverDesired()
		end, s(5))
		Api.LockTargetUnderCursor(task)
		   :Require({ voice = true, hands = true })
		if Api.AreRadarMissilesReady() and Api.IsBandit(target.id) then
			task:Say("radar/aimsevenstablelock")
		else
			local phrase = "radar/contextlocked"
			if target.identification == RadarTargetIdentification.FRIENDLY then
				phrase = phrase .. "friend"
			elseif target.identification == RadarTargetIdentification.HOSTILE then
				phrase = phrase .. "bandit"
			else
				phrase = phrase .. "bogey"
			end
			task:Say(phrase)
		end
		GetJester():AddTask(task)
	end
end

function Radar.UpdateTargetData()
	for id, target in pairs(State.all_targets) do
		target = radar_targets[id] or target

		-- Retain IFF result
		if State.unidentified_new_targets[id] then
			target.identification = Api.SelectIdentification(target.identification, State.unidentified_new_targets[id].identification)
		end
		if State.identified_targets[id] then
			target.identification = Api.SelectIdentification(target.identification, State.identified_targets[id].identification)
		end
		if State.processed_targets[id] then
			target.identification = Api.SelectIdentification(target.identification, State.processed_targets[id].identification)
		end
		if State.all_targets[id] then
			target.identification = Api.SelectIdentification(target.identification, State.all_targets[id].identification)
		end

		if State.unidentified_new_targets[id] then
			State.unidentified_new_targets[id] = target
		end
		if State.identified_targets[id] then
			State.identified_targets[id] = target
		end
		if State.processed_targets[id] then
			State.processed_targets[id] = target
		end
		if State.all_targets[id] then
			State.all_targets[id] = target
		end

		if State.target_to_highlight and State.target_to_highlight.id == target.id then
			State.target_to_highlight = target
		end
		if State.target_to_focus_on and State.target_to_focus_on.id == target.id then
			State.target_to_focus_on = target
		end
		if State.target_to_lock and State.target_to_lock.id == target.id then
			State.target_to_lock = target
		end
		if State.target_currently_locked and State.target_currently_locked.id == target.id then
			State.target_currently_locked = target
		end
	end
end

function Radar.UpdateTargetHighlight()
	-- While a directed nails-search owns the antenna, leave the cursor/highlight alone
	-- (otherwise this would clear the aim point and run auto-focus every tick).
	if State.nails_search_active then
		return
	end

	local move_radar_cursor = GetJester().behaviors[MoveRadarCursor]
	local move_radar_antenna = GetJester().behaviors[MoveRadarAntenna]

	if State.target_to_lock ~= nil then
		local target = radar_targets[State.target_to_lock.id] or State.target_to_lock -- prefer latest data if available
		move_radar_cursor:FollowTarget(target, true)
		move_radar_antenna:FollowTarget(target)
		return
	end

	-- If nothing is requested, pick the highest priority target if close
	if not State.pilot_requested_target_to_highlight then
		-- First reset to avoid sticking on an UNKNOWN who then became FRIENDLY
		State.target_to_highlight = nil
		State.target_to_focus_on = nil

		if State.is_auto_focus_allowed then
			local target = Api.GetTargetForAutoFocusOrNil()
			if target then
				State.target_to_highlight = target
				State.target_to_focus_on = target
			end
		end
	end

	if State.target_to_highlight then
		local target = radar_targets[State.target_to_highlight.id] or State.target_to_highlight -- prefer latest data if available
		move_radar_cursor:FollowTarget(target)
		move_radar_antenna:FollowTarget(target)
	else
		move_radar_cursor:ClearTarget()
	end
end

function Radar.FindNextPhase()
	State.task = nil

	--Inhibit regular radar ops when in dogfight.
	--TODO: Also inhibit if G-locked (cant move arms and brain when too much G)
	local closest_threat = GetJester().awareness:GetClosestAirThreat() or false
	local is_dogfight = closest_threat and closest_threat.polar_ned.length:ConvertTo(NM) < Constants.dogfight_distance
	if is_dogfight then
		return
	end

	local spendEnoughTimeInSameZone = State.time_spent_scanning_zone_no_bandits > State.max_scan_time_for_zone_no_bandits
	if State.current_phase == Config.phase.ADJUST_GAIN and spendEnoughTimeInSameZone then
		if State.max_scan_time_for_zone_no_bandits >= Config.MAX_FOCUS_ZONE_SCAN_TIME then
			GetJester():AddTask(Task:new():Say("radar/returningtoscan"))
		end
		-- Causes SELECT_NEXT_SCAN_ZONE to be next
		State.current_phase = Config.phase.PREPARE_SCAN_PATTERN
	end

	if State.current_phase == Config.phase.SCAN_SCREEN then
		State.scan_screen_timer = State.scan_screen_timer + Utilities.GetTime().dt
		if State.scan_screen_timer < Config.SCAN_SCREEN_TIME then
			-- Stay in SCAN_SCREEN phase by re-entering it
			State.current_phase = Config.phase.ADJUST_SCREEN
		end
	else
		State.scan_screen_timer = s(0)
	end

	local hasContactsToCallOut = Api.HasUnprocessedContacts()
	if State.current_phase == Config.phase.CALL_OUT_NEXT_CONTACTS and hasContactsToCallOut then
		-- Causes CALL_OUT_NEXT_CONTACTS to be called again
		State.current_phase = Config.phase.IDENTIFY_TARGETS
	end

	local is_locking_target = State.target_to_lock ~= nil or State.target_currently_locked ~= nil
	if State.current_phase == Config.phase.HANDLE_TARGET_LOCKING and not is_locking_target then
		-- Not interested in locking anymore, back to scanning
		State.current_phase = Config.phase.PREPARE_SCAN_PATTERN
	end

	if is_locking_target then
		--Log("HANDLE_TARGET_LOCKING")
		return Phases.HandleTargetLocking(), Config.phase.HANDLE_TARGET_LOCKING
	end

	-- Directed nails-search takes priority over the normal scan cycle (but yields to
	-- locking above, so a resolved contact is picked up as a lock on the next tick).
	if State.nails_search_active then
		return Phases.HandleNailsSearch(), Config.phase.HANDLE_NAILS_SEARCH
	end

	-- Prepare Scan Pattern
	if State.current_scan_zone == nil and State.current_phase ~= Config.phase.PREPARE_SCAN_PATTERN then
		--Log("PREPARE_SCAN_PATTERN")
		return Phases.PrepareScanPattern(), Config.phase.PREPARE_SCAN_PATTERN
	end
	-- Select Next Scan Zone
	if State.current_phase == Config.phase.PREPARE_SCAN_PATTERN then
		--Log("SELECT_NEXT_SCAN_ZONE")
		return Phases.SelectNextScanZone(), Config.phase.SELECT_NEXT_SCAN_ZONE
	end
	-- Adjust Screen
	if State.current_phase == Config.phase.SELECT_NEXT_SCAN_ZONE or State.current_phase == Config.phase.ADJUST_GAIN then
		--Log("ADJUST_SCREEN")
		return Phases.AdjustScreen(), Config.phase.ADJUST_SCREEN
	end
	-- Scan Screen
	if State.current_phase == Config.phase.ADJUST_SCREEN then
		--Log("SCAN_SCREEN")
		return Phases.ScanScreen(), Config.phase.SCAN_SCREEN
	end
	-- Analyze Current Zone
	if State.current_phase == Config.phase.SCAN_SCREEN then
		--Log("IDENTIFY_TARGETS")
		return Phases.IdentifyTargets(), Config.phase.IDENTIFY_TARGETS
	end
	-- Callout new contact
	if State.current_phase == Config.phase.IDENTIFY_TARGETS then
		--Log("CALL_OUT_NEXT_CONTACTS")
		return Phases.CallOutNextContacts(), Config.phase.CALL_OUT_NEXT_CONTACTS
	end
	-- Adjust gain
	if State.current_phase == Config.phase.CALL_OUT_NEXT_CONTACTS then
		--Log("ADJUST_GAIN")
		-- Loops back to ADJUST_SCREEN until State.time_spent_scanning_zone_no_bandits is beyond threshold
		return Phases.AdjustGain(), Config.phase.ADJUST_GAIN
	end
end

function Radar.Tick()
	if not forced_auto_focus_on then
		State.is_auto_focus_allowed = true
		forced_auto_focus_on = true
	end

	-- Sky-gain calibration is tied to radar power: while the radar is off/standby, clear
	-- it so it recalibrates on the next power-up (rather than once per sortie).
	if not Api.IsPowered() then
		if State.sky_gain_calibrated then
			Log("Jester Radar | radar off/standby - sky gain will recalibrate on power-up")
		end
		State.sky_gain_calibrated = false
		State.sky_gain = nil
		State.calibration_gain = nil
	end

	Routines.forget_old_targets:Tick()
	Routines.update_targets_priority:Tick()
	Routines.update_close_bandit_awareness:Tick()

	local can_operate_radar = State.is_active and Api.IsPowered()
	local is_regular_a2a_behavior = State.current_context_mode == Config.context_mode.A2A and not Api.IsInDogfightMode() and not Api.IsBoresightMode()
	local is_dive_toss = State.current_context_mode == Config.context_mode.A2G_DIVE_TOSS or State.current_context_mode == Config.context_mode.A2G_DIVE_LAYDOWN

	if can_operate_radar then
		if is_dive_toss then
			Radar.UpdateDiveToss()
		elseif Api.IsBoresightMode() or Api.IsRegularCageMode() then
			Radar.UpdateBoresightOrCageMode()
		end
	end

	if not can_operate_radar or not is_regular_a2a_behavior then
		if State.task ~= nil then
			-- Radar deselected, abort whatever is going on and reset
			State.Reset()
		end
		return
	end

	Routines.check_iff:Tick()

	if State.current_scan_zone ~= nil then
		State.time_spent_scanning_zone_no_bandits = State.time_spent_scanning_zone_no_bandits + Utilities.GetTime().dt
	end

	Radar.UpdateTargetData()
	Radar.UpdateTargetHighlight()

	if State.task ~= nil and not State.task:IsFinished() then
		-- Waiting for a task to finish
		return
	end

	local task, next_phase = Radar.FindNextPhase()
	if next_phase then
		State.current_phase = next_phase
	end
	if task then
		State.task = task
		GetJester():AddTask(task)
	end
end

-- Allows Jester to dynamically pick up the current situation, for example if the player manually has locked a target.
function Radar.ResetToSituation()
	State.Reset()

	local can_operate_radar = State.is_active and Api.IsPowered()
	local is_regular_a2a_behavior = State.current_context_mode == Config.context_mode.A2A and not Api.IsInDogfightMode() and not Api.IsBoresightMode()

	if not can_operate_radar or not is_regular_a2a_behavior then
		return
	end

	if not Api.IsInTrackState() then
		-- Start with regular scan pattern
		return
	end

	-- Continue with the currently locked target
	-- Find locked target
	local locked_target = Api.FindLockedTargetOrNil()

	if not locked_target then
		-- Faulty lock, create artificial target
		local target_id = GetRadarIntendedTrackTargetId() or Config.ARTIFICIAL_TARGET_ID
		local target_range = Api.GetLockedTargetRange()
		local now = Utilities.GetTime().mission_time
		locked_target = {
			id = target_id,
			identification = RadarTargetIdentification.HOSTILE,
			scan_azimuth = deg(0),
			scan_range = target_range:ConvertTo(NM),
			cheat_altitude = Api.GetAltitudeFromSlantRange(target_range:ConvertTo(NM)),
			estimated_vc = mps(0),
			number_of_hits = 2,
			grazing_angle = deg(0),
			last_seen_timestamp = now,
			first_seen_timestamp = now,
			last_hit_timestamp = now,
			first_hit_timestamp = now,
		}
	end

	-- Inject target data
	State.identified_targets[locked_target.id] = locked_target
	State.processed_targets[locked_target.id] = locked_target
	State.all_targets[locked_target.id] = locked_target
	Api.UpdateTargetsPriority()

	State.current_phase = Config.phase.HANDLE_TARGET_LOCKING
	State.target_to_highlight = locked_target
	State.pilot_requested_target_to_highlight = locked_target
	State.target_to_focus_on = locked_target
	State.target_to_lock = locked_target
	State.target_currently_locked = locked_target
	GetJester().behaviors[MoveRadarCursor]:FollowTarget(locked_target)
	GetJester().behaviors[MoveRadarAntenna]:FollowTarget(locked_target)
end

ListenTo("jester_reactivated", "Radar", function()
	Radar.ResetToSituation()
end)

return Radar
