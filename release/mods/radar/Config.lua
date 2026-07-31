---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.

local Config = {}

Config.state_type = {
	off = 0,
	standby = 1,
	search = 2,
	auto_acquisition = 3,
	acquisition = 4,
	track = 5
}

Config.screen_mode = {
	off = "off",
	standby = "standby",
	dscg_test = "dscg_test",
	radar_bit = "radar_bit",
	radar = "radar",
	tv = "tv",
}

Config.scan_type = {
	wide = "B_WIDE",
	narrow = "B_NAR",
}

Config.mode = {
	boresight = "BST",
	radar = "RDR",
	map = "MAP",
	air_to_ground = "AIR_GND",
	beacon = "BEACON",
	tv = "TV",
}

Config.range = {
	nm_5 = "RNG_5_NM",
	nm_10 = "RNG_10_NM",
	nm_25 = "RNG_25_NM",
	nm_50 = "RNG_50_NM",
	nm_100 = "RNG_100_NM",
	nm_200 = "RNG_200_NM",
}

Config.scan_zone = {
	TARGET_FOCUS = {
		name = "TARGET_FOCUS",
		is_relative = false,
	},
	CENTER_DOWNSTREAM_1 = {
		name = "CENTER_DOWNSTREAM_1",
		range = NM(30),
		altitude = ft(0),
		is_relative = true,
	},
	CENTER_DOWNSTREAM_2 = {
		name = "CENTER_DOWNSTREAM_2",
		range = NM(30),
		altitude = ft(0),
		is_relative = true,
	},
	SLIGHTLY_ABOVE = {
		name = "SLIGHTLY_ABOVE",
		range = NM(30),
		altitude = ft(2000),
		is_relative = true,
	},
	LOW = {
		name = "LOW",
		range = NM(30),
		altitude = ft(-10000),
		is_relative = true,
	},
	CENTER_UPSTREAM_1 = {
		name = "CENTER_UPSTREAM_1",
		range = NM(30),
		altitude = ft(0),
		is_relative = true,
	},
	CENTER_UPSTREAM_2 = {
		name = "CENTER_UPSTREAM_2",
		range = NM(30),
		altitude = ft(0),
		is_relative = true,
	},
	SLIGHTLY_BELOW = {
		name = "SLIGHTLY_BELOW",
		range = NM(30),
		altitude = ft(-2000),
		is_relative = true,
	},
	HIGH = {
		name = "HIGH",
		range = NM(30),
		altitude = ft(10000),
		is_relative = true,
	},
}

Config.phase = {
	PREPARE_SCAN_PATTERN = "PREPARE_SCAN_PATTERN",
	SELECT_NEXT_SCAN_ZONE = "SELECT_NEXT_SCAN_ZONE",
	ADJUST_SCREEN = "ADJUST_SCREEN",
	SCAN_SCREEN = "SCAN_SCREEN",
	IDENTIFY_TARGETS = "IDENTIFY_TARGETS",
	CALL_OUT_NEXT_CONTACTS = "CALL_OUT_NEXT_CONTACTS",
	ADJUST_GAIN = "ADJUST_GAIN",
	HANDLE_TARGET_LOCKING = "HANDLE_TARGET_LOCKING",
	HANDLE_NAILS_SEARCH = "HANDLE_NAILS_SEARCH",
}
Config.context_mode = {
	A2A = "A2A",
	A2G_DIVE_TOSS = "A2G_DIVE_TOSS",
	A2G_DIVE_LAYDOWN = "A2G_DIVE_LAYDOWN",
}
Config.context_action_type = {
	SHORT = "short",
	LONG = "long",
	DOUBLE = "double",
}

Config.MAX_ZONE_SCAN_TIME = s(5) -- max time spent scanning a zone without any new contacts before proceeding to the next zone
Config.MAX_HOSTILE_ZONE_SCAN_TIME = s(40) -- max time spent scanning a zone that just had a new hostile contact before proceeding to the next zone
Config.MAX_FOCUS_ZONE_SCAN_TIME = s(90) -- max time spent scanning a zone requested manually by the user before proceeding to the next zone

Config.FORGET_OLD_TARGETS_AFTER = min(2) -- time of how long a contact has not been seen on the screen, after which Jester forgets about it; will be called out new if it returns
Config.WAIT_WITH_REGULAR_IFF_FOR = s(20) -- time the IFF button has not been pressed after which Jester will execute it again
Config.SCAN_SCREEN_TIME = s(2.5) -- how long to stay in the SCAN_SCREEN phase; wait a few cycles to get a good picture and collect contacts

Config.MAX_CONTACT_CALLOUTS_PER_SENTENCE = 5 -- amount of how many groups Jester will callout in a single sentence; groups beyond that need another phase cycle
Config.DONT_CALLOUT_FRIENDLY_CLOSER_THAN = NM(5) -- distance threshold when friendlies (such as own-flight members) are not called out explicitly
Config.TIME_AFTER_TAKEOFF_START_CALLOUTS = s(20) -- to prevent spamming the pilot with callouts right after takeoff, this inhibits callouts for some time

