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

-- Single point through which Jester drives the coarse gain, so override detection has one
-- source of truth for "what we last commanded". Records the value/time, then clicks it.
function Phases.CommandCoarseGain(task, value)
	State.gain_last_commanded = value
	State.gain_last_command_time = Utilities.GetTime().mission_time
	return task:ClickFast("Radar Gain Coarse", value, true)
end

-- Behavioral detection of an external coarse-gain override (a bound HOTAS gain axis, or the
-- player working the knob). We can't read DCS input bindings from here, but if the knob keeps
-- sitting a STABLE distance away from what Jester last commanded, something else owns it.
-- After GAIN_OVERRIDE_STRIKES confirmed cycles, defer: Jester stops driving gain and leaves
-- the player's setting alone. Sticky for the session (an axis binding won't change mid-flight).
function Phases.DetectGainOverride()
	if State.gain_deferred_to_manual then return end
	if State.gain_last_commanded == nil or State.gain_last_command_time == nil then return end
	-- Let the last command settle before judging it.
	if (Utilities.GetTime().mission_time - State.gain_last_command_time) < Config.GAIN_OVERRIDE_GRACE then
		return
	end

	local current = Api.GetCurrentGainCoarse()
	if Math.Abs(current - State.gain_last_commanded) > Config.GAIN_OVERRIDE_EPS then
		-- Off target. Count it only if it's the SAME foreign value as before - an axis rests
		-- at a fixed position, whereas transient settling/switching wanders.
		if State.gain_override_value ~= nil and Math.Abs(current - State.gain_override_value) <= Config.GAIN_OVERRIDE_EPS then
			State.gain_override_strikes = State.gain_override_strikes + 1
		else
			State.gain_override_strikes = 1
			State.gain_override_value = current
		end
	else
		State.gain_override_strikes = 0
		State.gain_override_value = nil
	end

	if State.gain_override_strikes >= Config.GAIN_OVERRIDE_STRIKES then
		State.gain_deferred_to_manual = true
		Log("Jester Radar | Coarse gain under external (axis/manual) control - deferring; Jester will not drive gain")
		Config.ConsoleLog(string.format("%.1f GAIN deferred to manual (knob=%.3f, last cmd=%.3f)",
			Utilities.GetTime().mission_time:ConvertTo(s).value, current, State.gain_last_commanded))
		-- Optional spoken callout (staged; enable Config.ANNOUNCE_GAIN_DEFER once the clip exists).
		if Config.ANNOUNCE_GAIN_DEFER then
			local announce = Task:new()
			announce:SetPriority(1)
			announce:Say(Config.GAIN_DEFER_PHRASE)
			GetJester():AddTask(announce)
		end
	end
end

-- Forget a target entirely (after a lock drops or a lock attempt is abandoned): drop it
-- from every tracking list and clear any selection/cursor pointing at it. Without this,
-- the target lingered in State.all_targets and stayed highlighted, so a later context-lock
-- re-selected it and LockTarget re-locked it from that STALE snapshot - same id, bearing,
-- range and altitude - even after the jet had maneuvered. Forgotten here, it is re-acquired
-- fresh by the normal scan if it is really still out there.
function Phases.ForgetTarget(id)
	if id == nil then
		return
	end
	State.unidentified_new_targets[id] = nil
	State.identified_targets[id] = nil
	State.processed_targets[id] = nil
	State.all_targets[id] = nil

	-- Remember we just forgot this one, so the scan's fresh re-detection is absorbed
	-- silently for a short while instead of producing a repeat "new contact" call-out.
	State.recently_forgotten[id] = Utilities.GetTime().mission_time

	if State.target_to_highlight and State.target_to_highlight.id == id then
		State.target_to_highlight = nil
	end
	if State.pilot_requested_target_to_highlight and State.pilot_requested_target_to_highlight.id == id then
		State.pilot_requested_target_to_highlight = nil
	end
	if State.target_to_focus_on and State.target_to_focus_on.id == id then
		State.target_to_focus_on = nil
	end

	local move_radar_cursor = GetJester().behaviors[MoveRadarCursor]
	if move_radar_cursor then
		move_radar_cursor:ClearTarget()
	end
	local move_radar_antenna = GetJester().behaviors[MoveRadarAntenna]
	if move_radar_antenna then
		move_radar_antenna:ClearTarget()
	end

	Api.UpdateTargetsPriority() -- rebuild the bandit/non-bandit priority views without it
	Config.ConsoleLog(string.format("%.1f FORGET id=%s (quiet %ss)",
		Utilities.GetTime().mission_time:ConvertTo(s).value, tostring(id),
		tostring(Config.FORGOTTEN_TARGET_QUIET_TIME:ConvertTo(s).value)))
end

