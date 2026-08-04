
local Class = require 'base.Class'
local ReportIAS = require 'behaviors.NFO.common.ReportIAS'
local Situation = require 'base.Situation'
local Merged = require 'conditions.Merged'
local Landed = require 'conditions.Landed'
local InLandingConfig = require 'conditions.InLandingConfig'
local DogfightAdvisory = require 'behaviors.NFO.WVR.DogfightAdvisory'
local Utilities = require 'base.Utilities'
local Math = require 'base.Math'
local DbaseUtils = require 'behaviors.DbaseUtils'
local Sentence = require 'voice.Sentence'
local SayTask = require 'tasks.common.SayTask'
local Condition = require 'base.Condition'
local Constants = require 'behaviors.Constants'
local Labels = require 'base.Labels' -- for the hostile gate on the helicopter callout

-- Override of the stock Dogfight situation. Announces activation with voice: "check"
-- (checklists/check) then clock + type + distance, modeled on DogfightAdvisory's phrase
-- builders; announces deactivation with "clean, clean". Holds the merge through brief tally
-- loss via sticky merge memory (below). Also logs (Jester Console) what Jester knows about
-- the merge threat - the Eyeballs visual flags are only set when he's actually SEEN it.
local ANNOUNCE_DOGFIGHT_VOICE = true
local CHECK_PHRASE          = 'checklists/check'    -- Sounds/Jester/checklists/check*.ogg (activation cue)
local CLEAN_PHRASE          = 'checklists/clean'    -- Sounds/Jester/checklists/clean*.ogg (deactivation, said twice)
local FALLBACK_TYPE_PHRASE  = 'contacts_iff/bogey'
local HELICOPTER_PHRASE     = 'dawger/Helo' -- enemy rotorcraft (no dedicated aircraft phrase)
local HIGH_LOW_THRESHOLD    = deg(10)

-- Phrase builders (mirrored from behaviors/NFO/WVR/DogfightAdvisory.lua) --------
local function ContactHiLo(contact)
	local elev_body = contact.polar_body.elevation
	local elev_ned  = contact.polar_ned.elevation
	if elev_body > HIGH_LOW_THRESHOLD and elev_ned > HIGH_LOW_THRESHOLD then
		return 'high'
	elseif elev_body < -HIGH_LOW_THRESHOLD and elev_ned < -HIGH_LOW_THRESHOLD then
		return 'low'
	end
	return ''
end

local function ClockPhrase(contact)
	local oclock = Utilities.AngleToOClock(Math.Wrap360(contact.polar_body.azimuth))
	return 'spotting/bfm' .. oclock .. 'oclock' .. ContactHiLo(contact)
end

local function TypePhrase(contact)
	-- Enemy helicopters have no aircraft phrase; call them 'helicopter' (matches
	-- DogfightAdvisory). Rotorcraft aren't tagged with a 'helicopter' label, so match the
	-- type string; gate on 'hostile' so only enemy helos are called out.
	if DbaseUtils.IsHelicopterType(contact.type) and contact.CanBe and contact:CanBe(Labels.hostile) then
		return HELICOPTER_PHRASE
	end
	local data = DbaseUtils.GetAircraftPhrase(tostring(contact.type))
	if data then
		return data.phrase
	end
	return FALLBACK_TYPE_PHRASE
end

local function DistancePhrase(contact)
	local distance = Math.Round(contact.polar_ned.length:ConvertTo(NM))
	if distance.value > 0 then
		return string.format('misc/%.0fmiles', distance.value)
	end
	return 'spotting/wvrclose'
end

-- Sticky merge memory (EXPLORATION) --------------------------------------------
-- Awareness purges a contact 7s after it's last SENSED (RemoveOldContacts), and in a hard
-- fight the WSO loses tally for longer than that, so plain Merged.True/False toggles the
-- situation on and off. Activation still fires instantly when a bandit is inside
-- dogfight_distance; but instead of deactivating the moment tally is lost, we hold the merge
-- until no close bandit has been seen for MERGE_MEMORY. Kept local to this file - the shared
-- conditions/Merged.lua is untouched.
local MERGE_MEMORY = s(20)
local last_close_bandit_time = nil
local was_close = false

