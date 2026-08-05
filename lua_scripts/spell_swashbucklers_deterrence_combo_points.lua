-- ============================================================
-- DML Swashbuckler Deterrence Combo Cooldown Reduction
--
-- Deterrence 31567 has native cooldown set to 0 in SQL.
--
-- Lua manages the cooldown:
-- - Base cooldown: 120 seconds
-- - Each combo point spent reduces cooldown by 1 second
-- - If used early, Deterrence aura is stripped immediately
-- - Sends DMLCD cooldown broadcasts whenever the timer changes
--
-- Also adds configurable Swashbuckler combo-point builder spells:
-- - Arcane Shot ranks
-- - Concussive Shot 5116
-- - Backhand 6253
-- - Sunder Armor 58567
-- ============================================================

local CLASS_ROGUE = 4
local SUBCLASS_SWASHBUCKLER = 5

local SPELL_DETERRENCE = 31567

local PLAYER_EVENT_ON_LOGIN = 3
local PLAYER_EVENT_ON_LOGOUT = 4
local PLAYER_EVENT_ON_SPELL_CAST = 5

local DETERRENCE_BASE_COOLDOWN_SECONDS = 120
local CDR_PER_COMBO_POINT_SECONDS = 1

local COMBO_POINTS_TO_ADD = 1
local MAX_COMBO_POINTS = 5

local DEBUG_DETERRENCE_CDR = false
local DEBUG_COMBO_BUILDERS = false

local deterrenceCooldownEndByGuid = {}

-- Rogue finishers / combo point spenders.
-- These reduce Deterrence cooldown by 1 second per combo point spent.
local FINISHER_SPELLS = {
    -- Eviscerate
    [2098] = true, [6760] = true, [6761] = true, [6762] = true,
    [8623] = true, [8624] = true, [11299] = true, [11300] = true,
    [31016] = true, [26865] = true, [48667] = true, [48668] = true,

    -- Slice and Dice
    [5171] = true, [6774] = true,

    -- Kidney Shot
    [408] = true, [8643] = true,

    -- Rupture
    [1943] = true, [8639] = true, [8640] = true, [11273] = true,
    [11274] = true, [11275] = true, [26867] = true, [48671] = true,
    [48672] = true,

    -- Expose Armor
    [8647] = true, [8649] = true, [8650] = true, [11197] = true,
    [11198] = true, [26866] = true, [48669] = true,

    -- Envenom
    [32645] = true, [32684] = true, [57992] = true, [57993] = true,

    -- Deadly Throw
    [26679] = true, [48673] = true, [48674] = true,
}

-- Swashbuckler combo-point builders.
-- Add more custom ranged/pistol/sword spells here later.
-- Each listed spell adds 1 combo point to the target.
local COMBO_BUILDER_SPELLS = {
    -- Arcane Shot ranks
    [3044] = true,
    [14281] = true,
    [14282] = true,
    [14283] = true,
    [14284] = true,
    [14285] = true,
    [14286] = true,
    [14287] = true,
    [27019] = true,
    [49044] = true,
    [49045] = true,

    -- Concussive Shot
    [5116] = true,

    -- Backhand
    [6253] = true,

   -- abomination hook
    [59395] = true,

   -- scatter shot
    [19503] = true

}

local function Debug(player, msg)
    if DEBUG_DETERRENCE_CDR and player then
        player:SendBroadcastMessage("|cff00ccff[Swashbuckler]|r " .. tostring(msg))
    end

    if DEBUG_DETERRENCE_CDR then
        print("[DML Swash Deterrence CDR] " .. tostring(msg))
    end
end

local function ComboDebug(player, msg)
    if DEBUG_COMBO_BUILDERS and player then
        player:SendBroadcastMessage("|cff00ccff[Swash Combo]|r " .. tostring(msg))
    end

    if DEBUG_COMBO_BUILDERS then
        print("[DML Swash Combo] " .. tostring(msg))
    end
end

local function Now()
    return os.time()
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

local function GetDmlGuid(unit)
    if not unit then
        return 0
    end

    if unit.GetGUID then
        local ok, guid = pcall(function()
            return unit:GetGUID()
        end)

        if ok and guid then
            return guid
        end
    end

    if unit.GetGUIDLow then
        local ok, guid = pcall(function()
            return unit:GetGUIDLow()
        end)

        if ok and guid then
            return guid
        end
    end

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

