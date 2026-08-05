-- ============================================================
-- DML Warlock Vampiric Embrace -> Prophecy of Blood Link
--
-- Warlock/Cultist behavior:
-- If a Warlock has Vampiric Embrace active, also apply/refresh
-- Prophecy of Blood.
--
-- Main aura:
-- Vampiric Embrace 15286
--
-- Linked aura:
-- Prophecy of Blood 41231
--
-- Behavior:
-- Cast Vampiric Embrace on       -> applies Prophecy of Blood
-- Recast Vampiric Embrace off    -> removes Prophecy of Blood
-- Right-click/cancel VE          -> removes Prophecy within monitor tick
-- Right-click/cancel Prophecy    -> removes Vampiric Embrace within monitor tick
-- Login/server restart repair    -> relinks the auras if VE persisted alone
--
-- Priests are ignored.
-- ============================================================

local CLASS_WARLOCK = 9

local SPELL_VAMPIRIC_EMBRACE = 15286
local SPELL_PROPHECY_OF_BLOOD = 41231

local PLAYER_EVENT_ON_LOGIN = 3
local PLAYER_EVENT_ON_LOGOUT = 4
local PLAYER_EVENT_ON_SPELL_CAST = 5

local WARLOCK_VE_DEBUG = false

-- Check often enough that canceling either linked aura resolves quickly.
local PROPHECY_MONITOR_DELAY_MS = 5000

-- Prophecy naturally lasts about 30 sec, so refresh before that.
local PROPHECY_REFRESH_EVERY_MS = 20000

-- Delay login repair so saved auras have time to restore after login.
local LINK_REPAIR_DELAY_MS = 2000

local activeByGuid = {}

local function DmlDebug(message)
    if WARLOCK_VE_DEBUG then
        print("[DML Warlock VE Prophecy] " .. tostring(message))
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

local function GetDmlName(unit)
    if unit and unit.GetName then
        return unit:GetName()
    end

    return "unknown"
end

local function IsWarlock(player)
    return player and player:GetClass() == CLASS_WARLOCK
end

local function HasAuraSafe(player, spellId)
    if not player then
        return false
    end

    if player.HasAura then
        return player:HasAura(spellId)
    end

    return false
end

local function ApplyProphecy(player)
    if not player then
        return false
    end

    local ok, err = pcall(function()
        if player.AddAura then
            player:AddAura(SPELL_PROPHECY_OF_BLOOD, player)
        elseif player.CastSpell then
            player:CastSpell(player, SPELL_PROPHECY_OF_BLOOD, true)
        else
            error("No AddAura or CastSpell method available.")
        end
    end)

    if not ok then
        DmlDebug("Failed to apply Prophecy of Blood: " .. tostring(err))
        return false
    end

    return true
end

local function RemoveProphecy(player)
    if not player then
        return
    end

    if not HasAuraSafe(player, SPELL_PROPHECY_OF_BLOOD) then
        return
    end

    local ok, err = pcall(function()
        if player.RemoveAura then
            player:RemoveAura(SPELL_PROPHECY_OF_BLOOD)
        else
            error("No RemoveAura method available.")
        end
    end)

    if not ok then
        DmlDebug("Failed to remove Prophecy of Blood: " .. tostring(err))
    end
end

local function RemoveVampiricEmbrace(player)
    if not player then
        return
    end

    if not HasAuraSafe(player, SPELL_VAMPIRIC_EMBRACE) then
        return
    end

    local ok, err = pcall(function()
        if player.RemoveAura then
            player:RemoveAura(SPELL_VAMPIRIC_EMBRACE)
        else
            error("No RemoveAura method available.")
        end
    end)

    if not ok then
        DmlDebug("Failed to remove Vampiric Embrace: " .. tostring(err))
    end
end

local function StopProphecyLoop(player, guid)
    if guid and guid ~= 0 then
        activeByGuid[guid] = nil
    end

    RemoveProphecy(player)
end

