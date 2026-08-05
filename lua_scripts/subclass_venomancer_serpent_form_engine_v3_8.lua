-- ============================================================
-- DML Venomancer Serpent Engine v3.8
-- AzerothCore + ALE
--
-- Serpent Form loop:
--   * Serpent Form 54601 is converted to an instant triggered cast by Lua.
--   * Battle Stance aura 2457 supplies a native combat-safe Serpent action page
--     while the snake transform remains visually active.
--   * Its aura duration is enforced at 20 seconds by Lua.
--   * Serpent Form uses a Lua-managed 90-second cooldown.
--   * Cooldown begins only after the form ends.
--   * A 1.5-second entry lock prevents accidental immediate cancellation.
--   * After that lock, casting Serpent Form while active removes it and starts cooldown.
--   * Serpent-only abilities are rejected outside Serpent Form.
--   * Blood Tap 54790 uses its real aura stack count, capped at 5.
--   * Powerful Bite 59840 requires 5 stacks, consumes them on a hit,
--     and summons 1-3 Dalaran Serpents with working spell 3615.
--   * Venom Bolt 54970 reduces Serpent Form cooldown by 1 second on a hit
--     when the target has all three configured poisons.
--   * While Serpent Form is active, passive Flurry 12319 is temporarily
--     learned. A melee critical strike triggers Flurry aura 12966.
--     ALE sees that aura, applies Enrage 34670, and removes the Flurry aura.
--   * Other native Druid form casts are rejected while Serpent Form is active.
--   * Flurry helper 12319, Flurry aura 12966, Enrage, and Blood Tap are
--     removed when Serpent Form ends.
--
-- J3Spells may continue to handle Serpent Form damage scaling. Keep its
-- InstantCast option disabled; this Lua script owns instant activation and
-- also enforces the 20-second aura duration.
-- ============================================================

local CLASS_DRUID = 11
local SUBCLASS_VENOMANCER = 6

local PLAYER_EVENT_ON_LOGIN = 3
local PLAYER_EVENT_ON_LOGOUT = 4
local PLAYER_EVENT_ON_SPELL_CAST = 5
local PLAYER_EVENT_ON_AURA_APPLY = 64
local PLAYER_EVENT_ON_MODIFY_SPELL_DAMAGE_TAKEN = 70
local PLAYER_EVENT_ON_DEAL_DAMAGE = 72

local SPELL_EVENT_ON_PREPARE = 1

local DAMAGE_EFFECT_DIRECT = 0
local DAMAGE_EFFECT_SPELL_DIRECT = 1
local DAMAGE_EFFECT_DOT = 2

local SPELL_VENOM_BOLT = 54970
local SPELL_NAME_VENOM_BOLT = "Venom Bolt"

local SPELL_CORROSIVE_POISON = 13526
local SPELL_TOXIC_SPIT = 52931
local SPELL_SERPENT_STRIKE_POISON = 54593

local SPELL_SERPENT_FORM = 54601
local SPELL_SERPENT_BAR_STANCE = 2457
local SPELL_ENRAGE = 34670

-- Native WotLK Druid shapeshift spells. These are rejected during spell
-- preparation while Serpent Form is active so their model never replaces the
-- snake transform. No display ID is forced; spell 54601 owns the appearance.
local nativeDruidFormSpells = {
    [768] = true,    -- Cat Form
    [783] = true,    -- Travel Form
    [1066] = true,   -- Aquatic Form
    [5487] = true,   -- Bear Form
    [9634] = true,   -- Dire Bear Form
    [24858] = true,  -- Moonkin Form
    [33891] = true,  -- Tree of Life
    [33943] = true,  -- Flight Form
    [40120] = true,  -- Swift Flight Form
}

-- 12319 is the passive Rank 1 Flurry talent/proc listener.
-- A qualifying melee critical strike triggers visible aura 12966.
local SPELL_FLURRY_CRIT_LISTENER = 12319
local SPELL_FLURRY_CRIT_SIGNAL = 12966

local SPELL_BLOOD_TAP = 54790
local SPELL_NECROTIC_STRIKE = 70659
local SPELL_GAPING_MAW = 36617
local SPELL_INFECTED_BITE = 52469

local SPELL_POWERFUL_BITE = 59840
local SPELL_NAME_POWERFUL_BITE = "Powerful Bite"
local SPELL_SUMMON_DALARAN_SERPENT = 3615

local SERPENT_FORM_COOLDOWN_SECONDS = 90
local SERPENT_FORM_DURATION_MS = 25000
local SERPENT_FORM_INSTANT_CAST_DELAY_MS = 1
local SERPENT_FORM_EXIT_LOCK_MS = 1500
local SERPENT_FORM_APPLY_CHECK_MS = 250
local SERPENT_FORM_DURATION_SETTLE_MS = 100
local SERPENT_FORM_MONITOR_MS = 500

local VENOM_BOLT_CDR_SECONDS = 1
local BLOOD_TAP_MAX_STACKS = 5

local POWERFUL_BITE_SERPENT_MIN_SPAWNS = 1
local POWERFUL_BITE_SERPENT_MAX_SPAWNS = 3

