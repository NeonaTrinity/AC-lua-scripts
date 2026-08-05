-- ============================================================
-- DML Swashbuckler Razorhide -> Tank Class Passive Link
--
-- Razorhide 16610 targeting:
--   * The original cast pays its normal cost and cooldown once
--   * Any Razorhide aura applied to another unit is removed immediately
--   * Razorhide is then applied directly to the Swashbuckler only
--
-- Razorhide duration:
--   * The live Razorhide aura is extended to 30 minutes after each cast
--
-- If a Swashbuckler has Razorhide 16610:
--   * Apply/refresh Tank Class Passive 57339
--   * Apply Unbreakable Armor 51271 for 30 minutes
--   * Apply Wild Magic 45006 for 30 minutes
--   * Add 0.5 shield block value per point of Agility
--
-- If Razorhide falls off:
--   * Remove the Agility-based block-value bonus
--   * Remove Unbreakable Armor 51271
--   * Remove Wild Magic 45006
--   * Remove Tank Class Passive 57339
-- ============================================================

local CLASS_ROGUE = 4
local SUBCLASS_SWASHBUCKLER = 5

local SPELL_RAZORHIDE = 16610
local SPELL_TANK_CLASS_PASSIVE = 57339
local SPELL_RAZORHIDE_ARMOR_BONUS = 51271 -- Unbreakable Armor, +25% armor
local SPELL_RAZORHIDE_WILD_MAGIC = 45006

local PLAYER_EVENT_ON_LOGIN = 3
local PLAYER_EVENT_ON_LOGOUT = 4
local PLAYER_EVENT_ON_SPELL_CAST = 5
local PLAYER_EVENT_ON_AURA_APPLY = 64
local ALL_CREATURE_EVENT_ON_AURA_APPLY = 5

local RAZORHIDE_DURATION_MS = 30 * 60 * 1000
local RAZORHIDE_ARMOR_BONUS_DURATION_MS = 30 * 60 * 1000
local RAZORHIDE_WILD_MAGIC_DURATION_MS = 30 * 60 * 1000
local CHECK_DELAY_MS = 500
local MONITOR_DELAY_MS = 1000

-- AzerothCore stat index 1 is Agility.
local STAT_AGILITY = 1
local BLOCK_VALUE_PER_AGILITY = 0.5

-- AzerothCore WotLK UpdateFields.h:
-- PLAYER_SHIELD_BLOCK = UNIT_END + 0x037B = 0x040F.
local PLAYER_SHIELD_BLOCK_FIELD = 0x040F

local DEBUG_RAZORHIDE_LINK = false
-- Indexed by player GUIDLow.
-- Each state tracks only the block-value contribution written by this script.
local activeByGuid = {}

local function Debug(player, msg)
    if DEBUG_RAZORHIDE_LINK and player then
        player:SendBroadcastMessage("|cff00ccff[Razorhide]|r " .. tostring(msg))
    end

    if DEBUG_RAZORHIDE_LINK then
        print("[DML Razorhide Tank Passive] " .. tostring(msg))
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


local function GetAuraIdSafe(aura)
    if not aura or not aura.GetAuraId then
        return 0
    end

    local ok, auraId = pcall(function()
        return aura:GetAuraId()
    end)

    if not ok or type(auraId) ~= "number" then
        return 0
    end

    return auraId
end

local function GetAuraCasterSafe(aura)
    if not aura or not aura.GetCaster then
        return nil
    end

    local ok, caster = pcall(function()
        return aura:GetCaster()
    end)

    if ok then
        return caster
    end

    return nil
end

local function SetAuraObjectDurationSafe(aura, durationMs)
    if not aura then
        return false
    end

    local ok = pcall(function()
        if aura.SetMaxDuration then
            aura:SetMaxDuration(durationMs)
        end

        if aura.SetDuration then
            aura:SetDuration(durationMs)
        end
    end)

    return ok
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

local function HasAuraSafe(unit, spellId)
    if not unit or not unit.HasAura then
        return false
    end

    local ok, result = pcall(function()
        return unit:HasAura(spellId)
    end)

    return ok and result
end

