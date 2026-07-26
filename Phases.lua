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
		    :Click("Radar Range", State.pilot_requested_range)
	end
	if Api.IsInTrackState() then
		Api.UnlockTarget(task)
	end
	return task
end

function Phases.ComputeNextScanZone()
	if State.pilot_requested_scan_zone ~= nil then
		State.max_scan_time_for_zone_no_bandits = Config.MAX_FOCUS_ZONE_SCAN_TIME
		return State.pilot_requested_scan_zone
	end
	if State.target_to_focus_on ~= nil then
		return Config.scan_zone.TARGET_FOCUS
	end

	local next_zone = Config.scan_zone.CENTER_DOWNSTREAM_1
	if State.current_scan_zone == nil or State.current_scan_zone == Config.scan_zone.HIGH then
		next_zone = Config.scan_zone.CENTER_DOWNSTREAM_1
	elseif State.current_scan_zone == Config.scan_zone.CENTER_DOWNSTREAM_1 then
		next_zone = Config.scan_zone.CENTER_DOWNSTREAM_2
	elseif State.current_scan_zone == Config.scan_zone.CENTER_DOWNSTREAM_2 then
		next_zone = Config.scan_zone.SLIGHTLY_ABOVE
	elseif State.current_scan_zone == Config.scan_zone.SLIGHTLY_ABOVE then
		next_zone = Config.scan_zone.LOW
	elseif State.current_scan_zone == Config.scan_zone.LOW then
		next_zone = Config.scan_zone.CENTER_UPSTREAM_1
	elseif State.current_scan_zone == Config.scan_zone.CENTER_UPSTREAM_1 then
		next_zone = Config.scan_zone.CENTER_UPSTREAM_2
	elseif State.current_scan_zone == Config.scan_zone.CENTER_UPSTREAM_2 then
		next_zone = Config.scan_zone.SLIGHTLY_BELOW
	elseif State.current_scan_zone == Config.scan_zone.SLIGHTLY_BELOW then
		next_zone = Config.scan_zone.HIGH
	end
	return next_zone
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
		task:ClickFast("Radar Range", State.pilot_requested_range)
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

function Phases.AdjustGain()
	if State.pilot_requested_scan_zone == State.current_scan_zone then
		State.pilot_requested_scan_zone = nil
	end

	-- Gain adjustment is handled on the backend
	local interest_range
	if State.target_to_focus_on then
		interest_range = State.target_to_focus_on.scan_range
	else
		-- Reset for a general scan and adjustment
		interest_range = nil
	end
	-- Gain adjustment is gated behind a toggle (default on). Turn it off via the
	-- "radar_auto_gain" event / Radar wheel "Auto Gain" item to have Jester leave
	-- the radar gain and clutter interest range alone.
	if State.is_auto_gain_allowed then
		SetRadarClutterInterestRange(interest_range)
		RadarAdjustGain()
	end
	return nil
end

return Phases
