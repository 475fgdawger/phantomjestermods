---// DbaseUtils.lua
---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.

local Math = require('base.Math')

local DbaseUtils = {}

time_data = {
	dt = s(0),
	mission_time = s(0)
}

spawn_data = {
	hot_start = false,
	cold_start = false,
	hot_start_in_air = false,
	ins_alignment_stored = false,
}

function DbaseUtils.Append(table, object)
	table[#table+1] = object
	return object
end

function DbaseUtils.AppendTable(target_table, source_table)
	for i = 1, #source_table do
		target_table[#target_table + 1] = source_table[i]
	end
end

function DbaseUtils.GetTime()
	return time_data
end

function DbaseUtils.GetSpawnData()
	return spawn_data
end

local function DeepIterator(tbl, k)
	if k == nil or rawget(tbl, k)~=nil then
		local nextk, v = next(tbl, k)
		if nextk then
			return nextk, v
		else
			local meta = getmetatable(tbl)
			if meta~=nil then
				if meta.__index~=nil and type(meta.__index)=='table' and meta.__index~=tbl then
					nextk, v = DeepIterator(meta.__index, nil)
					while rawget(tbl, nextk)~=nil do
						nextk, v = DeepIterator(meta.__index, nextk)
					end
					return nextk, v
				end
			end
		end
	else
		local meta = getmetatable(tbl)
		if meta~=nil then
			if meta.__index~=nil and type(meta.__index)=='table' and meta.__index~=tbl then
				nextk, v = DeepIterator(meta.__index, k)
				while rawget(tbl, nextk)~=nil do
					nextk, v = DeepIterator(meta.__index, nextk)
				end
				return nextk, v
			end
		end
	end
	return nil, nil
end

DbaseUtils.DeepIterator = DeepIterator

local function DeepCopy(orig, copies)
	copies = copies or {}
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		if copies[orig] then
			copy = copies[orig]
		else
			copy = {}
			copies[orig] = copy
			for orig_key, orig_value in next, orig, nil do
				copy[DeepCopy(orig_key, copies)] = DeepCopy(orig_value, copies)
			end
			setmetatable(copy, DeepCopy(getmetatable(orig), copies))
		end
	else -- number, string, boolean, etc
		copy = orig
	end
	return copy
end

DbaseUtils.DeepCopy = DeepCopy

-- https://stackoverflow.com/a/53038524
function ArrayRemove(t, fnKeep)
	local j, n = 1, #t;

	for i=1,n do
		if (fnKeep(t, i, j)) then
			-- Move i's kept value to j's position, if it's not already there.
			if (i ~= j) then
				t[j] = t[i];
				t[i] = nil;
			end
			j = j + 1; -- Increment position of where we'll place the next kept value.
		else
			t[i] = nil;
		end
	end

	return t;
end

DbaseUtils.ArrayRemove = ArrayRemove

--IMPORTANT: Does not match the DCS strings exactly which may contain capital letters.
--Sanitize before reading in you filthy hobbits.
DbaseUtils.aircraft_to_phrase_map = {
	["a-50"] = {thatsaoran = "ThatsA", phrase = "aircraft/afifty"},
	["a-4e-c"] = {thatsaoran = "ThatsA", phrase = "aircraft/hawk"},--dawger placeholder until new soundfile
	["an-26b"] = {thatsaoran = "ThatsA", phrase = "aircraft/antwentysix"},
	["an-30m"] = {thatsaoran = "ThatsA", phrase = "aircraft/anthirty"},
	["su-27"] = {thatsaoran = "ThatsA", phrase = "aircraft/flanker"},
	["su-30"] = {thatsaoran = "ThatsA", phrase = "aircraft/flankerh"},
	["su-33"] = {thatsaoran = "ThatsA", phrase = "aircraft/flankerd"},
	["su-34"] = {thatsaoran = "ThatsA", phrase = "aircraft/fullback"},
	["mig-15bis"] = {thatsaoran = "ThatsA", phrase = "aircraft/fagot"},
	["mig-15bis_mac"] = {thatsaoran = "ThatsA", phrase = "aircraft/fagot"},
	["mig-15bis_fc"] = {thatsaoran = "ThatsA", phrase = "aircraft/fagot"},	
	["mig-21bis"] = {thatsaoran = "ThatsA", phrase = "aircraft/fishbed"},
	["mig-23"] = {thatsaoran = "ThatsA", phrase = "aircraft/flogger"},
	["mig-23mld"] = {thatsaoran = "ThatsA", phrase = "aircraft/flogger"},
	["mig-27k"] = {thatsaoran = "ThatsA", phrase = "aircraft/floggerd"},
	["il-76md"] = {thatsaoran = "ThatsA", phrase = "aircraft/ilseventysix"},
	["il-78m"] = {thatsaoran = "ThatsA", phrase = "aircraft/ilseventyeighttanker"},
	["jf-17"] = {thatsaoran = "ThatsA", phrase = "aircraft/jfseventeen"},
	["mig-19p"] = {thatsaoran = "ThatsA", phrase = "aircraft/farmer"},
	["mig-29"] = {thatsaoran = "ThatsA", phrase = "aircraft/fulcrum"},
	["mig-29g"] = {thatsaoran = "ThatsA", phrase = "aircraft/fulcrum"},
	["mig-29k"] = {thatsaoran = "ThatsA", phrase = "aircraft/fulcrum"},
	["mig-29c"] = {thatsaoran = "ThatsA", phrase = "aircraft/fulcrum"},
	["mig-29a"] = {thatsaoran = "ThatsA", phrase = "aircraft/fulcrum"},
	["mig-29s"] = {thatsaoran = "ThatsA", phrase = "aircraft/fulcrum"},
	["mig-29 fulcrum"] = {thatsaoran = "ThatsA", phrase = "aircraft/fulcrum"},
	["mig-25"] = {thatsaoran = "ThatsA", phrase = "aircraft/foxbat"},
	["mig-25rbt"] = {thatsaoran = "ThatsA", phrase = "aircraft/foxbat"},
	["mig-25pd"] = {thatsaoran = "ThatsA", phrase = "aircraft/foxbat"},
	["mig-25p"] = {thatsaoran = "ThatsA", phrase = "aircraft/foxbat"},
	["mig-31"] = {thatsaoran = "ThatsA", phrase = "aircraft/foxbat"},
	["su-24"] = {thatsaoran = "ThatsA", phrase = "aircraft/fencer"},
	["su-24m"] = {thatsaoran = "ThatsA", phrase = "aircraft/fencer"},
	["su-24mr"] = {thatsaoran = "ThatsA", phrase = "aircraft/fencer"},
	["su-17m4"] = {thatsaoran = "ThatsA", phrase = "aircraft/suseventeen"},
	["su-25"] = {thatsaoran = "ThatsA", phrase = "aircraft/frogfoot"},
	["su-25t"] = {thatsaoran = "ThatsA", phrase = "aircraft/frogfoot"},
	["su-25tm"] = {thatsaoran = "ThatsA", phrase = "aircraft/frogfoot"},
	["tu-160"] = {thatsaoran = "ThatsA", phrase = "aircraft/tuonesixty"},
	["tu-142"] = {thatsaoran = "ThatsA", phrase = "aircraft/tuonefourtytwo"},
	["tu-95"] = {thatsaoran = "ThatsA", phrase = "aircraft/tuninetyfive"},
	["tu-95ms"] = {thatsaoran = "ThatsA", phrase = "aircraft/tuninetyfive"},
	["tu-22m3"] = {thatsaoran = "ThatsA", phrase = "aircraft/tutwentytwo"},
	["l-39c"] = {thatsaoran = "ThatsAn", phrase = "aircraft/albatros"},
	["l-39za"] = {thatsaoran = "ThatsAn", phrase = "aircraft/albatros"},
	["l-39_mac"] = {thatsaoran = "ThatsAn", phrase = "aircraft/albatros"},
	["bae_harrier"] = {thatsaoran = "ThatsA", phrase = "aircraft/harrier"},
	["av-8b n/a"] = {thatsaoran = "ThatsA", phrase = "aircraft/harrier"},
	["a-10a"] = {thatsaoran = "ThatsA", phrase = "aircraft/warthog"},
	["a-10c"] = {thatsaoran = "ThatsA", phrase = "aircraft/warthog"},
	["ajs37"] = {thatsaoran = "ThatsA", phrase = "aircraft/viggen"},--dawger was ajsthirtyseven
	["b-1b"] = {thatsaoran = "ThatsA", phrase = "aircraft/bone"},
	["b-52h"] = {thatsaoran = "ThatsA", phrase = "aircraft/buff"},
	["c-17a"] = {thatsaoran = "ThatsA", phrase = "aircraft/cseventeen"},
	["c-130"] = {thatsaoran = "ThatsA", phrase = "aircraft/conethirty"},
	["c-101"] = {thatsaoran = "ThatsA", phrase = "aircraft/coneoone"},
	["c-101eb"] = {thatsaoran = "ThatsA", phrase = "aircraft/coneoone"},
	["c-101cc"] = {thatsaoran = "ThatsA", phrase = "aircraft/coneoone"},
	["e-2c"] = {thatsaoran = "ThatsA", phrase = "aircraft/etwo"},
	["e-3a"] = {thatsaoran = "ThatsA", phrase = "aircraft/sentry"},
	["f-4e"] = {thatsaoran = "ThatsA", phrase = "aircraft/phantom"},
	["f-4e-45mc"] = {thatsaoran = "ThatsA", phrase = "aircraft/phantom"},--dawger
	["f-5e"] = {thatsaoran = "ThatsA", phrase = "aircraft/tiger"},
	["f-5e_fc"] = {thatsaoran = "ThatsA", phrase = "aircraft/tiger"},--dawger
	["f-5e-3"] = {thatsaoran = "ThatsA", phrase = "aircraft/tiger"},
	["f-5e-3_fc"] = {thatsaoran = "ThatsA", phrase = "aircraft/tiger"},--dawger
	["f-14a"] = {thatsaoran = "ThatsA", phrase = "aircraft/tomcat"},
	["f-14a-135-gr"] = {thatsaoran = "ThatsA", phrase = "aircraft/tomcat"},--dawger
	["f-14a-135-gr-early"] = {thatsaoran = "ThatsA", phrase = "aircraft/tomcat"},--dawger
	["f-14b"] = {thatsaoran = "ThatsA", phrase = "aircraft/tomcat"},
	["f-14bu"] = {thatsaoran = "ThatsA", phrase = "aircraft/tomcat"},
	["f-15c"] = {thatsaoran = "ThatsAn", phrase = "aircraft/eagle"},
	["f-15e"] = {thatsaoran = "ThatsAn", phrase = "aircraft/eagle"},
	["f-16a"] = {thatsaoran = "ThatsA", phrase = "aircraft/viper"},
	["f-16a mlu"] = {thatsaoran = "ThatsA", phrase = "aircraft/viper"},
	["f-16c bl.50"] = {thatsaoran = "ThatsA", phrase = "aircraft/viper"},
	["f-16c bl.52d"] = {thatsaoran = "ThatsA", phrase = "aircraft/viper"},
	["f/a-18a"] = {thatsaoran = "ThatsA", phrase = "aircraft/hornet"},
	["f/a-18c"] = {thatsaoran = "ThatsA", phrase = "aircraft/hornet"},
	["fa-18c_hornet"] = {thatsaoran = "ThatsA", phrase = "aircraft/hornet"},
	["f/a-18clot20"] = {thatsaoran = "ThatsA", phrase = "aircraft/hornet"},
	["f-86"] = {thatsaoran = "ThatsA", phrase = "aircraft/sabre"},
	["f-86f"] = {thatsaoran = "ThatsA", phrase = "aircraft/sabre"},
	["f-86f sabre"] = {thatsaoran = "ThatsA", phrase = "aircraft/sabre"},--dawger
	["f-86f_mac"] = {thatsaoran = "ThatsA", phrase = "aircraft/sabre"},
	["f-100d"] = {thatsaoran = "ThatsA", phrase = "aircraft/sabre"},
	["f-117a"] = {thatsaoran = "ThatsA", phrase = "aircraft/foneseventeen"},
	["kc-10a"] = {thatsaoran = "ThatsA", phrase = "aircraft/kcten"},
	["kc-135"] = {thatsaoran = "ThatsA", phrase = "aircraft/kconethirtyfive"},
	["mirage-f1be"] = {thatsaoran = "ThatsA", phrase = "aircraft/mirage"},
	["mirage-f1ce"] = {thatsaoran = "ThatsA", phrase = "aircraft/mirage"},
	["mirage-f1ee"] = {thatsaoran = "ThatsA", phrase = "aircraft/mirage"},
	["mirage_2000-5"] = {thatsaoran = "ThatsA", phrase = "aircraft/miragetwothousand"},
	["m-2000c"] = {thatsaoran = "ThatsA", phrase = "aircraft/miragetwothousand"},
	["s-3b"] = {thatsaoran = "ThatsA", phrase = "aircraft/sthree"},
	["s-3b tanker"] = {thatsaoran = "ThatsA", phrase = "aircraft/sthree"},
	["hawk"] = {thatsaoran = "ThatsA", phrase = "aircraft/hawk"},
	["spitfirelfmkix"] = {thatsaoran = "ThatsA", phrase = "aircraft/spitfire"},
	["bf-109k-4"] = {thatsaoran = "ThatsA", phrase = "aircraft/meoneonine"},
	["fw-190d9"] = {thatsaoran = "ThatsA", phrase = "aircraft/oneninety"},
	["p-51d"] = {thatsaoran = "ThatsA", phrase = "aircraft/pfiftyone"},
	["p-51b"] = {thatsaoran = "ThatsA", phrase = "aircraft/pfiftyone"},
	["tf-51d"] = {thatsaoran = "ThatsA", phrase = "aircraft/pfiftyone"},
}

function DbaseUtils.GetAircraftPhrase(aircraft)
	local ac_string = string.lower(aircraft)
	local phrase = DbaseUtils.aircraft_to_phrase_map[ac_string]
	if phrase then
		return phrase
	end
end

-- Helicopter DCS unit-type strings (lowercased). The senses do NOT tag contacts with a
-- 'helicopter'/'airplane' label (confirmed empirically: a Mi-24P reports only
-- aircraft/hostile/airborne), so rotorcraft can only be recognized by their type string.
-- The exact type string is what appears in a contact's `.type`; add any that slip through.
DbaseUtils.helicopter_types = {
	["mi-24p"] = true, ["mi-24v"] = true,
	["mi-8mt"] = true, ["mi-8mtv2"] = true,
	["mi-26"] = true, ["mi-28n"] = true,
	["ka-50"] = true, ["ka-50_3"] = true, ["ka-27"] = true,
	["ah-64a"] = true, ["ah-64d"] = true, ["ah-64d_blk_ii"] = true, ["ah-1w"] = true,
	["uh-1h"] = true, ["uh-60a"] = true, ["oh-58d"] = true, ["sh-60b"] = true,
	["ch-47d"] = true, ["ch-47fbl1"] = true, ["ch-53e"] = true,
	["sa342m"] = true, ["sa342l"] = true, ["sa342mistral"] = true, ["sa342minigun"] = true,
}

function DbaseUtils.IsHelicopterType(type_string)
	if type(type_string) ~= "string" then
		return false
	end
	return DbaseUtils.helicopter_types[string.lower(type_string)] == true
end

local digit_to_word_map = {
	['0'] = 'zero',
	['1'] = 'one',
	['2'] = 'two',
	['3'] = 'three',
	['4'] = 'four',
	['5'] = 'five',
	['6'] = 'six',
	['7'] = 'seven',
	['8'] = 'eight',
	['9'] = 'nine'
}

local second_ten_plus_digit_to_word_map = {
	['0'] = 'ten',
	['1'] = 'eleven',
	['2'] = 'twelve',
	['3'] = 'thirteen',
	['4'] = 'fourteen',
	['5'] = 'fifteen',
	['6'] = 'sixteen',
	['7'] = 'seventeen',
	['8'] = 'eighteen',
	['9'] = 'nineteen'
}

local second_digit_to_word_map = {
	['2'] = 'twenty',
	['3'] = 'thirty',
	['4'] = 'forty',
	['5'] = 'fifty',
	['6'] = 'sixty',
	['7'] = 'seventy',
	['8'] = 'eighty',
	['9'] = 'ninety'
}

local magnitude_word = {
	[0] = '',
	[1] = 'thousand',
	[2] = 'million',
	[3] = 'billion',
	[4] = 'trillion'
}

local o_clock_to_word_map = DeepCopy(digit_to_word_map)
o_clock_to_word_map['0'] = 'twelve'
o_clock_to_word_map['10'] = 'ten'
o_clock_to_word_map['11'] = 'eleven'
o_clock_to_word_map['12'] = 'twelve'

function DbaseUtils.AngleToOClock(angle_real)
	local angle_deg = angle_real:ConvertTo(deg)
	local hour = angle_deg.value / 30.0
	local hour_string = string.format('%.0f', hour)
	local o_clock_word = o_clock_to_word_map[hour_string] or 'twelve'
	return o_clock_word
end

--O'Clock call from polar body and polar ned.
function DbaseUtils.GetOClockPhrase(polar_body, polar_ned)
	local azimuth = polar_body.azimuth
	local azimuth360 = Math.Wrap360(azimuth)
	local o_clock = DbaseUtils.AngleToOClock(azimuth360)
	local phrase = 'spotting/' .. o_clock .. 'oclock'
	if polar_body.elevation > deg(25) and polar_ned.elevation > deg(25) then
		phrase = phrase .. 'high'
	elseif polar_body.elevation < deg(-25) and polar_ned.elevation < deg(-25) then
		phrase = phrase .. 'low'
	end
	return phrase
end

--Polar ned distance to miles phrase.
function DbaseUtils.GetDistancePhrase(polar_ned)
	local distance = Math.Floor(polar_ned.length:ConvertTo(NM))
	local distance_string = string.format('%.0f', distance.value)
	local phrase = 'misc/' .. distance_string .. 'miles'
	return phrase
end

--Safer empty table check.
function DbaseUtils.TableIsNotEmpty(tbl)
	for _ in pairs(tbl) do
		return true
	end
	return false
end

-- Check if all passed params are a string.
function DbaseUtils.AreAllStrings(...)
	for _, v in ipairs({...}) do
		if type(v) ~= "string" then
			Log("This was not a string:" .. tostring(v))
			return false
		end
	end
	return true
end

function DbaseUtils.HasElements(table)
	for _ in pairs(table) do
		return true
	end
	return false
end

function DbaseUtils.NumberToText(number, misspellForty)
	local digits = string.format('%.0f', number)
	local text = ''
	local triplets = math.ceil(#digits / 3)
	if digits == '0' then
		return 'zero'
	end
	local offset = (#digits % 3) - 3
	if offset == -3 then
		offset = 0
	end
	for trip = 1, triplets do
		local inv_trip = triplets - trip
		local trip_index = trip - 1
		local hundreds_index = trip_index * 3 + 1 + offset
		local tens_index = trip_index * 3 + 2 + offset
		local units_index = trip_index * 3 + 3 + offset
		local hundreds_set = inv_trip * 3 + 2 < #digits
		local tens_set = inv_trip * 3 + 1 < #digits
		local any_digit_used = false
		if hundreds_set then
			local digit = digits:sub(hundreds_index, hundreds_index)
			if digit ~= '0' then
				any_digit_used = true
				text = text .. digit_to_word_map[digit] .. 'hundred'
			end
		end
		local ten_plus = false
		if tens_set then
			local digit = digits:sub(tens_index, tens_index)
			if digit == '1' then
				any_digit_used = true
				ten_plus = true
			elseif digit ~= '0' then
				any_digit_used = true
				if misspellForty and digit == '4' then
					text = text .. 'fourty' -- some old recordings have this misspelled
				else
					text = text .. second_digit_to_word_map[digit]
				end
			end
		end
		local digit = digits:sub(units_index, units_index)
		if ten_plus then
			text = text .. second_ten_plus_digit_to_word_map[digit]
		elseif digit ~= '0' then
			any_digit_used = true
			text = text .. digit_to_word_map[digit]
		end
		if inv_trip > 0 then
			text = text .. magnitude_word[inv_trip]
		end
	end
	return text
end

return DbaseUtils
