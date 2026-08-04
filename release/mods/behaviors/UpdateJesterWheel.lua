---// Copyright (c) 2023 Heatblur Simulations. All rights reserved.

local Class = require('base.Class')
local Behavior = require('base.Behavior')
local Urge = require('base.Urge')
local StressReaction = require('base.StressReaction')
local Math = require('base.Math')
local Utilities = require('base.Utilities')
local RadarState = require('radar.State')
local WingmanTracker = require('behaviors.WingmanTracker') -- to read the designation state for the wheel

local UpdateJesterWheel = Class(Behavior)
UpdateJesterWheel.a2g_pave_spike_added = false
UpdateJesterWheel.was_initialized = false
UpdateJesterWheel.start_alignment_added = false
UpdateJesterWheel.current_wpt_hold_renamed_to_deactivate = false
UpdateJesterWheel.ins_quick_realignment_option_provided = false
UpdateJesterWheel.auto_gain_added = false

local FrequencyToDisplayText = function(frequency)
	if (frequency == nil) then
		return ""
	end

	local frequency_valid = Math.RoundTo(frequency:ConvertTo(kHz), kHz(25))
	return string.format('%.3f', frequency_valid:ConvertTo(mHz).value)
end

local CoordinateToDisplayText = function(coord, degree_digits)
	if (coord == nil) then
		return ""
	end
	local coord_abs = Math.Abs(coord)
	local degrees = Math.Floor(coord_abs)
	local minutes = Math.Round((coord_abs - degrees) * 60)

	return string.format('%0' .. degree_digits .. 'd°%02d\'', degrees, minutes)
end

function UpdateJesterWheel:LatitudeToDisplayText(latitude)
	local hemisphere = latitude >= 0 and "N" or "S"
	local absLatitude = Math.Abs(latitude)
	return CoordinateToDisplayText(absLatitude, 2) .. hemisphere
end

function UpdateJesterWheel:LongitudeToDisplayText(longitude)
	local hemisphere = longitude >= 0 and "E" or "W"
	local absLongitude = Math.Abs(longitude)
	return CoordinateToDisplayText(absLongitude, 3) .. hemisphere
end

function UpdateJesterWheel:GetWaypointTextToDisplay(flightplan_no, waypoint_no, waypoint)
	local memory = GetJester().memory
	local isActiveWaypoint = (flightplan_no == memory:GetActiveFlightPlanNumber()) and (waypoint_no == memory:GetActiveWaypointNumber())
	local waypoint_active_suffix = isActiveWaypoint and " *" or ""
	local isHoldWaypoint = waypoint:GetHoldAt( )
	local holdSuffix = isHoldWaypoint and " (h)" or ""

	local max_name_length = 20
	local wpt_name = waypoint:GetWaypointName( )
	if not wpt_name or wpt_name == "" then
		wpt_name = self:LatitudeToDisplayText(waypoint.latitude) .. ", " .. self:LongitudeToDisplayText(waypoint.longitude)
	else
		-- Limit the waypoint name to max_length characters
		wpt_name = string.sub(wpt_name, 1, max_name_length)
	end

	local type_suffix_map = {
		DEFAULT = "",
		TARGET = "TGT",
		FENCE_IN = "F-I",
		FENCE_OUT = "F-O",
		HOMEBASE = "HB",
		ALTERNATE = "ALT",
		CAP = "CAP",
		IP = "IP",
		VIP = "VIP"
	}
	local waypoint_type = waypoint:GetSpecialWaypointType()
	local type_suffix = type_suffix_map[waypoint_type] or ""
	if waypoint_type == "CAP" then
		local cap_type = memory:GetWptCapType(flightplan_no, waypoint_no)
		if cap_type == 1 then
			type_suffix = " CAP1"
		elseif cap_type == 2 then
			type_suffix = " CAP2"
		end
	end

	local name = waypoint_active_suffix .. waypoint_no .. ": " .. type_suffix .. " " .. wpt_name .. holdSuffix
	return name
end

local FrequencyToActionText = function(frequency)
	if (frequency == nil) then
		return ""
	end

	local frequency_valid = Math.RoundTo(frequency:ConvertTo(kHz), kHz(25))
	return string.format('%.0f', frequency_valid.value)
end

local UpdateTuneAtc = function()
	local items = {}
	local i = 1
	local nearby_airfields = nearby_airfields or {}
	for _, airfield in ipairs(nearby_airfields) do
		if i > Wheel.MAX_OUTER_MENU_ITEMS then
			break
		end

		if airfield.atc_frequency ~= nil and airfield.atc_frequency.value > 1 then
			local frequency_display = FrequencyToDisplayText(airfield.atc_frequency)
			local frequency_action = FrequencyToActionText(airfield.atc_frequency)

			items[i] = Wheel.Item:new({
				name = airfield.name .. " (" .. frequency_display .. " mHz)",
				action = "radio_tune_atc",
				action_value = frequency_action
			})

			i = i + 1
		end
	end

	local no_airfields_nearby = #items == 0
	if no_airfields_nearby then
		items[1] = Wheel.Item:new({
			name = "No nearby station",
			action = "radio_tune_atc_no_station",
		})
	end

	local wrapping_item = Wheel.Item:new({
		name = "Tune ATC",
		outer_menu = Wheel.Menu:new({
			name = "Tune ATC",
			items = items,
		}),
	})

	Wheel.ReplaceItem(wrapping_item, "Tune ATC", { "UHF Radio" })
end

local UpdateTuneRadioAssets = function()
	local items = {}
	local i = 1
	local radio_tac_objects = radio_tac_objects or {}
	for _, obj in ipairs(radio_tac_objects) do
		if i > Wheel.MAX_OUTER_MENU_ITEMS then
			break
		end

		if obj.frequency ~= nil and obj.text ~= nil then
			local frequency_action = FrequencyToActionText(obj.frequency)

			items[i] = Wheel.Item:new({
				name = obj.text:gsub("\n", " "):sub(1, 18),
				action = "radio_tune_atc",
				action_value = frequency_action
			})

			i = i + 1
		end
	end

	local no_airfields_nearby = #items == 0
	if no_airfields_nearby then
		items[1] = Wheel.Item:new({
			name = "No nearby station",
			action = "radio_tune_atc_no_station",
		})
	end

	local wrapping_item = Wheel.Item:new({
		name = "Tune Assets",
		outer_menu = Wheel.Menu:new({
			name = "Tune Assets",
			items = items,
		}),
	})

	Wheel.ReplaceItem(wrapping_item, "Tune Assets", { "UHF Radio" })
end

local GenerateNavToAirfieldsItems = function(action_name, value_prefix, not_exit_menu)
	value_prefix = value_prefix and value_prefix .. ";" or ""
	not_exit_menu = not_exit_menu or false
	local items = {}
	local i = 1
	local nearby_airfields = nearby_airfields or {}
	for _, airfield in ipairs(nearby_airfields) do
		if i > Wheel.MAX_OUTER_MENU_ITEMS then
			break
		end

		local lat = tonumber(string.format("%.3f", airfield.latitude.value))
		local lon = tonumber(string.format("%.3f", airfield.longitude.value))
		local name = airfield.name and airfield.name:sub(1, 18):gsub(";", "") or ""  -- Max 20 characters and remove any ';'

		if lat ~= nil and lon ~= nil and name ~= nil then
			local coords_action = value_prefix .. tostring(lat) .. ";" .. tostring(lon)
			if value_prefix ~= "" then
				coords_action = coords_action .. ";" .. name
			end

			local reaction_ = not_exit_menu and Wheel.Reaction.NOTHING or Wheel.Reaction.CLOSE_REMEMBER
			items[i] = Wheel.Item:new({
				name = airfield.name:sub(1, 18),
				action = action_name,
				reaction = reaction_,
				action_value = coords_action
			})

			i = i + 1
		end
	end

	local no_airfields_nearby = #items == 0
	if no_airfields_nearby then
		items[1] = Wheel.Item:new({
			name = "No nearby Airfield",
			action = "no_airfield",
		})
	end

	return items
