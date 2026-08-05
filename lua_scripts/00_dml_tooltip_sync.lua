-- ============================================================
-- DML CooldownBar Tooltip Sync
--
-- Central server-to-addon sync for dynamic spell tooltip values.
--
-- Sends:
-- DMLCD|BONUS|spellId|value
-- DMLCD|MANA|spellId|value
--
-- Designed to be event-driven only:
-- login
-- logout
-- level change
-- spell learned
-- spell cast safety sync from spell scripts
-- ============================================================

DMLCD = DMLCD or {}

DMLCD.RegisteredSpells = DMLCD.RegisteredSpells or {}
DMLCD.SentByGuid = DMLCD.SentByGuid or {}

local DMLCD_DEBUG = true
local DMLCD_LOGIN_SYNC_DELAY_MS = 2000

local function DmlCdDebug(message)
    if DMLCD_DEBUG then
        print("[DML CooldownBar Sync] " .. tostring(message))
    end
end

local function GetDmlGuidLow(unit)
    if not unit then
        return 0
    end

    if unit.GetGUIDLow then
        return unit:GetGUIDLow()
    end

    if unit.GetGUID then
        return unit:GetGUID()
    end

    return 0
end

local function GetDmlName(unit)
    if unit and unit.GetName then
        return unit:GetName()
    end

    return "unknown"
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

local function PlayerHasRequiredSpell(player, spellId, config)
    if not player then
        return false
    end

    local requiredSpell = config.hasSpell or spellId

    if not requiredSpell or requiredSpell == 0 then
        return true
    end

    if player.HasSpell then
        return player:HasSpell(requiredSpell)
    end

    -- If ALE ever lacks HasSpell, do not block sync.
    return true
end

local function GetPlayerCache(guid)
    local playerCache = DMLCD.SentByGuid[guid]

    if not playerCache then
        playerCache = {}
        DMLCD.SentByGuid[guid] = playerCache
    end

    return playerCache
end

local function GetSpellCache(guid, spellId)
    local playerCache = GetPlayerCache(guid)
    local spellCache = playerCache[spellId]

    if not spellCache then
        spellCache = {}
        playerCache[spellId] = spellCache
    end

    return spellCache
end

local function ResolveNumberValue(valueSource, player, spellId, label)
    if valueSource == nil then
        return nil
    end

    if type(valueSource) == "function" then
        local ok, value = pcall(function()
            return valueSource(player, spellId)
        end)

        if not ok then
            DmlCdDebug(
                "Value calculation failed. SpellId=" ..
                tostring(spellId) ..
                " Label=" ..
                tostring(label) ..
                " Error=" ..
                tostring(value)
            )

            return 0
        end

        return tonumber(value) or 0
    end

    return tonumber(valueSource) or 0
end

local function SendCachedValue(player, guid, spellId, cacheKey, protocolKey, value, forceSend)
    if value == nil then
        return
    end

    local spellCache = GetSpellCache(guid, spellId)

    if forceSend or spellCache[cacheKey] ~= value then
        player:SendBroadcastMessage(
            "DMLCD|" ..
            tostring(protocolKey) ..
            "|" ..
            tostring(spellId) ..
            "|" ..
            tostring(value)
        )

        spellCache[cacheKey] = value

        DmlCdDebug(
            "Sent " ..
            tostring(protocolKey) ..
            ". Player=" ..
            GetDmlName(player) ..
            " SpellId=" ..
            tostring(spellId) ..
            " Value=" ..
            tostring(value) ..
            " Force=" ..
            tostring(forceSend)
        )
    end
end

function DMLCD.RegisterSpell(spellId, config)
    spellId = tonumber(spellId) or 0

    if spellId == 0 then
        DmlCdDebug("RegisterSpell failed: invalid spellId.")
        return false
    end

    if type(config) ~= "table" then
        DmlCdDebug("RegisterSpell failed: config must be a table. SpellId=" .. tostring(spellId))
        return false
    end

    DMLCD.RegisteredSpells[spellId] = config

    DmlCdDebug("Registered dynamic tooltip spell. SpellId=" .. tostring(spellId))

    return true
end

function DMLCD.SyncSpell(player, spellId, forceSend)
    spellId = tonumber(spellId) or 0

    if not player or spellId == 0 then
        return
    end

    local config = DMLCD.RegisteredSpells[spellId]

    if not config then
        return
    end

    local guid = GetDmlGuidLow(player)

    if guid == 0 then
        return
    end

    if not PlayerHasRequiredSpell(player, spellId, config) then
        return
    end

    local bonusValue = ResolveNumberValue(config.bonus, player, spellId, "BONUS")
    local manaValue = ResolveNumberValue(config.mana, player, spellId, "MANA")

    SendCachedValue(player, guid, spellId, "bonus", "BONUS", bonusValue, forceSend)
    SendCachedValue(player, guid, spellId, "mana", "MANA", manaValue, forceSend)
end

function DMLCD.SyncPlayer(player, forceSend)
    if not player then
        return
    end

    for spellId, _ in pairs(DMLCD.RegisteredSpells) do
        DMLCD.SyncSpell(player, spellId, forceSend)
    end
end

function DMLCD.ClearPlayer(player)
    local guid = GetDmlGuidLow(player)

    if guid ~= 0 then
        DMLCD.SentByGuid[guid] = nil
    end
end

local function OnDmlCdPlayerLogin(event, player)
    local playerName = GetDmlName(player)

    CreateLuaEvent(function()
        local ok, err = pcall(function()
            local livePlayer = nil

            if GetPlayerByName then
                livePlayer = GetPlayerByName(playerName)
            end

            if not livePlayer then
                return
            end

            DMLCD.SyncPlayer(livePlayer, true)
        end)

        if not ok then
            DmlCdDebug("Login sync error: " .. tostring(err))
        end
    end, DMLCD_LOGIN_SYNC_DELAY_MS, 1)
end

local function OnDmlCdPlayerLogout(event, player)
    DMLCD.ClearPlayer(player)
end

local function OnDmlCdPlayerLevelChange(event, player, oldLevel)
    DMLCD.SyncPlayer(player, false)
end

local function OnDmlCdPlayerLearnSpell(event, player, learnedSpell)
    local learnedSpellId = GetDmlSpellId(learnedSpell)

    if learnedSpellId == 0 then
        return
    end

    for spellId, config in pairs(DMLCD.RegisteredSpells) do
        local requiredSpell = config.hasSpell or spellId

        if learnedSpellId == spellId or learnedSpellId == requiredSpell then
            DMLCD.SyncSpell(player, spellId, true)
        end
    end
end

RegisterPlayerEvent(3, OnDmlCdPlayerLogin)
RegisterPlayerEvent(4, OnDmlCdPlayerLogout)
RegisterPlayerEvent(13, OnDmlCdPlayerLevelChange)
RegisterPlayerEvent(44, OnDmlCdPlayerLearnSpell)

print("[DML CooldownBar Sync] Central tooltip sync loaded.")