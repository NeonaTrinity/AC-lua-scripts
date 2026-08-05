-- ============================================================
-- DML Cleric Righteous Fury -> Multi-Stat Block Value
--
-- If a Cleric has Righteous Fury 25780:
--   * Add 0.5 shield block value per point of Strength
--   * Add 0.5 shield block value per point of Agility
--   * Add 0.5 shield block value per point of Intellect
--
-- Combined formula:
--   floor((Strength + Agility + Intellect) * 0.5)
--
-- If Righteous Fury falls off:
--   * Remove only the block-value bonus added by this script
--
-- Performance:
--   * The Cleric subclass database check occurs only when monitoring starts.
--   * The one-second monitor performs stat/aura reads and simple arithmetic.
-- ============================================================

local CLASS_PRIEST = 5
local SUBCLASS_CLERIC = 1

local SPELL_RIGHTEOUS_FURY = 25780

local PLAYER_EVENT_ON_LOGIN = 3
local PLAYER_EVENT_ON_LOGOUT = 4
local PLAYER_EVENT_ON_SPELL_CAST = 5

local CHECK_DELAY_MS = 500
local MONITOR_DELAY_MS = 1000

-- AzerothCore stat indexes:
--   0 = Strength
--   1 = Agility
--   2 = Stamina
--   3 = Intellect
--   4 = Spirit
local STAT_STRENGTH = 0
local STAT_AGILITY = 1
local STAT_INTELLECT = 3

local BLOCK_VALUE_PER_STAT_POINT = 0.5

-- AzerothCore WotLK UpdateFields.h:
-- PLAYER_SHIELD_BLOCK = UNIT_END + 0x037B = 0x040F.
local PLAYER_SHIELD_BLOCK_FIELD = 0x040F

local DEBUG_RIGHTEOUS_FURY_BLOCK = true

-- Indexed by player GUIDLow.
--
-- The subclass requirement is checked before a monitor starts. Monitor ticks
-- do not query the character database.
local activeByGuid = {}

local function Debug(player, message)
    if DEBUG_RIGHTEOUS_FURY_BLOCK and player then
        player:SendBroadcastMessage(
            "|cffffd700[Righteous Fury]|r " ..
            tostring(message)
        )
    end

    if DEBUG_RIGHTEOUS_FURY_BLOCK then
        print(
            "[DML Cleric Righteous Fury Block] " ..
            tostring(message)
        )
    end
end

local function GetDmlSpellId(spell)
    if not spell then
        return 0
    end

    if type(spell) == "number" then
        return spell
    end

    if type(spell) == "string" then
        return tonumber(spell) or 0
    end

    if spell.GetEntry then
        return spell:GetEntry()
    end

    if spell.GetId then
        return spell:GetId()
    end

    if spell.GetID then
        return spell:GetID()
    end

    return 0
end

local function GetSubclass(player)
    if not player then
        return 0
    end

    local guid = player:GetGUIDLow()

    local result = CharDBQuery(
        "SELECT subclass_id " ..
        "FROM character_subclass " ..
        "WHERE guid = " .. guid .. " " ..
        "LIMIT 1"
    )

    if result then
        return result:GetUInt32(0)
    end

    return 0
end

local function IsCleric(player)
    return player
        and player:GetClass() == CLASS_PRIEST
        and GetSubclass(player) == SUBCLASS_CLERIC
end

local function HasAuraSafe(unit, spellId)
    if not unit or not unit.HasAura then
        return false
    end

    local ok, result = pcall(function()
        return unit:HasAura(spellId)
    end)

    return ok and result
end

local function GetStatSafe(player, statIndex)
    if not player or not player.GetStat then
        return nil
    end

    local ok, value = pcall(function()
        return player:GetStat(statIndex)
    end)

    if not ok or type(value) ~= "number" then
        return nil
    end

    return math.max(0, math.floor(value))
end

