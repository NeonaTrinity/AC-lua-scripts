-- ============================================================
-- DML Venomancer Blocked Druid Skills
--
-- Blocks Cat Form, Bear Form, Dire Bear Form, and Teleport: Moonglade
-- for Venomancer subclass.
--
-- Behavior:
-- - On login: removes blocked spells and blocked auras.
-- - On spell learned: removes blocked spells again if learned later.
-- - On cast: strips blocked aura immediately if somehow cast.
-- ============================================================

local CLASS_DRUID = 11
local SUBCLASS_VENOMANCER = 6

local PLAYER_EVENT_ON_LOGIN = 3
local PLAYER_EVENT_ON_SPELL_CAST = 5
local PLAYER_EVENT_ON_SPELL_LEARNED = 44

local DEBUG_VENOMANCER_BLOCKED = true

local BLOCKED_SPELLS = {
    768,   -- Cat Form
    5487,  -- Bear Form
    9634,  -- Dire Bear Form
    18960, -- Teleport: Moonglade
}

local BLOCKED_SET = {}

for _, spellId in ipairs(BLOCKED_SPELLS) do
    BLOCKED_SET[spellId] = true
end

local function Debug(player, msg)
    if DEBUG_VENOMANCER_BLOCKED and player then
        player:SendBroadcastMessage("|cff33ff66[Venomancer]|r " .. tostring(msg))
    end

    if DEBUG_VENOMANCER_BLOCKED then
        print("[DML Venomancer Blocked Skills] " .. tostring(msg))
    end
end

local function GetDmlSpellId(spell)
    if not spell then return 0 end
    if type(spell) == "number" then return spell end
    if type(spell) == "string" then return tonumber(spell) or 0 end
    if spell.GetEntry then return spell:GetEntry() end
    if spell.GetId then return spell:GetId() end
    if spell.GetID then return spell:GetID() end
    return 0
end

local function GetSubclass(player)
    if not player then
        return 0
    end

    local guid = player:GetGUIDLow()

    local result = CharDBQuery(
        "SELECT subclass_id FROM character_subclass WHERE guid = " ..
        guid ..
        " LIMIT 1"
    )

    if result then
        return result:GetUInt32(0)
    end

    return 0
end

local function IsVenomancer(player)
    return player
        and player:GetClass() == CLASS_DRUID
        and GetSubclass(player) == SUBCLASS_VENOMANCER
end

local function RemoveBlockedAuras(player)
    if not player or not player.RemoveAura then
        return
    end

    for _, spellId in ipairs(BLOCKED_SPELLS) do
        pcall(function()
            if player:HasAura(spellId) then
                player:RemoveAura(spellId)
            end
        end)
    end
end

local function RemoveBlockedSpells(player)
    if not player then
        return
    end

    for _, spellId in ipairs(BLOCKED_SPELLS) do
        pcall(function()
            if player:HasSpell(spellId) then
                player:RemoveSpell(spellId)
            end
        end)
    end
end

local function EnforceBlockedSkills(player, reason)
    if not IsVenomancer(player) then
        return
    end

    RemoveBlockedAuras(player)
    RemoveBlockedSpells(player)

    Debug(player, "Venomancers cannot use Cat Form, Bear Form, Dire Bear Form, or Teleport: Moonglade.")
end

local function OnLogin(event, player)
    if not player then
        return
    end

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            EnforceBlockedSkills(livePlayer, "login")
        end,
        1000,
        1
    )
end

local function OnSpellCast(event, player, spell, skipCheck)
    if not player or not spell then
        return
    end

    local spellId = GetDmlSpellId(spell)

    if not BLOCKED_SET[spellId] then
        return
    end

    if not IsVenomancer(player) then
        return
    end

    if spell.Cancel then
        pcall(function()
            spell:Cancel()
        end)
    end

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            EnforceBlockedSkills(livePlayer, "cast")
        end,
        50,
        1
    )
end

local function OnSpellLearned(event, player, spellId)
    if not player then
        return
    end

    spellId = tonumber(spellId) or 0

    if not BLOCKED_SET[spellId] then
        return
    end

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            EnforceBlockedSkills(livePlayer, "learned")
        end,
        50,
        1
    )
end

RegisterPlayerEvent(PLAYER_EVENT_ON_LOGIN, OnLogin)
RegisterPlayerEvent(PLAYER_EVENT_ON_SPELL_CAST, OnSpellCast)
RegisterPlayerEvent(PLAYER_EVENT_ON_SPELL_LEARNED, OnSpellLearned)

print("[DML Venomancer Blocked Skills] Loaded.")