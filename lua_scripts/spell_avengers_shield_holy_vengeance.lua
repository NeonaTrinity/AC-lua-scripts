-- ============================================================
-- DML Paladin Avenger's Shield -> Holy Vengeance
--
-- When Paladin spell 37554 (Avenger's Shield) successfully deals
-- damage to an enemy, the Paladin trigger-casts Holy Vengeance
-- 31803 on that target.
--
-- Multi-target behavior:
--   * Every successful Avenger's Shield bounce is handled.
--   * Each unique target receives one Holy Vengeance application
--     from that Avenger's Shield cast.
--   * The Paladin is recorded as the Holy Vengeance aura caster.
--   * Holy Vengeance keeps its native duration and stack limit.
-- ============================================================

local CLASS_PALADIN = 2

local SPELL_AVENGERS_SHIELD = 37554
local SPELL_HOLY_VENGEANCE = 31803

local SPELL_EVENT_ON_CAST = 2
local PLAYER_EVENT_ON_LOGOUT = 4
local PLAYER_EVENT_ON_MODIFY_SPELL_DAMAGE_TAKEN = 70

-- Leaves enough time for the shield projectile and all chain bounces
-- to reach their targets.
local AVENGERS_SHIELD_HIT_WINDOW_MS = 4000

local DEBUG_AVENGERS_SHIELD = false

-- Indexed by Paladin GUIDLow.
-- Each state belongs to one Avenger's Shield cast.
local pendingByGuid = {}
local castSerialByGuid = {}

local function Debug(player, message)
    if not DEBUG_AVENGERS_SHIELD then
        return
    end

    if player and player.SendBroadcastMessage then
        player:SendBroadcastMessage(
            "|cffffcc33[Avenger's Shield]|r " .. tostring(message)
        )
    end

    print(
        "[DML Avenger's Shield Holy Vengeance] " ..
        tostring(message)
    )
end

local function GetPlayerCaster(caster)
    if not caster or not caster.IsPlayer or not caster.ToPlayer then
        return nil
    end

    local okIsPlayer, isPlayer = pcall(function()
        return caster:IsPlayer()
    end)

    if not okIsPlayer or not isPlayer then
        return nil
    end

    local okPlayer, player = pcall(function()
        return caster:ToPlayer()
    end)

    if not okPlayer then
        return nil
    end

    return player
end

local function GetSpellId(spell)
    if not spell then
        return 0
    end

    if type(spell) == "number" then
        return spell
    end

    if spell.GetEntry then
        local ok, spellId = pcall(function()
            return spell:GetEntry()
        end)

        if ok and type(spellId) == "number" then
            return spellId
        end
    end

    return 0
end

local function IsAvengersShieldSpellInfo(spellInfo)
    if not spellInfo or not spellInfo.GetName then
        return false
    end

    local ok, name = pcall(function()
        return spellInfo:GetName()
    end)

    return ok and name == "Avenger's Shield"
end

local function GetTargetKey(target)
    if not target or not target.GetGUIDLow or not target.GetTypeId then
        return nil
    end

    local okGuid, guidLow = pcall(function()
        return target:GetGUIDLow()
    end)

    local okType, typeId = pcall(function()
        return target:GetTypeId()
    end)

    if not okGuid or not okType then
        return nil
    end

    return tostring(typeId) .. ":" .. tostring(guidLow)
end

local function ClearPending(playerGuidLow, serial)
    local state = pendingByGuid[playerGuidLow]

    if not state or state.serial ~= serial then
        return
    end

    pendingByGuid[playerGuidLow] = nil
end

local function OnAvengersShieldCast(
    event,
    caster,
    spell,
    skipCheck
)
    local player = GetPlayerCaster(caster)

    if not player or not spell then
        return
    end

    if player:GetClass() ~= CLASS_PALADIN then
        return
    end

    if GetSpellId(spell) ~= SPELL_AVENGERS_SHIELD then
        return
    end

    local playerGuidLow = player:GetGUIDLow()
    local serial = (castSerialByGuid[playerGuidLow] or 0) + 1

    castSerialByGuid[playerGuidLow] = serial
    pendingByGuid[playerGuidLow] = {
        serial = serial,
        hitTargets = {},
    }

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            ClearPending(playerGuidLow, serial)
        end,
        AVENGERS_SHIELD_HIT_WINDOW_MS,
        1
    )

    Debug(
        player,
        "Tracking Avenger's Shield cast " .. tostring(serial) .. "."
    )
end

local function ApplyHolyVengeance(player, target)
    local ok, err = pcall(function()
        -- The Paladin is explicitly the spell caster. Triggered=true
        -- makes the automatic application instant and free while
        -- preserving the Paladin as the Holy Vengeance aura owner.
        player:CastSpell(
            target,
            SPELL_HOLY_VENGEANCE,
            true
        )
    end)

    if not ok then
        Debug(
            player,
            "Failed to apply Holy Vengeance: " .. tostring(err)
        )
        return false
    end

    if DEBUG_AVENGERS_SHIELD then
        local stackText = ""

        pcall(function()
            local aura = target:GetAura(SPELL_HOLY_VENGEANCE)

            if aura and aura.GetStackAmount then
                stackText =
                    " Stack count now: " ..
                    tostring(aura:GetStackAmount()) ..
                    "."
            end
        end)

        Debug(
            player,
            "Avenger's Shield applied one Holy Vengeance stack." ..
            stackText
        )
    end

    return true
end

local function OnSpellDamage(
    event,
    player,
    target,
    damage,
    spellInfo
)
    if not player or not target or not spellInfo then
        return
    end

    if player:GetClass() ~= CLASS_PALADIN then
        return
    end

    if type(damage) ~= "number" or damage <= 0 then
        return
    end

    local playerGuidLow = player:GetGUIDLow()
    local state = pendingByGuid[playerGuidLow]

    if not state then
        return
    end

    -- Event 70 exposes SpellInfo but not a reliable numeric spell ID.
    -- The spell-specific ON_CAST hook proves spell 37554 was cast, and
    -- the name check confirms this damage event belongs to its hit.
    if not IsAvengersShieldSpellInfo(spellInfo) then
        return
    end

    local targetKey = GetTargetKey(target)

    if not targetKey or state.hitTargets[targetKey] then
        return
    end

    -- Mark before the triggered cast so secondary events cannot apply
    -- another stack to the same target from this shield cast.
    state.hitTargets[targetKey] = true

    ApplyHolyVengeance(player, target)
end

local function OnLogout(event, player)
    if not player then
        return
    end

    local playerGuidLow = player:GetGUIDLow()

    pendingByGuid[playerGuidLow] = nil
    castSerialByGuid[playerGuidLow] = nil
end

RegisterSpellEvent(
    SPELL_AVENGERS_SHIELD,
    SPELL_EVENT_ON_CAST,
    OnAvengersShieldCast
)

RegisterPlayerEvent(
    PLAYER_EVENT_ON_MODIFY_SPELL_DAMAGE_TAKEN,
    OnSpellDamage
)

RegisterPlayerEvent(
    PLAYER_EVENT_ON_LOGOUT,
    OnLogout
)

print(
    "[DML Avenger's Shield Holy Vengeance] " ..
    "Spell 37554 now applies one Paladin-owned Holy Vengeance stack to every target hit."
)