local function SetRazorhideDuration(player)
    if not player or not player.GetAura then
        return false
    end

    local ok, changed = pcall(function()
        local aura = player:GetAura(SPELL_RAZORHIDE)

        if not aura then
            return false
        end

        if aura.SetMaxDuration then
            aura:SetMaxDuration(RAZORHIDE_DURATION_MS)
        end

        if aura.SetDuration then
            aura:SetDuration(RAZORHIDE_DURATION_MS)
        end

        return true
    end)

    if not ok then
        Debug(player, "Failed to set Razorhide duration to 30 minutes.")
        return false
    end

    if changed then
        Debug(player, "Razorhide duration set to 30 minutes.")
    end

    return changed
end

local function IsSameObjectSafe(left, right)
    if not left or not right then
        return false
    end

    -- Both objects are live only for this callback, so direct comparison is safe.
    local ok, same = pcall(function()
        return left == right
    end)

    return ok and same
end

local function GetAgilitySafe(player)
    if not player or not player.GetStat then
        return nil
    end

    local ok, value = pcall(function()
        return player:GetStat(STAT_AGILITY)
    end)

    if not ok or type(value) ~= "number" then
        return nil
    end

    return math.max(0, math.floor(value))
end

local function GetShieldBlockValueSafe(player)
    if not player or not player.GetShieldBlockValue then
        return nil
    end

    local ok, value = pcall(function()
        return player:GetShieldBlockValue()
    end)

    if not ok or type(value) ~= "number" then
        return nil
    end

    return math.max(0, math.floor(value))
end

local function SetShieldBlockValueSafe(player, value)
    if not player or not player.SetUInt32Value then
        return false, "SetUInt32Value is unavailable"
    end

    value = math.max(0, math.floor(value))

    local ok, err = pcall(function()
        player:SetUInt32Value(
            PLAYER_SHIELD_BLOCK_FIELD,
            value
        )
    end)

    return ok, err
end

local function GetOrCreateState(player)
    local guid = player:GetGUIDLow()
    local state = activeByGuid[guid]

    if not state then
        state = {
            lastBonus = 0,
            lastWrittenBlock = nil,
            lastAgility = nil
        }

        activeByGuid[guid] = state
    end

    return state
end

local function RefreshAgilityBlockBonus(player)
    if not player then
        return
    end

    local agility = GetAgilitySafe(player)
    local currentBlock = GetShieldBlockValueSafe(player)

    if agility == nil or currentBlock == nil then
        Debug(
            player,
            "Could not read Agility or shield block value."
        )

        return
    end

    local state = GetOrCreateState(player)
    local oldBonus = state.lastBonus or 0

    -- If the field still equals the value written by this script, remove the
    -- old scripted bonus to recover the true base value.
    --
    -- If the core recalculated the field because equipment or another aura
    -- changed, currentBlock differs from lastWrittenBlock and is treated as
    -- the newly recalculated base.
    local baseBlock = currentBlock

    if state.lastWrittenBlock ~= nil
        and currentBlock == state.lastWrittenBlock
    then
        baseBlock = math.max(
            0,
            currentBlock - oldBonus
        )
    end

    -- Block value is integer-based. Odd Agility totals round down:
    -- 51 Agility grants 25 block value.
    local newBonus = math.floor(
        agility * BLOCK_VALUE_PER_AGILITY
    )

    local desiredBlock = baseBlock + newBonus

    if desiredBlock ~= currentBlock then
        local ok, err = SetShieldBlockValueSafe(
            player,
            desiredBlock
        )

        if not ok then
            Debug(
                player,
                "Failed to update Agility block bonus: " ..
                tostring(err)
            )

            return
        end
    end

    local bonusChanged =
        state.lastBonus ~= newBonus
        or state.lastAgility ~= agility
        or state.lastWrittenBlock ~= desiredBlock

    state.lastBonus = newBonus
    state.lastWrittenBlock = desiredBlock
    state.lastAgility = agility

    if bonusChanged then
        Debug(
            player,
            "Agility block bonus updated: +" ..
            newBonus ..
            " block value from " ..
            agility ..
            " Agility. Total block value: " ..
            desiredBlock ..
            "."
        )
    end
end

