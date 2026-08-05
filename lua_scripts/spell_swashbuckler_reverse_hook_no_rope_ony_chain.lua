-- ============================================================
-- DML Swashbuckler Reverse Abomination Hook
--
-- Spell:
--   59395 - Abomination Hook
--
-- Swashbuckler-only behavior:
--   * Requires an equipped ranged weapon in slot 17.
--   * Uses the spell's normal hostile-target restriction.
--   * Cancels the normal target-to-caster pull.
--   * Plays Fake Shot 7105.
--   * Makes the target cast Hook back at the Swashbuckler.
--   * Uses Abomination Hook's normal chain visual.
--   * Uses MoveJump if the reverse Hook did not move the player.
--
-- Important timer safety:
--   Delayed target actions are registered ON THE TARGET.
--   ALE supplies a fresh liveTarget object to each callback.
--   The script never stores creature userdata inside a player timer.
-- ============================================================

local CLASS_ROGUE = 4
local SUBCLASS_SWASHBUCKLER = 5

local SPELL_ABOMINATION_HOOK = 59395
local SPELL_FAKE_SHOT = 7105

local HOOK_COOLDOWN_SECONDS = 60
local hookCooldownEndByGuid = {}

local PLAYER_EVENT_ON_LOGOUT = 4
local PLAYER_EVENT_ON_SPELL_CAST = 5

local EQUIPMENT_SLOT_RANGED = 17

local MIN_RANGE = 1.0
local MAX_RANGE = 40.0

local REVERSE_CAST_DELAY_MS = 175
local FALLBACK_DELAY_MS = 425
local GUARD_CLEAR_DELAY_MS = 1000

local REQUIRED_MOVEMENT = 3.0
local FALLBACK_SPEED_XY = 22.0
local FALLBACK_SPEED_Z = 8.0

local DEBUG_REVERSE_HOOK = false

-- Needed only when the hostile target is another player.
local reverseGuard = {}

local function Now()
    return os.time()
end

local function GetHookRemainingSeconds(player)
    if not player then
        return 0
    end

    local guid = player:GetGUIDLow()
    local cooldownEnd = hookCooldownEndByGuid[guid] or 0
    local remaining = cooldownEnd - Now()

    if remaining < 0 then
        remaining = 0
    end

    return remaining
end

local function SendDmlHookCooldown(player, remainingSeconds)
    if not player then
        return
    end

    local remainingMs = math.max(0, remainingSeconds) * 1000

    player:SendBroadcastMessage(
        "DMLCD|COOLDOWN|59395|" .. tostring(remainingMs)
    )

    if remainingMs <= 0 then
        player:SendBroadcastMessage("DMLCD|RESET|59395")
    end
end

local function StartHookCooldown(player)
    if not player then
        return
    end

    hookCooldownEndByGuid[player:GetGUIDLow()] =
        Now() + HOOK_COOLDOWN_SECONDS

    SendDmlHookCooldown(player, HOOK_COOLDOWN_SECONDS)
end

local function Log(player, message)
    local text = tostring(message)

    if DEBUG_REVERSE_HOOK and player then
        player:SendBroadcastMessage(
            "|cff00ccff[Reverse Hook]|r " .. text
        )
    end

    if DEBUG_REVERSE_HOOK then
        print(
            "[DML Swashbuckler Reverse Hook] " .. text
        )
    end
end

local function GetSpellId(spell)
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

local function GetSubclass(player)
    if not player then
        return 0
    end

    local result = CharDBQuery(
        "SELECT subclass_id " ..
        "FROM character_subclass " ..
        "WHERE guid = " ..
        player:GetGUIDLow() ..
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

local function HasRangedWeapon(player)
    if not player
        or not player.GetEquippedItemBySlot
    then
        return false
    end

    local ok, item = pcall(function()
        return player:GetEquippedItemBySlot(
            EQUIPMENT_SLOT_RANGED
        )
    end)

    return ok and item ~= nil
end

local function IsAliveSafe(unit)
    if not unit or not unit.IsAlive then
        return false
    end

    local ok, alive = pcall(function()
        return unit:IsAlive()
    end)

    return ok and alive
end

local function ToUnitSafe(object)
    if not object then
        return nil
    end

    if object.IsAlive
        and object.GetDistance
        and object.GetX
    then
        return object
    end

    if not object.ToUnit then
        return nil
    end

    local ok, unit = pcall(function()
        return object:ToUnit()
    end)

    if ok then
        return unit
    end

    return nil
end

local function GetTarget(player, spell)
    local target = nil

    if spell and spell.GetTarget then
        local ok, object = pcall(function()
            return spell:GetTarget()
        end)

        if ok then
            target = ToUnitSafe(object)
        end
    end

    if not target and player.GetSelection then
        local ok, object = pcall(function()
            return player:GetSelection()
        end)

        if ok then
            target = ToUnitSafe(object)
        end
    end

    return target
end

local function CancelHook(spell)
    if not spell or not spell.Cancel then
        return false
    end

    local ok = pcall(function()
        spell:Cancel()
    end)

    return ok
end

local function RemoveAuraSafe(unit, spellId)
    if not unit or not unit.RemoveAura then
        return
    end

    pcall(function()
        unit:RemoveAura(spellId)
    end)
end

local function GetLivePlayer(fullGuid)
    if not fullGuid or not GetPlayerByGUID then
        return nil
    end

    local ok, player = pcall(function()
        return GetPlayerByGUID(fullGuid)
    end)

    if ok then
        return player
    end

    return nil
end

local function ClearReverseGuardLater(
    player,
    guardedGuidLow
)
    if not player or not guardedGuidLow then
        return
    end

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            reverseGuard[guardedGuidLow] = nil
        end,
        GUARD_CLEAR_DELAY_MS,
        1
    )
