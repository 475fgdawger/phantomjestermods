---// Copyright (c) 2024 Heatblur Simulations. All rights reserved.

-- tailored for AN/ALR-46

-- TODO:
-- phrases not always playing in the intended order
-- more advanced logic for handling ambiguous contacts (type_2 or category_2 different than 1)
-- maybe add stuff like 'misc/anda', 'misc/andan', 'itsan...'

local Class = require('base.Class')
local Behavior = require('base.Behavior')
local Urge = require('base.Urge')
local StressReaction = require('base.StressReaction')
local SayTask = require('tasks.common.SayTask')
local Utilities = require('base.Utilities')
local Task = require('base.Task')
local CountermeasuresInteractions = require('tasks.common.CountermeasuresInteractions')

local ObserveRWR = Class(Behavior)
ObserveRWR.known_contacts = { }
ObserveRWR.last_contact_report_time_stamp = Utilities.GetTime().mission_time - s(20) -- by adjusting this value we can decide when he starts calling out stuff
ObserveRWR.last_singer_time_stamp = Utilities.GetTime().mission_time - s(99999)

ObserveRWR.minimum_interval_for_new_contact_report = s(30) -- minimum interval between new contact reports (double reports have other criteria)
ObserveRWR.maximum_interval_for_double_report = s(5) -- maximum interval between 2 events required to trigger double report
ObserveRWR.contact_forgetting_time = s(5 * 60)
ObserveRWR.last_contact_report_was_double = false -- 2 contacts were reported

ObserveRWR.maximum_altitude_for_aaa_report = ft(10000)

function GetAltitude()
	return GetJester().awareness:GetObservation("barometric_altitude")
end

function hour_to_string(hour)
    local hours = {
		[1] = 'one',
		[2] = 'two',
		[3] = 'three',
		[4] = 'four',
		[5] = 'five',
		[6] = 'six',
		[7] = 'seven',
		[8] = 'eight',
		[9] = 'nine',
		[10] = 'ten',
		[11] = 'eleven',
		[12] = 'twelve'
	}
	return hours[tonumber(hour)] or 'ERROR: INVALID HOUR'
end

function contains_id(table, id)
	if table == nil then
		return false
	end

    for _, contact in ipairs(table) do
        if contact.id == id then
            return true
        end
    end

    return false
end

function get_id_index(table, id)
    for index, contact in ipairs(table) do
        if contact.id == id then
            return index
        end
    end
end

function is_friendly(contact)
    for _, friendly_symbol in ipairs(rwr_symbols_friendly_only) do
        if friendly_symbol == contact.symbol1 or friendly_symbol == contact.symbol2 then
            return true
        end
    end

    if contact.known_friendly then
        return true
    end

    return false
end

function ObserveRWR:SayNails(hour, subsequent)
    local task = Task:new()

    if not subsequent then
        task:Say('phrases/nails' .. hour_to_string(hour) .. 'oclock')
    else
        task:Say('phrases/andnails')
        task:Say('spotting/' .. hour_to_string(hour) .. 'oclock')
    end

    GetJester():AddTask(task)
end

function ObserveRWR:SayMud(hour, type_1, type_2, subsequent)
    local task = Task:new()

    if not subsequent then
        task:Say('phrases/mud' .. hour_to_string(hour) .. 'oclock')
    else
        task:Say('phrases/andmud')
        task:Say('spotting/' .. hour_to_string(hour) .. 'oclock')
    end

    if type_1 then
        task:Say(type_1)
    end

    GetJester():AddTask(task)
end

function ObserveRWR:SaySinger(hour, type_1, type_2, subsequent)
    local task = Task:new()

    if not subsequent then
        task:Say('phrases/singer' .. hour_to_string(hour) .. 'oclock')
    else
        task:Say('phrases/andsinger')
        task:Say('spotting/' .. hour_to_string(hour) .. 'oclock')
    end

    if type_1 then
        task:Say(type_1)
    end

    GetJester():AddTask(task)
    self.last_singer_time_stamp = Utilities.GetTime().mission_time

    CountermeasuresInteractions.StartDispensingChaffIfAllowed()
end

function ObserveRWR:RememberNewContact(id)
    local new_contact = {}
    new_contact.id = id
    new_contact.activity = ""
    new_contact.last_seen_time_stamp = Utilities.GetTime().mission_time
    table.insert(self.known_contacts, new_contact)
end

function ObserveRWR:ReportNewContact(category_1, category_2, type_1, type_2, hour, subsequent)
    --Log('Jester RWR | reporting: ' .. type_1)
	if category_1 == 'airborne' then
        self:SayNails(hour, subsequent)
    elseif category_1 == 'surface' then
        self:SayMud(hour, type_1, type_2, subsequent)
    else
        return
    end

    self.last_contact_report_time_stamp = Utilities.GetTime().mission_time
end

