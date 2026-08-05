-- ============================================================
-- DML Holy Slam Mana Cost
--
-- Adds custom soft mana cost after Holy Slam is cast.
-- Synchronizes dynamic mana tooltip data with DMLCooldownBar.
--
-- Mana cost scaling:
-- Below level 18: 50 mana
-- Below level 28: 100 mana
-- Below level 58: 200 mana
-- Level 58+:      250 mana
--
-- NOTE:
-- This is a soft mana cost. It subtracts mana after the cast.
-- It does not prevent casting if the player only has enough mana
-- for the spell's original base cost.
-- ============================================================

local SPELL_HOLY_SLAM = 37572

local POWER_MANA = 0

local HOLY_SLAM_DEBUG = true
local HOLY_SLAM_MANA_DELAY_MS = 100

local function DmlDebug(message)
    if HOLY_SLAM_DEBUG then
        print("[DML Holy Slam Mana] " .. tostring(message))
    end
end

local function GetDmlSpellId(spell)
    if not spell then
        return 0
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

local function GetDmlName(unit)
    if unit and unit.GetName then
        return unit:GetName()
    end

    return "unknown"
end

local function GetHolySlamManaCost(player)
    local level = player:GetLevel()

    if level < 18 then
        return 50
    elseif level < 28 then
        return 100
    elseif level < 58 then
        return 200
    else
        return 250
    end
end

-- Register Holy Slam dynamic tooltip values with the central DMLCooldownBar sync.
-- 00_dml_tooltip_sync.lua should load before this script.
if DMLCD and DMLCD.RegisterSpell then
    DMLCD.RegisterSpell(SPELL_HOLY_SLAM, {
        hasSpell = SPELL_HOLY_SLAM,

        mana = function(player)
            return GetHolySlamManaCost(player)
        end,
    })
else
    DmlDebug("DMLCD tooltip sync not available during Holy Slam registration.")
end

local function ApplyHolySlamManaCost(player, manaCost, spellId)
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

local function ScheduleHolySlamManaCost(player, manaCost, spellId)
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
        tostring(HOLY_SLAM_MANA_DELAY_MS) ..
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

            ApplyHolySlamManaCost(livePlayer, manaCost, spellId)
        end)

        if not ok then
            DmlDebug("Mana cost event error: " .. tostring(err))
        end
    end, HOLY_SLAM_MANA_DELAY_MS, 1)
end

local function OnHolySlamCast(event, player, spell, skipCheck)
    local spellId = GetDmlSpellId(spell)

    if spellId ~= SPELL_HOLY_SLAM then
        return
    end

    local manaCost = GetHolySlamManaCost(player)

    DmlDebug(
        "Holy Slam cast detected. Player=" ..
        GetDmlName(player) ..
        " SpellId=" ..
        tostring(spellId) ..
        " Level=" ..
        tostring(player:GetLevel()) ..
        " ManaCost=" ..
        tostring(manaCost)
    )


    if DMLCD and DMLCD.SyncSpell then
        DMLCD.SyncSpell(player, SPELL_HOLY_SLAM, false)
    end

    ScheduleHolySlamManaCost(player, manaCost, spellId)
end

RegisterPlayerEvent(5, OnHolySlamCast)

print("[DML Holy Slam Mana] Mana and tooltip sync version loaded.")