end

local function SetReverseGuardForLiveTarget(
    player,
    liveTarget
)
    if not liveTarget or not liveTarget.ToPlayer then
        return
    end

    local ok, targetPlayer = pcall(function()
        return liveTarget:ToPlayer()
    end)

    if not ok or not targetPlayer then
        return
    end

    local guardedGuidLow =
        targetPlayer:GetGUIDLow()

    reverseGuard[guardedGuidLow] = true

    ClearReverseGuardLater(
        player,
        guardedGuidLow
    )
end

local function PlayFakeShot(player, target)
    if not player
        or not target
        or not player.CastSpell
    then
        return
    end

    pcall(function()
        player:CastSpell(
            target,
            SPELL_FAKE_SHOT,
            true
        )
    end)
end

local function ScheduleReverseHook(
    target,
    casterFullGuid
)
    target:RegisterEvent(
        function(eventId, delay, repeats, liveTarget)
            local livePlayer =
                GetLivePlayer(casterFullGuid)

            if not livePlayer
                or not IsAliveSafe(livePlayer)
                or not IsAliveSafe(liveTarget)
                or not liveTarget.CastCustomSpell
            then
                return
            end

            SetReverseGuardForLiveTarget(
                livePlayer,
                liveTarget
            )

            local ok, err = pcall(function()
                liveTarget:CastCustomSpell(
                    livePlayer,
                    SPELL_ABOMINATION_HOOK,
                    true,
                    0
                )
            end)

            if not ok then
                Log(
                    livePlayer,
                    "Reverse Hook cast failed: " ..
                    tostring(err)
                )
            end
        end,
        REVERSE_CAST_DELAY_MS,
        1
    )
end

local function ScheduleFallback(
    target,
    casterFullGuid,
    startingDistance
)
    target:RegisterEvent(
        function(eventId, delay, repeats, liveTarget)
            local livePlayer =
                GetLivePlayer(casterFullGuid)

            if not livePlayer
                or not IsAliveSafe(livePlayer)
                or not IsAliveSafe(liveTarget)
            then
                return
            end

            local remainingDistance =
                livePlayer:GetDistance(liveTarget)

            if startingDistance - remainingDistance
                >= REQUIRED_MOVEMENT
            then
                return
            end

            if not livePlayer.MoveJump then
                return
            end

            pcall(function()
                livePlayer:MoveJump(
                    liveTarget:GetX(),
                    liveTarget:GetY(),
                    liveTarget:GetZ(),
                    FALLBACK_SPEED_XY,
                    FALLBACK_SPEED_Z
                )
            end)
        end,
        FALLBACK_DELAY_MS,
        1
    )
end

local function BeginReverseSequence(
    player,
    target,
    startingDistance
)
    local casterFullGuid = player:GetGUID()

    -- 1. Fake Shot supplies the ranged firing animation.
    PlayFakeShot(
        player,
        target
    )

    -- 2. Every delayed target action is owned by the target and
    -- receives a fresh liveTarget from ALE.
    ScheduleReverseHook(
        target,
        casterFullGuid
    )

    ScheduleFallback(
        target,
        casterFullGuid,
        startingDistance
    )
end

local function OnSpellCast(
    event,
    player,
    spell,
    skipCheck
)
    if not player or not spell then
        return
    end

    if GetSpellId(spell)
        ~= SPELL_ABOMINATION_HOOK
    then
        return
    end

    local guidLow = player:GetGUIDLow()

    -- Allow an internally triggered Hook from a hostile player target.
    if reverseGuard[guidLow] then
        return
    end

        if not IsSwashbuckler(player) then
        return
    end

    local remainingCooldown = GetHookRemainingSeconds(player)

    if remainingCooldown > 0 then
        CancelHook(spell)

        SendDmlHookCooldown(player, remainingCooldown)

        player:SendNotification(
            "Abomination Hook is still on cooldown: " ..
            tostring(remainingCooldown) ..
            " second(s)."
        )

        return
    end

    if not HasRangedWeapon(player) then
        CancelHook(spell)

        player:SendNotification(
            "Reverse Hook requires an equipped ranged weapon."
        )

        return
    end

    local target = GetTarget(
        player,
        spell
    )

    if not target
        or target == player
        or not IsAliveSafe(target)
    then
        CancelHook(spell)
        return
    end

    local distance =
        player:GetDistance(target)

    if distance < MIN_RANGE
        or distance > MAX_RANGE
    then
        CancelHook(spell)
        return
    end

    if not target.RegisterEvent then
        CancelHook(spell)

        Log(
            player,
            "Target does not expose RegisterEvent."
        )

        return
    end

    if not CancelHook(spell) then
        return
    end

StartHookCooldown(player)

    BeginReverseSequence(
        player,
        target,
        distance
    )
end

local function OnLogout(event, player)
    if player then
        local guidLow = player:GetGUIDLow()

        reverseGuard[guidLow] = nil
        hookCooldownEndByGuid[guidLow] = nil
    end
end

RegisterPlayerEvent(
    PLAYER_EVENT_ON_SPELL_CAST,
    OnSpellCast
)

RegisterPlayerEvent(
    PLAYER_EVENT_ON_LOGOUT,
    OnLogout
)

print(
    "[DML Swashbuckler Reverse Hook] " ..
    "Safe hostile ranged Reverse Hook + Fake Shot chain-only version loaded."
)