local function close_bandit_present()
	local b = GetJester().awareness:GetClosestAirThreat()
	return b and b.polar_body.length:ConvertTo(NM) < Constants.dogfight_distance
end

local StickyMergedFalse = Class(Condition)
function StickyMergedFalse:Check()
	if close_bandit_present() then
		last_close_bandit_time = Utilities.GetTime().mission_time
		was_close = true
		return false -- still merged; don't deactivate
	end

	-- Tally lost. Log the moment we start coasting on memory (once, not every tick).
	if was_close then
		was_close = false
		Log(string.format("Jester | merge memory: tally lost, holding merge up to %.0fs",
			MERGE_MEMORY:ConvertTo(s).value))
	end

	if last_close_bandit_time == nil then
		return true -- never merged
	end
	return (Utilities.GetTime().mission_time - last_close_bandit_time) > MERGE_MEMORY
end

local Dogfight = Class(Situation)

Dogfight:AddActivationConditions(Merged.True:new())

Dogfight:AddDeactivationConditions(StickyMergedFalse:new())
Dogfight:AddDeactivationConditions(Landed())
Dogfight:AddDeactivationConditions(InLandingConfig.True:new())

function Dogfight:AnnounceActivation()
	Log("Jester | DogfightAdvisory ACTIVATED (Merged.True)")

	local threat = GetJester().awareness:GetClosestAirThreat()
	if not threat then
		Log("  ...but GetClosestAirThreat returned nothing (?)")
		return
	end

	-- Exploration dump: what does Jester know about the merge threat?
	Log(string.format("  merge threat: %s o'clock, %.1f nm, elev %+.0f deg, type=%s, id=%s",
		tostring(Utilities.AngleToOClock(Math.Wrap360(threat.polar_body.azimuth))),
		threat.polar_ned.length:ConvertTo(NM).value,
		threat.polar_body.elevation:ConvertTo(deg).value,
		tostring(threat.type), tostring(threat.true_id)))
	Log(string.format("  visual: obscured h/m/l=%s/%s/%s  navlights=%s  AB=%s  angular_size=%s",
		tostring(threat.is_heavily_obscured), tostring(threat.is_moderately_obscured),
		tostring(threat.is_lightly_obscured), tostring(threat.navlights_on),
		tostring(threat.afterburner_on), tostring(threat.angular_size)))

	-- Voice: "check" + clock + type + distance.
	if ANNOUNCE_DOGFIGHT_VOICE then
		local sentence = Sentence(CHECK_PHRASE, ClockPhrase(threat), TypePhrase(threat), DistancePhrase(threat))
		GetJester():AddTask(SayTask:new(sentence))
	end
end

function Dogfight:OnActivation()
	self:AddBehavior(DogfightAdvisory)
	--local report_ias = self:AddBehavior(ReportIAS)
	--report_ias:SetIASProperty(GetProperty('/WSO Mach And Airspeed Indicator/Gauge/Airspeed Needle Friction Component', 'Output'))

	pcall(function() self:AnnounceActivation() end) -- never let the announcement break activation
end

function Dogfight:OnDeactivation()
	self:RemoveBehavior(DogfightAdvisory)
	Log("Jester | DogfightAdvisory DEACTIVATED (Merged.False / landed / landing config)")

	-- Voice: "clean, clean".
	if ANNOUNCE_DOGFIGHT_VOICE then
		pcall(function()
			GetJester():AddTask(SayTask:new(Sentence(CLEAN_PHRASE, CLEAN_PHRASE)))
		end)
	end
end

Dogfight:Seal()

return Dogfight
