-- ============================================================
-- DML Swashbuckler Blocked Skills
--
-- Blocks Rogue Stealth, thrown weapons, bows, and crossbows
-- for Swashbuckler subclass.
--
-- Behavior:
-- - On login: removes blocked spells and blocked auras.
-- - On spell learned: removes blocked spells again if learned later.
-- - On cast: strips blocked aura immediately if somehow cast.
-- ============================================================

local CLASS_ROGUE = 4
local SUBCLASS_SWASHBUCKLER = 5

local PLAYER_EVENT_ON_LOGIN = 3
local PLAYER_EVENT_ON_SPELL_CAST = 5
local PLAYER_EVENT_ON_SPELL_LEARNED = 44

local DEBUG_SWASH_BLOCKED = true

local BLOCKED_SPELLS = {
    -- Stealth ranks
    1784,  -- Stealth Rank 1
    1785,  -- Stealth Rank 2
    1786,  -- Stealth Rank 3
    1787,  -- Stealth Rank 4
    26888, -- Stealth Rank 5

    -- Throw / thrown weapons
    2764,  -- Throw
    2567,  -- Thrown weapon skill

    -- Bows / crossbows
    264,   -- Bows weapon skill
    5011,  -- Crossbows weapon skill

    -- Optional bow/crossbow shoot spells.
    -- If either ID does not exist on your core, RemoveSpell safely ignores it.
    2480,  -- Shoot Bow
    7919,  -- Shoot Crossbow
}

local BLOCKED_SET = {}

for _, spellId in ipairs(BLOCKED_SPELLS) do
    BLOCKED_SET[spellId] = true
end

local function Debug(player, msg)
    if DEBUG_SWASH_BLOCKED and player then
        player:SendBroadcastMessage("|cff00ccff[Swashbuckler]|r " .. tostring(msg))
    end

    if DEBUG_SWASH_BLOCKED then
        print("[DML Swashbuckler Blocked Skills] " .. tostring(msg))
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

local function IsSwashbuckler(player)
    return player
        and player:GetClass() == CLASS_ROGUE
        and GetSubclass(player) == SUBCLASS_SWASHBUCKLER
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
    if not IsSwashbuckler(player) then
        return
    end

    RemoveBlockedAuras(player)
    RemoveBlockedSpells(player)

    Debug(player, "Swashbucklers cannot use Stealth, thrown weapons, bows, or crossbows.")
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

    if not IsSwashbuckler(player) then
        return
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

print("[DML Swashbuckler Blocked Skills] Loaded.")