-- ============================================================
-- DML Enhanced Holy Fire
--
-- Player-cast Holy Fire improvements:
--   * Every listed player-cast Holy Fire rank applies an 18-second DoT.
--   * NPC-cast Holy Fire keeps its native duration and damage behavior.
--   * Player-cast Holy Fire periodic ticks deal 15% more damage.
--   * A completed player Holy Fire cast has a 20% chance to
--     trigger-cast the same rank again on the same target.
--
-- Double-cast behavior:
--   * The bonus cast is instant and free.
--   * The player remains the caster.
--   * The direct-damage portion hits a second time.
--   * Holy Fire's DoT remains one aura; the second cast refreshes
--     that aura rather than creating two independent DoTs.
--   * The bonus cast cannot recursively trigger another bonus cast.
--
-- No class or subclass restriction is used. Priests, Templars,
-- and any other players who know Holy Fire receive the behavior.
-- NPC casters do not receive the duration, damage, or double-cast changes.
-- ============================================================

local HOLY_FIRE_DURATION_MS = 18 * 1000
local HOLY_FIRE_DOT_MULTIPLIER = 1.25
local HOLY_FIRE_DOUBLE_CAST_CHANCE = 20.0

local PLAYER_EVENT_ON_AURA_APPLY = 64
local PLAYER_EVENT_ON_MODIFY_PERIODIC_DAMAGE_AURAS_TICK = 68
local PLAYER_EVENT_ON_LOGOUT = 4

local ALL_CREATURE_EVENT_ON_AURA_APPLY = 5

local SPELL_EVENT_ON_CAST = 2

local DOUBLE_CAST_GUARD_CLEAR_MS = 250

local DEBUG_HOLY_FIRE = false

local holyFireSpellIds = {
    [14914] = true, -- Rank 1
    [15262] = true, -- Rank 2
    [15263] = true, -- Rank 3
    [15264] = true, -- Rank 4
    [15265] = true, -- Rank 5
    [15266] = true, -- Rank 6
    [15267] = true, -- Rank 7
    [15261] = true, -- Rank 8
    [25384] = true, -- Rank 9
    [48134] = true, -- Rank 10
    [48135] = true  -- Rank 11
}

-- Indexed by player GUIDLow. This prevents the triggered bonus cast
-- from rolling another double-cast chance.
local doubleCastGuardByGuid = {}

local function Debug(player, message)
    if not DEBUG_HOLY_FIRE then
        return
    end

    if player and player.SendBroadcastMessage then
        player:SendBroadcastMessage(
            "|cffffcc33[Holy Fire]|r " .. tostring(message)
        )
    end

    print("[DML Enhanced Holy Fire] " .. tostring(message))
end

local function GetAuraIdSafe(aura)
    if not aura then
        return 0
    end

    if aura.GetAuraId then
        local ok, spellId = pcall(function()
            return aura:GetAuraId()
        end)

        if ok and type(spellId) == "number" then
            return spellId
        end
    end

    if aura.GetId then
        local ok, spellId = pcall(function()
            return aura:GetId()
        end)

        if ok and type(spellId) == "number" then
            return spellId
        end
    end

    if aura.GetEntry then
        local ok, spellId = pcall(function()
            return aura:GetEntry()
        end)

        if ok and type(spellId) == "number" then
            return spellId
        end
    end

    return 0
end

local function GetSpellIdSafe(spell)
    if not spell or not spell.GetEntry then
        return 0
    end

    local ok, spellId = pcall(function()
        return spell:GetEntry()
    end)

    if ok and type(spellId) == "number" then
        return spellId
    end

    return 0
end

local function IsHolyFireSpellInfo(spellInfo)
    if not spellInfo or not spellInfo.GetName then
        return false
    end

    local ok, name = pcall(function()
        return spellInfo:GetName()
    end)

    return ok and name == "Holy Fire"
end

local function IsAuraCastByPlayer(aura)
    if not aura or not aura.GetCaster then
        return false
    end

    local okCaster, caster = pcall(function()
        return aura:GetCaster()
    end)

    if not okCaster or not caster or not caster.IsPlayer then
        return false
    end

    local okIsPlayer, isPlayer = pcall(function()
        return caster:IsPlayer()
    end)

    return okIsPlayer and isPlayer
end

local function SetHolyFireDuration(owner, aura)
    if not owner or not aura then
        return
    end

    local spellId = GetAuraIdSafe(aura)

    if not holyFireSpellIds[spellId] then
        return
    end

    -- Extend Holy Fire only when the aura's actual caster is a player.
    -- Player casts on creature targets still qualify; NPC casts do not.
    if not IsAuraCastByPlayer(aura) then
        return
    end

    local ok, err = pcall(function()
        if aura.SetMaxDuration then
            aura:SetMaxDuration(HOLY_FIRE_DURATION_MS)
        end

        if aura.SetDuration then
            aura:SetDuration(HOLY_FIRE_DURATION_MS)
        end
    end)

    if not ok then
        Debug(
            nil,
            "Failed to set Holy Fire " ..
            tostring(spellId) ..
            " to 18 seconds: " ..
            tostring(err)
        )
        return
    end

    Debug(
        nil,
        "Holy Fire " ..
        tostring(spellId) ..
        " set to 18 seconds."
    )
