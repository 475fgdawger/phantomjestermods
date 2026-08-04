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
local Labels       = require('base.Labels') -- contact classification (hostile gate for helicopters)

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
local HELICOPTER_PHRASE     = 'dawger/Helo' -- enemy rotorcraft (no dedicated aircraft phrase exists)
-- A group's call is only repeated once its range OR bearing has moved at least this
-- much since it was last announced (also re-called on a high/low or count change).
-- Raise these to make Jester quieter for a steady contact.
local MIN_DISTANCE_CHANGE   = NM(1)
local MIN_DIRECTION_CHANGE  = deg(30)

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
    self.last_call      = {} -- keyed by contact.true_id -> last announced { distance, azimuth, hilo, count }
end

-- Phrase builders ------------------------------------------------------------

local function TypePhrase(contact)
    -- Enemy helicopters have no dedicated aircraft phrase, so Jester would fall back to
    -- 'bogey'. Call an enemy rotorcraft 'helicopter' (dawger clip) instead. Only for
    -- hostiles: friendly rotorcraft keep the normal handling.
    -- The senses don't tag rotorcraft with a 'helicopter' label, so match the type string;
    -- gate on the (reliably set) 'hostile' label so only enemy helicopters are called out.
    if DbaseUtils.IsHelicopterType(contact.type) and contact.CanBe and contact:CanBe(Labels.hostile) then
        return HELICOPTER_PHRASE
    end
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

local function ContactDistanceNM(contact)
    return contact.polar_ned.length:ConvertTo(NM).value
end

local function ContactAzimuthDeg(contact)
    return Math.Wrap360(contact.polar_body.azimuth):ConvertTo(deg).value
end

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

-- Shortest angular difference between two bearings in degrees (0..180).
local function AngleDiffDeg(a, b)
    local d = math.abs(a - b) % 360
    if d > 180 then
        d = 360 - d
    end
    return d
end

local function ClockPhrase(contact)
    local oclock = Utilities.AngleToOClock(Math.Wrap360(contact.polar_body.azimuth))
    return 'spotting/bfm' .. oclock .. 'oclock' .. ContactHiLo(contact)
end

-- Announcement ---------------------------------------------------------------

-- Returns true if a group's call should be (re)spoken: it is new, or its range,
-- bearing, high/low, or count has changed by at least the configured thresholds
-- since it was last announced. Otherwise the repeat is skipped to avoid continuous
-- chatter on a steady contact.
function DogfightAdvisory:GroupChangedEnough(group)
    local ref  = group.nearest
    local prev = ref.true_id and self.last_call[ref.true_id]
    if not prev then
        return true -- new contact (or no id to track): always call
    end

    local dist_changed  = math.abs(ContactDistanceNM(ref) - prev.distance) >= MIN_DISTANCE_CHANGE:ConvertTo(NM).value
    local dir_changed   = AngleDiffDeg(ContactAzimuthDeg(ref), prev.azimuth) >= MIN_DIRECTION_CHANGE:ConvertTo(deg).value
    local hilo_changed  = ContactHiLo(ref) ~= prev.hilo
    local count_changed = math.min(#group.contacts, MAX_COUNT_PHRASE) ~= prev.count

    return dist_changed or dir_changed or hilo_changed or count_changed
end

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

    -- Forget last-call records for contacts no longer present, so a contact that
    -- drops out and returns is called fresh (and the cache stays bounded).
    local current_ids = {}
    for _, contact in ipairs(contacts) do
        if contact.true_id then
            current_ids[contact.true_id] = true
        end
    end
    local kept = {}
    for id, record in pairs(self.last_call) do
        if current_ids[id] then
            kept[id] = record
        end
    end
    self.last_call = kept

    for _, key in ipairs(order) do
        local group = groups[key]

        -- Skip repeating a call that has not changed enough since last time.
        if self:GroupChangedEnough(group) then
            local count    = math.min(#group.contacts, MAX_COUNT_PHRASE)
            local distance = DistancePhrase(group.nearest)

            local sentence
            if count > 1 then
                sentence = Sentence(group.clock, NUMBER_PHRASES[count], group.type, distance)
            else
                sentence = Sentence(group.clock, group.type, distance)
            end

            jester:AddTask(SayTask:new(sentence))

            local record = {
                distance = ContactDistanceNM(group.nearest),
                azimuth  = ContactAzimuthDeg(group.nearest),
                hilo     = ContactHiLo(group.nearest),
                count    = count,
            }
            for _, contact in ipairs(group.contacts) do
                contact.announced           = true
                contact.announced_timestamp = now
                jester.awareness:AddOrUpdateContact(contact)
                if contact.true_id then
                    self.last_call[contact.true_id] = record
                end
            end
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