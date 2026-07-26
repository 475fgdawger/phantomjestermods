
---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.

local Class = require('base.Class')
local Behavior = require('base.Behavior')
local SayTask = require('tasks.common.SayTask')
local Utilities = require 'base.Utilities'

local TaxiAdvisory = Class(Behavior)

local has_commented_on_ball_busting = true --false
local has_said_out_of_goddamned_mind = true --false
local has_said_slowdown = true --false
local fix_hotspawn_deadzone_timer = s(5)

function TaxiAdvisory:Constructor()
	Behavior.Constructor(self)
end

function TaxiAdvisory:Tick()
	local on_ground = GetJester().awareness:GetObservation("landed")
	if not on_ground then
		return
	end

	--Do nothing for 5 seconds because DCS jumping suspension on spawn and shit..
	if fix_hotspawn_deadzone_timer > s(0) then
		fix_hotspawn_deadzone_timer = fix_hotspawn_deadzone_timer - Utilities.GetTime().dt
	end
	if fix_hotspawn_deadzone_timer > s(0) then
		return
	end

	--Inhibit Taxi Advisory if we just landed to avoid weird comments when we go off the runway.
	local time_since_airborne = s(0)
	time_since_airborne = GetJester().memory:GetTimeSinceAirborne()
	if time_since_airborne < s(60) then
		return
	end

	local airspeed = kt(0)
	local ground_speed = GetJester().awareness:GetObservation("ground_speed")
	if ground_speed ~= nil then
		airspeed = ground_speed
	else
		return
	end

	--Autobots rollout; only happens sometimes, also set a flag to only happen once per session OR just "lets go flyin".

	--If we're hot start in air; just set the flag so it doesn't trigger after exiting rwy or landing first time..
	local on_runway = GetJester().awareness:GetObservation("on_runway")
	if spawn_data.hot_start_in_air or on_runway then
		GetJester().memory:SetHasSaidAutobotsRollout(true)
	end

	--Otherwise, once per session.
	--dawger deletion
	--[[if not GetJester().memory:GetHasSaidAutobotsRollout() then
		if airspeed > kt(5) then
			local dice = Dice.new(10)
			if dice:Roll() > 8 then
			else
				local task = SayTask:new('phrases/TimeToGoFlying')
				GetJester():AddTask(task)
			end
			GetJester().memory:SetHasSaidAutobotsRollout(true)
		end
	end]]

	--Below stuff kind of mirrors the f-14.
	--dawger deletion
	--[[if airspeed > kt(100) then
		if not has_said_out_of_goddamned_mind then
			local task = SayTask:new('phrases/outofgoddamnmind')
			GetJester():AddTask(task)
			has_said_out_of_goddamned_mind = true
			has_commented_on_ball_busting = true
			has_said_slowdown = true
		end
	elseif airspeed > kt(70) then
		if not has_commented_on_ball_busting then
			local task = SayTask:new('phrases/cobustourballs')
			GetJester():AddTask(task)
			has_commented_on_ball_busting = true
			has_said_slowdown = true
		end
	elseif airspeed > kt(60) then
		if not has_said_slowdown then
			local task = SayTask:new('phrases/youretoofast')
			GetJester():AddTask(task)
			has_said_slowdown = true
		end
	end]]
end

TaxiAdvisory:Seal()
return TaxiAdvisory
