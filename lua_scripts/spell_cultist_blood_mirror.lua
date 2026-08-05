-- ============================================================
-- DML Cultist Blood Mirror Control - party-member strict target-owned cleanup version
--
-- Spell: Blood Mirror 70445
--
-- Rules:
-- - Cultist/Warlock only.
-- - Cannot be used on self.
-- - Can only be used on another player in your party/raid.
-- - Hostile creatures/enemy players/non-party targets are blocked.
-- - Valid casts last 15 seconds instead of the normal 30 seconds.
-- - Invalid casts remove the aura and try to clear the server cooldown.
-- - Successful casts broadcast a DMLCD success message for addon-side cooldowns.
--
-- Important fix:
-- Delayed timers do NOT store/use old target userdata. ALE can invalidate
-- objects after a map change, logout, teleport, aura state change, etc.
-- Delayed code stores names/serials only and re-fetches live players later.
-- ============================================================

local SPELL_BLOOD_MIRROR = 70445

local CLASS_WARLOCK = 9
local SUBCLASS_CULTIST = 4

local PLAYER_EVENT_ON_LOGOUT = 4
local PLAYER_EVENT_ON_SPELL_CAST = 5

local BLOOD_MIRROR_DURATION_MS = 15000
local BLOOD_MIRROR_COOLDOWN_MS = 300000
local POST_CAST_CHECK_DELAY_MS = 250
local INVALID_CAST_CLEANUP_DELAY_MS = 50

local BLOOD_MIRROR_DEBUG = false

local INVALID_CAST_CLEANUP_DELAYS_MS = {
    50,
    250,
    750,
    1500,
}

-- If Blood Mirror uses separate aura spell IDs on caster/target, add them here.
local BLOOD_MIRROR_AURA_IDS = {
    70445,
}

local activeMirrorByGuid = {}
local castSerialByGuid = {}

local function DmlDebug(player, message)
    if BLOOD_MIRROR_DEBUG and player then
        player:SendBroadcastMessage("|cff8b0000[Blood Mirror]|r " .. tostring(message))
    end

    if BLOOD_MIRROR_DEBUG then
        print("[DML Blood Mirror] " .. tostring(message))
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

local function GetDmlGuidLow(unit)
    if not unit then
        return 0
    end

    if unit.GetGUIDLow then
        return unit:GetGUIDLow()
    end

    if unit.GetGUID then
        return unit:GetGUID()
    end

    return 0
end

local function GetDmlGuid(unit)
    if not unit then
        return 0
    end

    if unit.GetGUID then
        return unit:GetGUID()
    end

    if unit.GetGUIDLow then
        return unit:GetGUIDLow()
    end

    return 0
end

local function GetDmlName(unit)
    if unit and unit.GetName then
        return unit:GetName()
    end

    return "unknown"
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

local function HasAuraSafe(unit, spellId)
    if not unit or not unit.HasAura then
        return false
    end

    local ok, result = pcall(function()
        return unit:HasAura(spellId)
    end)

    if not ok then
        print(
            "[DML Blood Mirror] HasAura failed for " ..
            tostring(spellId) ..
            ": " ..
            tostring(result)
        )

        return false
    end

    return result
end

local function UnitHasAnyBloodMirrorAura(unit)
    for _, auraId in ipairs(BLOOD_MIRROR_AURA_IDS) do
        if HasAuraSafe(unit, auraId) then
            return true
        end
    end

    return false
end

local function RemoveBloodMirrorAuras(unit)
    if not unit or not unit.RemoveAura then
        return
    end

    for _, auraId in ipairs(BLOOD_MIRROR_AURA_IDS) do
        if HasAuraSafe(unit, auraId) then
            local ok, err = pcall(function()
                unit:RemoveAura(auraId)
            end)

            if not ok then
                print(
                    "[DML Blood Mirror] RemoveAura failed for " ..
                    tostring(auraId) ..
                    ": " ..
                    tostring(err)
                )
            end
        end
    end
end


local function ForceRemoveBloodMirrorAuras(unit)
    if not unit then
        return
    end

    for _, auraId in ipairs(BLOOD_MIRROR_AURA_IDS) do
        if unit.RemoveAura then
            pcall(function()
                unit:RemoveAura(auraId)
            end)
        end

        if unit.RemoveAurasDueToSpell then
            pcall(function()
                unit:RemoveAurasDueToSpell(auraId)
            end)
        end

        -- Some cores expose both spell-aura cleanup helpers. Call either when
        -- available; all calls are protected because ALE method support varies.
        if unit.RemoveAuraFromStack then
            pcall(function()
                unit:RemoveAuraFromStack(auraId)
            end)
        end
    end