function ObserveRWR:ForgetOldContacts()
    local current_time = Utilities.GetTime().mission_time
	local remove_older_than_time_stamp = current_time - self.contact_forgetting_time
	Utilities.ArrayRemove(self.known_contacts, function(t, i, _) return t[i].last_seen_time_stamp > remove_older_than_time_stamp end)
end

function ObserveRWR:UpdateContactLastSeenTimestamp(id)
    local index = get_id_index(self.known_contacts, id)
    self.known_contacts[index].last_seen_time_stamp = Utilities.GetTime().mission_time
end

function ObserveRWR:UpdateContactActivity(contact)
    local index = get_id_index(self.known_contacts, contact.id)

    if contact.activity == 'launch' and self.known_contacts[index].activity ~= 'launch' then
        if contact.category_1 == 'surface' then
            if (Utilities.GetTime().mission_time - self.last_singer_time_stamp) > self.maximum_interval_for_double_report then
                self:SaySinger(contact.hour, contact.type_1, contact.type_2, false)
            else
                self:SaySinger(contact.hour, contact.type_1, contact.type_2, true)
            end
        end
    end
    self.known_contacts[index].activity = contact.activity
end

function ObserveRWR:Constructor()
	Behavior.Constructor(self)

	local check_screen = function()
        if rwr_bit_test then
            return
        end

        if rwr_contacts == nil then
            return
        end

        local new_contacts = 0

--         Log('RWR |')
--         for _, unit_type in ipairs(neutral_unit_types) do
--             Log('Jester RWR | Neutral: ' .. unit_type)
--         end
--         for _, unit_type in ipairs(friendly_unit_types) do
--             Log('Jester RWR | Friendly: ' .. unit_type)
--         end
--         for _, unit_type in ipairs(enemy_unit_types) do
--             Log('Jester RWR | Enemy: ' .. unit_type)
--         end
--
--         for _, symbol in ipairs(rwr_symbols_friendly_only) do
--             Log('Jester RWR | friendly symbols: ' .. symbol)
--         end
--         Log(' ')

        for index, contact in ipairs(rwr_contacts) do
--             Log('Jester RWR | Contact Index: ' .. index)
--             Log('Jester RWR | Contact ID: ' .. contact.id)
--             Log('Jester RWR | Contact Symbol 1: ' .. contact.symbol_1)
--             Log('Jester RWR | Contact Symbol 2: ' .. contact.symbol_2)
--             Log('Jester RWR | Contact Type 1: ' .. contact.type_1)
--             Log('Jester RWR | Contact Type 2: ' .. contact.type_2)
--             Log('Jester RWR | Contact Hour: ' .. contact.hour)
--             Log('Jester RWR | Contact Range: ' .. contact.range)
--             Log('Jester RWR | Contact Priority: ' .. contact.priority)
--             Log('Jester RWR | Contact Activity: ' .. contact.activity)
--             if contact.known_friendly then
--                 Log('Jester RWR | Contact is Known Friendly')
--             end
--             Log(' ')

            if contains_id(self.known_contacts, contact.id) then
                -- known contact
                self:UpdateContactLastSeenTimestamp(contact.id)
                self:UpdateContactActivity(contact)
	        else
                -- new contact
		        new_contacts = new_contacts + 1
                self:RememberNewContact(contact.id)

                if is_friendly(contact) then
                    -- don't call out friendly contacts
                   --Log('Jester RWR | skipping friendly contact: ' .. contact.symbol_1)
                elseif contact.subcategory_1 == 'aaa' and contact.subcategory_2 == 'aaa' and GetAltitude() > self.maximum_altitude_for_aaa_report then
                    -- don't call out AAA when flying high
                   --Log('Jester RWR | skipping AAA: ' .. contact.symbol_1)
                else
                    -- proceed to checking time interval criteria
                    local time_from_last_new_contact_report = Utilities.GetTime().mission_time - self.last_contact_report_time_stamp

                    if time_from_last_new_contact_report > self.minimum_interval_for_new_contact_report then
                        self:ReportNewContact(contact.category_1, contact.category_2, contact.type_1, contact.type_2, contact.hour, false)
                        self.last_contact_report_was_double = false
                    elseif not self.last_contact_report_was_double and time_from_last_new_contact_report < self.maximum_interval_for_double_report then
                        self:ReportNewContact(contact.category_1, contact.category_2, contact.type_1, contact.type_2, contact.hour, true)
                        self.last_contact_report_was_double = true
                    end
                end
	        end
        end

        if new_contacts > 0 then
           --Log('Jester RWR | new contacts: ' .. new_contacts)
        end

        self:ForgetOldContacts()
	end

	self.check_urge = Urge:new({
		time_to_release = default_interval,
		on_release_function = check_screen,
		stress_reaction = StressReaction.ignorance,
	})
	self.check_urge:Restart()
end

function ObserveRWR:Tick()
    if self.check_urge then
        self.check_urge:Tick()
    end
end

ObserveRWR:Seal()
return ObserveRWR