local function RemoveAgilityBlockBonus(player)
    if not player then
        return
    end

    local guid = player:GetGUIDLow()
    local state = activeByGuid[guid]

    if not state or not state.lastBonus
        or state.lastBonus <= 0
    then
        return
    end

    local currentBlock = GetShieldBlockValueSafe(player)

    if currentBlock == nil then
        return
    end

    -- Only subtract if the current field still matches the value this script
    -- last wrote. If the core already recalculated it, the scripted bonus is
    -- already gone and must not be subtracted again.
    if state.lastWrittenBlock ~= nil
        and currentBlock == state.lastWrittenBlock
    then
        local restoredBlock = math.max(
            0,
            currentBlock - state.lastBonus
        )

        local ok, err = SetShieldBlockValueSafe(
            player,
            restoredBlock
        )

        if ok then
            Debug(
                player,
                "Removed +" ..
                state.lastBonus ..
                " Razorhide block value. Block value restored to " ..
                restoredBlock ..
                "."
            )
        else
            Debug(
                player,
                "Failed to remove Agility block bonus: " ..
                tostring(err)
            )
        end
    end

    state.lastBonus = 0
    state.lastWrittenBlock = nil
    state.lastAgility = nil
end

local function ApplyTankPassive(player)
    if not player then
        return
    end

    if HasAuraSafe(player, SPELL_TANK_CLASS_PASSIVE) then
        return
    end

    local ok, err = pcall(function()
        if player.AddAura then
            player:AddAura(SPELL_TANK_CLASS_PASSIVE, player)
        else
            player:CastSpell(player, SPELL_TANK_CLASS_PASSIVE, true)
        end
    end)

    if ok then
        Debug(player, "Tank Class Passive applied while Razorhide is active.")
    else
        Debug(player, "Failed to apply Tank Class Passive: " .. tostring(err))
    end
end

local function RemoveTankPassive(player)
    if not player then
        return
    end

    if not HasAuraSafe(player, SPELL_TANK_CLASS_PASSIVE) then
        return
    end

    local ok, err = pcall(function()
        player:RemoveAura(SPELL_TANK_CLASS_PASSIVE)
    end)

    if ok then
        Debug(player, "Tank Class Passive removed because Razorhide ended.")
    else
        Debug(player, "Failed to remove Tank Class Passive: " .. tostring(err))
    end
end

local function SetArmorBonusDuration(player)
    if not player or not player.GetAura then
        return false
    end

    local ok, changed = pcall(function()
        local aura = player:GetAura(SPELL_RAZORHIDE_ARMOR_BONUS)

        if not aura then
            return false
        end

        if aura.SetMaxDuration then
            aura:SetMaxDuration(RAZORHIDE_ARMOR_BONUS_DURATION_MS)
        end

        if aura.SetDuration then
            aura:SetDuration(RAZORHIDE_ARMOR_BONUS_DURATION_MS)
        end

        return true
    end)

    if not ok then
        Debug(player, "Failed to set Unbreakable Armor duration to 30 minutes.")
        return false
    end

    return changed
end

local function ApplyArmorBonus(player)
    if not player then
        return
    end

    if HasAuraSafe(player, SPELL_RAZORHIDE_ARMOR_BONUS) then
        return
    end

    local ok, err = pcall(function()
        if player.AddAura then
            player:AddAura(SPELL_RAZORHIDE_ARMOR_BONUS, player)
        else
            player:CastSpell(player, SPELL_RAZORHIDE_ARMOR_BONUS, true)
        end
    end)

    if not ok then
        Debug(player, "Failed to apply Razorhide armor bonus: " .. tostring(err))
        return
    end

    if SetArmorBonusDuration(player) then
        Debug(player, "Unbreakable Armor applied for 30 minutes.")
    else
        Debug(player, "Unbreakable Armor applied, but its duration could not be extended.")
    end
end

local function RemoveArmorBonus(player)
    if not player then
        return
    end

    if not HasAuraSafe(player, SPELL_RAZORHIDE_ARMOR_BONUS) then
        return
    end

    local ok, err = pcall(function()
        player:RemoveAura(SPELL_RAZORHIDE_ARMOR_BONUS)
    end)

    if ok then
        Debug(player, "Razorhide armor bonus removed.")
    else
        Debug(player, "Failed to remove Razorhide armor bonus: " .. tostring(err))
    end
end


