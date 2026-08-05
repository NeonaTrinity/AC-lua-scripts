-- ============================================================
-- DML Shared Smash Cooldown
--
-- Smash spells:
--   * 34618 - Smash
--   * 61070 - Tanking Smash alternative
--
-- Behavior:
--   * Casting either spell starts one shared 10-second cooldown.
--   * Both spell IDs are sent to DMLCooldownBar.
--   * Attempts to cast either spell during the shared timer are
--     cancelled during SPELL_EVENT_ON_PREPARE.
--   * Each spell keeps its existing native 10-second cooldown.
--   * Lua does not reset, replace, or otherwise alter native cooldowns.
-- ============================================================

local SPELL_SMASH = 34618
local SPELL_TANK_SMASH = 61070

local SHARED_COOLDOWN_MS = 10 * 1000

local SPELL_EVENT_ON_PREPARE = 1
local SPELL_EVENT_ON_CAST = 2
local PLAYER_EVENT_ON_LOGOUT = 4

local DML_ADDON_PREFIX = "DMLCD"
local CHAT_MSG_WHISPER = 7

local DEBUG_SHARED_SMASH = true

local SMASH_SPELLS = {
    [SPELL_SMASH] = true,
    [SPELL_TANK_SMASH] = true,
}

-- One shared timer per player GUIDLow.
local cooldownByGuid = {}
local serialByGuid = {}

local function Debug(player, message)
    if not DEBUG_SHARED_SMASH then
        return
    end

    if player and player.SendBroadcastMessage then
        player:SendBroadcastMessage(
            "|cffffcc33[Shared Smash]|r " .. tostring(message)
        )
    end

    print("[DML Shared Smash] " .. tostring(message))
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

local function SendDmlMessage(player, payload)
    if not player or not player.SendAddonMessage then
        return false
    end

    local ok, err = pcall(function()
        player:SendAddonMessage(
            DML_ADDON_PREFIX,
            payload,
            CHAT_MSG_WHISPER,
            player
        )
    end)

    if not ok then
        Debug(
            player,
            "Failed to send DML message: " .. tostring(err)
        )
    end

    return ok
end

local function SendDmlCooldown(player, spellId, durationMs)
    durationMs = math.max(
        1,
        math.floor(tonumber(durationMs) or 1)
    )

    SendDmlMessage(
        player,
        "COOLDOWN|" ..
        tostring(spellId) ..
        "|" ..
        tostring(durationMs)
    )
end

local function SendBothDmlCooldowns(player, durationMs)
    SendDmlCooldown(player, SPELL_SMASH, durationMs)
    SendDmlCooldown(player, SPELL_TANK_SMASH, durationMs)
end

local function SendBothDmlResets(player)
    SendDmlMessage(
        player,
        "RESET|" .. tostring(SPELL_SMASH)
    )

    SendDmlMessage(
        player,
        "RESET|" .. tostring(SPELL_TANK_SMASH)
    )
end

local function CancelSpellSafe(spell)
    if not spell or not spell.Cancel then
        return false
    end

    local ok, err = pcall(function()
        spell:Cancel()
    end)

    if not ok then
        print(
            "[DML Shared Smash] Failed to cancel blocked Smash: " ..
            tostring(err)
        )
    end

    return ok
end

local function GetRemainingCooldown(playerGuidLow)
    local state = cooldownByGuid[playerGuidLow]

    if not state then
        return 0
    end

    local elapsedMs = GetTimeDiff(state.startedAt)

    if elapsedMs >= SHARED_COOLDOWN_MS then
        cooldownByGuid[playerGuidLow] = nil
        return 0
    end

    return SHARED_COOLDOWN_MS - elapsedMs
end

local function FinishSharedCooldown(
    eventId,
    delay,
    repeats,
    player,
    playerGuidLow,
    serial
)
    local state = cooldownByGuid[playerGuidLow]

    if not state or state.serial ~= serial then
        return
    end

    cooldownByGuid[playerGuidLow] = nil
    SendBothDmlResets(player)

    Debug(
        player,
        "Both Smash spells are ready."
    )
end

local function StartSharedCooldown(player, castSpellId)
    local playerGuidLow = player:GetGUIDLow()

    if GetRemainingCooldown(playerGuidLow) > 0 then
        return
    end

    local serial = (serialByGuid[playerGuidLow] or 0) + 1
    serialByGuid[playerGuidLow] = serial

    cooldownByGuid[playerGuidLow] = {
        startedAt = GetCurrTime(),
        serial = serial,
    }

    SendBothDmlCooldowns(
        player,
        SHARED_COOLDOWN_MS
    )

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            FinishSharedCooldown(
                eventId,
                delay,
                repeats,
                livePlayer,
                playerGuidLow,
                serial
            )
        end,
        SHARED_COOLDOWN_MS,
        1
    )

    Debug(
        player,
        "Spell " ..
        tostring(castSpellId) ..
        " started the shared 10-second Smash cooldown."
    )
end

local function OnSmashPrepare(event, caster, spell)
    local player = GetPlayerCaster(caster)

    if not player or not spell then
        return
    end

    local spellId = GetSpellId(spell)

    if not SMASH_SPELLS[spellId] then
        return
    end

    local remainingMs = GetRemainingCooldown(
        player:GetGUIDLow()
    )

    if remainingMs <= 0 then
        return
    end

    if not CancelSpellSafe(spell) then
        Debug(
            player,
            "Could not cancel Smash while its shared cooldown was active."
        )
        return
    end

    SendBothDmlCooldowns(
        player,
        remainingMs
    )

    Debug(
        player,
        "Smash blocked; " ..
        tostring(math.ceil(remainingMs / 1000)) ..
        " second(s) remain."
    )
end

local function OnSmashCast(
    event,
    caster,
    spell,
    skipCheck
)
    local player = GetPlayerCaster(caster)

    if not player or not spell then
        return
    end

    local spellId = GetSpellId(spell)

    if not SMASH_SPELLS[spellId] then
        return
    end

    StartSharedCooldown(
        player,
        spellId
    )
end

local function OnLogout(event, player)
    if not player then
        return
    end

    local playerGuidLow = player:GetGUIDLow()

    cooldownByGuid[playerGuidLow] = nil
    serialByGuid[playerGuidLow] = nil
end

for spellId in pairs(SMASH_SPELLS) do
    RegisterSpellEvent(
        spellId,
        SPELL_EVENT_ON_PREPARE,
        OnSmashPrepare
    )

    RegisterSpellEvent(
        spellId,
        SPELL_EVENT_ON_CAST,
        OnSmashCast
    )
end

RegisterPlayerEvent(
    PLAYER_EVENT_ON_LOGOUT,
    OnLogout
)

print(
    "[DML Shared Smash] " ..
    "Spells 34618 and 61070 now share a Lua-enforced 10-second cooldown."
)