local function IsUsableUnit(unit)
    if not unit then
        return false
    end

    if unit.GetGUID then
        local ok, guid = pcall(function()
            return unit:GetGUID()
        end)

        return ok and guid ~= nil
    end

    if unit.GetGUIDLow then
        local ok, guid = pcall(function()
            return unit:GetGUIDLow()
        end)

        return ok and guid ~= nil
    end

    return true
end

local function GetSpellTarget(player, spell)
    -- Prefer the player's live selected target. Spell target userdata can be
    -- invalidated by ALE almost immediately after the cast event.
    if player and player.GetSelection then
        local ok, target = pcall(function()
            return player:GetSelection()
        end)

        if ok and IsUsableUnit(target) then
            return target
        end
    end

    if player and player.GetVictim then
        local ok, target = pcall(function()
            return player:GetVictim()
        end)

        if ok and IsUsableUnit(target) then
            return target
        end
    end

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

                if ok and IsUsableUnit(target) then
                    return target
                end
            end
        end
    end

    return nil
end

local function IsSameUnit(a, b)
    local guidA = GetDmlGuid(a)
    local guidB = GetDmlGuid(b)

    return guidA ~= 0 and guidA == guidB
end

local function IsValidComboTarget(player, target)
    if not player or not target then
        return false
    end

    if IsSameUnit(player, target) then
        return false
    end

    if player.IsHostileTo then
        local ok, hostile = pcall(function()
            return player:IsHostileTo(target)
        end)

        if ok then
            return hostile
        end
    end

    -- Fallback: allow if ALE does not expose hostility check.
    return true
end

local function GetComboPointsSafe(player, target)
    if not player or not player.GetComboPoints then
        return 0
    end

    if target then
        local ok, points = pcall(function()
            return player:GetComboPoints(target)
        end)

        if ok and points then
            return tonumber(points) or 0
        end
    end

    local ok, points = pcall(function()
        return player:GetComboPoints()
    end)

    if ok and points then
        return tonumber(points) or 0
    end

    return 0
end

local function TryAddComboPoints(player, target, points)
    if not player or not target or not player.AddComboPoints then
        return false, "AddComboPoints is not available."
    end

    -- Main expected ALE/Eluna-style signature.
    local ok, err = pcall(function()
        player:AddComboPoints(target, points)
    end)

    if ok then
        return true, nil
    end

    -- Fallback for builds that expose a target conversion helper.
    if target.ToUnit then
        local unitOk, unitTarget = pcall(function()
            return target:ToUnit()
        end)

        if unitOk and unitTarget then
            ok, err = pcall(function()
                player:AddComboPoints(unitTarget, points)
            end)

            if ok then
                return true, nil
            end
        end
    end

    return false, err
end

local function AddComboPoint(player, target, spellId)
    if not player or not target then
        return
    end

    if not player.AddComboPoints then
        ComboDebug(player, "AddComboPoints is not available in this ALE build.")
        return
    end

    if not IsValidComboTarget(player, target) then
        ComboDebug(player, "Combo point builder failed: invalid target.")
        return
    end

    local currentPoints = GetComboPointsSafe(player, target)

    if currentPoints >= MAX_COMBO_POINTS then
        ComboDebug(player, "Combo points already full.")
        return
    end

    local ok, err = TryAddComboPoints(player, target, COMBO_POINTS_TO_ADD)

    if ok then
        local newPoints = currentPoints + COMBO_POINTS_TO_ADD

        if newPoints > MAX_COMBO_POINTS then
            newPoints = MAX_COMBO_POINTS
        end

        ComboDebug(
            player,
            "Spell " ..
            tostring(spellId) ..
            " added 1 combo point. Current: " ..
            tostring(newPoints) ..
            "."
        )
    else
        ComboDebug(player, "Failed to add combo point: " .. tostring(err))
    end
end

local function RemoveDeterrenceAura(player)
    if not player or not player.RemoveAura then
        return
    end

    pcall(function()
        if player:HasAura(SPELL_DETERRENCE) then
            player:RemoveAura(SPELL_DETERRENCE)
        end
    end)
end

local function ResetNativeDeterrenceCooldown(player)
    if not player then
        return
    end

    pcall(function()
        if player.ResetSpellCooldown then
            player:ResetSpellCooldown(SPELL_DETERRENCE, true)
        elseif player.RemoveSpellCooldown then
            player:RemoveSpellCooldown(SPELL_DETERRENCE)
        end
    end)
end