end

local GenerateNavToAssetsItems = function(action_name, value_prefix, not_exit_menu)
	value_prefix = value_prefix and value_prefix .. ";" or ""
	not_exit_menu = not_exit_menu or false
	local items = {}
	local i = 1
	local nav_tac_objects = nav_tac_objects or {}
	for _, obj in ipairs(nav_tac_objects) do
		if i > Wheel.MAX_OUTER_MENU_ITEMS then
			break
		end

		local lat = tonumber(string.format("%.3f", obj.latitude.value))
		local lon = tonumber(string.format("%.3f", obj.longitude.value))
		local name = obj.text:gsub("\n", " "):sub(1, 18):gsub(";", "") or ""

		if lat ~= nil and lon ~= nil and name ~= nil  then
			local coords_action = value_prefix .. tostring(lat) .. ";" .. tostring(lon)
			if value_prefix ~= "" then
				coords_action = coords_action .. ";" .. name
			end

			local reaction_ = not_exit_menu and Wheel.Reaction.NOTHING or Wheel.Reaction.CLOSE_REMEMBER
			items[i] = Wheel.Item:new({
				name = name,
				action = action_name,
				reaction = reaction_,
				action_value = coords_action
			})

			i = i + 1
		end
	end

	local no_objects_nearby = #items == 0
	if no_objects_nearby then
		items[1] = Wheel.Item:new({
			name = "No assets nearby",
			action = "no_nav_asset",
		})
	end

	return items
end

local GenerateNavToMapMarkerItemsFor = function(markers, action_name, value_prefix, not_exit_menu)
	value_prefix = value_prefix and value_prefix .. ";" or ""
	not_exit_menu = not_exit_menu or false
	local items = {}
	local i = 1
	for _, marker in ipairs(markers or {}) do
		if i > Wheel.MAX_OUTER_MENU_ITEMS then
			break
		end

		local lat = tonumber(string.format("%.3f", marker.latitude.value))
		local lon = tonumber(string.format("%.3f", marker.longitude.value))
		local name = marker.text and marker.text:sub(1, 18):gsub(";", "") or ""

		if lat ~= nil and lon ~= nil and marker.creation_time then
			local coords_action = value_prefix .. tostring(lat) .. ";" .. tostring(lon)
			if value_prefix ~= "" then
				coords_action = coords_action .. ";" .. name
			end
			--local current_time = Utilities.GetTime().mission_time:ConvertTo(s)
			--local time_ago = current_time - marker.creation_time
			--local time_text = ""
			--if time_ago < min(1) then
			--	time_text = tostring(Math.Round(time_ago:ConvertTo(s).value)) .. " s ago"
			--elseif time_ago < min(60) then
			--	time_text = tostring(Math.Floor(time_ago:ConvertTo(min).value)) .. " min ago"
			--end
			local wpt_text = marker.text
			if wpt_text == nil or wpt_text == "" then
				wpt_text = "(No Name)"
			end

			--todo calculate time and distance to marker point

			local reaction_ = not_exit_menu and Wheel.Reaction.NOTHING or Wheel.Reaction.CLOSE_REMEMBER
			items[i] = Wheel.Item:new({
				name = wpt_text:sub(1, 18), -- .. ", " .. time_text,
				action = action_name,
				reaction = reaction_,
				action_value = coords_action
			})

			i = i + 1
		end
	end

	local no_markers = #items == 0
	if no_markers then
		items[1] = Wheel.Item:new({
			name = "No Map Markers",
			action = "no_markers",
		})
	end

	return items
end

local GenerateNavToMapMarkerItems = function(action_name, value_prefix, not_exit_menu)
	return {
		Wheel.Item:new({
			name = "Own Markers",
			outer_menu = Wheel.Menu:new({
				name = "Own Markers",
				items = GenerateNavToMapMarkerItemsFor(own_map_markers, action_name, value_prefix, not_exit_menu),
			}),
		}),
		Wheel.Item:new({
			name = "All Markers",
			outer_menu = Wheel.Menu:new({
				name = "All Markers",
				items = GenerateNavToMapMarkerItemsFor(all_map_markers, action_name, value_prefix, not_exit_menu),
			}),
		})
	}
end

local UpdateDivertTGT1ToAirfields = function()
	local items = GenerateNavToAirfieldsItems( "divert_tgt1_lat_lon" )
	local wrapping_item = Wheel.Item:new({
		name = "Airfields",
		outer_menu = Wheel.Menu:new({
			name = "Airfields",
			items = items,
		}),
	})
	Wheel.ReplaceItem(wrapping_item, "Airfields", { "Navigation", "Divert To"  })
end

local UpdateDivertTGT1ToAssets = function()
	local items = GenerateNavToAssetsItems( "divert_tgt1_lat_lon" )
	local wrapping_item = Wheel.Item:new({
		name = "Assets",
		outer_menu = Wheel.Menu:new({
			name = "Assets",
			items = items,
		}),
	})
	Wheel.ReplaceItem(wrapping_item, "Assets", { "Navigation", "Divert To"  })
end

local UpdateDivertTGT1ToMapMarkers = function()
	local items = GenerateNavToMapMarkerItems( "divert_tgt1_lat_lon" )
	local wrapping_item = Wheel.Item:new({
		name = "Map Markers",
		menu = Wheel.Menu:new({
			name = "Map Markers",
			items = items,
		}),
	})
	Wheel.ReplaceItem(wrapping_item, "Map Markers", { "Navigation", "Divert To"  })
end

