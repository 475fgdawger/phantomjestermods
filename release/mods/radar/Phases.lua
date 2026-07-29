---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.

local Utilities = require('base.Utilities')
local Math = require('base.Math')
local Task = require('base.Task')
local Config = require('radar.Config')
local State = require('radar.State')
local Api = require('radar.Api')
local MoveRadarCursor = require('radar.MoveRadarCursor')
local MoveRadarAntenna = require('radar.MoveRadarAntenna')
local BraCalls = require('other.BraCalls')

local Phases = {}

-- Testing: remember the last-logged auto-gain gate state so AdjustGain logs only
-- when it flips (ON<->OFF) instead of every radar cycle. Also fires on the first
-- call, confirming the default state.
local last_logged_auto_gain = nil

-- Don't re-click the coarse gain (and spam its log) when it's already at target.
-- Larger than any set/quantization error, smaller than the sky<->ground gain gap.
local GAIN_EPSILON = 0.02

function Phases.HandleTargetLocking()
	local task = Task:new()
	task:SetPriority(1)
	local target = radar_targets[State.target_to_lock.id] or State.target_to_lock

	-- Switch targets
	if State.target_currently_locked ~= nil and target.id ~= State.target_currently_locked.id then
		--Log("Switch targets")
		State.target_currently_locked = nil
		if Api.IsInTrackState() then
			--Log("Unlock current target")
			Api.UnlockTarget(task)
			   :Wait(s(1.5)) -- Wait a scan cycle for new target to hopefully appear on screen
		end
		return task
	end

	-- Lock target
	if State.target_currently_locked == nil and not Api.IsInTrackState() then
		--Log("Locking target...")
		GetJester().behaviors[MoveRadarCursor]:FollowTarget(target, true)
		GetJester().behaviors[MoveRadarAntenna]:FollowTarget(target)

		Api.SelectRangeFor(task, target.scan_range:ConvertTo(NM))

		State.time_spent_trying_to_lock_bandit = State.time_spent_trying_to_lock_bandit + Utilities.GetTime().dt
		if State.time_spent_trying_to_lock_bandit > Config.MAX_TRYING_TO_LOCK_BANDIT_TIME then
			--Log("Cant find target... giving up")
			State.target_to_lock = nil
			State.target_currently_locked = nil
			State.time_spent_trying_to_lock_bandit = s(0)

			return task:Say("contacts_iff/contactdropped", "radar/returningtoscan")
		end

		local last_seen_after = Utilities.GetTime().mission_time - target.last_hit_timestamp
		local is_recent_enough = last_seen_after < s(1)

		local move_radar_cursor = GetJester().behaviors[MoveRadarCursor]
		local is_cursor_over_target = move_radar_cursor:IsCursorOverDesired()

		if is_recent_enough and is_cursor_over_target then
			--Log("Trigger")
			State.time_spent_trying_to_lock_bandit = s(0)

			-- Changing the range within this task-queue will shortly lead to the
			-- cursor not being over the target anymore, so we have to wait again to prevent bad locks.
			task:WaitUntil(function()
				return move_radar_cursor:IsCursorOverDesired()
			end, s(5))

			return Api.LockTargetUnderCursor(task)
			          :Wait(s(0.5)) -- Make sure symbology changes before continuing
		else
			return nil
		end
	end

	-- Validate lock
	if State.target_currently_locked == nil and Api.IsInTrackState() then
		--Log("Validate lock")

		if Api.HasSkinTrack() then
			State.wrong_lock_attempts = 0

			local is_in_range = target.scan_range:ConvertTo(NM) < Config.SHORT_LOCKED_CALLS_IF_CLOSER_THAN
			if Api.AreRadarMissilesReady() and is_in_range and Api.IsBandit(target.id) then
				task:Say("radar/aimsevenstablelock")
			elseif is_in_range then
				local phrase = "radar/contextlocked"
				if target.identification == RadarTargetIdentification.FRIENDLY then
					phrase = phrase .. "friend"
				elseif target.identification == RadarTargetIdentification.HOSTILE then
					phrase = phrase .. "bandit"
				else
					phrase = phrase .. "bogey"
				end
				task:Say(phrase)
			else
				task:Say("radar/stablelock")
			end

			-- TODO Values should be interpreted to identify bad lock
			task:ClickFast("Radar Target Aspect", "wide") -- Vc
			    :Wait(s(1))
			    :ClickFast("Radar Target Aspect", "nose", true) -- Altitude
			    :Wait(s(2))
			    :ClickFast("Radar Target Aspect", "wide", true) -- back to Vc

			State.target_currently_locked = target
		else
			--Log("  Wrong lock")
			Api.UnlockTarget(task)

			State.wrong_lock_attempts = State.wrong_lock_attempts + 1
			if State.wrong_lock_attempts > Config.MAX_WRONG_LOCK_ATTEMPTS then
				--Log("Wrong locks... giving up")
				State.target_to_lock = nil
				State.target_currently_locked = nil
				State.wrong_lock_attempts = 0

				task:Say("radar/lostlock")
				    :Say("radar/returningtoscan")
			else
				task:Wait(s(1.5)) -- Wait a scan cycle for the target to hopefully reappear on screen
			end
		end
		return task
	end

	-- Hold lock
	if State.target_currently_locked ~= nil then
		local lost_lock = not Api.IsInTrackState() or not Api.HasSkinTrack()
		if lost_lock then
			--Log("Lost lock")
			State.target_to_lock = nil
			State.target_currently_locked = nil
			return task:Say("radar/lostlock")
			           :Say("radar/returningtoscan")
		end

		-- Log("Holding lock")

		if State.target_currently_locked.id == Config.ARTIFICIAL_TARGET_ID then
			-- Attempt to replace it
			local locked_target = Api.FindLockedTargetOrNil()
			if locked_target then
				State.identified_targets[locked_target.id] = locked_target
				State.processed_targets[locked_target.id] = locked_target
				State.all_targets[locked_target.id] = locked_target

				State.target_to_highlight = locked_target
				State.pilot_requested_target_to_highlight = locked_target
				State.target_to_focus_on = locked_target
				State.target_to_lock = locked_target
				State.target_currently_locked = locked_target
				GetJester().behaviors[MoveRadarCursor]:FollowTarget(locked_target)
				GetJester().behaviors[MoveRadarAntenna]:FollowTarget(locked_target)

				State.identified_targets[Config.ARTIFICIAL_TARGET_ID] = nil
				State.processed_targets[Config.ARTIFICIAL_TARGET_ID] = nil
				State.all_targets[Config.ARTIFICIAL_TARGET_ID] = nil
				Api.UpdateTargetsPriority()
			end
		end

		Api.SelectRangeFor(task, Api.GetLockedTargetRange())
		return task
	end
