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

Config.GAIN_COARSE_FAR = 0.6 -- Gain setting (coarse knob) for targets far away (> 25nm)
Config.GAIN_COARSE_CLOSE = 0.5 -- Gain setting (coarse knob) for targets close (<= 25nm)

Config.ARTIFICIAL_TARGET_ID = -1 -- Used if Jester is tracking a target he does not know about. He will try to replace it when the actual target shows up.

-- Nails Search: when a "nails" (airborne RWR emitter) appears in the forward arc
-- (10-2 o'clock) while Jester is free-scanning, he dwells on that bearing sweeping
-- elevation while walking coarse gain down from max, trying to resolve a lockable
-- contact. Auto-locks it if found, or gives up at NAILS_SEARCH_GAIN_MIN.
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
Config.NAILS_SEARCH_GAIN_START = 0.8            -- coarse gain to begin the walk (max)
Config.NAILS_SEARCH_GAIN_MIN = 0.5              -- coarse gain floor; give up here
Config.NAILS_SEARCH_GAIN_STEP = 0.05           -- coarse gain drop per dwell step
Config.NAILS_SEARCH_DWELL = s(2.5)             -- dwell time at each gain step
Config.NAILS_SEARCH_DISPLAY_RANGE = Config.range.nm_50 -- display range while searching
Config.NAILS_SEARCH_AIM_RANGE = NM(25)         -- range used to aim the acquisition point
Config.NAILS_SEARCH_ELEVATION_SWEEP = ft(20000) -- +/- relative altitude used to sweep elevation
Config.NAILS_SEARCH_AZIMUTH_TOLERANCE = deg(20) -- contact must be within this of the bearing to count
Config.NAILS_SEARCH_MIN_HITS = 2                -- radar hits before a contact is considered lockable

-- Normal-search gain hunt: while free-scanning at longer display ranges, Jester walks
-- the coarse gain down from SEARCH_GAIN_START to SEARCH_GAIN_MIN (one step per scan
-- cycle) then resets to the top, surfacing weak/distant returns a fixed gain misses.
-- Gated by the auto-gain toggle (State.is_auto_gain_allowed); see Phases.AdjustGain.
-- Add shorter ranges to SEARCH_GAIN_LONG_RANGES if you want the hunt closer in.
Config.SEARCH_GAIN_START = 0.8
Config.SEARCH_GAIN_MIN = 0.5
Config.SEARCH_GAIN_STEP = 0.05
Config.SEARCH_GAIN_LONG_RANGES = { -- display ranges at which the gain hunt runs
	[Config.range.nm_25] = true,
	[Config.range.nm_50] = true,
	[Config.range.nm_100] = true,
	[Config.range.nm_200] = true,
}

return Config