function UpdateJesterWheel:UpdateRadioWheelInfo()
	local cockpit = GetJester():GetCockpit()
	local mode = cockpit:GetManipulator("Radio Mode"):GetState()
	local comm_chan = cockpit:GetManipulator("Radio Comm Chan"):GetState()
	local aux_chan = cockpit:GetManipulator("Radio Aux Chan"):GetState()
	local freq_mode = cockpit:GetManipulator("Radio Freq Mode"):GetState()

	local info = ""
	if mode ~= nil and aux_chan ~= nil and freq_mode ~= nil and comm_chan ~= nil then
		local mode_map = {
			OFF = "OFF",
			TR_ADF = "TR/ADF",
			TR_G_ADF = "TR+G/ADF",
			ADF_G_CMD = "ADF+G/CMD",
			ADF_G = "ADF/G",
			GUARD_ADF = "G/ADF"
		}
		mode = mode_map[mode] or "Mode error"

		local freq_text = ""
		if freq_mode == "MANUAL" then
			local freq_hundreds = cockpit:GetManipulator("Radio Freq 1xx.xxx"):GetState()
			local freq_tens = cockpit:GetManipulator("Radio Freq x1x.xxx"):GetState()
			local freq_ones = cockpit:GetManipulator("Radio Freq xx1.xxx"):GetState()
			local freq_decones = cockpit:GetManipulator("Radio Freq xxx.1xx"):GetState()
			local freq_dectens = cockpit:GetManipulator("Radio Freq xxx.x11"):GetState()

			if freq_hundreds ~= nil and freq_tens ~= nil and freq_ones ~= nil and freq_decones ~= nil and freq_dectens ~= nil then
				if freq_hundreds == "T" or freq_hundreds == "A" then
					freq_text = freq_hundreds
				else
					local hundreds_map = {
						T = "T",
						TWO = "2",
						THREE = "3",
						A = "A"
					}
					local freq_hundreds_txt = hundreds_map[freq_hundreds] or "Freq hundreds error"

					local dectens_map = {
						ZERO = "00",
						TWENTY_FIVE = "25",
						FIFTY = "50",
						SEVENTY_FIVE = "75"
					}
					local freq_dectens_txt = dectens_map[freq_dectens] or "Freq dec tens error"

					freq_text = freq_hundreds_txt .. freq_tens .. freq_ones .. "." .. freq_decones .. freq_dectens_txt
				end
			else
				freq_text = "Error: retrieving frequency."
			end

		else --preset
			freq_text = "CH " .. comm_chan
		end

		info = mode .. ", " .. freq_text .. ", AUX CH " .. aux_chan
	else
		info = "Error: retrieving radio info."
	end

	Wheel.SetMenuInfo( info, { "UHF Radio" })
end

function UpdateJesterWheel:UpdateTacanWheelInfo()
	local mode_int_prop = GetProperty('/TACAN Info', 'Mode int')
	local channel_prop = GetProperty('/TACAN Info', 'Channel')
	local use_y_prop = GetProperty('/TACAN Info', 'Use y')

	local info = "Error: retrieving TACAN info."

	if mode_int_prop ~= nil and channel_prop ~= nil and use_y_prop ~= nil then
		local mode_str = ""
		if mode_int_prop.value == 0 then
			mode_str = "OFF"
		elseif mode_int_prop.value == 1 then
			mode_str = "REC"
		elseif mode_int_prop.value == 2 then
			mode_str = "TR"
		elseif mode_int_prop.value == 3 then
			mode_str = "AA REC"
		elseif mode_int_prop.value == 4 then
			mode_str = "AA TR"
		end

        if mode_int_prop.value == 0 then
            info = mode_str  -- Just "OFF"
        else
            local channel_str = string.format("%03d", channel_prop.value or 0)
            local band_str = use_y_prop.value and "Y" or "X"
            info = mode_str .. ", " .. channel_str .. band_str
        end
	end

	Wheel.SetMenuInfo( info, { "Navigation", "TACAN" })
end

function UpdateJesterWheel:GenerateTacanChannelTens()
	local items = {}
	-- Enumerate through 00 to 12 for the first two digits of TACAN channels
	for tens = 0, 12 do
		local tensStr = string.format("%02d", tens) -- Ensure two-digit formatting
		table.insert(items, Wheel.Item:new({
			name = tensStr,
			action = "nav_tacan_chan_tens",
			action_value = tensStr,
			reaction = Wheel.Reaction.NOTHING,
		}))
	end

	local wrapping_item = Wheel.Item:new({
		name = "Select Channel",
		outer_menu = Wheel.Menu:new({
			name = "Select Channel",
			items = items,
		}),
	})

	Wheel.ReplaceItem(wrapping_item, "Select Channel", { "Navigation", "TACAN" })
	Wheel.SetMenuInfo("1st and 2nd digit [XXYb]", { "Navigation", "TACAN", "Select Channel" })
end

function UpdateJesterWheel:UpdateNavWheelInfo()

	local function GetFlightplanNameSuffixString( flightplan_no )
		if flightplan_no == 1 then
			return "Primary"
		elseif flightplan_no == 2 then
			return "Secondary"
		end
		return "N/A"
	end

	local memory = GetJester().memory
	local info = "Error: retrieving Nav info."

	--local mode_prop = GetProperty('/Navigation Computer/Navigation Computer ASN 46A Mechanical Panel', 'Mode int')
	local cockpit = GetJester():GetCockpit()
	local mode_str = cockpit:GetManipulator("Nav Panel Function"):GetState()

	local ftpln_str = "N/A"
	local turn_point_str = "N/A"
	local turn_point_no_str = "0"
	local hold_info = ""

	local ins_alignment_state = GetJester().awareness:GetObservation("ins_alignment_state") --0->OFF, 1->ALIGNING_OR_STBY, 2->ATTITUDE_ONLY, 3->INERTIAL
	if ins_alignment_state == 0 then
		info = "INS: OFF"
	elseif ins_alignment_state == 1 then --aligning or stby
		local knob_pos = cockpit:GetManipulator("INS Mode Knob"):GetState()
		if knob_pos then
			if knob_pos == "STBY" then
				info = "INS: STBY"
				local heat_light_on = GetProperty("/INS ASN-63/Mode Logic/Warmup/Heat Light Logic", "Light On").value
				if heat_light_on then
					info = info .. " - HEATING"
				elseif heat_light_on == false then
					info = info .. " - WARMED UP"
				else
					info = "Error reading Warmup INS property"
				end
			elseif knob_pos == "ALIGN" then
				info = "INS: ALIGN"
				local aligning_state = GetProperty("/INS ASN-63/Mode Logic", "Alignment State").value --0->NONE, 1->COARSE, 2->FINE_LEVELING, 3->GYRO_COMP
				if aligning_state == 0 then
					info = "INS: OFF"
				elseif aligning_state == 1 then
					info = info .. " - COARSE ALIGNMENT"
				elseif aligning_state == 2 then
					info = info .. " - FINE LEVELING"
				elseif aligning_state == 3 then
					info = info .. " - GYRO COMPASSING"
				else
					info = "Error reading Aligning State INS property"
				end
			elseif knob_pos == "NAV" then
				info = "INS: NAV - COARSE ALIGNMENT"
			else
				info = "INS: OFF"
			end
		else
			info = "Error reading INS manipulator"
		end
	elseif ins_alignment_state == 2 then --attitude only
		info = "INS: ATTITUDE ONLY"
	else --inertial mode
		if mode_str == "TARGET_1" then
			local memorized_tp_data = memory:GetMemorizedLastActiveWptData()
			if memorized_tp_data ~= nil then
				ftpln_str = GetFlightplanNameSuffixString( memorized_tp_data.flightplan )
			end
			info = "Diversion Point\nActive: " .. ftpln_str
		else -- if mode_str == "TARGET_2" then
			local ftpln_no = memory:GetActiveFlightPlanNumber()
			ftpln_str = GetFlightplanNameSuffixString( ftpln_no )
			if ftpln_no ~= nil and ( ftpln_no == 1 or ftpln_no == 2 ) then
				local turn_point_no = memory:GetActiveWaypointNumber()
				local wpt_type = memory:GetActiveWaypointType()

				if turn_point_no ~= nil and turn_point_no > 0 and wpt_type then
					turn_point_no_str = tostring(turn_point_no)
					local type_phrases = {
						DEFAULT = "Turn Point",
						CAP = "CAP",
						IP = "IP",
						TARGET = "TGT",
						VIP = "VIP",  -- Visual Identification Point
						VIP_SILENT = "TP (Fix)",
						FENCE_IN = "F-In",
						FENCE_OUT = "F-Out",
						HOMEBASE = "HB",
						ALTERNATE = "ALT"
					}
					local custom_phrase = type_phrases[wpt_type] or "ERR WPT TYPE"

					if memory:GetIsActiveTurnPointHold() then
						hold_info = " (h)"
					end
					if wpt_type == "CAP" then
						if memory:GetIsCapping() then
							local cap_wpt_type = memory:GetActiveWptCAPType()

							if cap_wpt_type == 1 then
								custom_phrase = "CAP1"
							elseif cap_wpt_type == 2 then
								custom_phrase = "CAP2"
							else
								custom_phrase = "ERR CAP TYPE"
							end
						else
							custom_phrase = "CAP (STBY)"
						end
					end
					-- Combine the custom phrase with the turn point string
					turn_point_str = custom_phrase .. ": " .. turn_point_no_str
				end
			end
			info = turn_point_str .. hold_info .. "\nActive: " .. ftpln_str
		end
	end

	Wheel.SetMenuInfo( info, { "Navigation" })