end

-- Returns a still-fresh radar contact within the azimuth tolerance of the searched
-- bearing that has enough hits to be worth locking, or nil.
local function FindLockableContactNearAzimuth(azimuth)
	local best_target = nil
	local best_diff = nil
	for id, target in pairs(radar_targets or {}) do
		local hits = target.number_of_hits or 0
		if hits >= Config.NAILS_SEARCH_MIN_HITS and not target.found_in_acq_or_trk and IsObjectWithIdAlive(id) then
			local az_diff = Math.Abs(target.scan_azimuth:ConvertTo(deg) - azimuth:ConvertTo(deg))
			if az_diff < Config.NAILS_SEARCH_AZIMUTH_TOLERANCE and (best_diff == nil or az_diff < best_diff) then
				best_target = target
				best_diff = az_diff
			end
		end
	end
	return best_target
end

-- Directed search triggered by a forward-arc "nails" (see ObserveRWR / UserActions
-- "radar_nails_search"). Dwells on the nails bearing, sweeps antenna elevation, and
-- walks coarse gain down from max. If a lockable contact resolves at the bearing it
-- hands off to HANDLE_TARGET_LOCKING (auto-lock); if gain reaches the floor with
-- nothing found it gives up and resumes the normal scan. Invoked once per dwell step
-- (each returned task waits NAILS_SEARCH_DWELL before the next step).
function Phases.HandleNailsSearch()
	local task = Task:new()
	task:SetPriority(1)

	local move_radar_cursor = GetJester().behaviors[MoveRadarCursor]
	local move_radar_antenna = GetJester().behaviors[MoveRadarAntenna]
	local azimuth = State.nails_search_azimuth or deg(0)

	local now = Utilities.GetTime().mission_time

	-- Resolved a lockable contact at the bearing? Hand off to the lock flow.
	local target = FindLockableContactNearAzimuth(azimuth)
	if target then
		Log("Jester Radar | Nails search: resolved contact " .. tostring(target.id) .. " -> locking")
		State.nails_search_active = false
		State.nails_search_start = nil

		State.target_to_highlight = target
		State.pilot_requested_target_to_highlight = target
		State.target_to_focus_on = target
		State.target_to_lock = target
		move_radar_cursor:FollowTarget(target)
		move_radar_antenna:FollowTarget(target)
		return task -- next tick FindNextPhase enters HANDLE_TARGET_LOCKING
	end

	-- Use the fixed sky gain (no separate gain walk).
	local sky = Config.SKY_GAIN

	if State.nails_search_start == nil then
		-- One-time setup for this search: narrow scan, search display range.
		State.nails_search_start = now
		State.nails_search_sweep_up = true
		Log("Jester Radar | Nails search: begin at azimuth " .. tostring(azimuth) .. ", sky gain " .. tostring(sky))
		task:ClickFast("Radar Scan Type", Config.scan_type.narrow, true)
		    :ClickFast("Radar Range", Config.NAILS_SEARCH_DISPLAY_RANGE, true)
	elseif (now - State.nails_search_start) >= Config.NAILS_SEARCH_TIMEOUT then
		-- Timed out without resolving anything? Give up, resume scan.
		Log("Jester Radar | Nails search: timed out, nothing lockable - resuming scan")
		State.nails_search_active = false
		State.nails_search_start = nil
		State.current_scan_zone = nil -- forces PREPARE_SCAN_PATTERN next
		move_radar_cursor:ClearTarget()
		move_radar_antenna:ClearTarget()
		return task:Say("radar/returningtoscan")
	end

	-- Aim azimuth via the acquisition-gate cursor; sweep elevation via the antenna wheel;
	-- hold gain at the calibrated sky gain.
	local sweep_altitude = Config.NAILS_SEARCH_ELEVATION_SWEEP
	if not State.nails_search_sweep_up then
		sweep_altitude = ft(0) - Config.NAILS_SEARCH_ELEVATION_SWEEP
	end
	State.nails_search_sweep_up = not State.nails_search_sweep_up

	move_radar_cursor:MoveCursorTo(azimuth, Config.NAILS_SEARCH_AIM_RANGE)
	move_radar_antenna:MoveAntennaTo(Config.NAILS_SEARCH_AIM_RANGE, sweep_altitude, true)

	return task:ClickFast("Radar Gain Coarse", sky, true):Wait(Config.NAILS_SEARCH_DWELL)
