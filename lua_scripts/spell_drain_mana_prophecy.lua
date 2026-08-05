-- spell_drain_mana_prophecy.lua
--
-- Cultist Drain Mana bonus:
--   * Applies only to Cultists (subclass 4).
--   * Requires Prophecy of Blood aura 41231 at cast time.
--   * Re-checks Prophecy of Blood and the active Drain Mana channel every tick.
--   * Restores 125% of Drain Mana's detected mana cost over five ticks.
--   * Stops permanently for that cast if the channel is interrupted or the aura fades.
--   * Does not change Drain Mana's normal target drain or existing mana behavior.

local SPELL_DRAIN_MANA = 5138
local AURA_PROPHECY_OF_BLOOD = 41231

local CLASS_WARLOCK = 9
local SUBCLASS_CULTIST = 4

local PLAYER_EVENT_ON_SPELL_CAST = 5
local PLAYER_EVENT_ON_LOGOUT = 4

local POWER_MANA = 0
local CURRENT_CHANNELED_SPELL = 2

-- Five payments of the detected spell cost, totaling 125%.
local BONUS_TICK_COUNT = 5
local TOTAL_BONUS_MULTIPLIER = 1.25

-- Drain Mana is a five-second channel. Using 900 ms places the final
-- payment shortly before the channel ends, avoiding a race where the
-- channel object disappears at exactly 5000 ms.
local BONUS_TICK_INTERVAL_MS = 900

-- Leave at 0 to use spell:GetPowerCost().
-- If testing shows the custom spell module's scaled cost is not reported
-- by GetPowerCost(), set this to the desired actual Drain Mana cost.
local POWER_COST_OVERRIDE = 0

-- Leave enabled during the first test.
local DEBUG_MESSAGES = false

-- Indexed by player GUIDLow.
local activeDrainMana = {}
local castSerialByGuid = {}

local function DebugMessage(player, message)
    if DEBUG_MESSAGES and player then
        player:SendBroadcastMessage(
            "|cff8b0000[Drain Mana]|r " .. message
        )
    end
end

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

local function GetSpellId(spell)
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

local function GetDrainManaPowerCost(spell)
    if POWER_COST_OVERRIDE > 0 then
        return POWER_COST_OVERRIDE
    end

    if spell and spell.GetPowerCost then
        return spell:GetPowerCost()
    end

    return 0
end

local function IsChannelingDrainMana(player)
    if not player then
        return false
    end

    local currentSpell = player:GetCurrentSpell(
        CURRENT_CHANNELED_SPELL
    )

    return GetSpellId(currentSpell) == SPELL_DRAIN_MANA
end

local function GetTickManaAmount(state, tickNumber)
    local amount = state.baseTickAmount

    -- Distribute rounding remainder across the earliest ticks so the
    -- five payments add up to exactly state.totalBonusMana.
    if tickNumber <= state.remainderMana then
        amount = amount + 1
    end

    return amount
end

local function RestoreMana(player, amount)
    if not player or amount <= 0 then
        return 0
    end

    local currentMana = player:GetPower(POWER_MANA)
    local maxMana = player:GetMaxPower(POWER_MANA)

    if maxMana <= 0 or currentMana >= maxMana then
        return 0
    end

    local newMana = math.min(
        maxMana,
        currentMana + amount
    )

    local actualGain = newMana - currentMana

    if actualGain > 0 then
        -- Confirmed ALE order used by this project:
        -- SetPower(newValue, powerType)
        player:SetPower(newMana, POWER_MANA)
    end

    return actualGain
end

local function StopDrainManaBonus(
    player,
    guid,
    castSerial,
    reason
)
    local state = activeDrainMana[guid]

    if not state or state.castSerial ~= castSerial then
        return
    end

    activeDrainMana[guid] = nil

    if reason then
        DebugMessage(player, reason)
    end
end