Config.FOCUS_BANDIT_CLOSER_THAN = NM(30) -- range in which bandits are considered a threat and will automatically be highlighted and focused (unless disabled)
Config.SHORT_LOCKED_CALLS_IF_CLOSER_THAN = NM(15) -- when locking contacts closer than that, the locked-calls will be shortened
Config.MAX_TRYING_TO_LOCK_BANDIT_TIME = s(10) -- time after which Jester will abort waiting for a dropped contact while attempting to lock him
Config.MAX_WRONG_LOCK_ATTEMPTS = 5 -- amount of bad locks in a row after which Jester will abort attempting to lock a contact
Config.MAX_TRYING_TO_LOCK_CAGE_TARGET_TIME = s(10) -- time after which Jester will abort waiting for a contact in CAGE mode while attempting to lock him
Config.FORGOTTEN_TARGET_QUIET_TIME = s(20) -- after a contact is forgotten (dropped/aborted lock), re-detections within this long are tracked again silently (no repeat "new contact" callout); a later reappearance is announced fresh
Config.STALE_LOCK_MAX_AGE = s(3) -- a lock request for a contact not currently painted is refused (and the contact forgotten) if its last radar hit is older than this; within it, the contact is treated as an intermittent blink and the lock is allowed to wait for it

Config.GAIN_COARSE_FAR = 0.6 -- Gain setting (coarse knob) for targets far away (> 25nm)
Config.GAIN_COARSE_CLOSE = 0.5 -- Gain setting (coarse knob) for targets close (<= 25nm)

Config.ARTIFICIAL_TARGET_ID = -1 -- Used if Jester is tracking a target he does not know about. He will try to replace it when the actual target shows up.

-- Nails Search: when a "nails" (airborne RWR emitter) appears in the forward arc
-- (10-2 o'clock) while Jester is free-scanning, he dwells on that bearing sweeping
-- elevation while walking coarse gain down from max, trying to resolve a lockable
-- contact. Auto-locks it if found, or gives up after NAILS_SEARCH_TIMEOUT. Uses the
-- calibrated sky gain (see SKY_GAIN below) - no separate gain walk.
-- Driven by Radar.FindNextPhase -> Phases.HandleNailsSearch; triggered from
-- ObserveRWR via the "radar_nails_search" event (UserActions.lua). All values here
-- are meant to be tuned in-sim.
Config.NAILS_SEARCH_HOUR_AZIMUTH = { -- forward-arc clock hours -> antenna azimuth
	[10] = deg(-60),
	[11] = deg(-30),
	[12] = deg(0),
	[1]  = deg(30),
	[2]  = deg(60),
}
Config.NAILS_SEARCH_TIMEOUT = s(15)            -- give up the directed search after this long, BUT never before one full elevation scan (a complete up+down sweep) has been done - see Phases.HandleNailsSearch
Config.NAILS_SEARCH_DWELL = s(2.5)             -- dwell time at each elevation sweep step
Config.NAILS_SEARCH_DISPLAY_RANGE = Config.range.nm_50 -- display range while searching
Config.NAILS_SEARCH_AIM_RANGE = NM(25)         -- range used to aim the acquisition point
Config.NAILS_SEARCH_ELEVATION_SWEEP = ft(20000) -- +/- relative altitude used to sweep elevation
Config.NAILS_SEARCH_AZIMUTH_TOLERANCE = deg(20) -- contact must be within this of the bearing to count
Config.NAILS_SEARCH_MIN_HITS = 2                -- radar hits before a contact is considered lockable

-- Normal-search gain. Jester can't measure screen clutter (the radar API exposes no
-- noise/video level), so instead of calibrating he holds a fixed sky gain for sky
-- searches and drops to a fixed lower gain when a search produces ground clutter
-- (GetRadarMlcRange within the display range). Gated by the auto-gain toggle
-- (State.is_auto_gain_allowed). See Phases.AdjustGain. Tune SKY_GAIN to taste.
Config.SKY_GAIN            = 0.62793 -- coarse gain held for all sky searches (incl. nails search)
Config.GROUND_CLUTTER_GAIN = 0.5     -- coarse gain used when the search produces ground clutter