local function SendDmlCooldown(player, remainingSeconds)
    if not player then
        return
    end

    local remainingMs = math.max(0, remainingSeconds) * 1000

    player:SendBroadcastMessage(
        "DMLCD|COOLDOWN|31567|" .. tostring(remainingMs)
    )

    if remainingMs <= 0 then
        player:SendBroadcastMessage("DMLCD|RESET|31567")
    end
end

local function GetRemainingCooldownSeconds(player)
    if not player then
        return 0
    end

    local guid = player:GetGUIDLow()
    local cooldownEnd = deterrenceCooldownEndByGuid[guid] or 0
    local remaining = cooldownEnd - Now()

    if remaining < 0 then
        remaining = 0
    end

    return remaining
end

local function OnDeterrenceCast(player)
    local guid = player:GetGUIDLow()
    local remaining = GetRemainingCooldownSeconds(player)

    if remaining > 0 then
        player:RegisterEvent(
            function(eventId, delay, repeats, livePlayer)
                RemoveDeterrenceAura(livePlayer)
                ResetNativeDeterrenceCooldown(livePlayer)
                SendDmlCooldown(livePlayer, remaining)
            end,
            50,
            1
        )

        Debug(
            player,
            "Deterrence is still on cooldown: " ..
            tostring(remaining) ..
            " second(s)."
        )

        return
    end

    deterrenceCooldownEndByGuid[guid] =
        Now() + DETERRENCE_BASE_COOLDOWN_SECONDS

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            ResetNativeDeterrenceCooldown(livePlayer)
            SendDmlCooldown(livePlayer, DETERRENCE_BASE_COOLDOWN_SECONDS)
        end,
        50,
        1
    )

    Debug(player, "Deterrence activated. Cooldown started: 120 seconds.")
end

local function ReduceDeterrenceCooldown(player, comboPoints)
    if not player or comboPoints <= 0 then
        return
    end

    local guid = player:GetGUIDLow()
    local currentEnd = deterrenceCooldownEndByGuid[guid] or 0

    if currentEnd <= Now() then
        deterrenceCooldownEndByGuid[guid] = 0
        return
    end

    local reduction = comboPoints * CDR_PER_COMBO_POINT_SECONDS
    local newEnd = currentEnd - reduction

    if newEnd <= Now() then
        deterrenceCooldownEndByGuid[guid] = 0
        SendDmlCooldown(player, 0)
        Debug(player, "Deterrence cooldown is ready.")
        return
    end

    deterrenceCooldownEndByGuid[guid] = newEnd

    local remaining = newEnd - Now()

    SendDmlCooldown(player, remaining)

    Debug(
        player,
        "Spent " ..
        tostring(comboPoints) ..
        " combo point(s): Deterrence cooldown reduced by " ..
        tostring(reduction) ..
        " second(s). Remaining: " ..
        tostring(remaining) ..
        " second(s)."
    )
end

local function OnSpellCast(event, player, spell, skipCheck)
    if not player or not spell then
        return
    end

    if not IsSwashbuckler(player) then
        return
    end

    local spellId = GetDmlSpellId(spell)

    if spellId == SPELL_DETERRENCE then
        OnDeterrenceCast(player)
        return
    end

    local target = GetSpellTarget(player, spell)

    if COMBO_BUILDER_SPELLS[spellId] then
        -- Add immediately. Delaying this can invalidate the creature target
        -- userdata in ALE and causes "pointer to nonexisting object" errors.
        AddComboPoint(player, target, spellId)
        return
    end

    if not FINISHER_SPELLS[spellId] then
        return
    end

    local comboPoints = GetComboPointsSafe(player, target)

    if comboPoints <= 0 then
        return
    end

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            ReduceDeterrenceCooldown(livePlayer, comboPoints)
        end,
        50,
        1
    )
end

local function OnLogin(event, player)
    if not player then
        return
    end

    if not IsSwashbuckler(player) then
        return
    end

    ResetNativeDeterrenceCooldown(player)
    SendDmlCooldown(player, GetRemainingCooldownSeconds(player))
end

local function OnLogout(event, player)
    if not player then
        return
    end

    -- Session-based cooldown. Remove this line if you want cooldown to persist through logout.
    deterrenceCooldownEndByGuid[player:GetGUIDLow()] = nil
end

RegisterPlayerEvent(PLAYER_EVENT_ON_LOGIN, OnLogin)
RegisterPlayerEvent(PLAYER_EVENT_ON_LOGOUT, OnLogout)
RegisterPlayerEvent(PLAYER_EVENT_ON_SPELL_CAST, OnSpellCast)

print("[DML Swash Deterrence CDR] Lua-managed Deterrence cooldown + live combo builders loaded.")