end

local function ScheduleUnitBloodMirrorCleanup(unit, delayMs)
    if not unit or not unit.RegisterEvent then
        return
    end

    local ok, err = pcall(function()
        unit:RegisterEvent(
            function(eventId, delay, repeats, liveUnit)
                ForceRemoveBloodMirrorAuras(liveUnit)
            end,
            delayMs,
            1
        )
    end)

    if not ok then
        print(
            "[DML Blood Mirror] target-owned cleanup timer failed: " ..
            tostring(err)
        )
    end
end

local function GetCurrentSelectedUnit(player)
    if not player then
        return nil
    end

    local methods = {
        "GetSelectedUnit",
        "GetSelectionUnit",
        "GetTarget",
        "GetUnitTarget",
    }

    for _, methodName in ipairs(methods) do
        if player[methodName] then
            local ok, unit = pcall(function()
                return player[methodName](player)
            end)

            if ok and unit and type(unit) == "userdata" then
                return unit
            end
        end
    end

    -- Some Eluna/ALE builds expose GetSelection as a GUID only, not a unit.
    -- If your build returns a unit object, this catches it; if it returns a
    -- number/string GUID, we safely ignore it.
    if player.GetSelection then
        local ok, selected = pcall(function()
            return player:GetSelection()
        end)

        if ok and selected and type(selected) == "userdata" then
            return selected
        end
    end

    return nil
end

local function TryInterruptBloodMirror(player)
    if not player then
        return
    end

    if player.InterruptSpell then
        for _, spellType in ipairs({ 0, 1, 2, 3, 4 }) do
            pcall(function()
                player:InterruptSpell(spellType)
            end)
        end
    end

    if player.CastStop then
        pcall(function()
            player:CastStop()
        end)
    end

    if player.StopSpellCast then
        pcall(function()
            player:StopSpellCast()
        end)
    end
end

local function SendDmlCooldownReset(player)
    if not player then
        return
    end

    -- Addon-side hook. If your current addon does not parse these yet,
    -- patch the addon to clear 70445 when it sees DMLCD|RESET|70445.
    player:SendBroadcastMessage("DMLCD|RESET|" .. SPELL_BLOOD_MIRROR)
    player:SendBroadcastMessage("DMLCD|COOLDOWN|" .. SPELL_BLOOD_MIRROR .. "|0")
end

local function SendDmlSuccessfulCast(player)
    if not player then
        return
    end

    -- Addon-side hook. This lets the addon start the cooldown only after
    -- the server confirms Blood Mirror actually applied.
    player:SendBroadcastMessage("DMLCD|VALIDCAST|" .. SPELL_BLOOD_MIRROR)
    player:SendBroadcastMessage(
        "DMLCD|COOLDOWN|" ..
        SPELL_BLOOD_MIRROR ..
        "|" ..
        BLOOD_MIRROR_COOLDOWN_MS
    )
end

local function TryResetBloodMirrorCooldown(player)
    if not player then
        return
    end

    local ok, err = pcall(function()
        if player.ResetSpellCooldown then
            player:ResetSpellCooldown(SPELL_BLOOD_MIRROR, true)
        elseif player.RemoveSpellCooldown then
            player:RemoveSpellCooldown(SPELL_BLOOD_MIRROR)
        end
    end)

    if not ok then
        DmlDebug(player, "Cooldown reset failed or is unsupported: " .. tostring(err))
    end

    SendDmlCooldownReset(player)
end

local function GetSpellTarget(player, spell)
    if not spell then
        return nil
    end

    local possibleMethods = {
        "GetTarget",
        "GetUnitTarget",
        "GetTargetUnit",
        "GetExplTargetUnit",
    }

    for _, methodName in ipairs(possibleMethods) do
        if spell[methodName] then
            local ok, target = pcall(function()
                return spell[methodName](spell)
            end)

            if ok and target then
                return target
            end
        end
    end

    return nil
end

