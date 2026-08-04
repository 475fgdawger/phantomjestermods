---// WingmanTracker.lua
-- Designate a wingman (nearest friendly Jester can see) and track his visual status:
--   * lost sight for BLIND_TIMEOUT      -> "Blind, Wingman"
--   * regained sight after being blind  -> "Visual, Wingman, <clock>, <range>"
-- The wheel items (Designate / Find / Undesignate) are managed by UpdateJesterWheel, which
-- reads this behavior's wingman_id to reflect the designation state.

local Class     = require('base.Class')
local Behavior  = require('base.Behavior')
local Utilities = require('base.Utilities')
local Math      = require('base.Math')
require('base.Interactions') -- ListenTo / Dispatch
local Sentence  = require('voice.Sentence')
local SayTask   = require('tasks.common.SayTask')

local WingmanTracker = Class(Behavior)

-- Tunables -------------------------------------------------------------------
local BLIND_TIMEOUT      = s(15)
local HIGH_LOW_THRESHOLD = deg(10)

local VISUAL_PHRASE  = 'dawger/visual'
local WINGMAN_PHRASE = 'dawger/Wingman'
local BLIND_PHRASE   = 'dawger/Blind'

-- Phrase builders ------------------------------------------------------------
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
	-- Plain clock ('spotting/<word>oclock<hilo>') has both low- and high-intensity variants;
	-- the 'bfm<word>oclock' family is high-intensity (combat) only and would go silent for a
	-- peacetime designation call.
	local oclock = Utilities.AngleToOClock(Math.Wrap360(contact.polar_body.azimuth))
	return 'spotting/' .. oclock .. 'oclock' .. ContactHiLo(contact)
end

local function DistancePhrase(contact)
	local distance = Math.Round(contact.polar_ned.length:ConvertTo(NM))
	if distance.value > 0 then
		return string.format('misc/%.0fmiles', distance.value)
	end
	return 'spotting/wvrclose'
end

local function find_wingman(id)
	if id == nil then
		return nil
	end
	for _, contact in ipairs(GetJester().awareness:GetFriendlyAircraft() or {}) do
		if contact.true_id == id then
			return contact
		end
	end
	return nil
end

function WingmanTracker:Constructor()
	Behavior.Constructor(self)
	self.wingman_id        = nil
	self.is_blind          = false
	self.last_visible_time = nil

	ListenTo("wingman_designate", "WingmanDesignate", function()
		self:Designate()
	end)
	ListenTo("wingman_undesignate", "WingmanUndesignate", function()
		self:Undesignate()
	end)
	ListenTo("wingman_find", "WingmanFind", function()
		self:Find()
	end)
end

function WingmanTracker:Designate()
	local wingman = GetJester().awareness:GetClosestFriendlyAircraft()
	if not wingman or wingman.true_id == nil then
		Log("Jester | Wingman designate: no friendly aircraft in sight")
		return
	end
	self.wingman_id        = wingman.true_id
	self.is_blind          = false
	self.last_visible_time = Utilities.GetTime().mission_time
	Log("Jester | Wingman designated: id=" .. tostring(self.wingman_id))
	self:SayDesignated(wingman)
end

function WingmanTracker:SayDesignated(contact)
	GetJester():AddTask(SayTask:new(
		Sentence(WINGMAN_PHRASE, ClockPhrase(contact), DistancePhrase(contact))))
end

function WingmanTracker:Undesignate()
	Log("Jester | Wingman undesignated (was id=" .. tostring(self.wingman_id) .. ")")
	self.wingman_id        = nil
	self.is_blind          = false
	self.last_visible_time = nil
end

-- On-demand "where's my wingman" callout (the "Wingman - Find" wheel item, shown only once a
-- wingman is designated). Visible -> "Wingman, <clock>, <range>"; not visible -> "Blind, Wingman".
function WingmanTracker:Find()
	if self.wingman_id == nil then
		Log("Jester | Wingman find: none designated")
		return
	end
	local wingman = find_wingman(self.wingman_id)
	if wingman then
		self:SayDesignated(wingman)
	else
		self:SayBlind()
	end
end

function WingmanTracker:SayBlind()
	Log("Jester | Wingman: BLIND")
	GetJester():AddTask(SayTask:new(Sentence(BLIND_PHRASE, WINGMAN_PHRASE)))
end

function WingmanTracker:SayVisual(contact)
	Log("Jester | Wingman: VISUAL")
	GetJester():AddTask(SayTask:new(
		Sentence(VISUAL_PHRASE, WINGMAN_PHRASE, ClockPhrase(contact), DistancePhrase(contact))))
end

function WingmanTracker:Tick()
	if self.wingman_id == nil then
		return
	end

	local now     = Utilities.GetTime().mission_time
	local wingman = find_wingman(self.wingman_id)

	-- "Last seen" is when Jester actually SENSED him (his contact's last_seen_time_stamp), not
	-- merely when the contact is present in awareness: a friendly lingers in the contact list
	-- ~7s after last sight, so awareness presence alone would never go blind.
	if wingman and wingman.last_seen_time_stamp then
		self.last_visible_time = wingman.last_seen_time_stamp
	end
	if self.last_visible_time == nil then
		return
	end

	local since_seen = now - self.last_visible_time
	if since_seen >= BLIND_TIMEOUT then
		if not self.is_blind then
			self:SayBlind()
			self.is_blind = true
		end
	elseif self.is_blind and wingman then
		self:SayVisual(wingman)
		self.is_blind = false
	end
end

WingmanTracker:Seal()
return WingmanTracker