-- External coarse-gain override detection. DCS input bindings can't be read from here, but
-- a bound HOTAS gain axis (or the player working the knob) re-applies the gain every frame
-- and wins over Jester's clickable writes. We detect that behaviorally: if the knob keeps
-- sitting a STABLE distance away from what Jester last commanded, an external control owns
-- it, so Jester defers (stops driving gain) and leaves the player's setting alone. With no
-- such override, Jester drives SKY_GAIN/GROUND_CLUTTER_GAIN as normal.
Config.GAIN_OVERRIDE_EPS     = 0.05    -- how far the knob must sit from Jester's commanded value to count as overridden
Config.GAIN_OVERRIDE_STRIKES = 4       -- consecutive AdjustGain cycles at a stable foreign value before deferring
Config.GAIN_OVERRIDE_GRACE   = s(0.5)  -- settle time after a command before a mismatch is judged
-- Optional spoken callout when Jester defers gain to a manual/axis override. STAGED OFF:
-- the console/log line always fires; flip this to true once the voice clip exists at
-- Sounds/Jester/<GAIN_DEFER_PHRASE>*.ogg (e.g. radar/gainmanual1.ogg, ...2, ...3).
Config.ANNOUNCE_GAIN_DEFER = false
Config.GAIN_DEFER_PHRASE   = 'radar/gainmanual'
Config.RANGE_DWELL        = s(15)  -- how long to search each display range before stepping (range-sweep clock)
-- Descending ladder of the ranges the sweep/gain-hunt run at. The pilot's range is
-- the sweep ceiling; ranges not listed (5/10 nm) get the backend gain and no sweep.
Config.SEARCH_RANGE_LADDER = {
	Config.range.nm_200,
	Config.range.nm_100,
	Config.range.nm_50,
	Config.range.nm_25,
}

-- Elevation scan customization (see Phases.ComputeNextScanZone).
-- Jester has no true AGL / radar-altimeter reading, only barometric (MSL) altitude,
-- so this threshold is MSL. Below it he skips the below-level scan zones so he does
-- not waste sweeps looking into the ground.
Config.SKIP_DOWN_BELOW_ALTITUDE = ft(5000)

-- Elevation zone order. SCAN_ZONE_SEQUENCE_DEFAULT is the normal cycle (used at
-- 50/100/200 nm). At 25 nm Jester instead runs SCAN_ZONE_SEQUENCE_25NM: a manual
-- top-down bar scan from +30,000 ft down to -5,000 ft, referenced at 30 nm. In both,
-- the below-CENTER bars are dropped when flying at/below SKIP_DOWN_BELOW_ALTITUDE, so
-- he stops at CENTER (0 ft) and never scans into the ground.
Config.SCAN_ZONE_SEQUENCE_DEFAULT = {
	Config.scan_zone.CENTER_DOWNSTREAM_1,
	Config.scan_zone.CENTER_DOWNSTREAM_2,
	Config.scan_zone.SLIGHTLY_ABOVE,
	Config.scan_zone.LOW,
	Config.scan_zone.CENTER_UPSTREAM_1,
	Config.scan_zone.CENTER_UPSTREAM_2,
	Config.scan_zone.SLIGHTLY_BELOW,
	Config.scan_zone.HIGH,
}
-- 25 nm manual bar scan: +30,000 ft -> -5,000 ft in 5,000 ft steps (~1.6 deg each at
-- 30 nm), referenced at 30 nm per request. Edit the altitudes/step to taste.
local nm25_ref = NM(30)
Config.SCAN_ZONE_SEQUENCE_25NM = {
	{ name = "25NM_UP_30K",  range = nm25_ref, altitude = ft(30000),  is_relative = true },
	{ name = "25NM_UP_25K",  range = nm25_ref, altitude = ft(25000),  is_relative = true },
	{ name = "25NM_UP_20K",  range = nm25_ref, altitude = ft(20000),  is_relative = true },
	{ name = "25NM_UP_15K",  range = nm25_ref, altitude = ft(15000),  is_relative = true },
	{ name = "25NM_UP_10K",  range = nm25_ref, altitude = ft(10000),  is_relative = true },
	{ name = "25NM_UP_5K",   range = nm25_ref, altitude = ft(5000),   is_relative = true },
	{ name = "25NM_CENTER",  range = nm25_ref, altitude = ft(0),      is_relative = true },
	{ name = "25NM_DOWN_5K", range = nm25_ref, altitude = ft(-5000),  is_relative = true },
}

-- Lightweight file logger (Jester's built-in Log() only reaches the in-sim console,
-- which isn't persisted). Writes to <writedir>/jester_console.log. Truncated once per
-- Lua session so each flight starts a clean log instead of growing without bound.
-- Toggle with Config.JESTER_CONSOLE_LOG. Call via Config.ConsoleLog("...").
Config.JESTER_CONSOLE_LOG = true
local function console_log_path()
	local base
	pcall(function() if lfs and lfs.writedir then base = lfs.writedir() end end)
	if base then return base .. "jester_console.log" end
	return "C:/Users/Patrick/Saved Games/DCS_F4E/jester/jester_console.log"
end
local CONSOLE_LOG_FILE = console_log_path()
local console_log_started = false
function Config.ConsoleLog(msg)
	if not Config.JESTER_CONSOLE_LOG then
		return
	end
	local mode = "a"
	if not console_log_started then
		mode = "w" -- truncate on the first write of the session
		console_log_started = true
	end
	pcall(function()
		local f = io.open(CONSOLE_LOG_FILE, mode)
		if f then
			f:write(msg .. "\n")
			f:close()
		end
	end)
end

return Config