-- Exact spell-damage event 70 is preferred. This short pending window is kept
-- only as a compatibility fallback for builds/spells that do not expose the
-- expected SpellInfo through event 70.
local PENDING_HIT_WINDOW_SECONDS = 4

-- Avoid a character database query on every combat or aura event.
local SUBCLASS_CACHE_SECONDS = 30

-- Flurry is used only as a crit signal. Keep this true to prevent its temporary
-- haste buff from becoming an unintended extra Venomancer benefit.
local REMOVE_FLURRY_SIGNAL_AURA = true

local DEBUG_VENOMANCER_SERPENT = true

local serpentOnlySpells = {
    [SPELL_BLOOD_TAP] = true,
    [SPELL_NECROTIC_STRIKE] = true,
    [SPELL_GAPING_MAW] = true,
    [SPELL_INFECTED_BITE] = true,
    [SPELL_POWERFUL_BITE] = true,
}

local stateByGuid = {}

local function Debug(player, message)
    if DEBUG_VENOMANCER_SERPENT and player then
        player:SendBroadcastMessage(
            "|cff33ff66[Venomancer]|r " .. tostring(message)
        )
    end

    if DEBUG_VENOMANCER_SERPENT then
        print("[DML Venomancer Serpent Engine v3.8] " .. tostring(message))
    end
end

local function Now()
    return os.time()
end

local function CallMethodNumber(object, methodName)
    if not object then
        return nil
    end

    local method = object[methodName]

    if type(method) ~= "function" then
        return nil
    end

    local ok, value = pcall(function()
        return method(object)
    end)

    if not ok then
        return nil
    end

    return tonumber(value)
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

    return CallMethodNumber(spell, "GetEntry")
        or CallMethodNumber(spell, "GetId")
        or CallMethodNumber(spell, "GetID")
        or 0
end

local function GetAuraIdSafe(aura)
    return CallMethodNumber(aura, "GetAuraId") or 0
end

local function GetSpellInfoTextSafe(spellInfo, methodName)
    if not spellInfo then
        return nil
    end

    local method = spellInfo[methodName]

    if type(method) ~= "function" then
        return nil
    end

    local ok, value = pcall(function()
        return method(spellInfo)
    end)

    if not ok or value == nil then
        return nil
    end

    return tostring(value)
end

local function SpellInfoMatches(spellInfo, spellId, expectedName)
    if not spellInfo then
        return false
    end

    -- SpellInfo userdata supplied by ALE is callback-scoped. Never cache it or
    -- compare it with userdata retained from an earlier callback: ALE invalidates
    -- those pointers after the callback returns.
    local directId = GetDmlSpellId(spellInfo)

    if directId ~= 0 then
        return directId == spellId
    end

    -- Compatibility fallback for ALE builds whose SpellInfo binding exposes a
    -- name but no numeric ID. Read the value while this callback is active.
    local actualName = GetSpellInfoTextSafe(spellInfo, "GetName")
        or GetSpellInfoTextSafe(spellInfo, "GetSpellName")

    return actualName ~= nil and actualName == expectedName
end

local function GetState(player)
    if not player then
        return nil
    end

    local guid = player:GetGUIDLow()
    local state = stateByGuid[guid]

    if not state then
        state = {
            cooldownEnd = 0,
            inSerpentForm = false,

            subclassId = nil,
            subclassCacheUntil = 0,

            pendingSequence = 0,
            pendingVenomBolt = nil,
            pendingPowerfulBite = nil,

            instantSerpentCastPending = false,
            instantSerpentCastGuard = false,

            serpentExitLocked = false,
            serpentFormSerial = 0,

        }

        stateByGuid[guid] = state
    end

    return state
end

local function RefreshSubclassCache(player)
    local state = GetState(player)

    if not state then
        return 0
    end

    local guid = player:GetGUIDLow()
    local result = CharDBQuery(
        "SELECT subclass_id FROM character_subclass WHERE guid = " ..
        tostring(guid) ..
        " LIMIT 1"
    )

    state.subclassId = result and result:GetUInt32(0) or 0
    state.subclassCacheUntil = Now() + SUBCLASS_CACHE_SECONDS

    return state.subclassId
end

local function GetSubclassCached(player)
    local state = GetState(player)

    if not state then
        return 0
    end

    if state.subclassId == nil or Now() >= state.subclassCacheUntil then
        return RefreshSubclassCache(player)
    end

    return state.subclassId
end

local function IsVenomancer(player)
    return player
        and player:GetClass() == CLASS_DRUID
        and GetSubclassCached(player) == SUBCLASS_VENOMANCER
end

local function AsPlayer(caster)
    if not caster then
        return nil
    end

    if caster.GetGUIDLow and caster.GetClass then
        return caster
    end

    if caster.ToPlayer then
        local ok, player = pcall(function()
            return caster:ToPlayer()
        end)

        if ok then
            return player
        end
    end

    return nil
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

