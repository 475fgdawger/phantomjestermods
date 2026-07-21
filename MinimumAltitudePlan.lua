---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.
---
local Class = require('base.Class')
local Task = require('base.Task')
local SayTask = require('tasks.common.SayTask')
local Interactions = require('base.Interactions')

local MinimumAltitudeDialogue = Class(Task)

local say_roger = function()
	local task = SayTask:new('misc/roger')
	GetJester():AddTask(task)
end

local on_set_below_50 = function()
	local task = SayTask:new('phrases/LowAltPuckerFactor')
	GetJester():AddTask(task)
end

local on_set_below_100 = function()
	local task = SayTask:new('misc/roger')
	GetJester():AddTask(task)
end

local on_set_below_150 = function()
	local task = SayTask:new('misc/roger')
	GetJester():AddTask(task)
end

local on_set_below_200 = function()
	local task = SayTask:new('misc/roger')
	GetJester():AddTask(task)
end

function MinimumAltitudeDialogue:Constructor()
	Task.Constructor(self)

	local on_activation = function()
		self:RemoveAllActions()
 -- dawger No Questions
		--[[local question = Dialog.Question:new({
			name = "Jester",
			content = "Are we going low on this mission?",
			phrase = "phrases/GoingToDeck",
			label = "Minimum Altitude",
			timing = Dialog.Timing:new({
				question = s(10),
				action = s(15),
			}),
			options = {
				Dialog.Option:new({
					response = "Negative",
					action = "say_roger",
				}),
				Dialog.Option:new({
					response = "Yup",
					follow_up_question = Dialog.FollowUpQuestion:new({
						name = "Jester",
						content = "How low you thinking?",
						phrase = "phrases/HowLow",
						options = {
							Dialog.Option:new({
								response = "Below 50",
								action = "dlg_below_50",
							}),
							Dialog.Option:new({
								response = "Below 100",
								action = "dlg_below_100",
							}),
							Dialog.Option:new({
								response = "Below 150",
								action = "dlg_below_150",
							}),
							Dialog.Option:new({
								response = "Below 200",
								action = "dlg_below_200"})
								}
							}),
						}),
					},
				})

		Dialog.Push(question)]]

	end

	--[[ListenTo("dlg_below_50", "MinimumAltitudePlan", on_set_below_50)
	ListenTo("dlg_below_100", "MinimumAltitudePlan", on_set_below_100)
	ListenTo("dlg_below_150", "MinimumAltitudePlan", on_set_below_150)
	ListenTo("dlg_below_200", "MinimumAltitudePlan", on_set_below_200)
	ListenTo("say_roger", "MinimumAltitudePlan", say_roger)]]

	local task = SayTask:new('phrases/LowAltPuckerFactor')
	--GetJester():AddTask(task)

	self:AddOnActivationCallback(on_activation)
end

MinimumAltitudeDialogue:Seal()
return MinimumAltitudeDialogue