local function GetShieldBlockValueSafe(player)
    if not player or not player.GetShieldBlockValue then
        return nil
    end

    local ok, value = pcall(function()
        return player:GetShieldBlockValue()
    end)

    if not ok or type(value) ~= "number" then
        return nil
    end

    return math.max(0, math.floor(value))
end

local function SetShieldBlockValueSafe(player, value)
    if not player or not player.SetUInt32Value then
        return false, "SetUInt32Value is unavailable"
    end

    value = math.max(0, math.floor(value))

    local ok, err = pcall(function()
        player:SetUInt32Value(
            PLAYER_SHIELD_BLOCK_FIELD,
            value
        )
    end)

    return ok, err
end

local function GetOrCreateState(player)
    local guid = player:GetGUIDLow()
    local state = activeByGuid[guid]

    if not state then
        state = {
            lastBonus = 0,
            lastWrittenBlock = nil,
            lastStrength = nil,
            lastAgility = nil,
            lastIntellect = nil
        }

        activeByGuid[guid] = state
    end

    return state
end

local function RefreshClericBlockBonus(player)
    if not player then
        return
    end

    local strength = GetStatSafe(
        player,
        STAT_STRENGTH
    )

    local agility = GetStatSafe(
        player,
        STAT_AGILITY
    )

    local intellect = GetStatSafe(
        player,
        STAT_INTELLECT
    )

    local currentBlock =
        GetShieldBlockValueSafe(player)

    if strength == nil
        or agility == nil
        or intellect == nil
        or currentBlock == nil
    then
        Debug(
            player,
            "Could not read one or more stats or shield block value."
        )

        return
    end

    local state = GetOrCreateState(player)
    local oldBonus = state.lastBonus or 0

    -- If the field still contains the value written by this script, remove
    -- the old scripted bonus to recover the legitimate base block value.
    --
    -- If the core recalculated the field because gear or another aura
    -- changed, currentBlock differs from lastWrittenBlock and is treated as
    -- the newly recalculated base.
    local baseBlock = currentBlock

    if state.lastWrittenBlock ~= nil
        and currentBlock == state.lastWrittenBlock
    then
        baseBlock = math.max(
            0,
            currentBlock - oldBonus
        )
    end

    -- Combining the three stats before rounding preserves half-points shared
    -- between odd stat totals.
    local combinedStats =
        strength + agility + intellect

    local newBonus = math.floor(
        combinedStats *
        BLOCK_VALUE_PER_STAT_POINT
    )

    local desiredBlock =
        baseBlock + newBonus

    if desiredBlock ~= currentBlock then
        local ok, err =
            SetShieldBlockValueSafe(
                player,
                desiredBlock
            )

        if not ok then
            Debug(
                player,
                "Failed to update Cleric block bonus: " ..
                tostring(err)
            )

            return
        end
    end

    local bonusChanged =
        state.lastBonus ~= newBonus
        or state.lastStrength ~= strength
        or state.lastAgility ~= agility
        or state.lastIntellect ~= intellect
        or state.lastWrittenBlock ~= desiredBlock

    state.lastBonus = newBonus
    state.lastWrittenBlock = desiredBlock
    state.lastStrength = strength
    state.lastAgility = agility
    state.lastIntellect = intellect

    if bonusChanged then
        Debug(
            player,
            "Block bonus updated: +" ..
            newBonus ..
            " from " ..
            strength ..
            " Strength, " ..
            agility ..
            " Agility, and " ..
            intellect ..
            " Intellect. Total block value: " ..
            desiredBlock ..
            "."
        )
    end
end