end

local function OnPlayerAuraApply(event, player, aura)
    SetHolyFireDuration(player, aura)
end

local function OnCreatureAuraApply(event, creature, aura)
    SetHolyFireDuration(creature, aura)
end

local function OnPlayerPeriodicDamage(
    event,
    player,
    target,
    damage,
    spellInfo
)
    if not player or not target or type(damage) ~= "number" then
        return
    end

    if not IsHolyFireSpellInfo(spellInfo) then
        return
    end

    local increasedDamage = math.max(
        0,
        math.floor(
            damage * HOLY_FIRE_DOT_MULTIPLIER + 0.5
        )
    )

    Debug(
        player,
        "Holy Fire tick increased from " ..
        tostring(damage) ..
        " to " ..
        tostring(increasedDamage) ..
        "."
    )

    return increasedDamage
end

local function RollDoubleCast()
    if HOLY_FIRE_DOUBLE_CAST_CHANCE <= 0 then
        return false
    end

    if HOLY_FIRE_DOUBLE_CAST_CHANCE >= 100 then
        return true
    end

    -- Ten-thousand-point roll permits decimal percentages.
    local threshold = math.floor(
        HOLY_FIRE_DOUBLE_CAST_CHANCE * 100 + 0.5
    )

    return math.random(1, 10000) <= threshold
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

local function GetLivingUnitTarget(spell)
    if not spell or not spell.GetTarget then
        return nil
    end

    local okTarget, targetObject = pcall(function()
        return spell:GetTarget()
    end)

    if not okTarget or not targetObject then
        return nil
    end

    local target = targetObject

    if targetObject.ToUnit then
        local okUnit, converted = pcall(function()
            return targetObject:ToUnit()
        end)

        if okUnit and converted then
            target = converted
        end
    end

    if not target.IsAlive then
        return nil
    end

    local okAlive, alive = pcall(function()
        return target:IsAlive()
    end)

    if not okAlive or not alive then
        return nil
    end

    return target
end

local function ClearDoubleCastGuard(playerGuidLow)
    doubleCastGuardByGuid[playerGuidLow] = nil
end

local function OnHolyFireCast(event, caster, spell, skipCheck)
    local player = GetPlayerCaster(caster)

    if not player or not spell then
        return
    end

    local spellId = GetSpellIdSafe(spell)

    if not holyFireSpellIds[spellId] then
        return
    end

    local playerGuidLow = player:GetGUIDLow()

    -- Triggered casts normally report skipCheck = true. The explicit
    -- guard also protects against ALE builds that report it differently.
    if skipCheck or doubleCastGuardByGuid[playerGuidLow] then
        return
    end

    local target = GetLivingUnitTarget(spell)

    if not target or not RollDoubleCast() then
        return
    end

    doubleCastGuardByGuid[playerGuidLow] = true

    local ok, err = pcall(function()
        -- Player is explicitly the caster. The bonus cast therefore retains
        -- normal player ownership and native Holy Fire damage scaling.
        -- triggered=true makes only the bonus cast instant and free.
        player:CastSpell(
            target,
            spellId,
            true
        )
    end)

    -- Retain the guard briefly in case this ALE build dispatches the
    -- triggered spell callback after CastSpell returns.
    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            ClearDoubleCastGuard(playerGuidLow)
        end,
        DOUBLE_CAST_GUARD_CLEAR_MS,
        1
    )

    if not ok then
        ClearDoubleCastGuard(playerGuidLow)

        Debug(
            player,
            "Holy Fire double cast failed: " .. tostring(err)
        )

        return
    end

    Debug(
        player,
        "Holy Fire double cast triggered with rank " ..
        tostring(spellId) ..
        "."
    )
end

local function OnLogout(event, player)
    if not player then
        return
    end

    doubleCastGuardByGuid[player:GetGUIDLow()] = nil
end

RegisterPlayerEvent(
    PLAYER_EVENT_ON_AURA_APPLY,
    OnPlayerAuraApply
)

RegisterPlayerEvent(
    PLAYER_EVENT_ON_MODIFY_PERIODIC_DAMAGE_AURAS_TICK,
    OnPlayerPeriodicDamage
)

RegisterPlayerEvent(
    PLAYER_EVENT_ON_LOGOUT,
    OnLogout
)

RegisterAllCreatureEvent(
    ALL_CREATURE_EVENT_ON_AURA_APPLY,
    OnCreatureAuraApply
)

for spellId in pairs(holyFireSpellIds) do
    RegisterSpellEvent(
        spellId,
        SPELL_EVENT_ON_CAST,
        OnHolyFireCast
    )
end

print(
    "[DML Enhanced Holy Fire] " ..
    "Player-only 18-second DoT, +15% player DoT damage, and 20% player double cast loaded."
)