end

function UpdateJesterWheel:UpdateINSQuickRealignmentOption()
	local conditions_met = GetJester().awareness:GetObservation("ins_alignment_state") == 3 and GetJester().awareness:GetObservation("on_ground") and GetJester().awareness:GetObservation("bus_power") and GetJester().awareness:GetObservation("ground_speed") < kt(0.01)

	local location = {"Navigation"}
	if conditions_met ~= self.ins_quick_realignment_option_provided then
		if conditions_met then
			Wheel.AddItem(Wheel.Item:new( { name = "Fine-Align INS", action = "jester_realign_quick", action_value = "restart", reaction = Wheel.Reaction.CLOSE_TO_MAIN_MENU} ), location )
		else
			Wheel.RemoveItem("Fine-Align INS", location)
		end
		self.ins_quick_realignment_option_provided = conditions_met
	end
end

function UpdateJesterWheel:UpdateFlightplans()
	local memory = GetJester().memory

	local function GenerateFlightPlanItemsToEditFrom( action, waypoint_data )
		local flightplan_items = {}
		for fltpln_idx = 1, 2 do
			local fltpln = memory:GetFlightPlan(fltpln_idx)
			local fltpln_name = memory:GetFlightplanNameString(fltpln_idx)

			-- Check if the flight plan is empty or null
			if not fltpln or not fltpln.waypoints or #fltpln.waypoints == 0 then
				flightplan_items[fltpln_idx] = Wheel.Item:new({
					name = fltpln_name,
					menu = Wheel.Menu:new({
						name = fltpln_name,
						items = {
							Wheel.Item:new({
								name = "No Turn Points"
							})
						},
					}),
				})
			else
				local waypoints_items = {}
				for idx, wpt in ipairs(fltpln.waypoints) do
					-- Limit the number of waypoints to 8
					if idx > 8 then break end

					local name = self:GetWaypointTextToDisplay( fltpln_idx, idx, wpt )

					waypoints_items[#waypoints_items + 1] = Wheel.Item:new({
						name = name,
						action = action,
						reaction = Wheel.Reaction.NOTHING,
						action_value = waypoint_data .. ";" .. tostring(fltpln_idx) .. ";" .. tostring(idx)
					})
				end
				flightplan_items[fltpln_idx] = Wheel.Item:new({
					name = fltpln_name,
					menu = Wheel.Menu:new({
						name = fltpln_name,
						items = waypoints_items,
					}),
				})
			end
		end
		return flightplan_items
	end

	local function UpdateFlightplan(flightplan, menu_name, action_name)
		if not flightplan or not flightplan.waypoints then
			return Wheel.Item:new({ name = "Invalid or empty " .. menu_name })
		end

		local items = {}
		for i, waypoint in ipairs(flightplan.waypoints) do
			if i > Wheel.MAX_OUTER_MENU_ITEMS then
				break
			end

			if waypoint.latitude ~= nil and waypoint.longitude ~= nil then
				local action_value = ""
				if action_name == "hold_flightplan_1" or action_name == "hold_flightplan_2" then
					-- waypoint number for hold at
					action_value = tostring(i)
				else
					action_value = tostring(waypoint.latitude) .. ";" .. tostring(waypoint.longitude)
				end

				local flightplan_no = flightplan == memory:GetFlightPlan1() and 1 or 2
				local name = self:GetWaypointTextToDisplay(flightplan_no, i, waypoint)

				items[i] = Wheel.Item:new({
					name = name,
					action = action_name,
					action_value = action_value,
				})
			end
		end

		if #items == 0 then
			items[1] = Wheel.Item:new({ name = "No Turn Points in Flight Plan" })
		end

		return Wheel.Item:new({
			name = menu_name,
			outer_menu = Wheel.Menu:new({
				name = menu_name,
				items = items,
			}),
		})
	end

	local function UpdateEditFlightplan(flightplan, flightplan_no, menu_name)

		local function InsertNewWaypointAfterItems(flightplan_no_str, waypoint_no_str)
			local waypoint_data = flightplan_no_str .. ";" .. waypoint_no_str
			local add_after_items_ftpl = GenerateFlightPlanItemsToEditFrom( "add_wpt_after_fltpln", waypoint_data )
			local add_after_items_airfield = GenerateNavToAirfieldsItems("add_wpt_after_lat_long", waypoint_data, true )
			local add_after_items_asset = GenerateNavToAssetsItems("add_wpt_after_lat_long", waypoint_data, true )
			local add_after_items_map_marker = GenerateNavToMapMarkerItems("add_wpt_after_lat_long", waypoint_data, true )
			local add_items = {}
			add_items[1] = Wheel.Item:new({
					name = "Lat/Long",
					action = "add_wpt_after_lat_long_text",
					reaction = Wheel.Reaction.NOTHING,
					action_value = waypoint_data,
					text_entry = Wheel.TextEntry:new({
						hint = "H DD MM H DDD MM",
						max = 16,
						match = "[0123456789NSEWnsew ]+",
					}),
				})
			add_items[2] = Wheel.Item:new({
					name = "Flight Plan",
					menu = Wheel.Menu:new({
						name = "Add WPT from Flight Plan",
						items = add_after_items_ftpl,
					}),
				})
			add_items[3] = Wheel.Item:new({
				name = "Map Markers",
				menu = Wheel.Menu:new({
					name = "Add WPT from Map Markers",
					items = add_after_items_map_marker,
				}),
			})
			add_items[4] = Wheel.Item:new({
				name = "Airfields",
				outer_menu = Wheel.Menu:new({
					name = "Add WPT from Airfields",
					items = add_after_items_airfield,
				}),
			})
			add_items[5] = Wheel.Item:new({
				name = "Assets",
				outer_menu = Wheel.Menu:new({
					name = "Add WPT from Assets",
					items = add_after_items_asset,
				}),
			})
			return add_items
		end

		if not flightplan or not flightplan.waypoints then
			return Wheel.Item:new({ name = "Invalid or empty " .. menu_name })
		end

		local flightplan_no_str = tostring(flightplan_no)

		local wpt_items = {}
		for i, waypoint in ipairs(flightplan.waypoints) do
			if i > Wheel.MAX_MENU_ITEMS then
				break
			end

			if waypoint.latitude ~= nil and waypoint.longitude ~= nil then
				local latitude_display = self:LatitudeToDisplayText(waypoint.latitude)
				local longitude_display = self:LongitudeToDisplayText(waypoint.longitude)
				local wpt_no = tostring(i)

				local waypoint_data = flightplan_no_str .. ";" .. wpt_no
				--flightplan and waypoint to edit
				local edit_wpt_items = GenerateFlightPlanItemsToEditFrom( "edit_wpt_fltpln", waypoint_data )
				local add_before_items = GenerateFlightPlanItemsToEditFrom( "add_wpt_before_fltpln", waypoint_data )
				local add_after_items = InsertNewWaypointAfterItems(flightplan_no_str, wpt_no)
				local edit_wpt_airfields = GenerateNavToAirfieldsItems("edit_wpt_lat_long", waypoint_data, true )
				local insert_wpt_airfields = GenerateNavToAirfieldsItems("add_wpt_before_lat_long", waypoint_data, true )
				local edit_wpt_assets = GenerateNavToAssetsItems("edit_wpt_lat_long", waypoint_data, true )
				local insert_wpt_assets = GenerateNavToAssetsItems("add_wpt_before_lat_long", waypoint_data, true )
				local edit_wpt_map_marker = GenerateNavToMapMarkerItems("edit_wpt_lat_long", waypoint_data, true )
				local insert_wpt_map_marker = GenerateNavToMapMarkerItems("add_wpt_before_lat_long", waypoint_data, true )
				local edit_items = {
					Wheel.Item:new({
						name = "Edit Turn Point",
						menu = Wheel.Menu:new({
							name = "Edit Turn Point",
							items = {
								Wheel.Item:new({
									name = "Lat/Long",
									action = "edit_wpt_lat_long_text",
									reaction = Wheel.Reaction.NOTHING,
									action_value = flightplan_no_str .. ";" .. wpt_no,
									text_entry = Wheel.TextEntry:new({
										hint = "H DD MM H DDD MM",
										max = 16,
										match = "[0123456789NSEWnsew ]+",
									}),
								}),
								Wheel.Item:new({
									name = "Flight Plan",
									menu = Wheel.Menu:new({
										name = "Change WPT from Flight Plan",
										items = edit_wpt_items,
									}),
								}),
								Wheel.Item:new({
									name = "Map Markers  ",
									menu = Wheel.Menu:new({
										name = "Change WPT from Map Marker  ",
										items = edit_wpt_map_marker,
									}),
								}),
								Wheel.Item:new({
									name = "Airfields",
									outer_menu = Wheel.Menu:new({
										name = "Change WPT from Airfields",
										items = edit_wpt_airfields,
									}),
								}),
								Wheel.Item:new({
									name = "Assets",
									outer_menu = Wheel.Menu:new({
										name = "Change WPT from Assets",
										items = edit_wpt_assets,
									}),
								})
							},
						}),
					}),
					Wheel.Item:new({
						name = "Designate Waypoint",
						outer_menu = Wheel.Menu:new({
							name = "Designate Waypoint",
							items = {
								Wheel.Item:new({
									name = "Default (Turn Point)",
									action = "designate_wpt",
									reaction = Wheel.Reaction.NOTHING,
									action_value = flightplan_no_str .. ";" .. wpt_no .. ";" .. "DEFAULT",
								}),
								Wheel.Item:new({
									name = "Nav Fix",
									action = "designate_wpt",
									reaction = Wheel.Reaction.NOTHING,
									action_value = flightplan_no_str .. ";" .. wpt_no .. ";" .. "VIP",
								}),
								Wheel.Item:new({
									name = "CAP",
									action = "designate_wpt",
									reaction = Wheel.Reaction.NOTHING,
									action_value = flightplan_no_str .. ";" .. wpt_no .. ";" .. "CAP",
								}),
								Wheel.Item:new({
									name = "IP",
									action = "designate_wpt",
									reaction = Wheel.Reaction.NOTHING,
									action_value = flightplan_no_str .. ";" .. wpt_no .. ";" .. "IP",
								}),
								Wheel.Item:new({
									name = "Target",
									action = "designate_wpt",
									reaction = Wheel.Reaction.NOTHING,
									action_value = flightplan_no_str .. ";" .. wpt_no .. ";" .. "TARGET",
								}),
								Wheel.Item:new({
									name = "Fence In",
									action = "designate_wpt",
									reaction = Wheel.Reaction.NOTHING,
									action_value = flightplan_no_str .. ";" .. wpt_no .. ";" .. "FENCE_IN",
								}),
								Wheel.Item:new({
									name = "Fence Out",
									action = "designate_wpt",
									reaction = Wheel.Reaction.NOTHING,
									action_value = flightplan_no_str .. ";" .. wpt_no .. ";" .. "FENCE_OUT",
								}),
								Wheel.Item:new({
									name = "Homebase",
									action = "designate_wpt",
									reaction = Wheel.Reaction.NOTHING,
									action_value = flightplan_no_str .. ";" .. wpt_no .. ";" .. "HOMEBASE",
								}),
								Wheel.Item:new({
									name = "Alternate Airfield",
									action = "designate_wpt",
									reaction = Wheel.Reaction.NOTHING,
									action_value = flightplan_no_str .. ";" .. wpt_no .. ";" .. "ALTERNATE",
								}),
							},
						}),
					}),
					Wheel.Item:new({
						name = "Insert New Turn Point After",
						menu = Wheel.Menu:new({
							name = "Insert New Turn Point After",
							items = add_after_items,
						}),
					}),
					Wheel.Item:new({
						name = "Insert New Turn Point Before",
						menu = Wheel.Menu:new({
							name = "Insert New Turn Point Before",
							items = {
								Wheel.Item:new({
									name = "Lat/Long",
									action = "add_wpt_before_lat_long_text",
									reaction = Wheel.Reaction.NOTHING,
									action_value = flightplan_no_str .. ";" .. wpt_no,
									text_entry = Wheel.TextEntry:new({
										hint = "H DD MM H DDD MM",
										max = 16,
										match = "[0123456789NSEWnsew ]+",
									}),
								}),
								Wheel.Item:new({
									name = "Flight Plan",
									menu = Wheel.Menu:new({
										name = "Add WPT from Flight Plan",
										items = add_before_items,
									}),
								}),
								Wheel.Item:new({
									name = "Map Markers ",
									menu = Wheel.Menu:new({
										name = "Add WPT from Map Marker ",
										items = insert_wpt_map_marker,
									}),
								}),
								Wheel.Item:new({
									name = "Airfields",
									outer_menu = Wheel.Menu:new({
										name = "Add WPT from Airfields",
										items = insert_wpt_airfields,
									}),
								}),
								Wheel.Item:new({
									name = "Assets",
									outer_menu = Wheel.Menu:new({
										name = "Add WPT from Assets",
										items = insert_wpt_assets,
									}),
								})
							},
						}),
					}),
					Wheel.Item:new({
						name = "Delete Turn Point",
						action = "delete_wpt",
						reaction = Wheel.Reaction.NOTHING,
						action_value = flightplan_no_str .. ";" .. wpt_no
					})
				}

				local name = self:GetWaypointTextToDisplay( flightplan_no, i, waypoint )

				wpt_items[i] = Wheel.Item:new({
					name = name,
					menu = Wheel.Menu:new(
					{
						name = memory:GetFlightplanNameString(flightplan_no) .. ", WPT: " .. wpt_no,
						items = edit_items,
					}),
				})
			end
		end

		if #wpt_items == 0 then
			wpt_items[1] = Wheel.Item:new({
				name = "Add Turn Point",
				menu = Wheel.Menu:new({
					name = "Add Turn Point",
					items = InsertNewWaypointAfterItems(flightplan_no_str, "0"),
				}),

			})
		end

		return Wheel.Item:new({
			name = menu_name,
			menu = Wheel.Menu:new({
				name = menu_name,
				items = wpt_items,
			}),
		})
	end

	local function UpdateHoldingMenu()
		local function UpdateCurrentTurnPointHoldItemName()
			local is_curr_hold = memory:GetIsActiveTurnPointHold()
			if is_curr_hold and not self.current_wpt_hold_renamed_to_deactivate then
				Wheel.RenameItem("Current Turn Point Deactivate", "Current Turn Point Activate", { "Navigation", "Holding" } )
				self.current_wpt_hold_renamed_to_deactivate = true
			elseif not is_curr_hold and self.current_wpt_hold_renamed_to_deactivate then
				Wheel.RenameItem("Current Turn Point Activate", "Current Turn Point Deactivate", { "Navigation", "Holding" } )
				self.current_wpt_hold_renamed_to_deactivate = false
			end
		end

		local function UpdateDeactivationList()
			local flightplan_1 = memory:GetFlightPlan1()
			local flightplan_2 = memory:GetFlightPlan2()

			local items = {}
			local i = 1
			-- Iterate over waypoints in flightplan 1
			for index, turn_pt in ipairs(flightplan_1.waypoints) do
				if i > Wheel.MAX_OUTER_MENU_ITEMS then
					break
				end
				if turn_pt:GetHoldAt() then
					local index_str = tostring(index)
					items[i] = Wheel.Item:new({
						name = "Fltpln: Primary, WPT: " .. index_str,
						action = "deactivate_hold_fp1",
						action_value = index_str
					})
					i = i + 1
				end
			end

			-- Iterate over waypoints in flightplan 2
			for index, turn_pt in ipairs(flightplan_2.waypoints) do
				if i > Wheel.MAX_OUTER_MENU_ITEMS then
					break
				end
				if turn_pt:GetHoldAt() then
					local index_str = tostring(index)
					items[i] = Wheel.Item:new({
						name = "Fltpln: Secondary, WPT: " .. index_str,
						action = "deactivate_hold_fp2",
						action_value = index_str
					})
					i = i + 1
				end
			end

			if i == 1 then --no items added
				items[1] = Wheel.Item:new({
					name = "No planned holds",
					action = "no_holds",
				})
			end

			local wrapping_item = Wheel.Item:new({
				name = "Deactivate Planned Hold",
				outer_menu = Wheel.Menu:new({
					name = "Deactivate Planned Hold",
					items = items,
				}),
			})

			Wheel.ReplaceItem(wrapping_item, "Deactivate Planned Hold", { "Navigation", "Holding" })
		end

		UpdateCurrentTurnPointHoldItemName()
		UpdateDeactivationList()
	end

	local flightplan_1 = memory:GetFlightPlan1()
	local flightplan_2 = memory:GetFlightPlan2()

	local function UpdateGoToMenu()
		local function GetGotoMenu(flightplan_1, flightplan_2)
			if not flightplan_1 or not flightplan_1.waypoints or not flightplan_2 or not flightplan_2.waypoints then
				return Wheel.Item:new({ name = "Invalid Flight Plan" })
			end

			local active_fltpln_no = memory:GetActiveFlightPlanNumber()
			local memorized_fltpln_no = memory:GetMemorizedLastActiveWptData().flightplan
			local flightplan_2_active_or_memorized = active_fltpln_no ~= nil and ( active_fltpln_no == 2 or ( active_fltpln_no == 0 and memorized_fltpln_no ~= nil and memorized_fltpln_no == 2 ))

			local top_flightplan = flightplan_1
			local backup_flightplan = flightplan_2
			local primary_on_top = true
			if flightplan_2_active_or_memorized then
				top_flightplan = flightplan_2
				backup_flightplan = flightplan_1
				primary_on_top = false
			end

			local items = {}
			local item_no = 1
			items[item_no] = Wheel.Item:new({
				name = "Next Turn Point",
				action = "resume_next_wpt",
			})

			for i, waypoint in ipairs(top_flightplan.waypoints) do
				if i > Wheel.MAX_OUTER_MENU_ITEMS - 2 then -- -2 for the 'next wpt' and other flightplan items
					break
				end

				if waypoint.latitude ~= nil and waypoint.longitude ~= nil then
					local action_value = tostring(waypoint.latitude) .. ";" .. tostring(waypoint.longitude) .. ";" .. tostring(i)

					local flightplan_no = primary_on_top and 1 or 2
					local name = self:GetWaypointTextToDisplay(flightplan_no, i, waypoint)
					local act_name = primary_on_top and "resume_flightplan_1" or "resume_flightplan_2"

					item_no = item_no + 1
					items[item_no] = Wheel.Item:new({
						name = name,
						action = act_name,
						action_value = action_value,
					})
				end
			end

			-- Check if there are items in backup flightplan
			local backup_flightplan_empty = true
			for i, waypoint in ipairs(backup_flightplan.waypoints) do
				if waypoint.latitude ~= nil and waypoint.longitude ~= nil then
					backup_flightplan_empty = false
					break
				end
			end

			if #items == 1 and backup_flightplan_empty then
				items[1] = Wheel.Item:new({ name = "No Turn Points in Flight Plan" })
			end

			if not backup_flightplan_empty then
				local backup_flightplan_name = primary_on_top and "Secondary Flight Plan" or "Primary Flight Plan"
				local backup_flightplan_val = primary_on_top and "2" or "1"
				items[item_no + 1] = Wheel.Item:new({
					name = backup_flightplan_name,
					action = "resume_backup_flightplan",
					reaction = Wheel.Reaction.NOTHING,
					action_value = backup_flightplan_val,
				})
			end

			return Wheel.Item:new({
				name = "Go To / Resume",
				outer_menu = Wheel.Menu:new({
					name = "Go To / Resume",
					items = items,
				}),
			})
		end

		local goto_menu = GetGotoMenu(flightplan_1, flightplan_2)
		Wheel.ReplaceItem(goto_menu, "Go To / Resume", { "Navigation" })

	end

	local divert_tgt1_fltpln_1 = UpdateFlightplan(flightplan_1, "Primary Flight Plan", "divert_tgt1_lat_lon" )
	Wheel.ReplaceItem(divert_tgt1_fltpln_1, "Primary Flight Plan", { "Navigation", "Divert To", "Flight Plan" })

	local hold_at_fltpln_1 = UpdateFlightplan(flightplan_1, "Set For Primary Flight Plan", "hold_flightplan_1")
	Wheel.ReplaceItem(hold_at_fltpln_1, "Set For Primary Flight Plan", { "Navigation", "Holding" })

	local edit_fltpln_1 = UpdateEditFlightplan(flightplan_1, 1, "Primary Flight Plan")
	Wheel.ReplaceItem(edit_fltpln_1, "Primary Flight Plan", { "Navigation", "Edit Flight Plan" })

	local divert_tgt1_fltpln_2 = UpdateFlightplan(flightplan_2, "Secondary Flight Plan", "divert_tgt1_lat_lon")
	Wheel.ReplaceItem(divert_tgt1_fltpln_2, "Secondary Flight Plan", { "Navigation", "Divert To", "Flight Plan" })

	local hold_at_fltpln_2 = UpdateFlightplan(flightplan_2, "Set For Secondary Flight Plan", "hold_flightplan_2")
	Wheel.ReplaceItem(hold_at_fltpln_2, "Set For Secondary Flight Plan", { "Navigation", "Holding" })

	local edit_fltpln_2 = UpdateEditFlightplan(flightplan_2, 2, "Secondary Flight Plan")
	Wheel.ReplaceItem(edit_fltpln_2, "Secondary Flight Plan", { "Navigation", "Edit Flight Plan" })

	UpdateHoldingMenu()
	UpdateGoToMenu()
	self:UpdateNavWheelInfo()