end

-- Position of a display range in the descending SEARCH_RANGE_LADDER, or nil if the
-- range isn't part of the sweep (e.g. 5/10 nm).
local function ladder_index(range)
	for i, r in ipairs(Config.SEARCH_RANGE_LADDER) do
		if r == range then
			return i
		end
	end
	return nil
end

-- The pilot's selected range is the sweep MAX; Jester works down the ladder from
-- there to 25 nm and restarts. Returns the display range to scan at, initialising or
-- clamping the sweep as needed. A non-swept pilot range (5/10 nm) is used directly.
function Phases.GetSearchRange()
	local max_idx = ladder_index(State.pilot_requested_range)
	if not max_idx then
		State.search_range = nil
		return State.pilot_requested_range
	end
	local cur_idx = State.search_range and ladder_index(State.search_range)
	if not cur_idx or cur_idx < max_idx then
		State.search_range = State.pilot_requested_range -- (re)start at the pilot's max range
	end
	return State.search_range
end

-- Step the sweep one range shorter; restart at the pilot's max range past 25 nm.
function Phases.AdvanceSearchRange()
	local max_idx = ladder_index(State.pilot_requested_range)
	if not max_idx then
		return
	end
	local cur_idx = (State.search_range and ladder_index(State.search_range)) or max_idx
	if cur_idx >= #Config.SEARCH_RANGE_LADDER then
		State.search_range = State.pilot_requested_range
	else
		State.search_range = Config.SEARCH_RANGE_LADDER[cur_idx + 1]
	end
	-- Entering the critical 25 nm sweep: require a full bar scan before ranging out.
	if State.search_range == Config.range.nm_25 then
		State.nm25_sweep_complete = false
	end
