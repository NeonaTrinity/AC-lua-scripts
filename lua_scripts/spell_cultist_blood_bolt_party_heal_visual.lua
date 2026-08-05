-- ============================================================
-- DML Cultist Blood Bolt Party Heal
--
-- Spell: Blood Bolt 41229
--
-- Effect:
-- - When a Cultist deals damage with Blood Bolt, heal up to 4 party members.
-- - Does not heal the caster.
-- - Each chosen ally receives 25% of the damage dealt.
-- - Chooses the lowest-health party/raid members within range first.
--
-- This is standalone and can run beside the existing Blood Bolt damage/mana
-- script. If your existing Blood Bolt script already handles damage scaling,
-- leave that script alone and add this as its own file.
-- ============================================================

local SPELL_BLOOD_BOLT = 41229

local CLASS_WARLOCK = 9
local SUBCLASS_CULTIST = 4

local PLAYER_EVENT_ON_LOGOUT = 4
local PLAYER_EVENT_ON_SPELL_CAST = 5
local PLAYER_EVENT_ON_DEAL_DAMAGE = 72

local BLOOD_BOLT_HEAL_RANGE = 40
local BLOOD_BOLT_HEAL_MAX_TARGETS = 4
local BLOOD_BOLT_HEAL_PERCENT = 0.25
local BLOOD_BOLT_PENDING_CLEAR_MS = 3000

-- Optional visual-only hook. Set this to a harmless visual spell ID if you
-- want a sparkle/blood/heal effect on allies who receive the Blood Bolt heal.
-- Keep at 0 to disable visuals.
local BLOOD_BOLT_HEAL_VISUAL_SPELL = 37692
local BLOOD_BOLT_HEAL_VISUAL_REMOVE_MS = 0

local BLOOD_BOLT_HEAL_DEBUG = false

local pendingBloodBoltByGuid = {}
local castSerialByGuid = {}

local function Debug(player, message)
    if BLOOD_BOLT_HEAL_DEBUG and player then
        player:SendBroadcastMessage("|cff8b0000[Blood Bolt Heal]|r " .. tostring(message))
    end

    if BLOOD_BOLT_HEAL_DEBUG then
        print("[DML Blood Bolt Heal] " .. tostring(message))
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
    return player
        and player:GetClass() == CLASS_WARLOCK
        and GetSubclass(player) == SUBCLASS_CULTIST
end

local function IsBot(player)
    if player and player.IsBot then
        return player:IsBot()
    end

    return false
end

local function IsSameUnit(a, b)
    if not a or not b then
        return false
    end

    local guidA = GetDmlGuidLow(a)
    local guidB = GetDmlGuidLow(b)

    return guidA ~= 0 and guidA == guidB
end

local function IsAlivePlayer(unit)
    if not unit then
        return false
    end

    if unit.IsPlayer then
        local ok, isPlayer = pcall(function()
            return unit:IsPlayer()
        end)

        if ok and not isPlayer then
            return false
        end
    end

    if unit.IsAlive then
        local ok, alive = pcall(function()
            return unit:IsAlive()
        end)

        if ok and not alive then
            return false
        end
    elseif unit.IsDead then
        local ok, dead = pcall(function()
            return unit:IsDead()
        end)

        if ok and dead then
            return false
        end
    end

    return true
end

local function IsInRange(player, unit, range)
    if not player or not unit then
        return false
    end

    if player.IsWithinDistInMap then
        local ok, inRange = pcall(function()
            return player:IsWithinDistInMap(unit, range)
        end)

        if ok then
            return inRange
        end
    end

    if player.GetDistance then
        local ok, distance = pcall(function()
            return player:GetDistance(unit)
        end)

        if ok and distance then
            return distance <= range
        end
    end

    return true
end

local function IsGroupedWith(player, unit)
    if not player or not unit then
        return false
    end

    if IsSameUnit(player, unit) then
        return true
    end

    local methods = {
        "IsInGroupWith",
        "IsInSameGroupWith",
        "IsInRaidWith",
    }

    for _, methodName in ipairs(methods) do
        if player[methodName] then
            local ok, result = pcall(function()
                return player[methodName](player, unit)
            end)

            if ok and result then
                return true
            end
        end
    end

    return false
