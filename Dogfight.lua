
local Class = require 'base.Class'
local ReportIAS = require 'behaviors.NFO.common.ReportIAS'
local Situation = require 'base.Situation'
local Merged = require 'conditions.Merged'
local Landed = require 'conditions.Landed'
local InLandingConfig = require 'conditions.InLandingConfig'
local DogfightAdvisory = require 'behaviors.NFO.WVR.DogfightAdvisory'
local Utilities = require 'base.Utilities'
local Math = require 'base.Math'
local Task = require 'base.Task'

-- Announce when the Dogfight situation activates (i.e. DogfightAdvisory comes on).
-- For now a log entry in the in-sim Jester Console; the voice callout is staged behind
-- ANNOUNCE_DOGFIGHT_VOICE for later (create Sounds/Jester/<DOGFIGHT_VOICE_PHRASE>*.ogg,
-- then flip the flag). The activation dump also shows what Jester actually KNOWS about the
-- air threat that tripped Merged.True (closest air threat within dogfight_distance): the
-- Eyeballs visual-sense flags are only populated when he has really SEEN it - if they're
-- all nil/false he only has omniscient (SixthSense) position, no visual.
local ANNOUNCE_DOGFIGHT_VOICE = false
local DOGFIGHT_VOICE_PHRASE   = 'phrases/dogfight' -- placeholder; needs a shipped clip

local Dogfight = Class(Situation)

Dogfight:AddActivationConditions(Merged.True:new())

Dogfight:AddDeactivationConditions(Merged.False:new())
Dogfight:AddDeactivationConditions(Landed())
Dogfight:AddDeactivationConditions(InLandingConfig.True:new())

-- Logs the activation and everything Jester knows about the merge threat. Guarded so a
-- missing field can never break the situation's activation.
function Dogfight:AnnounceActivation()
	Log("Jester | DogfightAdvisory ACTIVATED (Merged.True)")

	local threat = GetJester().awareness:GetClosestAirThreat()
	if not threat then
		Log("  ...but GetClosestAirThreat returned nothing (?)")
		return
	end

	local clock    = Utilities.AngleToOClock(Math.Wrap360(threat.polar_body.azimuth))
	local range_nm = threat.polar_ned.length:ConvertTo(NM).value
	local elev_deg = threat.polar_body.elevation:ConvertTo(deg).value
	Log(string.format("  merge threat: %s o'clock, %.1f nm, elev %+.0f deg, type=%s, id=%s",
		tostring(clock), range_nm, elev_deg, tostring(threat.type), tostring(threat.true_id)))

	-- Visual acquisition tell: these come from the Eyeballs sense (set only when SEEN).
	Log(string.format("  visual: obscured h/m/l=%s/%s/%s  navlights=%s  AB=%s  angular_size=%s",
		tostring(threat.is_heavily_obscured), tostring(threat.is_moderately_obscured),
		tostring(threat.is_lightly_obscured), tostring(threat.navlights_on),
		tostring(threat.afterburner_on), tostring(threat.angular_size)))

	if ANNOUNCE_DOGFIGHT_VOICE then
		GetJester():AddTask(Task:new():Say(DOGFIGHT_VOICE_PHRASE))
	end
end

function Dogfight:OnActivation()
	self:AddBehavior(DogfightAdvisory)
	--local report_ias = self:AddBehavior(ReportIAS)
	--report_ias:SetIASProperty(GetProperty('/WSO Mach And Airspeed Indicator/Gauge/Airspeed Needle Friction Component', 'Output'))

	pcall(function() self:AnnounceActivation() end) -- never let the dump break activation
end

function Dogfight:OnDeactivation()
	self:RemoveBehavior(DogfightAdvisory)
	Log("Jester | DogfightAdvisory DEACTIVATED (Merged.False / landed / landing config)")
end

Dogfight:Seal()

return Dogfight
