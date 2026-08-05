-- ============================================================
-- DML Swashbuckler Fake Shot Taunt
--
-- Fake Shot = visible ranged shot / no damage
-- Taunt spell = 37486
--
-- When a Swashbuckler casts Fake Shot on an enemy, the caster
-- immediately casts Taunt on that same target.
-- ============================================================

local SPELL_FAKE_SHOT = 7105
local SPELL_SWASHBUCKLER_TAUNT = 56222

local CLASS_ROGUE = 4
local SUBCLASS_SWASHBUCKLER = 5

local PLAYER_EVENT_ON_SPELL_CAST = 5

local DEBUG_SWASH_TAUNT = false

local function Debug(player, msg)
    if DEBUG_SWASH_TAUNT and player then
        player:SendBroadcastMessage("|cff00ccff[Swashbuckler Taunt]|r " .. tostring(msg))
    end

    if DEBUG_SWASH_TAUNT then
        print("[DML Swashbuckler Taunt] " .. tostring(msg))
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
    if not player then return 0 end

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

local function IsValidTauntTarget(player, target)
    if not player or not target then
        return false
    end

    -- Do not taunt yourself.
    if target.GetGUID and player.GetGUID and target:GetGUID() == player:GetGUID() then
        return false
    end

    -- Prefer hostile check if ALE exposes it.
    if player.IsHostileTo then
        local ok, hostile = pcall(function()
            return player:IsHostileTo(target)
        end)

        if ok then
            return hostile
        end
    end

    -- Fallback: allow creatures/units if hostility check is unavailable.
    return true
end

local function CastSwashbucklerTaunt(player, target)
    if not player or not target then
        return
    end

    local ok, err = pcall(function()
        -- true = triggered cast.
        -- This usually bypasses cast time/resource checks and may bypass range.
        player:CastSpell(target, SPELL_SWASHBUCKLER_TAUNT, true)
    end)

    if ok then
        Debug(player, "Fake Shot triggered Taunt.")
    else
        Debug(player, "Taunt failed: " .. tostring(err))
    end
end

local function OnSwashbucklerFakeShotCast(event, player, spell, skipCheck)
    if not player or not spell then
        return
    end

    local spellId = GetDmlSpellId(spell)

    if spellId ~= SPELL_FAKE_SHOT then
        return
    end

    if SPELL_FAKE_SHOT == 0 then
        Debug(player, "SPELL_FAKE_SHOT is still 0. Add the real Fake Shot spell ID.")
        return
    end

    if not IsSwashbuckler(player) then
        return
    end

    local target = GetSpellTarget(player, spell)

    if not IsValidTauntTarget(player, target) then
        Debug(player, "Fake Shot Taunt failed: invalid target.")
        return
    end

    CastSwashbucklerTaunt(player, target)
end

RegisterPlayerEvent(
    PLAYER_EVENT_ON_SPELL_CAST,
    OnSwashbucklerFakeShotCast
)

print("[DML Swashbuckler Taunt] Fake Shot taunt script loaded.")