end

local function AddCandidate(candidates, seenGuids, caster, unit)
    if not unit then
        return
    end

    if IsSameUnit(caster, unit) then
        return
    end

    if not IsAlivePlayer(unit) then
        return
    end

    if not IsInRange(caster, unit, BLOOD_BOLT_HEAL_RANGE) then
        return
    end

    local guid = GetDmlGuidLow(unit)

    if guid == 0 or seenGuids[guid] then
        return
    end

    if not IsGroupedWith(caster, unit) then
        return
    end

    local health = unit:GetHealth()
    local maxHealth = unit:GetMaxHealth()

    if maxHealth <= 0 or health >= maxHealth then
        return
    end

    seenGuids[guid] = true

    table.insert(candidates, {
        unit = unit,
        health = health,
        maxHealth = maxHealth,
        missing = maxHealth - health,
        pct = health / maxHealth,
    })
end

local function GetPartyHealCandidates(caster)
    local candidates = {}
    local seenGuids = {}

    if caster.GetGroup then
        local ok, group = pcall(function()
            return caster:GetGroup()
        end)

        if ok and group and group.GetMembers then
            local okMembers, members = pcall(function()
                return group:GetMembers()
            end)

            if okMembers and members then
                for _, member in pairs(members) do
                    AddCandidate(candidates, seenGuids, caster, member)
                end
            end
        end
    end

    -- Fallback for cores where Group:GetMembers is not exposed to ALE.
    if #candidates == 0 and caster.GetPlayersInRange then
        local ok, players = pcall(function()
            return caster:GetPlayersInRange(BLOOD_BOLT_HEAL_RANGE)
        end)

        if ok and players then
            for _, nearbyPlayer in pairs(players) do
                AddCandidate(candidates, seenGuids, caster, nearbyPlayer)
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.pct == b.pct then
            return a.missing > b.missing
        end

        return a.pct < b.pct
    end)

    return candidates
end

local function PlayBloodBoltHealVisual(caster, ally)
    if BLOOD_BOLT_HEAL_VISUAL_SPELL == 0 then
        return
    end

    if not ally then
        return
    end

    -- Important: make the healed ally cast the cosmetic spell on themself.
    -- Some cosmetic spells display on the caster regardless of target, so
    -- caster:CastSpell(ally, visual, true) can show the effect on the Cultist.
    local ok, err = pcall(function()
        if ally.CastSpell then
            ally:CastSpell(ally, BLOOD_BOLT_HEAL_VISUAL_SPELL, true)
        elseif caster and caster.CastSpell then
            caster:CastSpell(ally, BLOOD_BOLT_HEAL_VISUAL_SPELL, true)
        end
    end)

    if not ok then
        print("[DML Blood Bolt Heal] Visual failed: " .. tostring(err))
        return
    end

    -- Optional cleanup for cosmetic spells that briefly apply an aura.
    -- Set BLOOD_BOLT_HEAL_VISUAL_REMOVE_MS to 0 to disable this.
    if BLOOD_BOLT_HEAL_VISUAL_REMOVE_MS <= 0 or not ally.RegisterEvent then
        return
    end

    ally:RegisterEvent(
        function(eventId, delay, repeats, liveAlly)
            if not liveAlly then
                return
            end

            local hasAuraOk, hasAura = pcall(function()
                return liveAlly.HasAura
                    and liveAlly:HasAura(BLOOD_BOLT_HEAL_VISUAL_SPELL)
            end)

            if hasAuraOk and hasAura and liveAlly.RemoveAura then
                pcall(function()
                    liveAlly:RemoveAura(BLOOD_BOLT_HEAL_VISUAL_SPELL)
                end)
            end
        end,
        BLOOD_BOLT_HEAL_VISUAL_REMOVE_MS,
        1
    )
end