-- True if `id` was forgotten (via forget_target) within FORGOTTEN_TARGET_QUIET_TIME.
-- Expired entries are purged so a later reappearance counts as a genuine re-acquisition.
local function was_recently_forgotten(id, now)
	local forgotten_at = State.recently_forgotten[id]
	if forgotten_at == nil then
		return false
	end
	if (now - forgotten_at) >= Config.FORGOTTEN_TARGET_QUIET_TIME then
		State.recently_forgotten[id] = nil
		return false
	end
	return true
end

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
			Phases.ForgetTarget(target.id) -- don't keep re-locking this stale contact
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
				Phases.ForgetTarget(target.id) -- don't keep re-locking this stale contact
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
			Phases.ForgetTarget(target.id) -- don't keep re-locking this stale contact
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
		Config.ConsoleLog(string.format("%.1f NAILS resolved id=%s -> locking",
			now:ConvertTo(s).value, tostring(target.id)))
		State.nails_search_active = false
		State.nails_search_start = nil

		-- NOTE: deliberately do NOT set pilot_requested_target_to_highlight here. That
		-- flag means "the pilot hand-picked this target - stop auto-selecting and stick
		-- to it", which suppressed auto-focus AND the normal call-out cycle even after
		-- this lock ended (Jester would steady on a contact but announce nothing).
		-- target_to_lock alone drives the auto-lock via HANDLE_TARGET_LOCKING, and
		-- leaving pilot_requested unset lets Jester resume normal scan+callouts afterwards.
		State.target_to_highlight = target
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
		State.nails_search_scans_completed = 0
		Log("Jester Radar | Nails search: begin at azimuth " .. tostring(azimuth) .. ", sky gain " .. tostring(sky))
		Config.ConsoleLog(string.format("%.1f NAILS begin az=%s", now:ConvertTo(s).value, tostring(azimuth)))
		task:ClickFast("Radar Scan Type", Config.scan_type.narrow, true)
		    :ClickFast("Radar Range", Config.NAILS_SEARCH_DISPLAY_RANGE, true)
	elseif (now - State.nails_search_start) >= Config.NAILS_SEARCH_TIMEOUT
			and (State.nails_search_scans_completed or 0) >= 1 then
		-- Timed out without resolving anything? Give up, resume scan. But only once at
		-- least one full elevation scan (a complete up+down sweep) has been done - if the
		-- sweep can't finish within the timeout, let it complete before giving up.
		Log("Jester Radar | Nails search: timed out, nothing lockable - resuming scan")
		Config.ConsoleLog(string.format("%.1f NAILS timeout -> resume scan (scans=%s)",
			now:ConvertTo(s).value, tostring(State.nails_search_scans_completed)))
		State.nails_search_active = false
		State.nails_search_start = nil
		State.current_scan_zone = nil -- forces PREPARE_SCAN_PATTERN next
		move_radar_cursor:ClearTarget()
		move_radar_antenna:ClearTarget()
		return task:Say("radar/returningtoscan")
	end

	-- Aim azimuth via the acquisition-gate cursor; sweep elevation via the antenna wheel;
	-- hold gain at the calibrated sky gain.
	local sweeping_up = State.nails_search_sweep_up
	local sweep_altitude = Config.NAILS_SEARCH_ELEVATION_SWEEP
	if not sweeping_up then
		sweep_altitude = ft(0) - Config.NAILS_SEARCH_ELEVATION_SWEEP
	end
	State.nails_search_sweep_up = not sweeping_up
	if not sweeping_up then
		-- Just finished the down half, so one full up+down elevation scan is complete.
		State.nails_search_scans_completed = (State.nails_search_scans_completed or 0) + 1
	end

	move_radar_cursor:MoveCursorTo(azimuth, Config.NAILS_SEARCH_AIM_RANGE)
	move_radar_antenna:MoveAntennaTo(Config.NAILS_SEARCH_AIM_RANGE, sweep_altitude, true)

	-- Hold sky gain during the sweep, unless the player's axis/knob owns the gain.
	if not State.gain_deferred_to_manual then
		Phases.CommandCoarseGain(task, sky)
	end
	return task:Wait(Config.NAILS_SEARCH_DWELL)
end

-- True (via a non-nil index) if a display range is one of the normal search ranges in
-- SEARCH_RANGE_LADDER; nil for a non-search range like 5/10 nm. AdjustGain uses this to
-- decide whether to drive the fixed sky gain or defer to the backend.
local function ladder_index(range)
	for i, r in ipairs(Config.SEARCH_RANGE_LADDER) do
		if r == range then
			return i
		end
	end
	return nil
end

-- Fixed display range - no range sweep. The search runs at a single range (the pilot's
-- requested range, default 50 nm); 25 nm is no longer part of the normal pattern. The pilot
-- can still pick a different range manually and it's honored as-is.
function Phases.GetSearchRange()
	State.search_range = State.pilot_requested_range
	return State.search_range
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

