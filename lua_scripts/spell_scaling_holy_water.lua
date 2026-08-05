-- ============================================================
-- DML Monster Slayer's Holy Water Scaling
--
-- Spell: Monster Slayer's Holy Water 54086
--
-- Adds custom soft mana cost and bonus damage scaling.
--
-- Mana cost scaling:
-- Below level 44: 0 mana
-- Level 44-48:    150 mana
-- Level 49-53:    180 mana
-- Level 54-58:    210 mana
-- Level 59:       230 mana
-- Level 60+:      250 mana
--
-- Damage scaling:
-- Below level 44: +0 damage
-- Level 44-48:    +0 damage
-- Level 49-53:    +25 damage
-- Level 54-58:    +50 damage
-- Level 59:       +75 damage
-- Level 60+:      +100 damage
--
-- Notes:
-- This is a soft mana cost. It subtracts mana after the cast.
-- It does not prevent casting if the player has less mana than the custom cost.
-- DMLCooldownBar tooltip sync is supported through 00_dml_tooltip_sync.lua.
-- ============================================================

local SPELL_MONSTER_SLAYER_HOLY_WATER = 54086

local POWER_MANA = 0

local HOLY_WATER_DEBUG = false
local HOLY_WATER_MANA_DELAY_MS = 100
local HOLY_WATER_PENDING_TIMEOUT_MS = 5000

local pendingHolyWaterByGuid = {}
local holyWaterQueueToken = 0

local function DmlDebug(message)
    if HOLY_WATER_DEBUG then
        print("[DML Holy Water Scaling] " .. tostring(message))
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

local function GetHolyWaterManaCost(player)
    local level = player:GetLevel()

    if level < 1 then
        return 0
    elseif level < 49 then
        return 150
    elseif level < 54 then
        return 180
    elseif level < 59 then
        return 210
    elseif level < 60 then
        return 230
    else
        return 250
    end
end

local function GetHolyWaterBonusDamage(player)
    local level = player:GetLevel()

    if level < 44 then
        return 0
    elseif level < 49 then
        return 0
    elseif level < 54 then
        return 25
    elseif level < 59 then
        return 50
    elseif level < 60 then
        return 75
    else
        return 100
    end
end

local function ApplyHolyWaterManaCost(player, manaCost, spellId)
    if not player or manaCost <= 0 then
        return false
    end

    if not player.GetPower or not player.SetPower then
        DmlDebug("Mana cost failed: missing GetPower/SetPower.")
        return false
    end

    local currentMana = player:GetPower(POWER_MANA)
    local newMana = currentMana - manaCost

    if newMana < 0 then
        newMana = 0
    end

    local ok, err = pcall(function()
        -- ALE order is SetPower(value, powerType)
        player:SetPower(newMana, POWER_MANA)
    end)

    if not ok then
        DmlDebug("Mana cost SetPower failed. Error=" .. tostring(err))
        return false
    end

    DmlDebug(
        "Mana cost applied. Player=" ..
        GetDmlName(player) ..
        " SpellId=" ..
        tostring(spellId) ..
        " OldMana=" ..
        tostring(currentMana) ..
        " NewMana=" ..
        tostring(newMana) ..
        " ManaCost=" ..
        tostring(currentMana - newMana)
    )

    return true
end

local function ScheduleHolyWaterManaCost(player, manaCost, spellId)
    if not player or manaCost <= 0 then
        return
    end

    local playerName = GetDmlName(player)

    DmlDebug(
        "Mana cost scheduled. Player=" ..
        tostring(playerName) ..
        " SpellId=" ..
        tostring(spellId) ..
        " DelayMs=" ..
        tostring(HOLY_WATER_MANA_DELAY_MS) ..
        " ManaCost=" ..
        tostring(manaCost)
    )

    CreateLuaEvent(function()
        local ok, err = pcall(function()
            local livePlayer = nil

            if GetPlayerByName then
                livePlayer = GetPlayerByName(playerName)
            end

            if not livePlayer then
                DmlDebug(
                    "Mana cost skipped: player could not be reacquired. Player=" ..
                    tostring(playerName) ..
                    " SpellId=" ..
                    tostring(spellId)
                )
                return
            end

            ApplyHolyWaterManaCost(livePlayer, manaCost, spellId)
        end)

        if not ok then
            DmlDebug("Mana cost event error: " .. tostring(err))
        end
    end, HOLY_WATER_MANA_DELAY_MS, 1)
end

local function ApplyHolyWaterBonusDamage(player, target, bonusDamage)
    if bonusDamage <= 0 then
        return true
    end

    if not player or not target then
        return false
    end

    if not player.DealDamage then
        DmlDebug("Bonus damage failed: player object does not expose DealDamage.")
        return false
    end

    local ok, err = pcall(function()
        player:DealDamage(target, bonusDamage)
    end)

    if ok then
        return true
    end

    DmlDebug("Bonus DealDamage failed: " .. tostring(err))
    return false
