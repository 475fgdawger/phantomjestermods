---// Copyright (c) 2024 Heatblur Simulations. All rights reserved.

-- tailored for AN/ALR-46

-- TODO:
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
require('base.Interactions') -- for Dispatch (radar_nails_search)

local ObserveRWR = Class(Behavior)
ObserveRWR.known_contacts = { }
ObserveRWR.last_contact_report_time_stamp = Utilities.GetTime().mission_time - s(20) -- by adjusting this value we can decide when he starts calling out stuff
ObserveRWR.last_singer_time_stamp = Utilities.GetTime().mission_time - s(99999)

ObserveRWR.minimum_interval_for_new_contact_report = s(30) -- minimum interval between new contact reports (double reports have other criteria)
ObserveRWR.maximum_interval_for_double_report = s(5) -- maximum interval between 2 events required to trigger double report
ObserveRWR.contact_forgetting_time = s(5 * 60)
ObserveRWR.last_contact_report_was_double = false -- 2 contacts were reported

ObserveRWR.maximum_altitude_for_aaa_report = ft(10000)

-- Forward-arc (10-2 o'clock) directed radar search. A search is dispatched both for a
-- brand-new forward-arc nails and when an already-known airborne contact drifts into
-- the arc (see MaybeSearchOnArcEntry). The per-contact cooldown stops a contact sitting
-- on the arc boundary from re-triggering a search every pass.
ObserveRWR.arc_reentry_cooldown = s(15)

-- Task priorities. Jester sorts pending tasks by priority (Jester.lua), so at
-- the previous default of 0 these call-outs queued behind all other chatter and,
-- being equal, were shuffled by the (non-stable) sort. These match the rest of
-- the codebase: routine radar reports use 1, urgent warnings (chaff/damage/eject)
-- use 2.
ObserveRWR.priority_new_contact = 1
ObserveRWR.priority_launch_warning = 2

-- Helpers are kept local so they don't leak into Jester's shared Lua state
-- (a global like GetAltitude is very likely to collide with another behavior).

local function GetAltitude()
	return GetJester().awareness:GetObservation("barometric_altitude")
end

local function hour_to_string(hour)
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

-- Forward arc for the directed radar search: 10, 11, 12, 1, 2 o'clock.
local FORWARD_ARC_HOURS = { [10] = true, [11] = true, [12] = true, [1] = true, [2] = true }

local function contains_id(table, id)
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

local function get_id_index(table, id)
    if table == nil then
        return nil
    end

    for index, contact in ipairs(table) do
        if contact.id == id then
            return index
        end
    end

    return nil
end

local function is_friendly(contact)
    -- NOTE: the RWR contact fields are symbol_1 / symbol_2 (with underscore).
    -- The previous version compared against symbol1 / symbol2, which are always
    -- nil, so the friendly-symbol filter never actually matched.
    if rwr_symbols_friendly_only then
        for _, friendly_symbol in ipairs(rwr_symbols_friendly_only) do
            if friendly_symbol == contact.symbol_1 or friendly_symbol == contact.symbol_2 then
                return true
            end
        end
    end

    if contact.known_friendly then
        return true
    end

    return false
end

-- A "call signature" identifies contacts that would produce an identical spoken
-- call-out, so we can avoid saying e.g. "nails one o'clock ... and nails one
-- o'clock" for two different aircraft sitting at the same clock position.
local function call_signature(category_1, hour, type_1)
    if category_1 == 'airborne' then
        -- "nails" does not speak a type, so any two airborne contacts at the
        -- same clock collapse to the same call-out
        return 'airborne@' .. tostring(hour)
    elseif category_1 == 'surface' then
        -- "mud" speaks the type, so an SA-2 and an SA-6 at the same clock are
        -- both worth calling; two identical emitters are not
        return 'surface@' .. tostring(hour) .. '#' .. tostring(type_1)
    end

    return nil
end

-- True if we have already announced a still-remembered contact that would
-- produce the same spoken call-out as `signature`.
function ObserveRWR:HasAnnouncedEquivalent(signature)
    if signature == nil then
        return false
    end

    for _, contact in ipairs(self.known_contacts) do
        if contact.announced and contact.call_signature == signature then
            return true
        end
    end

    return false
end

-- The Say* / Report* methods below APPEND phrases to a task passed in by the
-- caller rather than each creating and queuing their own task. This is what
-- keeps the phrases in the intended order: within one task the SayActions play
-- in insertion order, whereas separate tasks are re-sorted by priority every
-- Jester cycle (and equal priorities are shuffled by the non-stable sort).
-- They return true when they actually emitted something, so the caller knows
-- whether the task ended up with any content.

function ObserveRWR:SayNails(task, hour, subsequent)
    if not subsequent then
        task:Say('phrases/nails' .. hour_to_string(hour) .. 'oclock')
    else
        task:Say('phrases/andnails')
        task:Say('spotting/' .. hour_to_string(hour) .. 'oclock')
    end

    return true
end

function ObserveRWR:SayMud(task, hour, type_1, type_2, subsequent)
    if not subsequent then
        task:Say('phrases/mud' .. hour_to_string(hour) .. 'oclock')
    else
        task:Say('phrases/andmud')
        task:Say('spotting/' .. hour_to_string(hour) .. 'oclock')
    end

    if type_1 then
        task:Say(type_1)
    end

    return true
end

function ObserveRWR:SaySinger(task, hour, type_1, type_2, subsequent)
    if not subsequent then
        task:Say('phrases/singer' .. hour_to_string(hour) .. 'oclock')
    else
        task:Say('phrases/andsinger')
        task:Say('spotting/' .. hour_to_string(hour) .. 'oclock')
    end

    if type_1 then
        task:Say(type_1)
    end

    self.last_singer_time_stamp = Utilities.GetTime().mission_time

    CountermeasuresInteractions.StartDispensingChaffIfAllowed()

    return true
end

function ObserveRWR:RememberNewContact(id, signature, announced, hour)
    local new_contact = {}
    new_contact.id = id
    new_contact.activity = ""
    new_contact.call_signature = signature
    new_contact.announced = announced or false
    new_contact.last_seen_time_stamp = Utilities.GetTime().mission_time
    new_contact.last_hour = tonumber(hour) -- baseline bearing for forward-arc entry detection
    table.insert(self.known_contacts, new_contact)
end

function ObserveRWR:ReportNewContact(task, category_1, category_2, type_1, type_2, hour, subsequent)
    local reported = false

	if category_1 == 'airborne' then
        reported = self:SayNails(task, hour, subsequent)
        -- Forward-arc nails (10-2 o'clock): ask the radar to search that bearing.
        -- The radar side (UserActions "radar_nails_search") only acts while free-scanning.
        local h = tonumber(hour)
        if h and FORWARD_ARC_HOURS[h] then
            Dispatch("radar_nails_search", tostring(h))
        end
    elseif category_1 == 'surface' then
        reported = self:SayMud(task, hour, type_1, type_2, subsequent)
    else
        return false
    end

    --Log('Jester RWR | reporting: ' .. tostring(type_1))
    self.last_contact_report_time_stamp = Utilities.GetTime().mission_time
    return reported
end

function ObserveRWR:ForgetOldContacts()
    local current_time = Utilities.GetTime().mission_time
	local remove_older_than_time_stamp = current_time - self.contact_forgetting_time
	Utilities.ArrayRemove(self.known_contacts, function(t, i, _) return t[i].last_seen_time_stamp > remove_older_than_time_stamp end)
end

function ObserveRWR:UpdateContactLastSeenTimestamp(index)
    if index then
        self.known_contacts[index].last_seen_time_stamp = Utilities.GetTime().mission_time
    end
end

-- Returns true if it queued a singer call-out onto the singer_task.
function ObserveRWR:UpdateContactActivity(singer_task, index, contact)
    if not index then
        return false
    end

    local emitted = false
    local known = self.known_contacts[index]

    if contact.activity == 'launch' and known.activity ~= 'launch' then
        if contact.category_1 == 'surface' then
            local time_from_last_singer = Utilities.GetTime().mission_time - self.last_singer_time_stamp
            local subsequent = time_from_last_singer <= self.maximum_interval_for_double_report
            emitted = self:SaySinger(singer_task, contact.hour, contact.type_1, contact.type_2, subsequent)
        end
    end

    known.activity = contact.activity
    return emitted
end

-- Fires a directed nails-search when a known airborne contact transitions INTO the
-- forward arc (10-2 o'clock) - i.e. it was outside the arc last pass and is inside it
-- now. Tracks each contact's last hour to detect that edge, and rate-limits per contact
-- (arc_reentry_cooldown) so a contact hovering on the boundary can't spam searches.
function ObserveRWR:MaybeSearchOnArcEntry(index, contact)
    local known = self.known_contacts[index]
    local h     = tonumber(contact.hour)
    local prev  = known.last_hour
    known.last_hour = h -- always keep the latest hour for the next pass's edge detection

    if contact.category_1 ~= 'airborne' or is_friendly(contact) then
        return -- only airborne, non-friendly emitters warrant a search
    end

    local in_arc     = h ~= nil and FORWARD_ARC_HOURS[h] == true
    local was_in_arc = prev ~= nil and FORWARD_ARC_HOURS[prev] == true
    if not (in_arc and not was_in_arc) then
        return -- not a fresh entry into the forward arc
    end

    local now = Utilities.GetTime().mission_time
    if known.last_arc_search and (now - known.last_arc_search) < self.arc_reentry_cooldown then
        return -- searched this contact into the arc very recently; don't spam
    end
    known.last_arc_search = now
    Dispatch("radar_nails_search", tostring(h))
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

        -- Two tasks per pass: routine new-contact reports, and urgent launch
        -- warnings. Distinct priorities mean a launch warning deterministically
        -- precedes a "nails/mud" (the sort is only unstable among equal
        -- priorities), and everything inside a single task stays in order.
        local report_task = Task:new()
        local singer_task = Task:new()
        local report_has_content = false
        local singer_has_content = false

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

            local known_index = get_id_index(self.known_contacts, contact.id)

            if known_index then
                -- known contact
                self:UpdateContactLastSeenTimestamp(known_index)
                if self:UpdateContactActivity(singer_task, known_index, contact) then
                    singer_has_content = true
                end
                -- A known airborne contact that drifts into the forward arc (10-2)
                -- triggers a fresh directed radar search, just like a new nails there.
                self:MaybeSearchOnArcEntry(known_index, contact)
	        else
                -- new contact
                local signature = call_signature(contact.category_1, contact.hour, contact.type_1)

                if is_friendly(contact) then
                    -- don't call out friendly contacts; remember so we don't re-evaluate every tick
                    --Log('Jester RWR | skipping friendly contact: ' .. tostring(contact.symbol_1))
                    self:RememberNewContact(contact.id, signature, false, contact.hour)
                elseif contact.subcategory_1 == 'aaa' and contact.subcategory_2 == 'aaa' and GetAltitude() > self.maximum_altitude_for_aaa_report then
                    -- don't call out AAA when flying high; remember so we don't re-evaluate every tick
                    --Log('Jester RWR | skipping AAA: ' .. tostring(contact.symbol_1))
                    self:RememberNewContact(contact.id, signature, false, contact.hour)
                elseif self:HasAnnouncedEquivalent(signature) then
                    -- an identical call-out (same call & clock, and type for mud) was
                    -- already made for another contact; don't repeat it. Remember this
                    -- one so it's tracked but stays silent.
                    --Log('Jester RWR | skipping duplicate call-out: ' .. tostring(signature))
                    self:RememberNewContact(contact.id, signature, false, contact.hour)
                else
                    -- proceed to checking time interval criteria
                    local time_from_last_new_contact_report = Utilities.GetTime().mission_time - self.last_contact_report_time_stamp

                    if time_from_last_new_contact_report > self.minimum_interval_for_new_contact_report then
                        local reported = self:ReportNewContact(report_task, contact.category_1, contact.category_2, contact.type_1, contact.type_2, contact.hour, false)
                        if reported then report_has_content = true end
                        self.last_contact_report_was_double = false
                        self:RememberNewContact(contact.id, signature, reported, contact.hour)
                        new_contacts = new_contacts + 1
                    elseif not self.last_contact_report_was_double and time_from_last_new_contact_report < self.maximum_interval_for_double_report then
                        local reported = self:ReportNewContact(report_task, contact.category_1, contact.category_2, contact.type_1, contact.type_2, contact.hour, true)
                        if reported then report_has_content = true end
                        self.last_contact_report_was_double = true
                        self:RememberNewContact(contact.id, signature, reported, contact.hour)
                        new_contacts = new_contacts + 1
                    else
                        -- Timing gap: can't announce yet. Deliberately do NOT remember it,
                        -- so it gets another chance on a later pass instead of being
                        -- silently swallowed forever.
                    end
                end
	        end
        end

        -- Add the urgent launch warning first so it wins any priority tie-break,
        -- though Jester's priority sort already guarantees it plays before reports.
        if singer_has_content then
            singer_task:SetPriority(self.priority_launch_warning)
            GetJester():AddTask(singer_task)
        end

        if report_has_content then
            report_task:SetPriority(self.priority_new_contact)
            GetJester():AddTask(report_task)
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