end

function Phases.PrepareScanPattern()
	local task = Task:new():Click("Radar Mode", Config.mode.map)
	                 :Click("Radar Maneuver", "high")
	                 :Click("Radar Bars", "BARS_1")
	                 :Click("Radar Target Aspect", "wide")
	if State.target_to_focus_on ~= nil then
		task:Click("Radar Scan Type", Config.scan_type.narrow)
		Api.SelectRangeFor(task, State.target_to_focus_on.scan_range:ConvertTo(NM))
	else
		task:Click("Radar Scan Type", State.pilot_requested_scan_type)
		    :Click("Radar Range", Phases.GetSearchRange())
	end
	if Api.IsInTrackState() then
		Api.UnlockTarget(task)
	end
	return task
end

-- Build the elevation-zone order for the current situation: a top-down sweep at
-- 25 nm, otherwise the default cycle; with the below-level zones (LOW / SLIGHTLY_BELOW)
-- removed when flying below Config.SKIP_DOWN_BELOW_ALTITUDE (barometric MSL - Jester
-- has no true AGL).
local function elevation_zone_sequence()
	local display_range = State.search_range or State.pilot_requested_range
	local seq = Config.SCAN_ZONE_SEQUENCE_DEFAULT
	if display_range == Config.range.nm_25 then
		seq = Config.SCAN_ZONE_SEQUENCE_25NM
	end

	local own_altitude = GetJester().awareness:GetObservation("barometric_altitude")
	local low_threshold = Config.SKIP_DOWN_BELOW_ALTITUDE:ConvertTo(ft).value
	local is_low = own_altitude and own_altitude:ConvertTo(ft).value <= low_threshold
	if not is_low then
		return seq
	end

	-- At/below the low-altitude threshold: drop every below-CENTER bar so Jester stops
	-- at CENTER (0 ft) and never scans into the ground.
	local filtered = {}
	for _, zone in ipairs(seq) do
		local is_below_center = zone.is_relative and zone.altitude and zone.altitude:ConvertTo(ft).value < 0
		if not is_below_center then
			filtered[#filtered + 1] = zone
		end
	end
	return filtered
end

function Phases.ComputeNextScanZone()
	if State.pilot_requested_scan_zone ~= nil then
		State.max_scan_time_for_zone_no_bandits = Config.MAX_FOCUS_ZONE_SCAN_TIME
		return State.pilot_requested_scan_zone
	end
	if State.target_to_focus_on ~= nil then
		return Config.scan_zone.TARGET_FOCUS
	end

	-- Step through the (situation-dependent) elevation sequence, wrapping at the end.
	local seq = elevation_zone_sequence()
	local is_25nm = (State.search_range or State.pilot_requested_range) == Config.range.nm_25
	local idx
	for i, zone in ipairs(seq) do
		if State.current_scan_zone == zone then
			idx = i
			break
		end
	end
	if not idx then
		return seq[1] -- not in the current sequence (e.g. sequence just changed): start at top
	end
	if is_25nm and idx >= #seq then
		-- just scanned the last (bottom) bar of the 25 nm sweep: it's now complete
		State.nm25_sweep_complete = true
	end
	return seq[idx % #seq + 1]
end

function Phases.SelectScanZone(range, altitude, is_relative)
	range = range:ConvertTo(NM)
	altitude = altitude:ConvertTo(ft)
	--Log("Scanning " .. tostring(math.floor(range.value)) .. "nm at " .. tostring(math.floor(altitude.value)) .. "ft (relative: " .. tostring(is_relative) .. ")")

	local task = Task:new()
	if Api.IsInTrackState() then
		Api.UnlockTarget(task)
	end

	local move_radar_antenna = GetJester().behaviors[MoveRadarAntenna]
	move_radar_antenna:MoveAntennaTo(range, altitude, is_relative)
	return task:WaitUntil(function()
		return move_radar_antenna:IsAntennaOverDesired()
	end, s(5))
end

function Phases.SelectScanTarget(target)
	--Log("Scanning target " .. tostring(target.id))

	local task = Task:new()
	if Api.IsInTrackState() then
		Api.UnlockTarget(task)
	end

	local move_radar_antenna = GetJester().behaviors[MoveRadarAntenna]
	move_radar_antenna:FollowTarget(target)
	return task:WaitUntil(function()
		return move_radar_antenna:IsAntennaOverDesired()
	end, s(5))
end

function Phases.SelectNextScanZone()
	State.time_spent_scanning_zone_no_bandits = s(0)
	State.max_scan_time_for_zone_no_bandits = Config.MAX_ZONE_SCAN_TIME
	State.current_scan_zone = Phases.ComputeNextScanZone()

	local range = State.current_scan_zone.range
	local altitude = State.current_scan_zone.altitude
	local is_relative = State.current_scan_zone.is_relative

	if State.current_scan_zone == Config.scan_zone.TARGET_FOCUS then
		local target = radar_targets[State.target_to_focus_on.id] or State.target_to_focus_on
		return Phases.SelectScanTarget(target)
	end

	return Phases.SelectScanZone(range:ConvertTo(NM), altitude, is_relative)
end

function Phases.AdjustScreen()
	local task = Task:new()

	if State.target_to_highlight == nil and State.target_to_focus_on == nil then
		task:ClickFast("Radar Range", Phases.GetSearchRange())
	else
		local target = State.target_to_focus_on or State.target_to_highlight
		Api.SelectRangeFor(task, target.scan_range:ConvertTo(NM))
	end

	if State.target_to_focus_on == nil then
		task:ClickFast("Radar Scan Type", State.pilot_requested_scan_type)
	else
		task:ClickFast("Radar Scan Type", Config.scan_type.narrow)
	end

	return task
end

function Phases.ScanScreen()
	return nil
end

function Phases.IdentifyTargets()
	State.unidentified_new_targets = {}
	local count = 0
	local already_identified_count = 0
	local first_contact
	for id, target in pairs(radar_targets) do
		local is_not_noise = target.number_of_hits >= 2 and not target.found_in_acq_or_trk
		local is_new = State.identified_targets[id] == nil and State.processed_targets[id] == nil
		if is_not_noise and IsObjectWithIdAlive(id) then
			if is_new then
				State.unidentified_new_targets[id] = target
				State.all_targets[id] = target
				--Log("Spotted " .. Api.TargetToString(target))
				if count == 0 then
					first_contact = target
				end
				count = count + 1
			else
				already_identified_count = already_identified_count + 1
			end
		end
	end

	local task = Task:new()
	task:SetPriority(1)
	if count == 0 then
		return nil
	end

	local is_multiple_contacts = count > 1
	local is_only_contact_on_screen = already_identified_count == 0
	task:Say(BraCalls.IntroduceUnidentifiedContactPhrase(is_multiple_contacts, is_only_contact_on_screen))

	if count == 1 then
		-- e.g. "Ive got a bogey on screen, left 20, 15 miles, 15000 ft, ... positive IFF"
		local bearing = first_contact.scan_azimuth
		local range = first_contact.scan_range
		local altitude = Api.GetAltitudeFromSlantRange(first_contact.scan_range)
		task:Say(BraCalls.RadarBearingPhrase(bearing),
				BraCalls.RangePhrase(range),
				BraCalls.AltitudePhrase(altitude, false))
		State.has_single_unidentified_contact = true
	else
		-- e.g. "Ive got a bogey on screen, checking iff..."
		task:Say("contacts_iff/checkingiff")
		State.has_single_unidentified_contact = false
	end

	task:Require({ voice = true, hands = true })

	Api.ClickIffButton(task)
	   :Wait(s(3))
	   :Then(function()
		for id, target in pairs(State.unidentified_new_targets) do
			target_up_to_date = radar_targets[target.id] or target -- prefer latest data if available
			target_up_to_date.identification = Api.SelectIdentification(target_up_to_date.identification, target.identification)

			State.identified_targets[id] = target_up_to_date
			--Log("Identified " .. Api.TargetToString(target_up_to_date))
		end

		State.unidentified_new_targets = {}
	end)

	return task
end

function Phases.CallOutContactGroup(task, contact_group, is_first_callout)
	local lead_contact = contact_group[1]
	local is_friendly = Api.IsFriendly(lead_contact.id)

	if not is_friendly then
		State.max_scan_time_for_zone_no_bandits = Math.Max(State.max_scan_time_for_zone_no_bandits, Config.MAX_HOSTILE_ZONE_SCAN_TIME)
		State.time_spent_scanning_zone_no_bandits = s(0)
	end

	-- Technically, it would be `cos(antenna) * slant_range`, but for this purpose the slant_range is more realistic
	local bearing = lead_contact.scan_azimuth:ConvertTo(deg)
	local range = lead_contact.scan_range:ConvertTo(NM)
	local altitude = Api.GetAltitudeFromSlantRange(lead_contact.scan_range)

	local is_enough_time_after_takeoff = GetJester().memory:GetTimeSinceOnGround() >= Config.TIME_AFTER_TAKEOFF_START_CALLOUTS
	-- Ignore super close friendlies, also to avoid calling out own group when flying with buddies
	local is_close_friendly = is_friendly and range < Config.DONT_CALLOUT_FRIENDLY_CLOSER_THAN

	--Log("Processed targets (" .. tostring(#contact_group) .. "), lead: " .. tostring(lead_contact.id))
	for _, target in ipairs(contact_group) do
		State.processed_targets[target.id] = target
	end

	if State.has_single_unidentified_contact then
		if is_friendly then
			task:Say("contacts_iff/positiveiff")
		elseif Api.IsNeutral(lead_contact.id) then
			task:Say("contacts_iff/neutraliff")
		else
			task:Say("contacts_iff/negativeiff")
		end
	elseif is_enough_time_after_takeoff and not is_close_friendly then
		-- TODO It is unrealistic for Jester to make such precise callouts (requiring sin/cos math), IRL they estimated it. Should add some randomness and less precision.
		if lead_contact.cheat_altitude:ConvertTo(ft) > ft(40000) then
			task:Say(BraCalls.IntroduceContactPhrase(lead_contact.identification, #contact_group, not is_first_callout),
					BraCalls.RadarBearingPhrase(bearing),
					BraCalls.RangePhrase(range),
					"angels/dangerzone",
					BraCalls.AltitudePhrase(altitude, is_friendly))
		else
			task:Say(BraCalls.IntroduceContactPhrase(lead_contact.identification, #contact_group, not is_first_callout),
					BraCalls.RadarBearingPhrase(bearing),
					BraCalls.RangePhrase(range),
					BraCalls.AltitudePhrase(altitude, is_friendly))
		end
	end
	State.has_single_unidentified_contact = false

	return task
end

function Phases.CallOutNextContacts()
	local task = Task:new()
	task:SetPriority(1)

	local is_first_group = true
	for _ = 1, Config.MAX_CONTACT_CALLOUTS_PER_SENTENCE do
		local contact_group = Api.GetNextUnprocessedContactGroup()
		local contact = contact_group[1]
		if contact == nil then
			if is_first_group then
				return nil
			else
				break
			end
		end

		Phases.CallOutContactGroup(task, contact_group, is_first_group)
		is_first_group = false
	end

	Api.UpdateTargetsPriority()
	return task
end

local RANGE_NM = {
	[Config.range.nm_5] = 5, [Config.range.nm_10] = 10, [Config.range.nm_25] = 25,
	[Config.range.nm_50] = 50, [Config.range.nm_100] = 100, [Config.range.nm_200] = 200,
}

-- True when the current search produces ground clutter within the display range.
-- GetRadarMlcRange returns the main-lobe (ground) clutter range, or nil when the beam
-- isn't hitting the ground. NOTE: relies on that nil-when-looking-up behavior - validate in-sim.
local function is_ground_clutter_search()
	local mlc = GetRadarMlcRange()
	if not mlc then
		return false
	end
	local display_nm = RANGE_NM[State.search_range or State.pilot_requested_range] or 50
	return mlc:ConvertTo(NM).value <= display_nm
end

-- Range-sweep clock (decoupled from gain): advance the display range after RANGE_DWELL,
-- holding at 25 nm until the elevation bar scan has finished.
function Phases.TickRangeDwell()
	local now = Utilities.GetTime().mission_time
	if State.range_dwell_start == nil then
		State.range_dwell_start = now
		return
	end
	if (now - State.range_dwell_start) < Config.RANGE_DWELL then
		return
	end
	local at_25nm = (State.search_range or State.pilot_requested_range) == Config.range.nm_25
	if at_25nm and not State.nm25_sweep_complete then
		return -- hold at 25 nm until the bar scan completes
	end
	Phases.AdvanceSearchRange()
	State.range_dwell_start = now
end

function Phases.AdjustGain()
	if State.pilot_requested_scan_zone == State.current_scan_zone then
		State.pilot_requested_scan_zone = nil
	end

	-- Gain adjustment is gated behind a toggle (default on). Turn it off via the
	-- "radar_auto_gain" event / Radar wheel "Auto Gain" item to have Jester leave
	-- the radar gain and clutter interest range alone.
	if State.is_auto_gain_allowed ~= last_logged_auto_gain then
		Log("Jester Radar | AdjustGain gate: auto gain " .. (State.is_auto_gain_allowed and "ON (adjusting gain)" or "OFF (skipping gain)"))
		last_logged_auto_gain = State.is_auto_gain_allowed
	end
	if not State.is_auto_gain_allowed then
		return nil
	end

	-- Focusing a target, or a non-swept display range (5/10 nm): defer to backend gain.
	local display_range = Phases.GetSearchRange()
	if State.target_to_focus_on or not ladder_index(display_range) then
		local interest_range
		if State.target_to_focus_on then
			interest_range = State.target_to_focus_on.scan_range
		end
		SetRadarClutterInterestRange(interest_range)
		RadarAdjustGain()
		return nil
	end

	-- Step the display range on the dwell timer (independent of gain).
	Phases.TickRangeDwell()

	-- Fixed sky gain for sky searches; fixed lower gain when the search produces ground
	-- clutter. Jester can't measure clutter, so both are set values (tune in Config).
	local gain = Config.SKY_GAIN
	if is_ground_clutter_search() then
		gain = Config.GROUND_CLUTTER_GAIN
	end

	-- Already at the target gain: don't re-click every cycle. This is what was
	-- producing the recurring "Click 'Radar Gain Coarse': x" log spam.
	if Math.Abs(Api.GetCurrentGainCoarse() - gain) <= GAIN_EPSILON then
		return nil
	end

	local task = Task:new()
	task:SetPriority(1)
	return task:ClickFast("Radar Gain Coarse", gain, true)
end

return Phases