local function HealUnit(caster, ally, amount)
    if not caster or not ally or amount <= 0 then
        return 0
    end

    local maxHealth = ally:GetMaxHealth()
    local currentHealth = ally:GetHealth()

    if maxHealth <= 0 or currentHealth >= maxHealth then
        return 0
    end

    local newHealth = currentHealth + amount

    if newHealth > maxHealth then
        newHealth = maxHealth
    end

    local actualHeal = newHealth - currentHealth

    if actualHeal <= 0 then
        return 0
    end

    local ok, err = pcall(function()
        if caster.Heal then
            caster:Heal(ally, actualHeal)
        elseif ally.SetHealth then
            ally:SetHealth(newHealth)
        end
    end)

    if not ok then
        print("[DML Blood Bolt Heal] Heal failed: " .. tostring(err))
        return 0
    end

    PlayBloodBoltHealVisual(caster, ally)

    return actualHeal
end

local function HealPartyFromBloodBolt(caster, damage)
    if not caster or not damage or damage <= 0 then
        return
    end

    local healAmount = math.floor(damage * BLOOD_BOLT_HEAL_PERCENT)

    if healAmount <= 0 then
        return
    end

    local candidates = GetPartyHealCandidates(caster)
    local healedCount = 0

    for _, candidate in ipairs(candidates) do
        if healedCount >= BLOOD_BOLT_HEAL_MAX_TARGETS then
            break
        end

        local actualHeal = HealUnit(caster, candidate.unit, healAmount)

        if actualHeal > 0 then
            healedCount = healedCount + 1
        end
    end

    Debug(
        caster,
        "Blood Bolt healed " ..
        healedCount ..
        " party members for up to " ..
        healAmount ..
        " each."
    )
end

local function MarkBloodBoltCast(player)
    local guid = GetDmlGuidLow(player)

    if guid == 0 then
        return
    end

    castSerialByGuid[guid] = (castSerialByGuid[guid] or 0) + 1

    local serial = castSerialByGuid[guid]

    pendingBloodBoltByGuid[guid] = {
        serial = serial,
        consumed = false,
    }

    player:RegisterEvent(
        function(eventId, delay, repeats, livePlayer)
            local state = pendingBloodBoltByGuid[guid]

            if state and state.serial == serial then
                pendingBloodBoltByGuid[guid] = nil
            end
        end,
        BLOOD_BOLT_PENDING_CLEAR_MS,
        1
    )
end

local function ConsumePendingBloodBolt(player)
    local guid = GetDmlGuidLow(player)

    if guid == 0 then
        return false
    end

    local state = pendingBloodBoltByGuid[guid]

    if not state or state.consumed then
        return false
    end

    state.consumed = true
    pendingBloodBoltByGuid[guid] = nil

    return true
end

local function OnBloodBoltCast(event, player, spell, skipCheck)
    if not player or not spell then
        return
    end

    if GetDmlSpellId(spell) ~= SPELL_BLOOD_BOLT then
        return
    end

    if IsBot(player) or not IsCultist(player) then
        return
    end

    MarkBloodBoltCast(player)
end

local function OnBloodBoltDealDamage(event, player, target, damage, spell)
    if not player or not target or not damage or damage <= 0 then
        return
    end

    if IsBot(player) or not IsCultist(player) then
        return
    end

    local spellId = GetDmlSpellId(spell)

    if spellId ~= SPELL_BLOOD_BOLT then
        -- Some ALE builds do not pass spell info to damage event 72.
        -- In that case, allow exactly one damage event immediately after a
        -- confirmed Blood Bolt cast.
        if not ConsumePendingBloodBolt(player) then
            return
        end
    else
        ConsumePendingBloodBolt(player)
    end

    HealPartyFromBloodBolt(player, damage)
end

local function OnBloodBoltLogout(event, player)
    if not player then
        return
    end

    local guid = GetDmlGuidLow(player)

    if guid ~= 0 then
        pendingBloodBoltByGuid[guid] = nil
        castSerialByGuid[guid] = nil
    end
end

RegisterPlayerEvent(PLAYER_EVENT_ON_LOGOUT, OnBloodBoltLogout)
RegisterPlayerEvent(PLAYER_EVENT_ON_SPELL_CAST, OnBloodBoltCast)
RegisterPlayerEvent(PLAYER_EVENT_ON_DEAL_DAMAGE, OnBloodBoltDealDamage)

print("[DML Blood Bolt] Cultist party heal + optional visual loaded.")
