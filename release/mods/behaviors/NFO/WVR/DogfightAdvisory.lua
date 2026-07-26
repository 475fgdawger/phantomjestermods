---// DawgerDogfightAdvisoryV002.lua

local Class        = require('base.Class')
local Behavior     = require('base.Behavior')
local Math         = require('base.Math')
local Utilities    = require('base.Utilities')
local DbaseUtils   = require('behaviors.DbaseUtils')
local Sentence     = require('voice.Sentence')
local SayTask      = require('tasks.common.SayTask')
local SayFuel      = require('tasks.fuel.SayFuelQuantity')
local Constants    = require('behaviors.Constants')

local DogfightAdvisory = Class(Behavior)

-- Tunables -------------------------------------------------------------------
local FUEL_GAUGE            = '/Pilot Fuel Quantity Indicator/Fuel Meter'
local DEFAULT_FUEL_QUANTITY = lb(12150)
local STALE_CONTACT_AGE     = s(3)
local ANALYSIS_INTERVAL     = s(1)
local FUEL_INTERVAL         = s(30)
local REPORT_INTERVAL       = s(4)
local FRIENDLY_WEZ_HALF_ARC = deg(35)
local HIGH_LOW_THRESHOLD    = deg(10)
local FALLBACK_TYPE_PHRASE  = 'contacts_iff/bogey'

local MAX_COUNT_PHRASE = 4
local NUMBER_PHRASES = {
    [2] = 'numbers/two',
    [3] = 'numbers/three',
    [4] = 'numbers/four',
}

function DogfightAdvisory:Constructor()
    Behavior.Constructor(self)
    self.analysis_timer = s(0)
    self.report_timer   = s(0)
    self.fuel_timer     = s(0)
    self.contacts       = {}
end

-- Phrase builders ------------------------------------------------------------

local function TypePhrase(contact)
    local type_string = tostring(contact.type)
    local data = DbaseUtils.GetAircraftPhrase(type_string)
    if data then
        return data.phrase
    end
    Log('No type phrase for: ' .. type_string)
    return FALLBACK_TYPE_PHRASE
end

local function DistancePhrase(contact)
    local distance = Math.Round(contact.polar_ned.length:ConvertTo(NM))
    if distance.value > 0 then
        return string.format('misc/%.0fmiles', distance.value)
    end
    return 'spotting/wvrclose'
end

local function ClockPhrase(contact)
    local hi_or_lo = ''
    local elev_body = contact.polar_body.elevation
    local elev_ned  = contact.polar_ned.elevation

    if elev_body > HIGH_LOW_THRESHOLD and elev_ned > HIGH_LOW_THRESHOLD then
        hi_or_lo = 'high'
    elseif elev_body < -HIGH_LOW_THRESHOLD and elev_ned < -HIGH_LOW_THRESHOLD then
        hi_or_lo = 'low'
    end

    local oclock = Utilities.AngleToOClock(Math.Wrap360(contact.polar_body.azimuth))
    return 'spotting/bfm' .. oclock .. 'oclock' .. hi_or_lo
end

-- Announcement ---------------------------------------------------------------

function DogfightAdvisory:SayStandardAdvisory(contacts)
    local jester = GetJester()
    local now    = Utilities.GetTime().mission_time

    local groups = {}
    local order  = {}

    for _, contact in ipairs(contacts) do
        local clock   = ClockPhrase(contact)
        local type_ph = TypePhrase(contact)
        local key     = clock .. '|' .. type_ph

        if not groups[key] then
            groups[key] = {
                clock    = clock,
                type     = type_ph,
                nearest  = contact,
                contacts = {},
            }
            table.insert(order, key)
        end

        local group = groups[key]
        table.insert(group.contacts, contact)

        if contact.polar_ned.length:ConvertTo(NM) < group.nearest.polar_ned.length:ConvertTo(NM) then
            group.nearest = contact
        end
    end

    for _, key in ipairs(order) do
        local group    = groups[key]
        local count    = math.min(#group.contacts, MAX_COUNT_PHRASE)
        local distance = DistancePhrase(group.nearest)

        local sentence
        if count > 1 then
            sentence = Sentence(group.clock, NUMBER_PHRASES[count], group.type, distance)
        else
            sentence = Sentence(group.clock, group.type, distance)
        end

        jester:AddTask(SayTask:new(sentence))

        for _, contact in ipairs(group.contacts) do
            contact.announced           = true
            contact.announced_timestamp = now
            jester.awareness:AddOrUpdateContact(contact)
        end
    end
end

-- Situation analysis ---------------------------------------------------------

local function IsFresh(contact, now)
    return (now - contact.last_seen_time_stamp) <= STALE_CONTACT_AGE
end

local function IsInDogfightRange(contact)
    return contact.polar_ned.length:ConvertTo(NM) < Constants.dogfight_distance
end

function DogfightAdvisory:AnalyzeSituationAndGetContactsToAnnounce()
    local jester  = GetJester()
    local now     = Utilities.GetTime().mission_time
    local results = {}

    for _, threat in ipairs(jester.awareness:GetAirThreats() or {}) do
        if IsInDogfightRange(threat) and IsFresh(threat, now) then
            table.insert(results, threat)
        end
    end

    for _, friend in ipairs(jester.awareness:GetFriendlyAircraft() or {}) do
        if IsInDogfightRange(friend) and IsFresh(friend, now) then
            local azimuth = Math.Wrap360(friend.polar_body.azimuth)
            if azimuth <= FRIENDLY_WEZ_HALF_ARC or azimuth >= (deg(360) - FRIENDLY_WEZ_HALF_ARC) then
                table.insert(results, friend)
            end
        end
    end

    return results
end

-- Fuel -----------------------------------------------------------------------

function DogfightAdvisory:GetTotalFuelQuantity()
    local prop = GetProperty(FUEL_GAUGE, 'Internal Fuel Quantity')
    return (prop and prop.value) or DEFAULT_FUEL_QUANTITY
end

function DogfightAdvisory:ReportFuelIfBFM()
    if GetJester().awareness:GetObservation('Afterburner') then
        GetJester():AddTask(SayFuel:new(self:GetTotalFuelQuantity()))
    end
end

-- Tick -----------------------------------------------------------------------

function DogfightAdvisory:Tick()
    local dt = Utilities.GetTime().dt

    self.fuel_timer = self.fuel_timer + dt
    if self.fuel_timer >= FUEL_INTERVAL then
        self.fuel_timer = s(0)
        self:ReportFuelIfBFM()
    end

    self.analysis_timer = self.analysis_timer + dt
    if self.analysis_timer >= ANALYSIS_INTERVAL then
        self.analysis_timer = s(0)
        self.contacts = self:AnalyzeSituationAndGetContactsToAnnounce()
    end

    if #self.contacts < 1 then
        self.report_timer = s(0)
        return
    end

    self.report_timer = self.report_timer + dt
    if self.report_timer < REPORT_INTERVAL then
        return
    end
    self.report_timer = s(0)

    self:SayStandardAdvisory(self.contacts)
end

DogfightAdvisory:Seal()
return DogfightAdvisory