local function IsSameUnit(a, b)
    if not a or not b then
        return false
    end

    local guidA = GetDmlGuid(a)
    local guidB = GetDmlGuid(b)

    return guidA ~= 0 and guidA == guidB
end

local function IsPlayerUnit(unit)
    if not unit then
        return false
    end

    if unit.IsPlayer then
        local ok, result = pcall(function()
            return unit:IsPlayer()
        end)

        if ok then
            return result
        end
    end

    -- Fallback: real players generally expose GetPlayerName/GetAccountId/etc,
    -- but creatures do not. Keep this conservative; if we cannot prove player,
    -- do not allow Blood Mirror.
    if unit.GetAccountId or unit.GetSession then
        return true
    end

    return false
end

local function IsGroupedWith(player, target)
    if not player or not target then
        return false
    end

    if IsSameUnit(player, target) then
        return true
    end

    -- Direct helper methods, if ALE exposes them.
    local methods = {
        "IsInGroupWith",
        "IsInSameGroupWith",
        "IsInRaidWith",
    }

    for _, methodName in ipairs(methods) do
        if player[methodName] then
            local ok, result = pcall(function()
                return player[methodName](player, target)
            end)

            if ok and result then
                return true
            end
        end
    end

    -- Reliable fallback: Blood Bolt party heal proved Group:GetMembers works
    -- on this server, so compare the target against the caster's group list.
    if player.GetGroup then
        local okGroup, group = pcall(function()
            return player:GetGroup()
        end)

        if okGroup and group and group.GetMembers then
            local okMembers, members = pcall(function()
                return group:GetMembers()
            end)

            if okMembers and members then
                local targetGuid = GetDmlGuidLow(target)

                for _, member in pairs(members) do
                    if GetDmlGuidLow(member) == targetGuid then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function IsAllowedBloodMirrorTarget(player, target)
    if not target then
        return false, "Blood Mirror failed: no valid target detected."
    end

    if IsSameUnit(player, target) then
        return false, "Blood Mirror cannot be cast on yourself."
    end

    -- Keep this strict: Blood Mirror is only allowed on another grouped unit.
    -- We check group membership first because some ALE target userdata does not
    -- reliably expose IsPlayer(), even when the target is a real party member.
    -- This blocks hostile creatures/enemy players/non-party targets without
    -- relying on flaky IsFriendlyTo/IsHostileTo results from this ALE build.
    if not IsGroupedWith(player, target) then
        return false, "Blood Mirror can only be cast on a party or raid member."
    end

    -- Extra hostility check when exposed. Group membership is the main gate,
    -- but this catches duel/PvP oddities if the core reports them.
    if player.IsHostileTo then
        local ok, hostile = pcall(function()
            return player:IsHostileTo(target)
        end)

        if ok and hostile then
            return false, "Blood Mirror can only be cast on friendly targets."
        end
    end

    if target.IsHostileTo then
        local ok, hostile = pcall(function()
            return target:IsHostileTo(player)
        end)

        if ok and hostile then
            return false, "Blood Mirror can only be cast on friendly targets."
        end
    end

    return true, ""
end

local function GetLivePlayerByName(name)
    if not name or name == "unknown" or not GetPlayerByName then
        return nil
    end

    return GetPlayerByName(name)
end

local function ScheduleInvalidCastCleanup(player, target, targetName, reason)
    DmlDebug(player, reason)

    -- Event 5 is post/near-post cast in ALE, so this is a soft block:
    -- immediately strip the aura from both units, then repeat a few short
    -- cleanup passes in case the core applies Blood Mirror slightly later.
    -- Important: for creature targets, schedule cleanup ON THE TARGET too.
    -- Player-owned timers can end up holding stale creature userdata, but a
    -- target-owned timer receives the live creature as its callback argument.
    TryInterruptBloodMirror(player)
    ForceRemoveBloodMirrorAuras(player)
    ForceRemoveBloodMirrorAuras(target)

    local selectedTarget = GetCurrentSelectedUnit(player)
    ForceRemoveBloodMirrorAuras(selectedTarget)

    TryResetBloodMirrorCooldown(player)

    for _, cleanupDelay in ipairs(INVALID_CAST_CLEANUP_DELAYS_MS) do
        ScheduleUnitBloodMirrorCleanup(target, cleanupDelay)
        ScheduleUnitBloodMirrorCleanup(selectedTarget, cleanupDelay)

        player:RegisterEvent(
            function(eventId, delay, repeats, caster)
                if caster then
                    TryInterruptBloodMirror(caster)
                    ForceRemoveBloodMirrorAuras(caster)

                    local liveSelected = GetCurrentSelectedUnit(caster)
                    ForceRemoveBloodMirrorAuras(liveSelected)

                    TryResetBloodMirrorCooldown(caster)
                end

                -- For player targets, re-fetch by name too. For creature targets,
                -- the target-owned cleanup timer above is the reliable path.
                local liveTarget = GetLivePlayerByName(targetName)

                if liveTarget then
                    ForceRemoveBloodMirrorAuras(liveTarget)
                end
            end,
            cleanupDelay,
            1
        )
    end
