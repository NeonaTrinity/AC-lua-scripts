-- ============================================================
-- DML Blood Bolt Mana Refund
--
-- Spell: Blood Bolt 41229
--
-- Refund scaling:
-- Level 0-4:   70 mana
-- Level 5-9:   50 mana
-- Level 10-15: 30 mana
-- Level 16-20: 20 mana
-- Level 21+:    0 mana
--
-- No damage scaling here. Damage is handled by the module.
-- ============================================================

local SPELL_BLOOD_BOLT = 41229

local POWER_MANA = 0

local BLOOD_BOLT_DEBUG = TRUE
local BLOOD_BOLT_REFUND_DELAY_MS = 100

local function DmlDebug(message)
    if BLOOD_BOLT_DEBUG then
        print("[DML Blood Bolt Refund] " .. tostring(message))
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

local function GetDmlName(unit)
    if unit and unit.GetName then
        return unit:GetName()
    end

    return "unknown"
end

local function GetBloodBoltRefundMana(player)
    local level = player:GetLevel()

    if level <= 4 then
        return 70
    elseif level <= 9 then
        return 50
    elseif level <= 15 then
        return 30
    elseif level <= 20 then
        return 20
    else
        return 0
    end
end

local function ApplyBloodBoltRefund(player, refundMana, spellId)
    if not player or refundMana <= 0 then
        return false
    end

    if not player.GetPower or not player.SetPower then
        DmlDebug("Mana refund failed: missing GetPower/SetPower.")
        return false
    end

    local currentMana = player:GetPower(POWER_MANA)
    local maxMana = player:GetMaxPower(POWER_MANA)
    local newMana = currentMana + refundMana

    if newMana > maxMana then
        newMana = maxMana
    end

    local actualRefund = newMana - currentMana

    if actualRefund <= 0 then
        return true
    end

    local ok, err = pcall(function()
        -- ALE order is SetPower(value, powerType)
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
        tostring(actualRefund)
    )

    return true
end

local function ScheduleBloodBoltRefund(player, refundMana, spellId)
    if not player or refundMana <= 0 then
        return
    end

    local playerName = GetDmlName(player)

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

            ApplyBloodBoltRefund(livePlayer, refundMana, spellId)
        end)

        if not ok then
            DmlDebug("Mana refund event error: " .. tostring(err))
        end
    end, BLOOD_BOLT_REFUND_DELAY_MS, 1)
end

local function OnBloodBoltCast(event, player, spell, skipCheck)
    local spellId = GetDmlSpellId(spell)

    if spellId ~= SPELL_BLOOD_BOLT then
        return
    end

    local refundMana = GetBloodBoltRefundMana(player)

    if refundMana <= 0 then
        return
    end

    DmlDebug(
        "Blood Bolt cast detected. Player=" ..
        GetDmlName(player) ..
        " Level=" ..
        tostring(player:GetLevel()) ..
        " RefundMana=" ..
        tostring(refundMana)
    )

    -- Event 5 fires close to completion.
    -- Wait one short server tick so the refund happens after the spell cost is applied.
    ScheduleBloodBoltRefund(player, refundMana, spellId)
end

RegisterPlayerEvent(5, OnBloodBoltCast)

print("[DML Blood Bolt Refund] Mana refund script loaded.")