end

local UpdateTacanGroundChannels = function()
	local items = {}
	local i = 1
	local tacans = tacans or {}
	for _, tac in ipairs(tacans) do
		if i > Wheel.MAX_OUTER_MENU_ITEMS then
			break
		end

		if tac.channel ~= nil and tac.use_y ~= nil and tac.use_aa ~= nil and tac.tactical == false then
			local band = tac.use_y and "y" or "x"
			local act = tac.use_aa and "nav_tacan_aa" or "nav_tacan_tr"
			local value = string.format("%03d", tac.channel) .. band
			items[i] = Wheel.Item:new({
				name = tac.name:gsub("\n", " "):sub(1, 18),
				action = act,
				action_value = value,
			})

			i = i + 1
		end
	end

	local no_airfields_nearby = #items == 0
	if no_airfields_nearby then
		items[1] = Wheel.Item:new({
			name = "No nearby station",
			action = "nav_tacan_ground_no_station",
		})
	end

	local wrapping_item = Wheel.Item:new({
		name = "Tune Ground Station",
		outer_menu = Wheel.Menu:new({
			name = "Tune Ground Station",
			items = items,
		}),
	})

	Wheel.ReplaceItem(wrapping_item, "Tune Ground Station", { "Navigation", "TACAN" })
end