local function GetAuraSafe(unit, spellId)
    if not unit or not unit.GetAura then
        return nil
    end

    local ok, aura = pcall(function()
        return unit:GetAura(spellId)
    end)

    if ok then
        return aura
    end

    return nil
end

local function RemoveAuraSafe(unit, spellId)
    if not unit or not unit.RemoveAura then
        return
    end

    pcall(function()
        if unit:HasAura(spellId) then
            unit:RemoveAura(spellId)
        end
    end)
end

local function CastTriggeredSelfSafe(player, spellId)
    if not player or not player.CastSpell then
        return false
    end

    local ok, err = pcall(function()
        player:CastSpell(player, spellId, true)
    end)

    if not ok then
        Debug(player, "Failed to cast spell " .. spellId .. ": " .. tostring(err))
    end

    return ok
end

local function HasSpellSafe(player, spellId)
    if not player or not player.HasSpell then
        return false
    end

    local ok, result = pcall(function()
        return player:HasSpell(spellId)
    end)

    return ok and result
end

local function LearnSpellSafe(player, spellId)
    if not player or not player.LearnSpell then
        return false
    end

    if HasSpellSafe(player, spellId) then
        return true
    end

    local ok, err = pcall(function()
        player:LearnSpell(spellId)
    end)

    if not ok then
        Debug(player, "Failed to learn helper spell " .. spellId .. ": " .. tostring(err))
    end

    return ok and HasSpellSafe(player, spellId)
end

local function RemoveSpellSafe(player, spellId)
    if not player or not player.RemoveSpell then
        return false
    end

    if not HasSpellSafe(player, spellId) then
        return true
    end

    local ok, err = pcall(function()
        player:RemoveSpell(spellId)
    end)

    if not ok then
        Debug(player, "Failed to remove helper spell " .. spellId .. ": " .. tostring(err))
    end

    return ok
end

local function CancelSpell(spell)
    if not spell or not spell.Cancel then
        return false
    end

    local ok = pcall(function()
        spell:Cancel()
    end)

    return ok
end

local function GetUnitGuidLowSafe(unit)
    if not unit or not unit.GetGUIDLow then
        return nil
    end

    local ok, guid = pcall(function()
        return unit:GetGUIDLow()
    end)

    if ok then
        return guid
    end

    return nil
end

local function IsInSerpentForm(player)
    return HasAuraSafe(player, SPELL_SERPENT_FORM)
end

-- Battle Stance is used only as the native action-bar paging state for
-- Serpent Form. AddAura is preferred because it mirrors the confirmed
-- working `.aura 2457` server test and does not require the Druid to know
-- or normally qualify to cast the Warrior stance spell.
local function EnableSerpentBarStance(player)
    if not player or not IsVenomancer(player) or not IsInSerpentForm(player) then
        return false
    end

    if HasAuraSafe(player, SPELL_SERPENT_BAR_STANCE) then
        return true
    end

    local ok, err = pcall(function()
        if player.AddAura then
            player:AddAura(SPELL_SERPENT_BAR_STANCE, player)
        else
            player:CastSpell(player, SPELL_SERPENT_BAR_STANCE, true)
        end
    end)

    if not ok then
        Debug(
            player,
            "Failed to enable Serpent action bar stance " ..
            tostring(SPELL_SERPENT_BAR_STANCE) ..
            ": " .. tostring(err)
        )
        return false
    end

    return HasAuraSafe(player, SPELL_SERPENT_BAR_STANCE)
end

local function DisableSerpentBarStance(player)
    RemoveAuraSafe(player, SPELL_SERPENT_BAR_STANCE)
end

local function RemoveNativeDruidForms(player)
    if not player then
        return
    end

    for spellId in pairs(nativeDruidFormSpells) do
        RemoveAuraSafe(player, spellId)
    end
end

local function EnforceSerpentFormDuration(aura)
    if not aura then
        return
    end

    local ok, err = pcall(function()
        if aura.SetMaxDuration then
            aura:SetMaxDuration(SERPENT_FORM_DURATION_MS)
        end

        if aura.SetDuration then
            aura:SetDuration(SERPENT_FORM_DURATION_MS)
        end
    end)

    if not ok and DEBUG_VENOMANCER_SERPENT then
        print(
            "[DML Venomancer Serpent Engine] Failed to enforce Serpent Form duration: " ..
            tostring(err)
        )
    end
end

local function SettleSerpentFormDuration(eventId, delay, repeats, player)
    if not player or not IsVenomancer(player) then
        return
    end

    -- Reacquire the Aura inside this callback. ALE aura userdata is callback-
    -- scoped and must never be retained across a delayed event.
    local aura = GetAuraSafe(player, SPELL_SERPENT_FORM)

    if aura then
        EnforceSerpentFormDuration(aura)
    end
end

-- ============================================================
-- Native Flurry crit signal -> Enrage
-- ============================================================

local function EnableSerpentCritListener(player)
    if not player or not IsVenomancer(player) or not IsInSerpentForm(player) then
        return false
    end

    return LearnSpellSafe(player, SPELL_FLURRY_CRIT_LISTENER)
end

