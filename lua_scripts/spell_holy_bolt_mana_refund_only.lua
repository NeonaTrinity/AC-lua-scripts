-- ============================================================
-- DML Holy Bolt Mana Refund
--
-- Holy Bolt Rank 1: 34232
-- Base cost is 90 mana.
-- Refunds 40 mana after casting, for a net cost of 50 mana.
--
-- This script does not modify spell damage.
-- ============================================================

local SPELL_HOLY_BOLT_RANK_1 = 34232
local POWER_MANA = 0

local HOLY_BOLT_REFUND_DEBUG = false

-- Event 5 fires close to spell completion.
-- Wait one short server tick so the normal spell cost is applied first.
local HOLY_BOLT_REFUND_DELAY_MS = 100
local HOLY_BOLT_REFUND_AMOUNT = 40

local function DmlDebug(message)
    if HOLY_BOLT_REFUND_DEBUG then
        print("[DML Holy Bolt Mana Refund] " .. tostring(message))
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

local function RefundManaToLivePlayer(player, refundAmount, spellId)
    if not player or refundAmount <= 0 then
        return false
    end

    if not player.GetPower or not player.GetMaxPower or not player.SetPower then
        DmlDebug("Mana refund failed: missing GetPower/GetMaxPower/SetPower.")
        return false
    end

    local currentMana = player:GetPower(POWER_MANA)
    local maxMana = player:GetMaxPower(POWER_MANA)
    local newMana = currentMana + refundAmount

    if newMana > maxMana then
        newMana = maxMana
    end

    local ok, err = pcall(function()
        -- ALE order is SetPower(value, powerType).
        player:SetPower(newMana, POWER_MANA)
    end)

    if not ok then
        DmlDebug("Mana refund SetPower failed. Error=" .. tostring(err))
        return false
    end

    DmlDebug(
        "Mana refund applied. Player=" ..
        GetDmlName(player) ..
        " SpellId=" ..
        tostring(spellId) ..
        " OldMana=" ..
        tostring(currentMana) ..
        " NewMana=" ..
        tostring(newMana) ..
        " RefundMana=" ..
        tostring(newMana - currentMana)
    )

    return true
end

local function ScheduleHolyBoltManaRefund(player, refundAmount, spellId)
    if not player or refundAmount <= 0 then
        return
    end

    local playerName = GetDmlName(player)

    DmlDebug(
        "Mana refund scheduled. Player=" ..
        tostring(playerName) ..
        " SpellId=" ..
        tostring(spellId) ..
        " DelayMs=" ..
        tostring(HOLY_BOLT_REFUND_DELAY_MS) ..
        " RefundMana=" ..
        tostring(refundAmount)
    )

    CreateLuaEvent(function()
        local ok, err = pcall(function()
            local livePlayer = nil

            if GetPlayerByName then
                livePlayer = GetPlayerByName(playerName)
            end

            if not livePlayer then
                DmlDebug(
                    "Mana refund skipped: player could not be reacquired. Player=" ..
                    tostring(playerName) ..
                    " SpellId=" ..
                    tostring(spellId)
                )
                return
            end

            RefundManaToLivePlayer(livePlayer, refundAmount, spellId)
        end)

        if not ok then
            DmlDebug("Mana refund event error: " .. tostring(err))
        end
    end, HOLY_BOLT_REFUND_DELAY_MS, 1)
end

local function OnHolyBoltCast(event, player, spell, skipCheck)
    local spellId = GetDmlSpellId(spell)

    if spellId ~= SPELL_HOLY_BOLT_RANK_1 then
        return
    end

    ScheduleHolyBoltManaRefund(
        player,
        HOLY_BOLT_REFUND_AMOUNT,
        spellId
    )
end

RegisterPlayerEvent(5, OnHolyBoltCast)

print(
    "[DML Holy Bolt Mana Refund] " ..
    "Rank 1 refund-only version loaded."
)