local function OnDrainManaBonusTick(
    eventId,
    delay,
    repeats,
    player,
    guid,
    castSerial
)
    local state = activeDrainMana[guid]

    -- Ignore callbacks left behind by an older cast.
    if not state or state.castSerial ~= castSerial then
        return
    end

    -- Both requirements must continue to pass.
    if not IsCultist(player) then
        StopDrainManaBonus(
            player,
            guid,
            castSerial,
            "Bonus stopped: caster is not a Cultist."
        )
        return
    end

    if not player:HasAura(AURA_PROPHECY_OF_BLOOD) then
        StopDrainManaBonus(
            player,
            guid,
            castSerial,
            "Bonus stopped: Prophecy of Blood is no longer active."
        )
        return
    end

    if not IsChannelingDrainMana(player) then
        StopDrainManaBonus(
            player,
            guid,
            castSerial,
            "Bonus stopped: Drain Mana was interrupted or ended."
        )
        return
    end

    state.tickNumber = state.tickNumber + 1

    local requestedMana = GetTickManaAmount(
        state,
        state.tickNumber
    )

    local restoredMana = RestoreMana(
        player,
        requestedMana
    )

    DebugMessage(
        player,
        "Tick " ..
        state.tickNumber ..
        "/" ..
        BONUS_TICK_COUNT ..
        ": restored " ..
        restoredMana ..
        " mana."
    )

    if state.tickNumber >= BONUS_TICK_COUNT then
        activeDrainMana[guid] = nil

        DebugMessage(
            player,
            "Prophecy bonus complete: " ..
            state.totalBonusMana ..
            " mana scheduled from a detected cost of " ..
            state.powerCost ..
            "."
        )
    end
end

local function OnDrainManaCast(
    event,
    player,
    spell,
    skipCheck
)
    if not player or not spell then
        return
    end

    if GetSpellId(spell) ~= SPELL_DRAIN_MANA then
        return
    end

    if IsBot(player) then
        return
    end

    -- Requirement 1: the caster must be a Cultist.
    if not IsCultist(player) then
        return
    end

    -- Requirement 2: Prophecy of Blood must already be active.
    if not player:HasAura(AURA_PROPHECY_OF_BLOOD) then
        DebugMessage(
            player,
            "No bonus: Prophecy of Blood is not active."
        )
        return
    end

    local powerCost = GetDrainManaPowerCost(spell)

    if not powerCost or powerCost <= 0 then
        DebugMessage(
            player,
            "No mana cost was detected. " ..
            "Set POWER_COST_OVERRIDE if the custom module's cost " ..
            "is not exposed through spell:GetPowerCost()."
        )
        return
    end

    local totalBonusMana = math.max(
        1,
        math.floor(
            powerCost * TOTAL_BONUS_MULTIPLIER + 0.5
        )
    )

    local baseTickAmount = math.floor(
        totalBonusMana / BONUS_TICK_COUNT
    )

    local remainderMana =
        totalBonusMana -
        (baseTickAmount * BONUS_TICK_COUNT)

    local guid = player:GetGUIDLow()

    local castSerial =
        (castSerialByGuid[guid] or 0) + 1

    castSerialByGuid[guid] = castSerial

    activeDrainMana[guid] = {
        castSerial = castSerial,
        powerCost = powerCost,
        totalBonusMana = totalBonusMana,
        baseTickAmount = baseTickAmount,
        remainderMana = remainderMana,
        tickNumber = 0
    }

    DebugMessage(
        player,
        "Prophecy bonus started. Detected mana cost: " ..
        powerCost ..
        "; total bonus: " ..
        totalBonusMana ..
        "."
    )

    -- Use a player-bound timer so ALE supplies a valid Player object.
    -- The cast serial prevents old timers from paying out during a new cast.
    player:RegisterEvent(
        function(eventId, delay, repeats, caster)
            OnDrainManaBonusTick(
                eventId,
                delay,
                repeats,
                caster,
                guid,
                castSerial
            )
        end,
        BONUS_TICK_INTERVAL_MS,
        BONUS_TICK_COUNT
    )
end

local function OnCultistLogout(event, player)
    if not player then
        return
    end

    local guid = player:GetGUIDLow()

    activeDrainMana[guid] = nil
    castSerialByGuid[guid] = nil
end

RegisterPlayerEvent(
    PLAYER_EVENT_ON_SPELL_CAST,
    OnDrainManaCast
)

RegisterPlayerEvent(
    PLAYER_EVENT_ON_LOGOUT,
    OnCultistLogout
)

print(
    "[Cultist] Prophecy of Blood Drain Mana bonus script loaded."
)
