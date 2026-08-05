-- ============================================================
-- DML Paladin Exorcism -> Holy Vengeance + Shared Cooldown
--
-- Holy Vengeance:
--   * A successful Templar Exorcism damage hit trigger-casts 31803.
--   * Event 70 applies it directly from the confirmed damage hit.
--   * The Templar remains the Holy Vengeance aura caster/owner.
--   * Each hit adds one native Holy Vengeance stack.
--
-- Templar restriction:
--   * This entire script applies only to Paladins with subclass ID 2.
--   * Non-Templar Paladins retain native Exorcism behavior and cooldowns.
--
-- Exorcism cooldown:
--   * All nine Exorcism ranks share one Lua-managed 6-second timer for Templars.
--   * Attempts during that timer are cancelled before casting.
--   * The valid native Exorcism cast remains intact, preserving
--     mana cost, cast behavior, hit result, and damage.
--   * Native rank cooldowns are cleared after the valid cast.
--   * DMLCooldownBar receives COOLDOWN and RESET messages.
-- ============================================================

local CLASS_PALADIN = 2
local SUBCLASS_TEMPLAR = 2

local PLAYER_EVENT_ON_MODIFY_SPELL_DAMAGE_TAKEN = 70
local PLAYER_EVENT_ON_LOGOUT = 4

local SPELL_EVENT_ON_PREPARE = 1
local SPELL_EVENT_ON_CAST = 2

local SPELL_HOLY_VENGEANCE = 31803

local EXORCISM_RANKS = {
    [879]   = true, -- Rank 1
    [5614]  = true, -- Rank 2
    [5615]  = true, -- Rank 3
    [10312] = true, -- Rank 4
    [10313] = true, -- Rank 5
    [10314] = true, -- Rank 6
    [27138] = true, -- Rank 7
    [48800] = true, -- Rank 8
    [48801] = true, -- Rank 9
}

local EXORCISM_COOLDOWN_MS = 6000
local NATIVE_COOLDOWN_CLEAR_DELAY_MS = 1

-- SendAddonMessage uses the prefix and payload as separate arguments.
-- The client receives this conceptually as:
--   DMLCD | COOLDOWN|spellId|milliseconds
--   DMLCD | RESET|spellId
local DML_ADDON_PREFIX = "DMLCD"
local CHAT_MSG_WHISPER = 7

local DEBUG_EXORCISM = false

-- One shared Exorcism cooldown per Paladin GUIDLow.
-- { startedAt, displaySpellId, serial }
local cooldownByGuid = {}
local cooldownSerialByGuid = {}

local function GetSubclass(player)
    if not player then
        return 0
    end

    local guidLow = player:GetGUIDLow()

    local result = CharDBQuery(
        "SELECT subclass_id FROM character_subclass WHERE guid = " ..
        tostring(guidLow) ..
        " LIMIT 1"
    )

    if result then
        return result:GetUInt32(0)
    end

    return 0
end

local function IsTemplar(player)
    return player
        and player:GetClass() == CLASS_PALADIN
        and GetSubclass(player) == SUBCLASS_TEMPLAR
end

local function Debug(player, message)
    if not DEBUG_EXORCISM then
        return
    end

    if player then
        player:SendBroadcastMessage(
            "|cffffcc33[Exorcism]|r " .. tostring(message)
        )
    end

    print(
        "[DML Exorcism Holy Vengeance] " .. tostring(message)
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

local function IsExorcismSpellInfo(spellInfo)
    if not spellInfo or not spellInfo.GetName then
        return false
    end

    local ok, name = pcall(function()
        return spellInfo:GetName()
    end)

    return ok and name == "Exorcism"
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
            "Failed to send DML cooldown message: " ..
            tostring(err)
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

local function SendDmlReset(player, spellId)
    SendDmlMessage(
        player,
        "RESET|" .. tostring(spellId)
    )
end

local function GetCooldownRemaining(playerGuidLow)
    local state = cooldownByGuid[playerGuidLow]

    if not state then
        return 0
    end

    local elapsed = GetTimeDiff(state.startedAt)

    if elapsed >= EXORCISM_COOLDOWN_MS then
        cooldownByGuid[playerGuidLow] = nil
        return 0
    end

    return EXORCISM_COOLDOWN_MS - elapsed
end

local function ClearNativeExorcismCooldowns(player, castSpellId)
    if not player or not player.ResetSpellCooldown then
        return
    end

    local ok, err = pcall(function()
        -- Clear every rank server-side so the Lua family timer is the
        -- only authoritative Exorcism cooldown.
        for spellId in pairs(EXORCISM_RANKS) do
            player:ResetSpellCooldown(spellId, false)
        end

        -- Send one explicit client update for the rank just cast.
        player:ResetSpellCooldown(castSpellId, true)
    end)

    if not ok then
        Debug(
            player,
            "Failed to clear native Exorcism cooldown: " ..
            tostring(err)
        )
    end
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
    SendDmlReset(player, state.displaySpellId)

    Debug(
        player,
        "Shared Exorcism cooldown ready."
    )
end

local function StartSharedCooldown(player, spellId)
    local playerGuidLow = player:GetGUIDLow()
    local serial = (cooldownSerialByGuid[playerGuidLow] or 0) + 1

    cooldownSerialByGuid[playerGuidLow] = serial
    cooldownByGuid[playerGuidLow] = {
        startedAt = GetCurrTime(),
        displaySpellId = spellId,
        serial = serial,
    }

    SendDmlCooldown(
        player,
        spellId,
        EXORCISM_COOLDOWN_MS
    )

    -- Delay this by 1 ms so AzerothCore has already written the spell's
    -- native cooldown before Lua removes it.
    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            ClearNativeExorcismCooldowns(
                livePlayer,
                spellId
            )
        end,
        NATIVE_COOLDOWN_CLEAR_DELAY_MS,
        1
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
        EXORCISM_COOLDOWN_MS,
        1
    )

    Debug(
        player,
        "Shared Exorcism cooldown started for 6 seconds."
    )