local function DisableSerpentCritListener(player)
    if not player then
        return
    end

    RemoveAuraSafe(player, SPELL_FLURRY_CRIT_SIGNAL)
    RemoveAuraSafe(player, SPELL_ENRAGE)

    -- This spell ID is reserved as the internal Venomancer crit listener.
    -- Removing it here also repairs stale helper spells after an ALE reload.
    RemoveSpellSafe(player, SPELL_FLURRY_CRIT_LISTENER)
end

local function ApplyEnrageFromFlurrySignal(player)
    if not player or not IsVenomancer(player) then
        return
    end

    if not IsInSerpentForm(player) then
        RemoveAuraSafe(player, SPELL_FLURRY_CRIT_SIGNAL)
        RemoveAuraSafe(player, SPELL_ENRAGE)
        RemoveSpellSafe(player, SPELL_FLURRY_CRIT_LISTENER)
        return
    end

    CastTriggeredSelfSafe(player, SPELL_ENRAGE)

    if REMOVE_FLURRY_SIGNAL_AURA then
        RemoveAuraSafe(player, SPELL_FLURRY_CRIT_SIGNAL)
    end

    Debug(player, "Melee critical strike detected: Enrage applied.")
end

-- ============================================================
-- Blood Tap: real aura stacks are the source of truth
-- ============================================================

local function GetBloodTapStacks(player)
    local aura = GetAuraSafe(player, SPELL_BLOOD_TAP)

    if not aura or not aura.GetStackAmount then
        return 0
    end

    local ok, stacks = pcall(function()
        return aura:GetStackAmount()
    end)

    if not ok then
        return 0
    end

    return tonumber(stacks) or 0
end

local function SetBloodTapStacks(player, amount)
    if not player then
        return false
    end

    amount = math.max(0, math.min(BLOOD_TAP_MAX_STACKS, amount or 0))

    if amount <= 0 then
        RemoveAuraSafe(player, SPELL_BLOOD_TAP)
        return true
    end

    local aura = GetAuraSafe(player, SPELL_BLOOD_TAP)

    if not aura and player.AddAura then
        local ok, addedAura = pcall(function()
            return player:AddAura(SPELL_BLOOD_TAP, player)
        end)

        if ok then
            aura = addedAura
        end
    end

    if not aura or not aura.SetStackAmount then
        return false
    end

    local ok = pcall(function()
        aura:SetStackAmount(amount)
    end)

    return ok
end

local function AddOneBloodTapStack(player, stacksBeforeCast)
    if not player or not IsVenomancer(player) or not IsInSerpentForm(player) then
        return
    end

    local baseStacks = tonumber(stacksBeforeCast)

    if baseStacks == nil then
        baseStacks = GetBloodTapStacks(player)
    end

    local newStacks = math.min(BLOOD_TAP_MAX_STACKS, baseStacks + 1)

    if SetBloodTapStacks(player, newStacks) then
        Debug(
            player,
            "Blood Tap stack: " ..
            tostring(newStacks) ..
            "/" ..
            tostring(BLOOD_TAP_MAX_STACKS) ..
            "."
        )
    else
        Debug(player, "Failed to set the Blood Tap aura stack count.")
    end
end

local function ClearBloodTap(player)
    SetBloodTapStacks(player, 0)
end

local function HasFullBloodTap(player)
    return GetBloodTapStacks(player) >= BLOOD_TAP_MAX_STACKS
end

-- ============================================================
-- Serpent Form cooldown
-- ============================================================

local function SendSerpentCooldown(player, remainingSeconds)
    if not player then
        return
    end

    local remainingMs = math.max(0, remainingSeconds) * 1000

    player:SendBroadcastMessage(
        "DMLCD|COOLDOWN|" ..
        tostring(SPELL_SERPENT_FORM) ..
        "|" ..
        tostring(remainingMs)
    )

    if remainingMs <= 0 then
        player:SendBroadcastMessage(
            "DMLCD|RESET|" .. tostring(SPELL_SERPENT_FORM)
        )
    end
end

local function GetSerpentCooldownRemaining(player)
    local state = GetState(player)

    if not state then
        return 0
    end

    return math.max(0, (state.cooldownEnd or 0) - Now())
end

local function ClearSerpentExitLock(state)
    if not state then
        return
    end

    state.serpentExitLocked = false
    state.serpentFormSerial = (state.serpentFormSerial or 0) + 1
end

local function ArmSerpentExitLock(player)
    local state = GetState(player)

    if not state then
        return
    end

    state.serpentFormSerial = (state.serpentFormSerial or 0) + 1
    local serial = state.serpentFormSerial
    state.serpentExitLocked = true

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            local liveState = GetState(livePlayer)

            if not liveState or liveState.serpentFormSerial ~= serial then
                return
            end

            liveState.serpentExitLocked = false
        end,
        SERPENT_FORM_EXIT_LOCK_MS,
        1
    )
end

