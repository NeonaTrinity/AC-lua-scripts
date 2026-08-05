-- ============================================================
-- DML Swashbuckler Sunder -> Sinister Strike / Hemorrhage
--
-- When a Swashbuckler casts Sunder 58567:
--
-- Level 1-29:
--   Spends 35 energy.
--   Casts the best available Sinister Strike rank.
--
-- Level 30+:
--   Casts the correct rank of Hemorrhage based on Rogue level.
--
-- Sinister Strike ranks:
-- Rank 1 / Level 1  / 1752
-- Rank 2 / Level 6  / 1757
-- Rank 3 / Level 14 / 1758
-- Rank 4 / Level 22 / 1759
--
-- Hemorrhage ranks:
-- Rank 1 / Level 30 / 16511
-- Rank 2 / Level 40 / 17347
-- Rank 3 / Level 50 / 17348
-- Rank 4 / Level 60 / 26864
-- Rank 5 / Level 70 / 48660
-- ============================================================

local SPELL_SUNDER = 58567

local SPELL_SINISTER_RANK_1 = 1752
local SPELL_SINISTER_RANK_2 = 1757
local SPELL_SINISTER_RANK_3 = 1758
local SPELL_SINISTER_RANK_4 = 1759

local SPELL_HEMORRHAGE_RANK_1 = 16511
local SPELL_HEMORRHAGE_RANK_2 = 17347
local SPELL_HEMORRHAGE_RANK_3 = 17348
local SPELL_HEMORRHAGE_RANK_4 = 26864
local SPELL_HEMORRHAGE_RANK_5 = 48660

local CLASS_ROGUE = 4
local SUBCLASS_SWASHBUCKLER = 5

local PLAYER_EVENT_ON_SPELL_CAST = 5

local POWER_ENERGY = 3

local SINISTER_ENERGY_COST = 35
local SINISTER_CAST_TRIGGERED = true

local DEBUG_SUNDER_HEMO = false

local function Debug(player, msg)
    if DEBUG_SUNDER_HEMO and player then
        player:SendBroadcastMessage("|cff00ccff[Swashbuckler]|r " .. tostring(msg))
    end

    if DEBUG_SUNDER_HEMO then
        print("[DML Swash Sunder Strike] " .. tostring(msg))
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

local function GetSinisterStrikeSpellForLevel(player)
    local level = player:GetLevel()

    if level >= 22 then
        return SPELL_SINISTER_RANK_4
    elseif level >= 14 then
        return SPELL_SINISTER_RANK_3
    elseif level >= 6 then
        return SPELL_SINISTER_RANK_2
    end

    return SPELL_SINISTER_RANK_1
end

local function GetHemorrhageSpellForLevel(player)
    local level = player:GetLevel()

    if level >= 70 then
        return SPELL_HEMORRHAGE_RANK_5
    elseif level >= 60 then
        return SPELL_HEMORRHAGE_RANK_4
    elseif level >= 50 then
        return SPELL_HEMORRHAGE_RANK_3
    elseif level >= 40 then
        return SPELL_HEMORRHAGE_RANK_2
    elseif level >= 30 then
        return SPELL_HEMORRHAGE_RANK_1
    end

    return 0
end

local function GetSpellTarget(player, spell)
    if spell then
        local methods = {
            "GetTarget",
            "GetUnitTarget",
            "GetTargetUnit",
            "GetExplTargetUnit",
        }

        for _, methodName in ipairs(methods) do
            if spell[methodName] then
                local ok, target = pcall(function()
                    return spell[methodName](spell)
                end)

                if ok and target then
                    return target
                end
            end
        end
    end

    if player and player.GetSelection then
        local ok, target = pcall(function()
            return player:GetSelection()
        end)

        if ok and target then
            return target
        end
    end

    return nil
end

local function IsSameUnit(a, b)
    if not a or not b then
        return false
    end

    if a.GetGUID and b.GetGUID then
        local ok, same = pcall(function()
            return a:GetGUID() == b:GetGUID()
        end)

        if ok then
            return same
        end
    end

    return false
end


local function TrySpendEnergy(player, amount)
    if not player or amount <= 0 then
        return false
    end

    if not player.GetPower or not player.SetPower then
        Debug(player, "Energy cost failed: power API missing.")
        return false
    end

    local currentEnergy = player:GetPower(POWER_ENERGY)

    if currentEnergy < amount then
        Debug(
            player,
            "Not enough energy for Sinister Strike bonus. Need " ..
            tostring(amount) ..
            "."
        )
        return false
    end

    player:SetPower(currentEnergy - amount, POWER_ENERGY)
    return true
end

local function CastSinisterStrike(player, target)
    if not player or not target then
        return
    end

    if IsSameUnit(player, target) then
        Debug(player, "Sinister Strike trigger failed: invalid self target.")
        return
    end

    if not TrySpendEnergy(player, SINISTER_ENERGY_COST) then
        return
    end

    local sinisterSpell = GetSinisterStrikeSpellForLevel(player)

    local ok, err = pcall(function()
        player:CastSpell(target, sinisterSpell, SINISTER_CAST_TRIGGERED)
    end)

    if ok then
        Debug(
            player,
            "Sunder triggered Sinister Strike " ..
            tostring(sinisterSpell) ..
            " for " ..
            tostring(SINISTER_ENERGY_COST) ..
            " energy."
        )
    else
        -- Refund the manual cost if the triggered cast itself fails.
        local currentEnergy = player:GetPower(POWER_ENERGY)
        local maxEnergy = player:GetMaxPower(POWER_ENERGY)
        local refundEnergy = currentEnergy + SINISTER_ENERGY_COST

        if refundEnergy > maxEnergy then
            refundEnergy = maxEnergy
        end

        player:SetPower(refundEnergy, POWER_ENERGY)

        Debug(player, "Sinister Strike trigger failed: " .. tostring(err))
    end
end


local function CastHemorrhage(player, target)
    if not player or not target then
        return
    end

    if IsSameUnit(player, target) then
        Debug(player, "Hemorrhage trigger failed: invalid self target.")
        return
    end

    local hemorrhageSpell = GetHemorrhageSpellForLevel(player)

    if hemorrhageSpell == 0 then
        Debug(player, "Hemorrhage trigger skipped: requires level 30.")
        return
    end

    local ok, err = pcall(function()
        player:CastSpell(target, hemorrhageSpell, true)
    end)

    if ok then
        Debug(player, "Sunder triggered Hemorrhage " .. tostring(hemorrhageSpell) .. ".")
    else
        Debug(player, "Hemorrhage trigger failed: " .. tostring(err))
    end
end

local function CastSunderBonus(player, target)
    if not player or not target then
        return
    end

    if player:GetLevel() < 30 then
        CastSinisterStrike(player, target)
    else
        CastHemorrhage(player, target)
    end
end

local function OnSunderCast(event, player, spell, skipCheck)
    if not player or not spell then
        return
    end

    local spellId = GetDmlSpellId(spell)

    if spellId ~= SPELL_SUNDER then
        return
    end

    if not IsSwashbuckler(player) then
        return
    end

    local target = GetSpellTarget(player, spell)

    if not target then
        Debug(player, "Sunder detected, but no target was found.")
        return
    end

    CastSunderBonus(player, target)
end

RegisterPlayerEvent(
    PLAYER_EVENT_ON_SPELL_CAST,
    OnSunderCast
)

print("[DML Swash Sunder Strike] Swashbuckler Sunder -> Sinister/Hemorrhage script loaded.")