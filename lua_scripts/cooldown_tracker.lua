-- custom_cooldown_messages.lua
-- ALE server script for custom cooldown notifications and addon hooks.
--
-- Human-readable message:
--   Seal of Protection used - 5 minutes cooldown.
--
-- Machine-readable system message consumed by the DML Cooldown Bar addon:
--   DMLCD|START|<spellId>|<cooldownMs>|<castToken>|<spellName>|<rank>|<customText>|<family>
--   DMLCD|READY|<spellId>|0|<castToken>|<spellName>|<rank>|<customText>|<family>
--   DMLCD|LEARN|<spellId>|0|0|<spellName>|<rank>|<customText>|<family>
--
-- The cast token prevents an older timer from marking a spell ready after
-- that spell has been cast again.

local SPELL_EVENT_ON_CAST = 2
local SHOW_HUMAN_MESSAGES = false

local TRACKED_SPELLS = {
    [17177] = {
        name = "Seal of Protection",
        cooldown_ms = 300000,
        notify_ready = true
    },

    [13903] = {
        name = "Seal of Sacrifice",
        cooldown_ms = 300000,
        notify_ready = true
    },

    [13953] = {
        name = "Holy Strike",
        family = "holy_strike",
        rank = 1,
        custom_text = "", -- Add the finalized Rank 1 damage text here.
        cooldown_ms = 1500,
        notify_ready = false
    },

    [17143] = {
        name = "Holy Strike",
        family = "holy_strike",
        rank = 2,
        custom_text = "", -- Add the finalized Rank 2 damage text here.
        cooldown_ms = 1500,
        notify_ready = false
    },

    [46565] = {
        name = "Holyform",
        cooldown_ms = 1500,
        notify_ready = false
    },

    [71954] = {
        name = "Holy Champion",
        cooldown_ms = 1500,
        notify_ready = false
    },

    [37572] = {
	name = "Holy Slam",
	cooldown_ms = 60000,
	notify_ready = true
	},

    [34232] = {
        name = "Holy Bolt",
        family = "holy_bolt",
        rank = 1,
        custom_text = "", -- Add the finalized Rank 1 damage text here.
        cooldown_ms = 0,
        notify_ready = false
    },

    [34346] = {
        name = "Holy Bolt",
        family = "holy_bolt",
        rank = 2,
        custom_text = "", -- Add the finalized Rank 2 damage text here.
        cooldown_ms = 0,
        notify_ready = false
    },

[879] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 1,
    custom_text = "", -- Add the finalized Rank 1 damage text here.
    cooldown_ms = 6000,
    lua_managed = true,
    notify_ready = false
},

[5614] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 2,
    custom_text = "", -- Add the finalized Rank 2 damage text here.
    cooldown_ms = 6000,
    lua_managed = true,
    notify_ready = false
},

[5615] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 3,
    custom_text = "", -- Add the finalized Rank 3 damage text here.
    cooldown_ms = 6000,
    lua_managed = true,
    notify_ready = false
},

[10312] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 4,
    custom_text = "", -- Add the finalized Rank 4 damage text here.
    cooldown_ms = 6000,
    lua_managed = true,
    notify_ready = false
},

[10313] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 5,
    custom_text = "", -- Add the finalized Rank 5 damage text here.
    cooldown_ms = 6000,
    lua_managed = true,
    notify_ready = false
},

[10314] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 6,
    custom_text = "", -- Add the finalized Rank 6 damage text here.
    cooldown_ms = 6000,
    lua_managed = true,
    notify_ready = false
},

[27138] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 7,
    custom_text = "", -- Add the finalized Rank 7 damage text here.
    cooldown_ms = 6000,
    lua_managed = true,
    notify_ready = false
},

[48800] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 8,
    custom_text = "", -- Add the finalized Rank 8 damage text here.
    cooldown_ms = 6000,
    lua_managed = true,
    notify_ready = false
},