local function StartSerpentCooldown(player)
    local state = GetState(player)

    if not state then
        return
    end

    state.cooldownEnd = Now() + SERPENT_FORM_COOLDOWN_SECONDS
    state.inSerpentForm = false
    state.pendingVenomBolt = nil
    state.pendingPowerfulBite = nil
    ClearSerpentExitLock(state)

    ClearBloodTap(player)
    DisableSerpentCritListener(player)
    DisableSerpentBarStance(player)

    SendSerpentCooldown(player, SERPENT_FORM_COOLDOWN_SECONDS)

    Debug(
        player,
        "Serpent Form cooldown started: " ..
        tostring(SERPENT_FORM_COOLDOWN_SECONDS) ..
        " seconds."
    )
end

local function ReduceSerpentCooldown(player, seconds)
    local state = GetState(player)

    if not state then
        return
    end

    local remaining = GetSerpentCooldownRemaining(player)

    if remaining <= 0 then
        return
    end

    state.cooldownEnd = math.max(
        Now(),
        (state.cooldownEnd or 0) - seconds
    )

    remaining = GetSerpentCooldownRemaining(player)
    SendSerpentCooldown(player, remaining)

    Debug(
        player,
        "Serpent Form cooldown reduced by " ..
        tostring(seconds) ..
        " second(s). Remaining: " ..
        tostring(remaining) ..
        "."
    )
end

local function HasAllMainPoisons(target)
    return target
        and HasAuraSafe(target, SPELL_CORROSIVE_POISON)
        and HasAuraSafe(target, SPELL_TOXIC_SPIT)
        and HasAuraSafe(target, SPELL_SERPENT_STRIKE_POISON)
end

local function MonitorSerpentForm(eventId, delay, repeats, player)
    if not player then
        return
    end

    local state = GetState(player)

    if not state then
        return
    end

    if not IsVenomancer(player) then
        state.inSerpentForm = false
        state.pendingVenomBolt = nil
        state.pendingPowerfulBite = nil
        state.instantSerpentCastPending = false
        state.instantSerpentCastGuard = false
        ClearSerpentExitLock(state)
        ClearBloodTap(player)
        DisableSerpentCritListener(player)
        DisableSerpentBarStance(player)
            return
    end

    if IsInSerpentForm(player) then
        -- Do not reset the aura duration here. This monitor runs every 500 ms;
        -- calling SetDuration(20000) on each pass would refresh Serpent Form
        -- forever. Duration is enforced once in OnAuraApply when the aura begins.
        state.inSerpentForm = true
        RemoveNativeDruidForms(player)
        EnableSerpentBarStance(player)
        EnableSerpentCritListener(player)

        player:RegisterEvent(
            MonitorSerpentForm,
            SERPENT_FORM_MONITOR_MS,
            1
        )

        return
    end

    if state.inSerpentForm then
        StartSerpentCooldown(player)
    else
        -- Repair leaked helper state after a reload or unusual aura removal.
        DisableSerpentCritListener(player)
        DisableSerpentBarStance(player)
        ClearBloodTap(player)
    end
end

local function RepairSerpentState(player)
    if not player or not IsVenomancer(player) then
        return
    end

    local state = GetState(player)

    if not state then
        return
    end

    if IsInSerpentForm(player) then
        state.inSerpentForm = true
        RemoveNativeDruidForms(player)
        EnableSerpentBarStance(player)
        EnableSerpentCritListener(player)

        player:RegisterEvent(
            MonitorSerpentForm,
            SERPENT_FORM_MONITOR_MS,
            1
        )

        return
    end

    if state.inSerpentForm then
        StartSerpentCooldown(player)
    else
        DisableSerpentCritListener(player)
        DisableSerpentBarStance(player)
        ClearBloodTap(player)
    end
end

local function OnNativeDruidFormPrepare(event, caster, spell)
    local player = AsPlayer(caster)

    if not player or not spell or not IsVenomancer(player) then
        return
    end

    if not IsInSerpentForm(player) then
        return
    end

    CancelSpell(spell)
    player:SendNotification(
        "You cannot enter another form while Serpent Form is active."
    )
end

-- Powerful Bite is instant, so its requirements must be enforced during
-- ON_PREPARE. Cancelling it later from PLAYER_EVENT_ON_SPELL_CAST can allow
-- the instant damage to occur before ALE processes the cancellation.
local function OnPowerfulBitePrepare(event, caster, spell)
    local player = AsPlayer(caster)

    if not player or not spell or not IsVenomancer(player) then
        return
    end

    if not IsInSerpentForm(player) then
        CancelSpell(spell)

        player:SendNotification(
            "You must be in Serpent Form to use Powerful Bite."
        )

        return
    end

    if not HasFullBloodTap(player) then
        CancelSpell(spell)

        player:SendNotification(
            "Powerful Bite requires 5 stacks of Blood Tap."
        )

        return
    end
end