local function SetWildMagicDuration(player)
    if not player or not player.GetAura then
        return false
    end

    local ok, changed = pcall(function()
        local aura = player:GetAura(SPELL_RAZORHIDE_WILD_MAGIC)

        if not aura then
            return false
        end

        return SetAuraObjectDurationSafe(
            aura,
            RAZORHIDE_WILD_MAGIC_DURATION_MS
        )
    end)

    if not ok then
        Debug(player, "Failed to set Wild Magic duration to 30 minutes.")
        return false
    end

    return changed
end

local function ApplyWildMagic(player)
    if not player then
        return
    end

    if HasAuraSafe(player, SPELL_RAZORHIDE_WILD_MAGIC) then
        return
    end

    local aura = nil
    local ok, err = pcall(function()
        if player.AddAura then
            aura = player:AddAura(SPELL_RAZORHIDE_WILD_MAGIC, player)
        else
            player:CastSpell(player, SPELL_RAZORHIDE_WILD_MAGIC, true)
        end
    end)

    if not ok then
        Debug(player, "Failed to apply Wild Magic: " .. tostring(err))
        return
    end

    local durationSet = false

    if aura then
        durationSet = SetAuraObjectDurationSafe(
            aura,
            RAZORHIDE_WILD_MAGIC_DURATION_MS
        )
    else
        durationSet = SetWildMagicDuration(player)
    end

    if durationSet then
        Debug(player, "Wild Magic applied for 30 minutes.")
    else
        Debug(player, "Wild Magic applied, but its duration could not be extended.")
    end
end

local function RemoveWildMagic(player)
    if not player then
        return
    end

    if not HasAuraSafe(player, SPELL_RAZORHIDE_WILD_MAGIC) then
        return
    end

    local ok, err = pcall(function()
        player:RemoveAura(SPELL_RAZORHIDE_WILD_MAGIC)
    end)

    if ok then
        Debug(player, "Wild Magic removed because Razorhide ended.")
    else
        Debug(player, "Failed to remove Wild Magic: " .. tostring(err))
    end
end

local function StopMonitor(player)
    if not player then
        return
    end

    local guid = player:GetGUIDLow()
    activeByGuid[guid] = nil
end

local function MonitorRazorhide(eventId, delay, repeats, player)
    if not player then
        return
    end

    local guid = player:GetGUIDLow()

    if not activeByGuid[guid] then
        return
    end

    if not IsSwashbuckler(player) then
        RemoveAgilityBlockBonus(player)
        RemoveArmorBonus(player)
        RemoveWildMagic(player)
        RemoveTankPassive(player)
        StopMonitor(player)
        return
    end

    if HasAuraSafe(player, SPELL_RAZORHIDE) then
        ApplyTankPassive(player)
        ApplyArmorBonus(player)
        ApplyWildMagic(player)
        RefreshAgilityBlockBonus(player)

        player:RegisterEvent(
            MonitorRazorhide,
            MONITOR_DELAY_MS,
            1
        )

        return
    end

    RemoveAgilityBlockBonus(player)
    RemoveArmorBonus(player)
    RemoveWildMagic(player)
    RemoveTankPassive(player)
    StopMonitor(player)
end

local function StartMonitor(player)
    if not player or not IsSwashbuckler(player) then
        return
    end

    local guid = player:GetGUIDLow()

    if activeByGuid[guid] then
        return
    end

    GetOrCreateState(player)

    player:RegisterEvent(
        MonitorRazorhide,
        MONITOR_DELAY_MS,
        1
    )
end

local function RepairRazorhideLink(player, reason)
    if not player then
        return
    end

    if not IsSwashbuckler(player) then
        RemoveAgilityBlockBonus(player)
        RemoveArmorBonus(player)
        RemoveWildMagic(player)
        RemoveTankPassive(player)
        StopMonitor(player)
        return
    end

    if HasAuraSafe(player, SPELL_RAZORHIDE) then
        StartMonitor(player)
        ApplyTankPassive(player)
        ApplyArmorBonus(player)
        ApplyWildMagic(player)
        RefreshAgilityBlockBonus(player)
        return
    end

    RemoveAgilityBlockBonus(player)
    RemoveArmorBonus(player)
    RemoveWildMagic(player)
    RemoveTankPassive(player)
    StopMonitor(player)
end


