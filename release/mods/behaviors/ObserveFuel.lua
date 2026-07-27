---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.

local Class = require('base.Class')
local Behavior = require('base.Behavior')
local Urge = require('base.Urge')
local StressReaction = require('base.StressReaction')
local SayTask = require('tasks.common.SayTask')
local CheckFuelDialog = require('tasks.fuel.CheckFuelDialog')

local default_fuel_quantity = lb(12150)
local default_interval = min(12)
local out_of_fuel = lb(10)
local bingo_fuel = lb(4000) -- TODO Make configurable
local joker_fuel = bingo_fuel + lb(2000) -- TODO Make configurable
local fuel_gauge = '/Pilot Fuel Quantity Indicator/Fuel Meter'
local fuel_error_dice = Dice.new(-2000, 2000)

local ObserveFuel = Class(Behavior)
ObserveFuel.fuel_estimate = default_fuel_quantity
ObserveFuel.estimates_below_joker = false
ObserveFuel.estimates_below_bingo = false
ObserveFuel.knows_out_of_fuel = false

function GetTotalFuelQuantity()
	-- max internal fuel 12,150 lbs
	local prop = GetProperty(fuel_gauge, 'Internal Fuel Quantity')
	local gauge_readout = prop and prop.value or nil
	if gauge_readout then
		return gauge_readout
	else
		return default_fuel_quantity
	end
end

function ObserveFuel:Constructor()
	Behavior.Constructor(self)

	local check_gauge = function()
		local tasks = {}
		-- WSO can not see the fuel gauge, but based on their experience they can roughly estimate it.
		-- We mock that by just using the actual value and adding a random error.
		local actual_fuel_quantity = GetTotalFuelQuantity()
		self.fuel_estimate = actual_fuel_quantity --[[dawger + lb(fuel_error_dice:Roll())]]

		Log("Fuel estimate: " .. tostring(self.fuel_estimate.value))

		-- Bingo/Joker dialogs
		if (actual_fuel_quantity < out_of_fuel and not self.knows_out_of_fuel) then
			self.knows_out_of_fuel = true
			local task = SayTask:new('misc/outoffuel')
			GetJester():AddTask(task)
			tasks[#tasks + 1] = task
		end

		--Inhibit when in combat or near a friendly tanker.
		local awareness = GetJester() and GetJester().awareness or nil
		local closest_tanker = awareness and awareness:GetClosestFriendlyTanker() or false
		local distance_to_closest_friendly_airfield = awareness:GetDistanceToClosestFriendlyAirfield()

		if closest_tanker and closest_tanker.polar_ned and closest_tanker.polar_ned.length then
			local dist_to_tanker = closest_tanker.polar_ned.length:ConvertTo(NM)
			if dist_to_tanker and dist_to_tanker < NM(7) then
				return tasks
			end
		end

		if distance_to_closest_friendly_airfield < NM(7) then
			return tasks
		end

		if not GetJester().awareness:GetInCombatOrDanger() then
			if (self.fuel_estimate < bingo_fuel and not self.estimates_below_bingo and not self.knows_out_of_fuel) then
				self.estimates_below_bingo = true
				local task = CheckFuelDialog:new()
				GetJester():AddTask(task)
				tasks[#tasks + 1] = task
			elseif (self.fuel_estimate < joker_fuel and not self.estimates_below_joker and not self.estimates_below_bingo and not self.knows_out_of_fuel) then
				self.estimates_below_joker = true
				local task = CheckFuelDialog:new()
				GetJester():AddTask(task)
				tasks[#tasks + 1] = task
			end
		end
		return tasks
	end

	self.check_urge = Urge:new({
		time_to_release = default_interval,
		on_release_function = check_gauge,
		stress_reaction = StressReaction.ignorance,
	})
	self.check_urge:Restart()
end

function ObserveFuel:Tick()
	if self.check_urge then
		if self.knows_out_of_fuel then
			-- TODO Ejection tolerance
			self.check_urge:SetStressReaction(StressReaction.obsession)
			self.check_urge:SetGainRateMultiplier(5)
		elseif self.estimates_below_bingo then
			self.check_urge:SetStressReaction(StressReaction.obsession)
			self.check_urge:SetGainRateMultiplier(5)
		elseif self.estimates_below_joker then
			self.check_urge:SetStressReaction(StressReaction.fixation)
			self.check_urge:SetGainRateMultiplier(2)
		else
			self.check_urge:SetStressReaction(StressReaction.ignorance)
			self.check_urge:SetGainRateMultiplier(1)
		end

		self.check_urge:Tick()
	end
end

ObserveFuel:Seal()
return ObserveFuel