-- This earlier spell hook is used for Serpent Form itself.
local function OnSerpentFormPrepare(event, caster, spell)
    local player = AsPlayer(caster)

    if not player or not spell or not IsVenomancer(player) then
        return
    end

    local state = GetState(player)

    if not state then
        return
    end

    -- The Lua-triggered replacement cast can pass this hook too. Let that
    -- one cast through, then immediately close the recursion guard.
    if state.instantSerpentCastGuard then
        state.instantSerpentCastGuard = false
        return
    end

    -- Ignore duplicate button presses while the one-millisecond replacement
    -- cast is waiting to run.
    if state.instantSerpentCastPending then
        CancelSpell(spell)
        return
    end

    if IsInSerpentForm(player) then
        CancelSpell(spell)

        -- The instant replacement cast does not create a normal client GCD.
        -- Ignore immediate double presses so entering the form cannot
        -- accidentally consume the entire 90-second cooldown.
        if state.serpentExitLocked then
            player:SendNotification(
                "Serpent Form cannot be cancelled immediately after shifting."
            )
            return
        end

        RemoveAuraSafe(player, SPELL_SERPENT_FORM)
        StartSerpentCooldown(player)
        return
    end

    local remaining = GetSerpentCooldownRemaining(player)

    if remaining > 0 then
        CancelSpell(spell)
        SendSerpentCooldown(player, remaining)

        player:SendNotification(
            "Serpent Form is still on cooldown: " ..
            tostring(remaining) ..
            " second(s)."
        )

        return
    end

    -- Stop the native 2.5-second cast. After this Prepare callback has fully
    -- returned, perform the same spell as a triggered instant cast. Delaying
    -- by one millisecond avoids re-entering ALE while the cancelled Spell
    -- object is still being processed.
    CancelSpell(spell)
    state.inSerpentForm = false
    state.instantSerpentCastPending = true

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            local liveState = GetState(livePlayer)

            if not liveState then
                return
            end

            liveState.instantSerpentCastPending = false

            if not IsVenomancer(livePlayer)
                or IsInSerpentForm(livePlayer)
                or GetSerpentCooldownRemaining(livePlayer) > 0
            then
                liveState.instantSerpentCastGuard = false
                return
            end

            RemoveNativeDruidForms(livePlayer)
            liveState.instantSerpentCastGuard = true

            local ok, err = pcall(function()
                livePlayer:CastSpell(
                    livePlayer,
                    SPELL_SERPENT_FORM,
                    true
                )
            end)

            -- Some ALE builds call Prepare for triggered casts and clear the
            -- guard there; others may not. Always clear it after CastSpell.
            liveState.instantSerpentCastGuard = false

            if not ok then
                Debug(
                    livePlayer,
                    "Instant Serpent Form cast failed: " .. tostring(err)
                )
                return
            end

            livePlayer:RegisterEvent(
                function(checkEventId, checkDelay, checkRepeats, checkPlayer)
                    RepairSerpentState(checkPlayer)
                end,
                SERPENT_FORM_APPLY_CHECK_MS,
                1
            )
        end,
        SERPENT_FORM_INSTANT_CAST_DELAY_MS,
        1
    )
end

-- ============================================================
-- Powerful Bite summons
-- ============================================================

local function SummonDalaranSerpents(player)
    if not player then
        return
    end

    local count = math.random(
        POWERFUL_BITE_SERPENT_MIN_SPAWNS,
        POWERFUL_BITE_SERPENT_MAX_SPAWNS
    )

    for i = 1, count do
        pcall(function()
            player:CastSpell(
                player,
                SPELL_SUMMON_DALARAN_SERPENT,
                true
            )
        end)
    end

    Debug(
        player,
        "Powerful Bite summoned " ..
        tostring(count) ..
        " Dalaran serpent(s)."
    )
end

-- ============================================================
-- Exact spell hits plus compatibility fallback
-- ============================================================

local function GetSpellTarget(player, spell)
    if not player then
        return nil
    end

    if spell and spell.GetTarget then
        local ok, target = pcall(function()
            return spell:GetTarget()
        end)

        if ok and target then
            return target
        end
    end

    if player.GetSelection then
        local ok, target = pcall(function()
            return player:GetSelection()
        end)

        if ok then
            return target
        end
    end

    return nil
end

local function ClearExpiredPendingHits(state)
    if not state then
        return
    end

    local now = Now()

    if state.pendingVenomBolt and now > state.pendingVenomBolt.expiresAt then
        state.pendingVenomBolt = nil
    end

    if state.pendingPowerfulBite and now > state.pendingPowerfulBite.expiresAt then
        state.pendingPowerfulBite = nil
    end
end

local function RememberPendingSpell(player, target, spellId)
    local state = GetState(player)

    if not state then
        return
    end

    local targetGuid = GetUnitGuidLowSafe(target)

    if not targetGuid then
        Debug(player, "Could not identify the target for spell " .. spellId .. ".")
        return
    end

    ClearExpiredPendingHits(state)
    state.pendingSequence = (state.pendingSequence or 0) + 1

    local pending = {
        targetGuid = targetGuid,
        expiresAt = Now() + PENDING_HIT_WINDOW_SECONDS,
        sequence = state.pendingSequence,
    }

    if spellId == SPELL_VENOM_BOLT then
        state.pendingVenomBolt = pending
    elseif spellId == SPELL_POWERFUL_BITE then
        state.pendingPowerfulBite = pending
    end
