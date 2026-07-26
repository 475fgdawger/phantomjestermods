
---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.
local Class = require('base.Class')
local Behavior = require('base.Behavior')
local Urge = require('base.Urge')
local StressReaction = require('base.StressReaction')
local SayTask = require('tasks.common.SayTask')
local SayTaskWithDelay = require('tasks.common.SayTaskWithDelay')
local Awareness = require('memory.Awareness')
local Utilities = require 'base.Utilities'
local EjectTask = require('tasks.common.Eject')

local CommentOnLanding = Class(Behavior)

function CommentOnLanding:Constructor()
	Behavior.Constructor(self)

	local was_landed = false
	local has_said_nice_landing = false

	local complain = function(task)
		local on_rwy = GetJester().awareness:GetObservation("on_runway")
		if on_rwy then
			local task = SayTaskWithDelay:new('phrases/hardlanding', s(4))
			--GetJester():AddTask(task)
			--Log("Landing: Complaining about hard landing.")
		end
	end

	local anger = function(task)
		local on_rwy = GetJester().awareness:GetObservation("on_runway")
		if on_rwy then
			local task = SayTaskWithDelay:new('phrases/bouncybouncy', s(1))
			--GetJester():AddTask(task)
			--Log("Landing: Complaining about bouncy landing.")
		end
	end

	--Hard and bouncy landing are just driven from events from Awareness.
	ListenTo("hard_landing", "CommentOnLanding", complain)
	ListenTo("repeated_hard_landing", "CommentOnLanding", anger)

end

function CommentOnLanding:Tick()

	--If we had smooth oleo rates recently; we'll comment on a nice landing.
	local landed_state = GetJester().awareness:GetObservation("landed")

	--check buffered state for touchdown moment - would be nice to have this as an event instead maybe somewhere.
	local touchdown_moment = false
	if not self.was_landed then
		if landed_state then
			touchdown_moment = true
		end
	end

	if not self.has_said_nice_landing and touchdown_moment then

		local curr_time = Utilities.GetTime().mission_time
		local on_rwy = GetJester().awareness:GetObservation("on_runway")

		local harsh_landing_timestamp = GetJester().awareness:GetObservation("last_significant_oleo_rate_time")
		local time_since_significant_oleo = curr_time - harsh_landing_timestamp

		if landed_state and time_since_significant_oleo > s(60) and on_rwy then
			local goodlandingtask = SayTaskWithDelay:new('phrases/goodlanding', s(6))
			--Log("Landing: Complimenting on good landing.")
			GetJester():AddTask(goodlandingtask)
			self.has_said_nice_landing = true
		end
	end

	self.was_landed = GetJester().awareness:GetObservation("landed")

end

CommentOnLanding:Seal()
return CommentOnLanding
