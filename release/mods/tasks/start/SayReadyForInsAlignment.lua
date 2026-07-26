---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.

local Class = require('base.class')
local Task = require('base.Task')
local SayTask = require('tasks.common.SayTask')

local SayReadyForInsAlignment = Class(Task)

local action_yes = function(task)
	GetJester():AddTask(Task:new():Roger())
	GetJester().memory:SetReadyForInsAlignment(true)
end

local action_yes_silent = function(task)
	GetJester().memory:SetReadyForInsAlignment(true)
end

local action_no = function(task)
	GetJester():AddTask(Task:new():Roger())
	GetJester().memory:SetReadyForInsAlignment(false)
end

local action_let_you_know = function(task)
	GetJester():AddTask(SayTask:new('phrases/alrightletmeknow'))
	GetJester().memory:SetUserInitiatesAlignment(true)
	GetJester().memory:SetStartAlignmentOption(true)
end

local action_expired = function(task)
	GetJester():AddTask(SayTask:new('phrases/alrightletmeknow'))

end

function SayReadyForInsAlignment:Constructor()
	Task.Constructor(self)

	local on_activation = function()
		self:RemoveAllActions()

		local question = Dialog.Question:new({
			name = "Jester",
			content = "Are you ready for alignment?",
			phrase = "phrases/areyoureadytoalign",
			label = "Ready for alignment?",
			timing = Dialog.Timing:new({
				question = s(15),
				action = s(20),
			}),
			expire_action = "expired",
			options = {
				Dialog.Option:new({
					response = "Yep!",
					action = "yes",
				}),
				Dialog.Option:new({
					response = "Negative, will let you know.",
					action = "no",
				}),
				Dialog.Option:new({
					response = "I'll let you know!",
					action = "let_you_know",
				}),
			},
		})

		--dawger test no alignment question Dialog.Push(question)

		ListenTo("yes", "SayReadyForInsAlignment", action_yes)
		ListenTo("yes_silent", "SayReadyForInsAlignment", action_yes_silent)
		ListenTo("no", "SayReadyForInsAlignment", action_no)
		ListenTo("let_you_know", "SayReadyForInsAlignment", action_let_you_know)
		ListenTo("expired", "SayReadyForInsAlignment", action_expired)



	end

	self:AddOnActivationCallback(on_activation)

end

SayReadyForInsAlignment:Seal()
return SayReadyForInsAlignment