end

local function OnHolyWaterCast(event, player, spell, skipCheck)
    local spellId = GetDmlSpellId(spell)

    if spellId ~= SPELL_MONSTER_SLAYER_HOLY_WATER then
        return
    end

    local guid = GetDmlGuidLow(player)

    if guid == 0 then
        return
    end

    holyWaterQueueToken = holyWaterQueueToken + 1

    local token = holyWaterQueueToken

    pendingHolyWaterByGuid[guid] = {
        spellId = spellId,
        token = token,
    }

    local manaCost = GetHolyWaterManaCost(player)

    DmlDebug(
        "Holy Water cast detected. Player=" ..
        GetDmlName(player) ..
        " Guid=" ..
        tostring(guid) ..
        " SpellId=" ..
        tostring(spellId) ..
        " Level=" ..
        tostring(player:GetLevel()) ..
        " ManaCost=" ..
        tostring(manaCost) ..
        " BonusDamage=" ..
        tostring(GetHolyWaterBonusDamage(player))
    )

    if DMLCD and DMLCD.SyncSpell then
        DMLCD.SyncSpell(player, SPELL_MONSTER_SLAYER_HOLY_WATER, false)
    end

    ScheduleHolyWaterManaCost(player, manaCost, spellId)

    CreateLuaEvent(function()
        local pending = pendingHolyWaterByGuid[guid]

        if pending and pending.token == token then
            pendingHolyWaterByGuid[guid] = nil

            DmlDebug(
                "Pending Holy Water expired. Guid=" ..
                tostring(guid) ..
                " SpellId=" ..
                tostring(spellId) ..
                " Token=" ..
                tostring(token)
            )
        end
    end, HOLY_WATER_PENDING_TIMEOUT_MS, 1)
end

local function OnPlayerDealDamage(event, player, target, damage, damagetype)
    local guid = GetDmlGuidLow(player)

    if guid == 0 then
        return damage
    end

    local pending = pendingHolyWaterByGuid[guid]

    if not pending then
        return damage
    end

    pendingHolyWaterByGuid[guid] = nil

    local bonusDamage = GetHolyWaterBonusDamage(player)
    local totalExpected = damage + bonusDamage

    local bonusApplied = ApplyHolyWaterBonusDamage(player, target, bonusDamage)

    if bonusApplied then
        DmlDebug(
            "Holy Water bonus applied as second damage hit. Player=" ..
            GetDmlName(player) ..
            " BaseDamage=" ..
            tostring(damage) ..
            " BonusDamage=" ..
            tostring(bonusDamage) ..
            " TotalExpected=" ..
            tostring(totalExpected) ..
            " DamageType=" ..
            tostring(damagetype) ..
            " Target=" ..
            GetDmlName(target)
        )

        -- Return original damage because bonus was applied separately.
        return damage
    end

    DmlDebug(
        "Holy Water bonus hit failed; falling back to combined damage. Player=" ..
        GetDmlName(player) ..
        " BaseDamage=" ..
        tostring(damage) ..
        " BonusDamage=" ..
        tostring(bonusDamage) ..
        " NewDamage=" ..
        tostring(totalExpected) ..
        " DamageType=" ..
        tostring(damagetype) ..
        " Target=" ..
        GetDmlName(target)
    )

    -- Fallback keeps total damage correct.
    return totalExpected
end

local function OnHolyWaterPlayerLogout(event, player)
    local guid = GetDmlGuidLow(player)

    if guid ~= 0 then
        pendingHolyWaterByGuid[guid] = nil
    end
end

-- Register Monster Slayer's Holy Water dynamic tooltip values with the central DMLCooldownBar sync.
-- 00_dml_tooltip_sync.lua should load before this script.
if DMLCD and DMLCD.RegisterSpell then
    DMLCD.RegisterSpell(SPELL_MONSTER_SLAYER_HOLY_WATER, {
        hasSpell = SPELL_MONSTER_SLAYER_HOLY_WATER,

        bonus = function(player)
            return GetHolyWaterBonusDamage(player)
        end,

        mana = function(player)
            return GetHolyWaterManaCost(player)
        end,
    })
else
    DmlDebug("DMLCD tooltip sync not available during Holy Water registration.")
end

RegisterPlayerEvent(4, OnHolyWaterPlayerLogout)
RegisterPlayerEvent(5, OnHolyWaterCast)
RegisterPlayerEvent(72, OnPlayerDealDamage)

print("[DML Holy Water Scaling] Damage, mana, and tooltip sync version loaded.")