end

local function CancelSpellSafe(spell)
    if not spell or not spell.Cancel then
        return false
    end

    local ok = pcall(function()
        spell:Cancel()
    end)

    return ok
end

local function OnExorcismPrepare(event, caster, spell)
    local player = GetPlayerCaster(caster)

    if not player or not spell then
        return
    end

    if not IsTemplar(player) then
        return
    end

    local spellId = GetSpellId(spell)

    if not EXORCISM_RANKS[spellId] then
        return
    end

    local playerGuidLow = player:GetGUIDLow()
    local remainingMs = GetCooldownRemaining(playerGuidLow)

    if remainingMs <= 0 then
        return
    end

    CancelSpellSafe(spell)

    -- Update the rank the player actually attempted, while all ranks
    -- still share the same Lua timer.
    SendDmlCooldown(
        player,
        spellId,
        remainingMs
    )

    Debug(
        player,
        "Exorcism blocked; " ..
        tostring(math.ceil(remainingMs / 1000)) ..
        " second(s) remain."
    )
end

local function OnExorcismCast(
    event,
    caster,
    spell,
    skipCheck
)
    local player = GetPlayerCaster(caster)

    if not player or not spell then
        return
    end

    if not IsTemplar(player) then
        return
    end

    local spellId = GetSpellId(spell)

    if not EXORCISM_RANKS[spellId] then
        return
    end

    -- A triggered Exorcism still qualifies for Holy Vengeance through
    -- the confirmed damage event, but it should not begin a button cooldown.
    -- but it should not begin a player-button cooldown.
    if skipCheck then
        return
    end

    StartSharedCooldown(player, spellId)
end

local function ApplyHolyVengeance(player, target)
    local ok, err = pcall(function()
        -- The Templar is explicitly the caster/owner. Triggered=true
        -- makes the automatic application instant and free.
        player:CastSpell(
            target,
            SPELL_HOLY_VENGEANCE,
            true
        )
    end)

    if not ok then
        Debug(
            player,
            "Failed to apply Holy Vengeance after Exorcism: " ..
            tostring(err)
        )
        return
    end

    if DEBUG_EXORCISM then
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
            "Exorcism applied one Holy Vengeance stack." ..
            stackText
        )
    end
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

    if not IsTemplar(player) then
        return
    end

    -- Only a successful positive-damage Exorcism hit applies a stack.
    if type(damage) ~= "number" or damage <= 0 then
        return
    end

    -- SpellInfo:GetName() matches every Exorcism rank, so no fragile
    -- pending target captured from Spell:GetTarget() is required.
    if not IsExorcismSpellInfo(spellInfo) then
        return
    end

    ApplyHolyVengeance(player, target)
end

local function OnLogout(event, player)
    if not player then
        return
    end

    local guidLow = player:GetGUIDLow()

    cooldownByGuid[guidLow] = nil
    cooldownSerialByGuid[guidLow] = nil
end

for spellId in pairs(EXORCISM_RANKS) do
    RegisterSpellEvent(
        spellId,
        SPELL_EVENT_ON_PREPARE,
        OnExorcismPrepare
    )

    RegisterSpellEvent(
        spellId,
        SPELL_EVENT_ON_CAST,
        OnExorcismCast
    )
end

RegisterPlayerEvent(
    PLAYER_EVENT_ON_MODIFY_SPELL_DAMAGE_TAKEN,
    OnSpellDamage
)

RegisterPlayerEvent(
    PLAYER_EVENT_ON_LOGOUT,
    OnLogout
)

print(
    "[DML Exorcism Holy Vengeance] " ..
    "Templar-only direct Exorcism-hit Holy Vengeance + shared Lua-managed 6-second cooldown loaded."
)