[48801] = {
    name = "Exorcism",
    family = "exorcism",
    rank = 9,
    custom_text = "", -- Add the finalized Rank 9 damage text here.
    cooldown_ms = 6000,
    lua_managed = true,
    notify_ready = false
},


    [54086] = {
	name = "Holy Water",
	cooldown_ms = 6000,
	notify_ready = true
	},



    [33400] = {
	name = "Accelerated Mending",
	cooldown_ms = 300000,
	notify_ready = true
	},

    [16451] = {
	name = "Judge's Gavel",
	cooldown_ms = 300000,
	notify_ready = true
	},

    [58464] = {
	name = "Chains of Ice",
	cooldown_ms = 60000,
	notify_ready = true
	},

    [32906] = {
        name = "Chomp",
        cooldown_ms = 1500,
        notify_ready = false
    },

    [9741] = {
        name = "Avantir's Rage",
        cooldown_ms = 60000,
        notify_ready = true
    },

    [36213] = {
        name = "Angered Earth",
        cooldown_ms = 60000,
        notify_ready = true
    },

    [33054] = {
        name = "Spell Shield",
        cooldown_ms = 1800000,
        notify_ready = true
    },


    [38026] = {
        name = "Viscous Shield",
        cooldown_ms = 300000,
        notify_ready = true
    },

    [34355] = {
        name = "Poison Shield",
        cooldown_ms = 1500,
        notify_ready = true
    },

    [56855] = {
        name = "Cyclone Strike",
        cooldown_ms = 1500,
        notify_ready = true
    },

    [3419] = {
        name = "Improved Blocking",
        cooldown_ms = 16000,
        notify_ready = true
    },


    [30472] = {
        name = "Aura of Discipline",
        cooldown_ms = 1800000,
        notify_ready = true
    },

    [61070] = {
        name = "Smash",
	cooldown_ms = 10000,
	notify_ready = false,
	lua_managed = true
    },

    [34618] = {
        name = "Smash",
	cooldown_ms = 10000,
	notify_ready = false,
	lua_managed = true
    },

    [25515] = {
        name = "Bash",
        cooldown_ms = 45000,
        notify_ready = true
    },

    [61580] = {
        name = "Thunderstomp",
        cooldown_ms = 20000,
        notify_ready = true
    },

    [60160] = {
        name = "Death and Decay",
        cooldown_ms = 10000,
        notify_ready = true
    },

    [49701] = {
        name = "Blood Siphon",
        cooldown_ms = 30000,
        notify_ready = true
    },

    [11972] = {
        name = "Shield Bash",
        cooldown_ms = 12000,
        notify_ready = true
    },

    [39647] = {
        name = "Curse of Mending",
        cooldown_ms = 1200000,
        notify_ready = true
    },

    [36476] = {
        name = "Blood Heal",
        cooldown_ms = 10000,
        notify_ready = false
    },

    [36950] = {
        name = "Blinding Light",
        cooldown_ms = 180000,
        notify_ready = true
    },

    [70445] = {
        name = "Blood Mirror",
        cooldown_ms = 300000,
        notify_ready = true
    },

    [52761] = {
        name = "Barbed net",
        cooldown_ms = 60000,
        notify_ready = true
    },

    [6253] = {
        name = "Backhand",
        cooldown_ms = 30000,
        notify_ready = true
    },

    [7105] = {
        name = "Fake Shot",
        cooldown_ms = 10000,
        notify_ready = true
    },

    [31567] = {
        name = "Deterrence",
        cooldown_ms = 120000,
        notify_ready = false,
    	lua_managed = true
    },

[59395] = {
    name = "Abomination Hook",
    cooldown_ms = 60000,
    notify_ready = false,
    lua_managed = true
},

[33969] = {
    name = "Draining Bolt",
    cooldown_ms = 30000,
    notify_ready = true
},

[25198] = {
    name = "Poison Cloud",
    cooldown_ms = 10000,
    notify_ready = false
},

[11445] = {
    name = "Bone Armor",
    cooldown_ms = 180000,
    notify_ready = true
},

    [63226] = {
        name = "Poison Breath",
        cooldown_ms = 45000,
        notify_ready = true
    },

    [54593] = {
        name = "Sepent Strike",
        cooldown_ms = 1500,
        notify_ready = false
    },

    [13526] = {
        name = "Corrosive Poison",
        cooldown_ms = 1500,
        notify_ready = false
    },

    [61095] = {
        name = "Plagueblast",
        cooldown_ms = 45000,
        notify_ready = false
    },

    [53669] = {
        name = "Poisoned Fangs",
        cooldown_ms = 6000,
        notify_ready = false
    },

    [70659] = {
        name = "Nectroic Strike",
        cooldown_ms = 10000,
        notify_ready = false
    },

[54601] = {
    name = "Serpent Form",
    cooldown_ms = 90000,
    notify_ready = false,
    lua_managed = true
},

[52469] = {
    name = "Infected Bite",
    cooldown_ms = 8000,
    notify_ready = false
},

[36617] = {
    name = "Gaping Maw",
    cooldown_ms = 1500,
    notify_ready = false
},

[54790] = {
    name = "Blood Tap",
    cooldown_ms = 1500,
    notify_ready = false
},

[59840] = {
    name = "Powerful Bite",
    cooldown_ms = 1500,
    notify_ready = false
},

[41396] = {
    name = "Sleep",
    cooldown_ms = 1500,
    notify_ready = false
},

[59701] = {
    name = "Holy Nova",
    cooldown_ms = 6000,
    notify_ready = false
},

[31803] = {
    name = "Holy Vengeance",
    cooldown_ms = 0,
    notify_ready = false
},

[37554] = {
    name = "Avenger's Shield",
    cooldown_ms = 12000,
    notify_ready = false
}



}

