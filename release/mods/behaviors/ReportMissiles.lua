
---// ReportMissiles.lua
---// Copyright (c) 2024 Heatblur Simulations. All rights reserved.

-- Report relevant (possibly targeted at us) missiles detected using eyeballs

local Class = require('base.Class')
local Behavior = require('base.Behavior')
local Math = require('base.Math')
local Urge = require('base.Urge')
local Utilities = require('base.Utilities')
local StressReaction = require('base.StressReaction')
local Task = require('base.Task')
local SayTask = require('tasks.common.SayTask')
local SayTaskWithDelay = require ('tasks.common.SayTaskWithDelay')
local Labels = require 'base.Labels'
local Sentence = require 'voice.Sentence'
local Constants = require 'base.Constants'
local SaySentenceWithDelay = require 'tasks.common.SaySentenceWithDelay'
local SixthSense = require 'senses.SixthSense'
local CountermeasuresInteractions = require('tasks.common.CountermeasuresInteractions')

local ReportMissiles = Class(Behavior)

ReportMissiles.known_missiles = { }

-- Jester sorts pending tasks by priority (Jester.lua). A visually-spotted
-- incoming missile is the most urgent call-out there is, so it uses the top
-- tier (eject / countermeasures), well above the default 0 it used before.
ReportMissiles.priority_missile_warning = 3

function ReportMissiles:Constructor()
	Behavior.Constructor(self)
end

function ReportMissiles:GetAzimuth(missile)
    local azimuth = missile.polar_body.azimuth:ConvertTo(deg)

    if azimuth.value < 0 then
        azimuth = azimuth + deg(360)
    end

   --Log('ReportMissiles | Azimuth: ' .. tostring(azimuth))
    return azimuth
end

function ReportMissiles:AzimuthToHour(azimuth)
    local hour = math.floor(azimuth:ConvertTo(deg).value / 30.5)
    if hour == 0 then
        hour = 12
    end

    -- 15<->45 deg = 1 o'clock
	-- 45<->75 deg = 2 o'clock
	-- 75<->105 deg = 3 o'clock
	-- etc.

	return hour
end

function ReportMissiles:HourToString(hour)
    local hours = {
		[1] = 'one',
		[2] = 'two',
		[3] = 'three',
		[4] = 'four',
		[5] = 'five',
		[6] = 'six',
		[7] = 'seven',
		[8] = 'eight',
		[9] = 'nine',
		[10] = 'ten',
		[11] = 'eleven',
		[12] = 'twelve'
	}
	return hours[tonumber(hour)] or 'ERROR: INVALID HOUR'
end

function ReportMissiles:IsMissileKnown(missile)
    for _, known_missile in ipairs(self.known_missiles) do
        if known_missile == missile.true_id then
            return true
        end
    end

    return false
end

function ReportMissiles:IsMissileAThreat(missile)
    local distance = missile.polar_ned.length

    if missile:Is(Labels.friendly) and distance < NM(1) then
       --Log('ReportMissiles | Close Friendly Missile')
        return false -- close friendly missiles are not considered a threat
    end

    local aircraft_velocity_ned = GetJester().awareness:GetObservation("velocity_ned") or Vector(coords.NED, 0, 0, 0, mps)
    local aircraft_velocity_body = TransformToBody(aircraft_velocity_ned)
	local relative_velocity_body = missile.velocity_body - aircraft_velocity_body

    local threat_x = missile.position_body.x.value * relative_velocity_body.x.value < 0
    if missile.position_body.x.value > 0 and relative_velocity_body.x.value > 0 then
        threat_x = missile.position_body.x < NM(1)
    end

    local threat_y = missile.position_body.y.value * relative_velocity_body.y.value < 0

   --Log('ReportMissiles | Position: ' .. tostring(missile.position_body))
   --Log('ReportMissiles | Velocity: ' .. tostring(missile.velocity_body))
   --Log('ReportMissiles | Distance: ' .. tostring(missile.polar_ned.length))
   --Log('ReportMissiles | Threat in X: ' .. tostring(threat_x))
   --Log('ReportMissiles | Threat in Y: ' .. tostring(threat_y))

    return threat_x and threat_y
end

-- to check if missile is after launch process (proper horizontal speed, not only vertical)
-- for example when SA-15 launches a missile it goes vertical first
-- we want to wait a bit to check if it's a threat later
function ReportMissiles:IsMissileHorizontal(missile)
    local v_x = missile.velocity_ned.x:ConvertTo(mps).value
    local v_y = missile.velocity_ned.y:ConvertTo(mps).value
    local v_margin = mps(20)
    return math.abs(v_x) > v_margin.value or math.abs(v_y) > v_margin.value
end

-- Appends the call-out to the caller's task rather than creating and queuing its
-- own. Multiple missile warnings in one Tick then share a single task and play
-- in order, instead of being shuffled by Jester's (non-stable) priority sort.
-- NOTE: previously this called the global hour_to_string, which only existed
-- because ObserveRWR leaked it; use this behavior's own HourToString method.
function ReportMissiles:SayMissile(task, hour)
--     task:Say('spotting/missile')
--     task:Say('spotting/missileHI')
--     task:Say('spotting/missilelaunch')
--     task:Say('spotting/samlaunch')
--     task:Say('spotting/samsamsam')
    task:Say('spotting/missile', 'spotting/' .. self:HourToString(hour) .. 'oclock')
end

function ReportMissiles:Tick()
    local contacts = GetJester().awareness:GetContacts()

    -- One task per Tick keeps a salvo's warnings in order.
    local task = Task:new()
    local reported_hours = {}
    local has_content = false

    for _, contact in ipairs(contacts) do
        if contact:Is(Labels.missile) then
            local missile = contact
            if (self:IsMissileHorizontal(missile) and not self:IsMissileKnown(missile)) then
                table.insert(self.known_missiles, missile.true_id)
               --Log('ReportMissiles | New missile detected, ID:' .. missile.true_id)

                if (self:IsMissileAThreat(missile)) then
                    local hour = self:AzimuthToHour(self:GetAzimuth(missile))

                    -- Don't say "missile three ... missile three" for two threats
                    -- at the same clock in the same Tick. Scoped to this Tick only:
                    -- missiles are never forgotten, so a session-wide clock filter
                    -- would wrongly silence a later real missile at the same hour.
                    if not reported_hours[hour] then
                        reported_hours[hour] = true
                        self:SayMissile(task, hour)
                        has_content = true
                    end
                end
            end
        end
    end

    if has_content then
        task:SetPriority(self.priority_missile_warning)
        GetJester():AddTask(task)
        CountermeasuresInteractions.StartDispensingIfAllowed()
    end
end

ReportMissiles:Seal()
return ReportMissiles