end

local function ScheduleDurationCleanup(player, targetName, castSerial)
    local casterGuid = GetDmlGuidLow(player)

    activeMirrorByGuid[casterGuid] = {
        castSerial = castSerial,
        targetName = targetName,
    }

    DmlDebug(
        player,
        "Blood Mirror linked to " ..
        tostring(targetName) ..
        " for 15 seconds."
    )

    player:RegisterEvent(
        function(eventId, delay, repeats, caster)
            local state = activeMirrorByGuid[casterGuid]

            if not state or state.castSerial ~= castSerial then
                return
            end

            activeMirrorByGuid[casterGuid] = nil

            if caster then
                RemoveBloodMirrorAuras(caster)
            end

            local liveTarget = GetLivePlayerByName(targetName)

            if liveTarget then
                RemoveBloodMirrorAuras(liveTarget)
            end

            if caster then
                DmlDebug(caster, "Blood Mirror faded after 15 seconds.")
            end
        end,
        BLOOD_MIRROR_DURATION_MS,
        1
    )
end

local function SchedulePostCastValidation(player, targetName)
    local casterGuid = GetDmlGuidLow(player)

    if casterGuid == 0 then
        return
    end

    castSerialByGuid[casterGuid] = (castSerialByGuid[casterGuid] or 0) + 1

    local castSerial = castSerialByGuid[casterGuid]

    player:RegisterEvent(
        function(eventId, delay, repeats, caster)
            if not caster then
                return
            end

            local liveTarget = GetLivePlayerByName(targetName)
            local casterHasAura = UnitHasAnyBloodMirrorAura(caster)
            local targetHasAura = liveTarget and UnitHasAnyBloodMirrorAura(liveTarget)

            if casterHasAura or targetHasAura then
                SendDmlSuccessfulCast(caster)
                ScheduleDurationCleanup(caster, targetName, castSerial)
                return
            end

            -- If the cast event fired but no Blood Mirror aura was actually
            -- created, treat it as a failed/blocked cast for addon cooldown sync.
            TryResetBloodMirrorCooldown(caster)
        end,
        POST_CAST_CHECK_DELAY_MS,
        1
    )
end

local function OnBloodMirrorCast(event, player, spell, skipCheck)
    if not player or not spell then
        return
    end

    local spellId = GetDmlSpellId(spell)

    if spellId ~= SPELL_BLOOD_MIRROR then
        return
    end

    if IsBot(player) then
        return
    end

    if not IsCultist(player) then
        return
    end

    local target = GetSpellTarget(player, spell)
    local targetName = GetDmlName(target)

    if not target then
        ScheduleInvalidCastCleanup(
            player,
            target,
            targetName,
            "Blood Mirror failed: no valid target detected."
        )

        return
    end

    local allowedTarget, blockReason = IsAllowedBloodMirrorTarget(player, target)

    if not allowedTarget then
        ScheduleInvalidCastCleanup(
            player,
            target,
            targetName,
            blockReason
        )

        return
    end

    SchedulePostCastValidation(player, targetName)
end

local function OnBloodMirrorLogout(event, player)
    if not player then
        return
    end

    local guid = GetDmlGuidLow(player)

    if guid ~= 0 then
        activeMirrorByGuid[guid] = nil
        castSerialByGuid[guid] = nil
    end
end

RegisterPlayerEvent(PLAYER_EVENT_ON_LOGOUT, OnBloodMirrorLogout)
RegisterPlayerEvent(PLAYER_EVENT_ON_SPELL_CAST, OnBloodMirrorCast)

print("[DML Blood Mirror] Cultist party-member strict target-owned cleanup control loaded.")