local ACTIVE_CAST_TOKENS = {}

local function FormatCooldown(milliseconds)
    if milliseconds >= 60000 then
        local minutes = milliseconds / 60000

        if minutes == math.floor(minutes) then
            return string.format(
                "%d minute%s",
                minutes,
                minutes == 1 and "" or "s"
            )
        end

        return string.format("%.1f minutes", minutes)
    end

    local seconds = milliseconds / 1000

    if seconds == math.floor(seconds) then
        return string.format(
            "%d second%s",
            seconds,
            seconds == 1 and "" or "s"
        )
    end

    return string.format("%.1f seconds", seconds)
end

local function SanitizeProtocolText(text)
    return tostring(text or ""):gsub("|", "/")
end

local function SendAddonHook(player, eventName, spellId, cooldownMs, castToken, config)
    config = config or {}

    local payload = string.format(
        "DMLCD|%s|%d|%d|%d|%s|%s|%s|%s",
        eventName,
        spellId,
        cooldownMs or 0,
        castToken or 0,
        SanitizeProtocolText(config.name),
        SanitizeProtocolText(config.rank),
        SanitizeProtocolText(config.custom_text),
        SanitizeProtocolText(config.family)
    )

    -- The addon listens to CHAT_MSG_SYSTEM and consumes messages beginning
    -- with "DMLCD|". Pipes in editable text are replaced with slashes.
    player:SendBroadcastMessage(payload)
end

-- Optional helper for subclass/item scripts that call player:LearnSpell().
-- Call this immediately after the spell was successfully learned.
function DMLCooldownTrackerSendLearn(player, spellId)
    spellId = tonumber(spellId)
    local config = spellId and TRACKED_SPELLS[spellId]
    if not player or not config then
        return false
    end

    SendAddonHook(player, "LEARN", spellId, 0, 0, config)
    return true
end

-- Sends tooltip/rank metadata without auto-assigning a spell.
function DMLCooldownTrackerSendMeta(player, spellId)
    spellId = tonumber(spellId)
    local config = spellId and TRACKED_SPELLS[spellId]
    if not player or not config then
        return false
    end

    SendAddonHook(player, "META", spellId, 0, 0, config)
    return true
end

local function GetNextCastToken(playerGuid, spellId)
    if not ACTIVE_CAST_TOKENS[playerGuid] then
        ACTIVE_CAST_TOKENS[playerGuid] = {}
    end

    local nextToken = (ACTIVE_CAST_TOKENS[playerGuid][spellId] or 0) + 1
    ACTIVE_CAST_TOKENS[playerGuid][spellId] = nextToken
    return nextToken
end

local function IsCurrentCastToken(playerGuid, spellId, castToken)
    return ACTIVE_CAST_TOKENS[playerGuid]
        and ACTIVE_CAST_TOKENS[playerGuid][spellId] == castToken
end

local function CheckAndSendReady(playerGuid, spellId, castToken)
    if not IsCurrentCastToken(playerGuid, spellId, castToken) then
        return
    end

    local player = GetPlayerByGUID(playerGuid)
    if not player then
        return
    end

    local config = TRACKED_SPELLS[spellId]
    if not config then
        return
    end

    if player:HasSpellCooldown(spellId) then
        CreateLuaEvent(
            function()
                CheckAndSendReady(playerGuid, spellId, castToken)
            end,
            1000,
            1
        )
        return
    end

	if SHOW_HUMAN_MESSAGES then
    		player:SendBroadcastMessage(
        		string.format("%s is ready.", config.name)
   	 )
	end

    SendAddonHook(
        player,
        "READY",
        spellId,
        0,
        castToken,
        config
    )
end

local function OnTrackedSpellCast(event, caster, spell, skipCheck)
    local player = caster:ToPlayer()
    if not player then
        return
    end

    local spellId = spell:GetEntry()
    local config = TRACKED_SPELLS[spellId]
    if not config then
        return
    end

    local playerGuid = player:GetGUID()
    local castToken = GetNextCastToken(playerGuid, spellId)

   if SHOW_HUMAN_MESSAGES then
   	 player:SendBroadcastMessage(
        	string.format(
            	"%s used - %s cooldown.",
            	config.name,
            	FormatCooldown(config.cooldown_ms)
        	)
    	)
	end

    SendAddonHook(
        player,
        "START",
        spellId,
        config.cooldown_ms,
        castToken,
        config
    )

    if config.notify_ready then
        CreateLuaEvent(
            function()
                CheckAndSendReady(playerGuid, spellId, castToken)
            end,
            config.cooldown_ms,
            1
        )
    end
end

for spellId, _ in pairs(TRACKED_SPELLS) do
    RegisterSpellEvent(
        spellId,
        SPELL_EVENT_ON_CAST,
        OnTrackedSpellCast
    )
end


print("Cooldown tracker with DML ADDON hook loaded.")