-- Elevation cycle chosen by own altitude:
--   * at/below SKIP_DOWN_BELOW_ALTITUDE (5,000 ft): the low-altitude MP pattern -
--     mostly level with occasional high looks, NO below-level bars (don't scan into the
--     ground). See Config.SCAN_ZONE_SEQUENCE_LOW.
--   * above it: the original look-down search (Config.SCAN_ZONE_SEQUENCE_DEFAULT, which
--     includes the LOW / SLIGHTLY_BELOW bars) so Jester can find bandits below him.
-- Range is a fixed 50 nm at either altitude (Phases.GetSearchRange); no 25 nm sweep.
-- NOTE: altitude is barometric (MSL) - Jester has no true AGL.
local function elevation_zone_sequence()
	local own_altitude = GetJester().awareness:GetObservation("barometric_altitude")
	local low_threshold = Config.SKIP_DOWN_BELOW_ALTITUDE:ConvertTo(ft).value
	local is_low = own_altitude and own_altitude:ConvertTo(ft).value <= low_threshold
	if is_low then
		return Config.SCAN_ZONE_SEQUENCE_LOW
	end
	return Config.SCAN_ZONE_SEQUENCE_DEFAULT
end

function Phases.ComputeNextScanZone()
	if State.pilot_requested_scan_zone ~= nil then
		State.max_scan_time_for_zone_no_bandits = Config.MAX_FOCUS_ZONE_SCAN_TIME
		return State.pilot_requested_scan_zone
	end
	if State.target_to_focus_on ~= nil then
		return Config.scan_zone.TARGET_FOCUS
	end

	-- Step through the elevation sequence, wrapping at the end.
	local seq = elevation_zone_sequence()
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
	local now = Utilities.GetTime().mission_time
	local count = 0
	local already_identified_count = 0
	local total = 0     -- diagnostic: all radar_targets this pass
	local notnoise = 0  -- diagnostic: alive, above the hit threshold
	local suppressed = 0 -- diagnostic: absorbed silently (recently forgotten)
	local first_contact
	for id, target in pairs(radar_targets) do
		total = total + 1
		local is_not_noise = target.number_of_hits >= 2 and not target.found_in_acq_or_trk
		local is_new = State.identified_targets[id] == nil and State.processed_targets[id] == nil
		if is_not_noise and IsObjectWithIdAlive(id) then
			notnoise = notnoise + 1
			if is_new and was_recently_forgotten(id, now) then
				-- Contact we just forgot after a dropped/aborted lock: keep it tracked with
				-- fresh data (so it stays lockable/highlightable) but stay quiet for the
				-- quiet window - no immediate repeat call-out. Crucially, do NOT mark it
				-- processed here: that would silence it forever. Leaving it un-processed
				-- means once the window expires (was_recently_forgotten purges the entry) it
				-- is announced fresh like any other contact - Jester keeps detecting it.
				State.all_targets[id] = target
				already_identified_count = already_identified_count + 1
				suppressed = suppressed + 1
			elseif is_new then
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

	Config.ConsoleLog(string.format(
		"%.1f IDENTIFY total=%d notnoise=%d new=%d suppressed=%d known=%d srange=%s",
		now:ConvertTo(s).value, total, notnoise, count, suppressed, already_identified_count,
		tostring(State.search_range)))
	-- When contacts are present but getting filtered, dump each one's hit count / flags /
	-- range / azimuth so we can see WHY (e.g. number_of_hits stuck at 1 = beam grazing).
	if total > 0 then
		for id, target in pairs(radar_targets) do
			Config.ConsoleLog(string.format("     tgt id=%s hits=%s acqtrk=%s alive=%s rng=%s az=%s",
				tostring(id), tostring(target.number_of_hits), tostring(target.found_in_acq_or_trk),
				tostring(IsObjectWithIdAlive(id)), tostring(target.scan_range), tostring(target.scan_azimuth)))
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

	-- A bound gain axis / manual knob owns the gain (detected below): defer to the player.
	if State.gain_deferred_to_manual then
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

	-- Fixed sky gain for sky searches; fixed lower gain when the search produces ground
	-- clutter. Jester can't measure clutter, so both are set values (tune in Config).
	local gain = Config.SKY_GAIN
	if is_ground_clutter_search() then
		gain = Config.GROUND_CLUTTER_GAIN
	end

	-- Did our last command stick? If the knob keeps getting pulled to a stable foreign value,
	-- an axis/manual control owns the gain - defer and stop fighting it.
	Phases.DetectGainOverride()
	if State.gain_deferred_to_manual then
		return nil
	end

	-- Already at the target gain: don't re-click every cycle. This is what was
	-- producing the recurring "Click 'Radar Gain Coarse': x" log spam.
	if Math.Abs(Api.GetCurrentGainCoarse() - gain) <= GAIN_EPSILON then
		return nil
	end

	local task = Task:new()
	task:SetPriority(1)
	return Phases.CommandCoarseGain(task, gain)
end

return Phases