local UpdateTacanAssetChannels = function()
	local items = {}
	local i = 1
	local tacans = tacans or {}
	for _, tac in ipairs(tacans) do
		if i > Wheel.MAX_OUTER_MENU_ITEMS then
			break
		end

		if tac.channel ~= nil and tac.use_y ~= nil and tac.use_aa ~= nil and tac.tactical == true then
			local band = tac.use_y and "y" or "x"
			local act = tac.use_aa and "nav_tacan_aa" or "nav_tacan_tr"
			local value = string.format("%03d", tac.channel) .. band
			items[i] = Wheel.Item:new({
				name = tac.name:gsub("\n", " "):sub(1, 18),
				action = act,
				action_value = value,
			})

			i = i + 1
		end
	end

	local no_airfields_nearby = #items == 0
	if no_airfields_nearby then
		items[1] = Wheel.Item:new({
			name = "No nearby station",
			action = "nav_tacan_assets_no_station",
		})
	end

	local wrapping_item = Wheel.Item:new({
		name = "Tune Assets",
		outer_menu = Wheel.Menu:new({
			name = "Tune Assets",
			items = items,
		}),
	})

	Wheel.ReplaceItem(wrapping_item, "Tune Assets", { "Navigation", "TACAN" })
end

local UpdateTacanChannels = function()
	UpdateTacanGroundChannels()
	UpdateTacanAssetChannels()