end

local function ClearPendingSpell(player, spellId)
    local state = GetState(player)

    if not state then
        return
    end

    if spellId == SPELL_VENOM_BOLT then
        state.pendingVenomBolt = nil
    elseif spellId == SPELL_POWERFUL_BITE then
        state.pendingPowerfulBite = nil
    end
end

local function ResolvePendingSpellHit(player, target, damageType)
    local state = GetState(player)

    if not state then
        return 0
    end

    ClearExpiredPendingHits(state)

    local targetGuid = GetUnitGuidLowSafe(target)

    if not targetGuid then
        return 0
    end

    local matchedSpellId = 0
    local matchedSequence = -1
    local venom = state.pendingVenomBolt
    local bite = state.pendingPowerfulBite

    if venom
        and venom.targetGuid == targetGuid
        and damageType == DAMAGE_EFFECT_SPELL_DIRECT
    then
        matchedSpellId = SPELL_VENOM_BOLT
        matchedSequence = venom.sequence or 0
    end

    if bite
        and bite.targetGuid == targetGuid
        and (
            damageType == DAMAGE_EFFECT_DIRECT
            or damageType == DAMAGE_EFFECT_SPELL_DIRECT
        )
        and (bite.sequence or 0) > matchedSequence
    then
        matchedSpellId = SPELL_POWERFUL_BITE
    end

    ClearPendingSpell(player, matchedSpellId)
    return matchedSpellId
end

local function HandleSuccessfulSpellHit(player, target, spellId)
    if not player or not target or not IsVenomancer(player) then
        return
    end

    if spellId == SPELL_VENOM_BOLT then
        ClearPendingSpell(player, SPELL_VENOM_BOLT)

        if HasAllMainPoisons(target) then
            ReduceSerpentCooldown(player, VENOM_BOLT_CDR_SECONDS)
        end

        return
    end

    if spellId == SPELL_POWERFUL_BITE then
        ClearPendingSpell(player, SPELL_POWERFUL_BITE)

        if not IsInSerpentForm(player) or not HasFullBloodTap(player) then
            return
        end

        SummonDalaranSerpents(player)
        ClearBloodTap(player)
    end
end

-- ALE event 70 supplies the outgoing SpellInfo for direct spell damage on the
-- AzerothCore hook. This is the preferred path because poison periodic ticks
-- use the periodic-damage hook rather than this direct-spell hook.
local function OnModifySpellDamageTaken(event, player, target, damage, spellInfo)
    if not player or not target or not spellInfo or not IsVenomancer(player) then
        return
    end

    if (tonumber(damage) or 0) <= 0 then
        return
    end

    if SpellInfoMatches(
        spellInfo,
        SPELL_VENOM_BOLT,
        SPELL_NAME_VENOM_BOLT
    ) then
        HandleSuccessfulSpellHit(player, target, SPELL_VENOM_BOLT)
        return
    end

    if SpellInfoMatches(
        spellInfo,
        SPELL_POWERFUL_BITE,
        SPELL_NAME_POWERFUL_BITE
    ) then
        HandleSuccessfulSpellHit(player, target, SPELL_POWERFUL_BITE)
    end
end

-- Compatibility fallback. It is reached only if the exact event-70 path did
-- not already clear the pending cast. Periodic damage is explicitly rejected.
local function OnDealDamage(event, player, target, damage, damageType)
    if not player or not target or not IsVenomancer(player) then
        return
    end

    if (tonumber(damage) or 0) <= 0 or damageType == DAMAGE_EFFECT_DOT then
        return
    end

    local spellId = ResolvePendingSpellHit(player, target, damageType)

    if spellId ~= 0 then
        HandleSuccessfulSpellHit(player, target, spellId)
    end
end

-- ============================================================
-- Spell casts and aura signals
-- ============================================================

local function OnSpellCast(event, player, spell, skipCheck)
    if not player or not spell or not IsVenomancer(player) then
        return
    end

    local spellId = GetDmlSpellId(spell)

    if spellId == 0 or spellId == SPELL_SERPENT_FORM then
        return
    end

    if nativeDruidFormSpells[spellId] and IsInSerpentForm(player) then
        CancelSpell(spell)
        RemoveAuraSafe(player, spellId)
        EnableSerpentBarStance(player)
        return
    end

    if spellId == SPELL_VENOM_BOLT then
        RememberPendingSpell(
            player,
            GetSpellTarget(player, spell),
            spellId
        )
        return
    end

    if not serpentOnlySpells[spellId] then
        return
    end

    if not IsInSerpentForm(player) then
        CancelSpell(spell)

        player:SendNotification(
            "You must be in Serpent Form to use that ability."
        )

        return
    end

    if spellId == SPELL_BLOOD_TAP then
        local stacksBeforeCast = GetBloodTapStacks(player)

        player:RegisterEvent(
            function(eventId, delay, repeats, livePlayer)
                AddOneBloodTapStack(livePlayer, stacksBeforeCast)
            end,
            100,
            1
        )

        return
    end

    if spellId == SPELL_POWERFUL_BITE then
        -- Form and five-stack requirements were already enforced by the
        -- spell-specific ON_PREPARE hook before this instant attack began.
        RememberPendingSpell(
            player,
            GetSpellTarget(player, spell),
            spellId
        )
    end
