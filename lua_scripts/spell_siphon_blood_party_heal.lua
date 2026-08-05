-- spell_siphon_blood_party_heal.lua
--
-- Siphon Blood: additional Cultist party healing
--
-- Normal spell behavior remains unchanged:
--   * Siphon Blood damages enemies.
--   * The caster receives the spell's normal self-heal.
--
-- This script additionally:
--   * Refunds 50 mana if cast below level 40.
--   * Totals the damage dealt immediately after the cast.
--   * Finds the two lowest-health party members within 30 yards.
--   * Excludes the caster.
--   * Heals each selected ally for 50% of the total damage dealt.

local SPELL_SIPHON_BLOOD = 49701

local CLASS_WARLOCK = 9
local SUBCLASS_CULTIST = 4

local PLAYER_EVENT_ON_SPELL_CAST = 5
local PLAYER_EVENT_ON_LOGOUT = 4
local PLAYER_EVENT_ON_DEAL_DAMAGE = 72

local HEAL_RANGE = 30
local MAX_EXTRA_TARGETS = 2
local ALLY_HEAL_MULTIPLIER = 0.50

-- Siphon Blood is an immediate cone attack.
-- This brief window collects all cone-target damage events.
local DAMAGE_CAPTURE_WINDOW_MS = 350

-- Mana refund support.
local POWER_MANA = 0
local SIPHON_BLOOD_REFUND_MANA = 50
local SIPHON_BLOOD_REFUND_MAX_LEVEL = 39
local SIPHON_BLOOD_REFUND_DELAY_MS = 100

-- Leave this enabled while testing.
local DEBUG_MESSAGES = false

-- Indexed by player GUIDLow.
local activeSiphons = {}
local castSerialByGuid = {}

local function IsBot(player)
    if player and player.IsBot then
        return player:IsBot()
    end

    return false
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

local function IsCultist(player)
    if not player then
        return false
    end

    return player:GetClass() == CLASS_WARLOCK
        and GetSubclass(player) == SUBCLASS_CULTIST
end

local function GetCastSpellId(spell)
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

local function DebugMessage(player, message)
    if DEBUG_MESSAGES and player then
        player:SendBroadcastMessage(
            "|cff8b0000[Siphon Blood]|r " .. message
        )
    end
end

local function GetEligiblePartyMembers(caster)
    local eligible = {}

    if not caster then
        return eligible
    end

    local group = caster:GetGroup()

    if not group then
        return eligible
    end

    local casterGuid = caster:GetGUID()
    local members = group:GetMembers()

    if not members then
        return eligible
    end

    for _, member in pairs(members) do
        if member
            and member:GetGUID() ~= casterGuid
            and member:IsAlive()
            and member:GetMaxHealth() > 0
            and member:GetHealth() < member:GetMaxHealth()
            and caster:IsWithinDistInMap(
                member,
                HEAL_RANGE,
                true
            )
        then
            local health = member:GetHealth()
            local maxHealth = member:GetMaxHealth()
            local healthPercent = health / maxHealth
            local missingHealth = maxHealth - health

            table.insert(eligible, {
                player = member,
                healthPercent = healthPercent,
                missingHealth = missingHealth
            })
        end
    end

    -- Lowest health percentage first.
    -- If two players have the same percentage, prioritize
    -- the player missing more raw health.
    table.sort(eligible, function(a, b)
        if a.healthPercent == b.healthPercent then
            return a.missingHealth > b.missingHealth
        end

        return a.healthPercent < b.healthPercent
    end)

    return eligible
end

local function HealLowestPartyMembers(caster, totalDamage)
    if not caster or totalDamage <= 0 then
        return
    end

    local group = caster:GetGroup()

    -- Solo casting keeps only the spell's normal caster heal.
    if not group then
        DebugMessage(
            caster,
            "No party found; no additional allies healed."
        )

        return
    end

    local candidates = GetEligiblePartyMembers(caster)

    if #candidates == 0 then
        DebugMessage(
            caster,
            "No injured party members were in range."
        )

        return
    end

    local healAmount = math.floor(
        totalDamage * ALLY_HEAL_MULTIPLIER
    )

    if healAmount < 1 then
        return
    end

    local targetsHealed = math.min(
        MAX_EXTRA_TARGETS,
        #candidates
    )

    for index = 1, targetsHealed do
        local target = candidates[index].player

        if target
            and target:IsAlive()
            and target:GetHealth() < target:GetMaxHealth()
            and caster:IsWithinDistInMap(
                target,
                HEAL_RANGE,
                true
            )
        then
            caster:DealHeal(
                target,
                SPELL_SIPHON_BLOOD,
                healAmount,
                false
            )

            DebugMessage(
                caster,
                "Healed " ..
                target:GetName() ..
                " for up to " ..
                healAmount ..
                "."
            )
        end
    end