local function RemoveClericBlockBonus(player)
    if not player then
        return
    end

    local guid = player:GetGUIDLow()
    local state = activeByGuid[guid]

    if not state
        or not state.lastBonus
        or state.lastBonus <= 0
    then
        return
    end

    local currentBlock =
        GetShieldBlockValueSafe(player)

    if currentBlock == nil then
        return
    end

    -- Only subtract when the field still matches the value this script last
    -- wrote. If the core already recalculated it, the scripted contribution
    -- is already gone and must not be subtracted again.
    if state.lastWrittenBlock ~= nil
        and currentBlock == state.lastWrittenBlock
    then
        local restoredBlock = math.max(
            0,
            currentBlock - state.lastBonus
        )

        local ok, err =
            SetShieldBlockValueSafe(
                player,
                restoredBlock
            )

        if ok then
            Debug(
                player,
                "Removed +" ..
                state.lastBonus ..
                " Righteous Fury block value. Block value restored to " ..
                restoredBlock ..
                "."
            )
        else
            Debug(
                player,
                "Failed to remove Cleric block bonus: " ..
                tostring(err)
            )
        end
    end

    state.lastBonus = 0
    state.lastWrittenBlock = nil
    state.lastStrength = nil
    state.lastAgility = nil
    state.lastIntellect = nil
end

local function StopMonitor(player)
    if not player then
        return
    end

    activeByGuid[player:GetGUIDLow()] = nil
end

local function MonitorRighteousFury(
    eventId,
    delay,
    repeats,
    player
)
    if not player then
        return
    end

    local guid = player:GetGUIDLow()
    local state = activeByGuid[guid]

    if not state then
        return
    end

    -- No subclass database query here. Eligibility was confirmed before the
    -- monitor began.
    if HasAuraSafe(
        player,
        SPELL_RIGHTEOUS_FURY
    ) then
        RefreshClericBlockBonus(player)

        player:RegisterEvent(
            MonitorRighteousFury,
            MONITOR_DELAY_MS,
            1
        )

        return
    end

    RemoveClericBlockBonus(player)
    StopMonitor(player)
end

local function StartMonitor(player)
    if not player then
        return
    end

    local guid = player:GetGUIDLow()

    if activeByGuid[guid] then
        return
    end

    GetOrCreateState(player)

    player:RegisterEvent(
        MonitorRighteousFury,
        MONITOR_DELAY_MS,
        1
    )
end

local function RepairRighteousFuryBlock(
    player,
    reason
)
    if not player then
        return
    end

    -- This is the only routine that checks the character database.
    if not IsCleric(player) then
        RemoveClericBlockBonus(player)
        StopMonitor(player)
        return
    end

    if HasAuraSafe(
        player,
        SPELL_RIGHTEOUS_FURY
    ) then
        StartMonitor(player)
        RefreshClericBlockBonus(player)
        return
    end

    RemoveClericBlockBonus(player)
    StopMonitor(player)
end

local function OnLogin(event, player)
    if not player then
        return
    end

    player:RegisterEvent(
        function(
            eventId,
            delay,
            repeats,
            livePlayer
        )
            RepairRighteousFuryBlock(
                livePlayer,
                "login"
            )
        end,
        CHECK_DELAY_MS,
        1
    )
end

local function OnLogout(event, player)
    if not player then
        return
    end

    activeByGuid[player:GetGUIDLow()] = nil
end

local function OnSpellCast(
    event,
    player,
    spell,
    skipCheck
)
    if not player or not spell then
        return
    end

    if GetDmlSpellId(spell)
        ~= SPELL_RIGHTEOUS_FURY
    then
        return
    end

    player:RegisterEvent(
        function(
            eventId,
            delay,
            repeats,
            livePlayer
        )
            RepairRighteousFuryBlock(
                livePlayer,
                "cast"
            )
        end,
        CHECK_DELAY_MS,
        1
    )
end

RegisterPlayerEvent(
    PLAYER_EVENT_ON_LOGIN,
    OnLogin
)

RegisterPlayerEvent(
    PLAYER_EVENT_ON_LOGOUT,
    OnLogout
)

RegisterPlayerEvent(
    PLAYER_EVENT_ON_SPELL_CAST,
    OnSpellCast
)

print(
    "[DML Cleric Righteous Fury Block] " ..
    "Cleric Strength + Agility + Intellect block link loaded."
)
