---// DogfightCondition.lua
---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.

--Merged with a bandit?
local Class = require 'base.Class'
local Condition = require 'base.Condition'
--local JesterConstants = require 'base.Constants' --dawger
local Constants = require 'behaviors.Constants'

local Merged = {}

Merged.True = Class(Condition)

function Merged.True:Check()
	local closest_bandit = GetJester().awareness:GetClosestAirThreat() or false
	if closest_bandit then
		if closest_bandit.polar_body.length:ConvertTo(NM) < Constants.dogfight_distance then
			--Log("Merged Condition True")
			return true
		end
	end
	
	return false
end

Merged.False = Class(Condition)

function Merged.False:Check()
	
	local bandits = GetJester().awareness:GetAirThreats() or false
			if not bandits or #bandits < 1 then
				--Log("Merged Condition False by Absense")
				return true
			else 
				local closest_bandit = GetJester().awareness:GetClosestAirThreat() or false
				if closest_bandit.polar_body.length:ConvertTo(NM) > Constants.dogfight_distance then
					--Log("Merged Condition False")
					return true
				end	
		end
	
			
	
		
end

Merged.True:Seal()
Merged.False:Seal()
return Merged