end

local function OnAuraApply(event, player, aura)
    if not player or not aura then
        return
    end

    local auraId = GetAuraIdSafe(aura)

    -- Return before subclass lookup for every unrelated aura on the server.
    if auraId ~= SPELL_SERPENT_FORM
        and auraId ~= SPELL_SERPENT_BAR_STANCE
        and auraId ~= SPELL_FLURRY_CRIT_SIGNAL
        and auraId ~= SPELL_ENRAGE
        and not nativeDruidFormSpells[auraId]
    then
        return
    end

    if not IsVenomancer(player) then
        return
    end

    if nativeDruidFormSpells[auraId] then
        if IsInSerpentForm(player) then
            RemoveAuraSafe(player, auraId)
            EnableSerpentBarStance(player)
            end
        return
    end

    if auraId == SPELL_SERPENT_FORM then
        -- Apply the 20-second duration now, then once more after 100 ms so it
        -- wins over any later spell/aura hook without continuously refreshing.
        EnforceSerpentFormDuration(aura)
        player:RegisterEvent(
            SettleSerpentFormDuration,
            SERPENT_FORM_DURATION_SETTLE_MS,
            1
        )

        local state = GetState(player)

        if state then
            state.inSerpentForm = true
        end

        ArmSerpentExitLock(player)
        RemoveNativeDruidForms(player)
        EnableSerpentBarStance(player)
        EnableSerpentCritListener(player)

        player:RegisterEvent(
            MonitorSerpentForm,
            SERPENT_FORM_MONITOR_MS,
            1
        )

        return
    end

    -- Battle Stance 2457 is reserved as the Serpent Form action-page flag for
    -- Venomancers. If another source applies it outside Serpent Form, remove it
    -- so the main action bar cannot become stuck on the Serpent page.
    if auraId == SPELL_SERPENT_BAR_STANCE then
        if not IsInSerpentForm(player) then
            DisableSerpentBarStance(player)
        end
        return
    end

    if auraId == SPELL_FLURRY_CRIT_SIGNAL then
        ApplyEnrageFromFlurrySignal(player)
        return
    end

    -- Enrage is a Serpent Form-only effect for Venomancers, even if another
    -- system attempts to apply the same aura outside the form.
    if auraId == SPELL_ENRAGE and not IsInSerpentForm(player) then
        RemoveAuraSafe(player, SPELL_ENRAGE)
    end
end

-- ============================================================
-- Login/logout repair
-- ============================================================

local function OnLogin(event, player)
    if not player then
        return
    end

    RefreshSubclassCache(player)

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            if not livePlayer then
                return
            end

            if not IsVenomancer(livePlayer) then
                return
            end

            local remaining = GetSerpentCooldownRemaining(livePlayer)

            if remaining > 0 then
                SendSerpentCooldown(livePlayer, remaining)
            end

            RepairSerpentState(livePlayer)
        end,
        1000,
        1
    )
end

local function OnLogout(event, player)
    if not player then
        return
    end

    local state = GetState(player)

    if state then
        if state.inSerpentForm then
            state.cooldownEnd = Now() + SERPENT_FORM_COOLDOWN_SECONDS
        end

        state.inSerpentForm = false
        state.pendingVenomBolt = nil
        state.pendingPowerfulBite = nil
        state.instantSerpentCastPending = false
        state.instantSerpentCastGuard = false
        ClearSerpentExitLock(state)
    end

    ClearBloodTap(player)
    DisableSerpentCritListener(player)
    DisableSerpentBarStance(player)
end

for spellId in pairs(nativeDruidFormSpells) do
    RegisterSpellEvent(
        spellId,
        SPELL_EVENT_ON_PREPARE,
        OnNativeDruidFormPrepare
    )
end

RegisterSpellEvent(
    SPELL_POWERFUL_BITE,
    SPELL_EVENT_ON_PREPARE,
    OnPowerfulBitePrepare
)

RegisterSpellEvent(
    SPELL_SERPENT_FORM,
    SPELL_EVENT_ON_PREPARE,
    OnSerpentFormPrepare
)

RegisterPlayerEvent(PLAYER_EVENT_ON_LOGIN, OnLogin)
RegisterPlayerEvent(PLAYER_EVENT_ON_LOGOUT, OnLogout)
RegisterPlayerEvent(PLAYER_EVENT_ON_SPELL_CAST, OnSpellCast)
RegisterPlayerEvent(PLAYER_EVENT_ON_AURA_APPLY, OnAuraApply)
RegisterPlayerEvent(
    PLAYER_EVENT_ON_MODIFY_SPELL_DAMAGE_TAKEN,
    OnModifySpellDamageTaken
)
RegisterPlayerEvent(PLAYER_EVENT_ON_DEAL_DAMAGE, OnDealDamage)

print("[DML Venomancer Serpent Engine v3.8] Loaded.")