end

local CreatePaveSpikeMenu = function()
	return Wheel.Item:new({
		name = "Pave Spike",
		menu = Wheel.Menu:new({
			name = "Pave Spike",
			items = {
				Wheel.Item:new({ name = "Operation", outer_menu = Wheel.Menu:new({
					name = "Operation",
					items = {
						Wheel.Item:new({ name = "Ready", action = "pave_spike_op", action_value = "ready", reaction = Wheel.Reaction.CLOSE_REMEMBER }),
						Wheel.Item:new({ name = "Standby", action = "pave_spike_op", action_value = "standby", reaction = Wheel.Reaction.CLOSE_REMEMBER }),
					},
				}) }),
				Wheel.Item:new({
					name = "Laser Code",
					action = "pave_spike_laser_code",
					reaction = Wheel.Reaction.CLOSE_REMEMBER,
					text_entry = Wheel.TextEntry:new({
						hint = "4 digit code",
						max = 4,
						match = "[1-8]{0,4}",
					}),
				}),
			},
		}),
	})
end

function UpdateJesterWheel:UpdatePaveSpike()
	local location = { "Air To Ground" }

	local pod_equipped = GetProperty("/EO TGT Designator System", "Pod loaded").value
	if pod_equipped and not self.a2g_pave_spike_added then
		local pave_spike_menu = CreatePaveSpikeMenu()
		Wheel.AddItem(pave_spike_menu, location)
		self.a2g_pave_spike_added = true
	elseif not pod_equipped and self.a2g_pave_spike_added then
		Wheel.RemoveItem("Pave Spike", location)
		self.a2g_pave_spike_added = false
	end
end

function UpdateJesterWheel:UpdateCrewContact()
	local location = { "Crew Contract" }

	local activate_alignment_option = GetJester().memory:GetStartAlignmentOption()
	if activate_alignment_option and not self.start_alignment_added then
		Wheel.AddItem(Wheel.Item:new( { name = "Start Alignment", action = "jester_start_alignment", action_value = "start", reaction = Wheel.Reaction.CLOSE_REMEMBER } ), location)
		self.start_alignment_added = true
	elseif not activate_alignment_option and self.start_alignment_added then
		Wheel.RemoveItem("Start Alignment", location)
		self.start_alignment_added = false
	end

	-- Wingman designation (handled by the WingmanTracker behavior via these events).
	-- The wheel reflects the current designation state:
	--   * no wingman  -> "Wingman - Designate" only (action: wingman_designate)
	--   * designated  -> "Wingman - Find" (action: wingman_find) + "Wingman - Undesignate"
	local tracker = GetJester().behaviors[WingmanTracker]
	local has_wingman = tracker ~= nil and tracker.wingman_id ~= nil

	local desired_primary = has_wingman and "Wingman - Find" or "Wingman - Designate"
	local desired_action  = has_wingman and "wingman_find" or "wingman_designate"
	if self.wingman_primary_name ~= desired_primary then
		if self.wingman_primary_name then
			Wheel.RemoveItem(self.wingman_primary_name, location)
		end
		Wheel.AddItem(Wheel.Item:new( { name = desired_primary, action = desired_action, reaction = Wheel.Reaction.CLOSE_REMEMBER } ), location)
		self.wingman_primary_name = desired_primary
	end

	if has_wingman and not self.wingman_undesignate_shown then
		Wheel.AddItem(Wheel.Item:new( { name = "Wingman - Undesignate", action = "wingman_undesignate", reaction = Wheel.Reaction.CLOSE_REMEMBER } ), location)
		self.wingman_undesignate_shown = true
	elseif not has_wingman and self.wingman_undesignate_shown then
		Wheel.RemoveItem("Wingman - Undesignate", location)
		self.wingman_undesignate_shown = false
	end
end

function UpdateJesterWheel:IdentificationToCategory(identification)
	if identification == RadarTargetIdentification.UNKNOWN then
		return Wheel.Category.TARGET_UNKNOWN
	elseif identification == RadarTargetIdentification.FRIENDLY then
		return Wheel.Category.TARGET_FRIENDLY
	elseif identification == RadarTargetIdentification.NEUTRAL then
		return Wheel.Category.TARGET_NEUTRAL
	else
		return Wheel.Category.TARGET_HOSTILE
	end
