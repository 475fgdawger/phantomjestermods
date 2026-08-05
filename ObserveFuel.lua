---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.

local Class = require('base.Class')
local Behavior = require('base.Behavior')
local Urge = require('base.Urge')
local StressReaction = require('base.StressReaction')
local SayTask = require('tasks.common.SayTask')

local default_fuel_quantity = lb(12150)
local default_interval = min(1) -- base poll; sped up to ~5s in afterburner (see AB_GAIN)
local AB_GAIN = 12             -- min(1) base / 12 ≈ 5s poll while in afterburner
local out_of_fuel = lb(10)
local bingo_fuel = lb(3000) -- announce "Bingo" (kept as the nominal value; may become user-configurable)
local joker_fuel = lb(5000) -- announce "Joker" (kept as the nominal value; may become user-configurable)
local NON_AB_LEAD = lb(175)  -- outside afterburner the poll is only ~1/min at ~350 lb/min mil burn, so
                             -- trigger this much early (~half a poll) to center the call on the nominal
                             -- value. No lead in afterburner (the ~5s poll is already tight).
local fuel_gauge = '/Pilot Fuel Quantity Indicator/Fuel Meter'

-- Own-ship afterburner via the 'Afterburner' observation (a boolean; the same signal
-- DogfightAdvisory uses). Resolved defensively in case it is ever a labeled value.
local function in_afterburner()
	local aw = GetJester() and GetJester().awareness
	if not aw then return false end
	local ok, v = pcall(function() return aw:GetObservation('Afterburner') end)
	if not ok then return false end
	local t = type(v)
	if t == 'boolean' then return v end
	if t == 'number' then return v ~= 0 end
	if t == 'table' or t == 'userdata' then
		local ok2, inner = pcall(function() return v.value end)
		return (ok2 and inner) and true or false
	end
	return v and true or false
end

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
		local actual_fuel_quantity = GetTotalFuelQuantity()
		self.fuel_estimate = actual_fuel_quantity -- exact gauge reading (no error applied)

		if (actual_fuel_quantity < out_of_fuel and not self.knows_out_of_fuel) then
			self.knows_out_of_fuel = true
			local task = SayTask:new('misc/outoffuel')
			GetJester():AddTask(task)
			tasks[#tasks + 1] = task
		end

		local awareness = GetJester() and GetJester().awareness or nil
		local ok_cmb, in_combat = pcall(function() return awareness:GetInCombatOrDanger() end)
		in_combat = (ok_cmb and in_combat) and true or false
		local ab = in_afterburner()

		-- Detection thresholds: nominal value plus a lead when not in afterburner (see NON_AB_LEAD).
		local lead = ab and lb(0) or NON_AB_LEAD
		local bingo_threshold = bingo_fuel + lead
		local joker_threshold = joker_fuel + lead

		-- Proximity inhibits (tanker/airfield within 7 nm) are BYPASSED when in combat or
		-- afterburner - in those cases the fuel state is called regardless of position.
		if not (ab or in_combat) then
			local tanker_nm = nil
			local closest_tanker = awareness and awareness:GetClosestFriendlyTanker() or false
			if closest_tanker and closest_tanker.polar_ned and closest_tanker.polar_ned.length then
				local ok, v = pcall(function() return closest_tanker.polar_ned.length:ConvertTo(NM).value end)
				if ok then tanker_nm = v end
			end
			if tanker_nm ~= nil and tanker_nm < 7 then
				return tasks
			end

			-- If the airfield distance can't be determined, do NOT inhibit (an unknown/nil
			-- must not silence fuel calls).
			local airfield_nm = nil
			local ok_af, af = pcall(function() return awareness:GetDistanceToClosestFriendlyAirfield():ConvertTo(NM).value end)
			if ok_af then airfield_nm = af end
			if airfield_nm ~= nil and airfield_nm < 7 then
				return tasks
			end
		end

		if (self.fuel_estimate < bingo_threshold and not self.estimates_below_bingo and not self.knows_out_of_fuel) then
			self.estimates_below_bingo = true
			local task = SayTask:new('misc/bingo')
			GetJester():AddTask(task)
			tasks[#tasks + 1] = task
		elseif (self.fuel_estimate < joker_threshold and not self.estimates_below_joker and not self.estimates_below_bingo and not self.knows_out_of_fuel) then
			self.estimates_below_joker = true
			local task = SayTask:new('misc/joker')
			GetJester():AddTask(task)
			tasks[#tasks + 1] = task
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
		-- Poll rate: 1 min normally, ~5s in afterburner.
		self.check_urge:SetStressReaction(StressReaction.ignorance)
		self.check_urge:SetGainRateMultiplier(in_afterburner() and AB_GAIN or 1)
		self.check_urge:Tick()
	end
end

ObserveFuel:Seal()
return ObserveFuel