end

local function ScheduleSiphonBloodManaRefund(player)
    if not player then
        return
    end

    if player:GetLevel() > SIPHON_BLOOD_REFUND_MAX_LEVEL then
        return
    end

    -- Use a player-bound timer so ALE supplies a valid Player
    -- object when the delayed callback runs.
    player:RegisterEvent(
        function(eventId, delay, repeats, caster)
            if not caster then
                return
            end

            if not caster.GetPower or not caster.SetPower or not caster.GetMaxPower then
                DebugMessage(
                    caster,
                    "Mana refund failed: missing GetPower/SetPower/GetMaxPower."
                )

                return
            end

            local currentMana = caster:GetPower(POWER_MANA)
            local maxMana = caster:GetMaxPower(POWER_MANA)
            local newMana = currentMana + SIPHON_BLOOD_REFUND_MANA

            if newMana > maxMana then
                newMana = maxMana
            end

            local actualRefund = newMana - currentMana

            if actualRefund <= 0 then
                return
            end

            -- ALE order is SetPower(value, powerType)
            caster:SetPower(newMana, POWER_MANA)

            DebugMessage(
                caster,
                "Refunded " ..
                actualRefund ..
                " mana."
            )
        end,
        SIPHON_BLOOD_REFUND_DELAY_MS,
        1
    )
end

local function FinishSiphonCapture(
    caster,
    casterGuid,
    castSerial
)
    local state = activeSiphons[casterGuid]

    -- Ignore an older timer if another cast replaced it.
    if not state or state.castSerial ~= castSerial then
        return
    end

    activeSiphons[casterGuid] = nil

    -- This caster is supplied by Player:RegisterEvent and should
    -- be valid for the duration of this callback.
    if not caster then
        return
    end

    local totalDamage = state.totalDamage or 0

    DebugMessage(
        caster,
        "Captured total damage: " .. totalDamage
    )

    HealLowestPartyMembers(
        caster,
        totalDamage
    )
end

local function OnSiphonBloodCast(
    event,
    player,
    spell,
    skipCheck
)
    if not player or not spell then
        return
    end

    local spellId = GetCastSpellId(spell)

    if spellId ~= SPELL_SIPHON_BLOOD then
        return
    end

    if IsBot(player) then
        return
    end

    if not IsCultist(player) then
        return
    end

    ScheduleSiphonBloodManaRefund(player)

    local guid = player:GetGUIDLow()

    local castSerial =
        (castSerialByGuid[guid] or 0) + 1

    castSerialByGuid[guid] = castSerial

    activeSiphons[guid] = {
        castSerial = castSerial,
        totalDamage = 0
    }

    DebugMessage(
        player,
        "Damage capture started."
    )

    -- Use a player-bound timer so ALE supplies a valid Player
    -- object when the delayed callback runs.
    --
    -- Capturing the original player userdata inside CreateLuaEvent
    -- caused the invalidated-object error.
    player:RegisterEvent(
        function(eventId, delay, repeats, caster)
            FinishSiphonCapture(
                caster,
                guid,
                castSerial
            )
        end,
        DAMAGE_CAPTURE_WINDOW_MS,
        1
    )
end

local function OnCultistDealDamage(
    event,
    player,
    target,
    damage,
    damageType
)
    if not player then
        return
    end

    local guid = player:GetGUIDLow()
    local state = activeSiphons[guid]

    if not state then
        return
    end

    if not target or not damage or damage <= 0 then
        return
    end

    state.totalDamage =
        state.totalDamage + damage

    DebugMessage(
        player,
        "Captured hit for " ..
        damage ..
        " damage; type " ..
        tostring(damageType) ..
        "."
    )
end

local function OnCultistLogout(event, player)
    if not player then
        return
    end

    local guid = player:GetGUIDLow()

    activeSiphons[guid] = nil
    castSerialByGuid[guid] = nil
end

RegisterPlayerEvent(
    PLAYER_EVENT_ON_SPELL_CAST,
    OnSiphonBloodCast
)

RegisterPlayerEvent(
    PLAYER_EVENT_ON_DEAL_DAMAGE,
    OnCultistDealDamage
)

RegisterPlayerEvent(
    PLAYER_EVENT_ON_LOGOUT,
    OnCultistLogout
)

print(
    "[Cultist] Siphon Blood party-healing + mana refund script loaded."
)