end

function UpdateJesterWheel:TargetToItem(target, max_time_after_last_seen, action)
	local identification = target.identification
	target = radar_targets[target.id] or target

	local last_seen_after = Utilities.GetTime().mission_time - target.last_hit_timestamp
	local is_recent_enough = last_seen_after < max_time_after_last_seen

	if not is_recent_enough then
		return nil
	end

	local bearing = math.floor(target.scan_azimuth:ConvertTo(deg).value)
	local range = math.floor(target.scan_range:ConvertTo(NM).value)

	local bearing_text = tostring(math.abs(bearing)) .. "° "
	if bearing < 0 then
		bearing_text = bearing_text .. "L"
	else
		bearing_text = bearing_text .. "R"
	end

	return Wheel.Item:new({
		name = bearing_text .. ", " .. tostring(range) .. " nm",
		action = action,
		action_value = tostring(target.id),
		reaction = Wheel.Reaction.CLOSE_REMEMBER,
		category = self:IdentificationToCategory(identification)
	})
end

function UpdateJesterWheel:UpdateRadarFocusTarget()
	local items = {}
	local i = 1
	-- Bandits
	for _, target in ipairs(RadarState.bandits_by_priority_desc) do
		if i > Wheel.MAX_OUTER_MENU_ITEMS then
			break
		end

		local item = self:TargetToItem(target, s(60), "radar_focus_target")
		if item then
			items[i] = item
			i = i + 1
		end
	end
	-- Not bandits
	for _, target in ipairs(RadarState.not_bandits_by_priority_desc) do
		if i > Wheel.MAX_OUTER_MENU_ITEMS then
			break
		end

		local item = self:TargetToItem(target, s(60), "radar_focus_target")
		if item then
			items[i] = item
			i = i + 1
		end
	end

	local no_known_targets = #items == 0
	if no_known_targets then
		items[1] = Wheel.Item:new({
			name = "No targets",
			action = "radar_focus_target_no_target",
		})
	end

	local wrapping_item = Wheel.Item:new({
		name = "Focus Target",
		category = Wheel.Category.FOCUS,
		outer_menu = Wheel.Menu:new({
			name = "Focus Target",
			items = items,
		}),
	})

	Wheel.ReplaceItem(wrapping_item, "Focus Target", { "Radar" })
end

function UpdateJesterWheel:UpdateRadarLockTarget()
	local items = {}
	local i = 1
	-- Bandits
	for _, target in ipairs(RadarState.bandits_by_priority_desc) do
		if i > Wheel.MAX_OUTER_MENU_ITEMS then
			break
		end

		local item = self:TargetToItem(target, s(3), "radar_lock_target")
		if item then
			items[i] = item
			i = i + 1
		end
	end
	-- Not bandits
	for _, target in ipairs(RadarState.not_bandits_by_priority_desc) do
		if i > Wheel.MAX_OUTER_MENU_ITEMS then
			break
		end

		local item = self:TargetToItem(target, s(3), "radar_lock_target")
		if item then
			items[i] = item
			i = i + 1
		end
	end

	local no_known_targets = #items == 0
	if no_known_targets then
		items[1] = Wheel.Item:new({
			name = "No targets",
			action = "radar_lock_target_no_target",
		})
	end

	local wrapping_item = Wheel.Item:new({
		name = "Lock Target",
		category = Wheel.Category.LOCK,
		outer_menu = Wheel.Menu:new({
			name = "Lock Target",
			items = items,
		}),
	})

	Wheel.ReplaceItem(wrapping_item, "Lock Target", { "Radar" })
end

function UpdateJesterWheel:UpdateRadarAutoGain()
	local location = { "Radar" }

	-- Add the toggle once. The Radar menu always exists, so a simple guard is enough.
	if not self.auto_gain_added then
		Wheel.AddItem(Wheel.Item:new({
			name = "Auto Gain",
			outer_menu = Wheel.Menu:new({
				name = "Auto Gain",
				items = {
					Wheel.Item:new({ name = "On",  action = "radar_auto_gain", action_value = "on",  reaction = Wheel.Reaction.CLOSE_REMEMBER }),
					Wheel.Item:new({ name = "Off", action = "radar_auto_gain", action_value = "off", reaction = Wheel.Reaction.CLOSE_REMEMBER }),
				},
			}),
		}), location)
		self.auto_gain_added = true
		Log("Jester Radar | Auto Gain wheel item added (default is_auto_gain_allowed = " .. tostring(RadarState.is_auto_gain_allowed) .. ")")
	end

	local state_text = RadarState.is_auto_gain_allowed and "Currently: ON" or "Currently: OFF"
	Wheel.SetMenuInfo(state_text, { "Radar", "Auto Gain" })
end

function UpdateJesterWheel:UpdateRadarWheelInfo()
	local cockpit = GetJester():GetCockpit()
	local target_aspect = cockpit:GetManipulator("Radar Target Aspect"):GetState() or "wide"

	local aspect_to_text = {
		wide = "Vc - Wide",
		nose = "Alt - Nose",
		fwd = "Asp - Forward",
		aft = "Vc - Aft",
		tail = "Hdg - Tail",
	}
	local info = aspect_to_text[target_aspect]

	Wheel.SetMenuInfo( info, { "Radar" })
end

function UpdateJesterWheel:SlowUpdates()
	UpdateTacanChannels()
	UpdateTuneAtc()
	UpdateTuneRadioAssets()
	UpdateDivertTGT1ToAirfields()
	UpdateDivertTGT1ToMapMarkers()
	UpdateDivertTGT1ToAssets()
	self:UpdateFlightplans()
end

function UpdateJesterWheel:MediumUpdates()
	self:UpdatePaveSpike()
	self:UpdateCrewContact()
	self:UpdateRadarWheelInfo()
	self:UpdateRadarFocusTarget()
	self:UpdateRadarLockTarget()
	self:UpdateRadarAutoGain()
	self:UpdateRadioWheelInfo()
	self:UpdateTacanWheelInfo()
	self:UpdateNavWheelInfo()
	self:UpdateINSQuickRealignmentOption()
	if not self.was_initialized then
		self:Initialize()
		self.was_initialized = true
	end
end

function UpdateJesterWheel:Constructor()
	Behavior.Constructor(self)

	self:SlowUpdates()

	self.check_slow_updates = Urge:new({
		time_to_release = s(30),
		on_release_function = function()
			self:SlowUpdates()
		end,
		stress_reaction = StressReaction.ignorance,
	})
	self.check_slow_updates:Restart()

	self.check_medium_updates = Urge:new({
		time_to_release = s(5),
		on_release_function = function()
			self:MediumUpdates()
		end,
		stress_reaction = StressReaction.ignorance,
	})
	self.check_medium_updates:Restart()
end

function UpdateJesterWheel:Tick()
	if self.check_slow_updates then
		self.check_slow_updates:Tick()
	end
	if self.check_medium_updates then
		self.check_medium_updates:Tick()
	end
end

function UpdateJesterWheel:Initialize()
	self:GenerateTacanChannelTens()
	self:UpdateFlightplans()
	self:UpdateRadioWheelInfo()
	self:UpdateRadarWheelInfo()
	self:UpdateTacanWheelInfo()
	self:UpdateNavWheelInfo()
	self.was_initialized = true
end

UpdateJesterWheel:Seal()
return UpdateJesterWheel