local function HandleRazorhideAuraApplied(owner, aura)
    if not owner or not aura then
        return
    end

    if GetAuraIdSafe(aura) ~= SPELL_RAZORHIDE then
        return
    end

    local caster = GetAuraCasterSafe(aura)

    if not caster or not caster.GetClass or not caster.GetGUIDLow then
        return
    end

    if not IsSwashbuckler(caster) then
        return
    end

    -- Correct self-casts remain on the Swashbuckler and are extended normally.
    if IsSameObjectSafe(owner, caster) then
        SetAuraObjectDurationSafe(aura, RAZORHIDE_DURATION_MS)
        return
    end

    -- ALE's spell-prepare cancellation can still allow this instant aura to
    -- finish applying on some builds. Remove the wrong-target aura at the aura
    -- hook, then apply Razorhide directly to the original caster. The original
    -- cast already paid its normal mana cost and cooldown, so AddAura must not
    -- charge the player a second time.
    local removed = pcall(function()
        if aura.Remove then
            aura:Remove()
        elseif owner.RemoveAura then
            owner:RemoveAura(SPELL_RAZORHIDE)
        end
    end)

    if not removed then
        Debug(caster, "Failed to remove Razorhide from the non-self target.")
    end

    caster:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            if not livePlayer or not IsSwashbuckler(livePlayer) then
                return
            end

            local selfAura = nil

            if livePlayer.GetAura then
                local ok, existingAura = pcall(function()
                    return livePlayer:GetAura(SPELL_RAZORHIDE)
                end)

                if ok then
                    selfAura = existingAura
                end
            end

            if not selfAura then
                local ok, appliedAura = pcall(function()
                    if livePlayer.AddAura then
                        return livePlayer:AddAura(
                            SPELL_RAZORHIDE,
                            livePlayer
                        )
                    end

                    livePlayer:CastSpell(
                        livePlayer,
                        SPELL_RAZORHIDE,
                        true
                    )

                    return nil
                end)

                if not ok then
                    Debug(
                        livePlayer,
                        "Failed to redirect Razorhide to the Swashbuckler."
                    )
                    return
                end

                selfAura = appliedAura
            end

            if selfAura then
                SetAuraObjectDurationSafe(
                    selfAura,
                    RAZORHIDE_DURATION_MS
                )
            else
                SetRazorhideDuration(livePlayer)
            end

            RepairRazorhideLink(livePlayer, "redirected aura")
            Debug(livePlayer, "Razorhide redirected to the Swashbuckler.")
        end,
        1,
        1
    )
end

local function OnPlayerAuraApply(event, player, aura)
    HandleRazorhideAuraApplied(player, aura)
end

local function OnCreatureAuraApply(event, creature, aura)
    HandleRazorhideAuraApplied(creature, aura)
end

local function OnLogin(event, player)
    if not player then
        return
    end

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            RepairRazorhideLink(livePlayer, "login")
        end,
        CHECK_DELAY_MS,
        1
    )
end

local function OnLogout(event, player)
    if not player then
        return
    end

    local guid = player:GetGUIDLow()
    activeByGuid[guid] = nil
end

local function OnSpellCast(event, player, spell, skipCheck)
    if not player or not spell then
        return
    end

    local spellId = GetDmlSpellId(spell)

    if spellId ~= SPELL_RAZORHIDE then
        return
    end

    if not IsSwashbuckler(player) then
        return
    end

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            if not livePlayer then
                return
            end

            SetRazorhideDuration(livePlayer)
            RepairRazorhideLink(livePlayer, "cast")
        end,
        CHECK_DELAY_MS,
        1
    )
end

RegisterPlayerEvent(PLAYER_EVENT_ON_LOGIN, OnLogin)
RegisterPlayerEvent(PLAYER_EVENT_ON_LOGOUT, OnLogout)
RegisterPlayerEvent(PLAYER_EVENT_ON_SPELL_CAST, OnSpellCast)
RegisterPlayerEvent(PLAYER_EVENT_ON_AURA_APPLY, OnPlayerAuraApply)

RegisterAllCreatureEvent(
    ALL_CREATURE_EVENT_ON_AURA_APPLY,
    OnCreatureAuraApply
)

print(
    "[DML Razorhide Tank Passive] " ..
    "Swashbuckler Razorhide self-only + 30-minute Unbreakable Armor/Wild Magic link loaded."
)