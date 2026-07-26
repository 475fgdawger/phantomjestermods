
---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.

--Takeoff advisory - quite limited in the F-4 apparently according to Kirk.

local Class = require('base.Class')
local Behavior = require('base.Behavior')
local SayTask = require('tasks.common.SayTask')
local Utilities = require ('base.Utilities')
local Memory = require('memory.Memory')

local TakeOffAdvisory = Class(Behavior)

local default_interval = s(2)
local speed_margin = kt(5)

function TakeOffAdvisory:Constructor()
	Behavior.Constructor(self)

	self.hundred_kts_was_reported = false
	self.eighty_was_reported = false
	self.off_the_peg_was_reported = false

end

function TakeOffAdvisory:Tick()

	local airspeed = kt(0)
	if GetJester().awareness:GetObservation("indicated_airspeed") ~= nil then
		airspeed = GetJester().awareness:GetObservation("indicated_airspeed")
	else
		return
	end

	--Inhibit takeoff advisory if recently airborne as if we're on the runway it runs.
	local time_since_airborne = s(0)
	time_since_airborne = GetJester().memory:GetTimeSinceAirborne()
	if time_since_airborne < s(100) then
		return
	end

	--Key things from Kirk:
	--Report off the peg when airspeed is moving.
	--Report 80 knots. And report 100 knots. So pilot knows more or less. That's it.
	-- dawger better takeoff speed calls
	--if airspeed < kt(85) + speed_margin and airspeed > kt(85) - speed_margin then
	if airspeed < kt(80)  and airspeed > kt(70) then
		if not self.eighty_was_reported then
			--Log("80 knots!")
			local task = SayTask:new('checklists/eightyknots')
			GetJester():AddTask(task)
			self.eighty_was_reported = true
		end
	end
	--if airspeed < kt(105) + speed_margin and airspeed > kt(105) - speed_margin then
	if airspeed < kt(100) and airspeed > kt(90)  then
		if not self.hundred_kts_was_reported then
			local task = SayTask:new('checklists/100kts')
			GetJester():AddTask(task)
			self.hundred_kts_was_reported = true
		end
	end

	if airspeed < kt(20) then --If we slow down for some reason (aborted takeoff) reset these so jester can call them again.
		self.eighty_was_reported = false
		self.hundred_kts_was_reported = false
	end

	local rpm_gauge_left = GetJester().awareness:GetObservation("rpm_left_engine")
	local rpm_gauge_right = GetJester().awareness:GetObservation("rpm_right_engine")
	if airspeed > kt(45) and rpm_gauge_left > percent(95) and rpm_gauge_right > percent(95) then
		if not self.off_the_peg_was_reported then
			local task = SayTask:new('checklists/engineairspeedoffpeg')
			GetJester():AddTask(task)
			self.off_the_peg_was_reported = true
		end
		self.off_the_peg_was_reported = true
	end

end

TakeOffAdvisory:Seal()
return TakeOffAdvisory