local function ScheduleProphecyMonitor(player)
    if not player then
        return
    end

    local guid = GetDmlGuidLow(player)

    if guid == 0 then
        return
    end

    if activeByGuid[guid] then
        return
    end

    local playerName = GetDmlName(player)

    activeByGuid[guid] = {
        elapsed = 0,
    }

    DmlDebug("Started linked Prophecy monitor for " .. tostring(playerName))

    local function Tick()
        CreateLuaEvent(function()
            local ok, err = pcall(function()
                local livePlayer = nil

                if GetPlayerByName then
                    livePlayer = GetPlayerByName(playerName)
                end

                if not livePlayer then
                    activeByGuid[guid] = nil
                    return
                end

                -- Only Warlocks get the linked aura. Priests are ignored.
                if not IsWarlock(livePlayer) then
                    StopProphecyLoop(livePlayer, guid)
                    return
                end

                -- Vampiric Embrace is the controlling aura.
                if not HasAuraSafe(livePlayer, SPELL_VAMPIRIC_EMBRACE) then
                    StopProphecyLoop(livePlayer, guid)
                    DmlDebug("Stopped linked Prophecy; Vampiric Embrace is gone for " .. tostring(playerName))
                    return
                end

                local state = activeByGuid[guid]

                if not state then
                    return
                end

                state.elapsed = state.elapsed + PROPHECY_MONITOR_DELAY_MS

                -- If Prophecy is missing while VE is still active, treat that as the
                -- player canceling the linked tank mode. Remove VE too.
                if not HasAuraSafe(livePlayer, SPELL_PROPHECY_OF_BLOOD) then
                    RemoveVampiricEmbrace(livePlayer)
                    StopProphecyLoop(livePlayer, guid)

                    DmlDebug("Prophecy was canceled; Vampiric Embrace removed for " .. tostring(playerName))
                    return
                end

                -- Otherwise refresh Prophecy before its natural 30 sec expiration.
                if state.elapsed >= PROPHECY_REFRESH_EVERY_MS then
                    ApplyProphecy(livePlayer)
                    state.elapsed = 0

                    DmlDebug("Refreshed Prophecy of Blood for " .. tostring(playerName))
                end

                Tick()
            end)

            if not ok then
                activeByGuid[guid] = nil
                DmlDebug("Monitor error: " .. tostring(err))
            end
        end, PROPHECY_MONITOR_DELAY_MS, 1)
    end

    -- Apply once right away, then monitor.
    ApplyProphecy(player)
    Tick()
end

local function RepairWarlockVampiricProphecyLink(player, reason)
    if not player then
        return
    end

    if not IsWarlock(player) then
        return
    end

    local guid = GetDmlGuidLow(player)

    if guid == 0 then
        return
    end

    local hasVampiricEmbrace = HasAuraSafe(player, SPELL_VAMPIRIC_EMBRACE)
    local hasProphecy = HasAuraSafe(player, SPELL_PROPHECY_OF_BLOOD)

    -- VE is the controlling aura.
    -- If VE exists, Prophecy should exist and the monitor should be active.
    if hasVampiricEmbrace then
        if not hasProphecy then
            ApplyProphecy(player)

            DmlDebug(
                "Repair applied missing Prophecy of Blood. Reason=" ..
                tostring(reason) ..
                " Player=" ..
                GetDmlName(player)
            )
        end

        ScheduleProphecyMonitor(player)
        return
    end

    -- If Prophecy exists without VE, remove it.
    if hasProphecy then
        RemoveProphecy(player)

        DmlDebug(
            "Repair removed orphaned Prophecy of Blood. Reason=" ..
            tostring(reason) ..
            " Player=" ..
            GetDmlName(player)
        )
    end

    activeByGuid[guid] = nil
end

local function OnWarlockLogin(event, player)
    if not player then
        return
    end

    if not IsWarlock(player) then
        return
    end

    -- Delay a little so saved auras are fully restored before checking.
    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            RepairWarlockVampiricProphecyLink(livePlayer, "login")
        end,
        LINK_REPAIR_DELAY_MS,
        1
    )
end

local function OnWarlockVampiricEmbraceCast(event, player, spell, skipCheck)
    local spellId = GetDmlSpellId(spell)

    if spellId ~= SPELL_VAMPIRIC_EMBRACE then
        return
    end

    if not IsWarlock(player) then
        return
    end

    local playerName = GetDmlName(player)

    -- Wait one short tick so the aura state reflects whether the cast turned VE on or off.
    CreateLuaEvent(function()
        local livePlayer = nil

        if GetPlayerByName then
            livePlayer = GetPlayerByName(playerName)
        end

        if not livePlayer then
            return
        end

        RepairWarlockVampiricProphecyLink(livePlayer, "cast")
    end, 500, 1)
end

local function OnWarlockLogout(event, player)
    local guid = GetDmlGuidLow(player)

    if guid ~= 0 then
        activeByGuid[guid] = nil
    end
end

RegisterPlayerEvent(PLAYER_EVENT_ON_LOGIN, OnWarlockLogin)
RegisterPlayerEvent(PLAYER_EVENT_ON_LOGOUT, OnWarlockLogout)
RegisterPlayerEvent(PLAYER_EVENT_ON_SPELL_CAST, OnWarlockVampiricEmbraceCast)

print("[DML Warlock VE Prophecy] Linked aura script with login repair loaded.")
