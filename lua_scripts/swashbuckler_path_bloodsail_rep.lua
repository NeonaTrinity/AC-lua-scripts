-- swashbuckler_path_bloodsail_rep.lua
-- Grants 10,000 Bloodsail Buccaneers reputation when a real player
-- completes The Swashbuckler Path at the Swashbuckler Trainer.

local NPC_SWASHBUCKLER_TRAINER = 900104
local QUEST_SWASHBUCKLER_PATH = 980110

local FACTION_BLOODSAIL_BUCCANEERS = 87
local BLOODSAIL_REPUTATION_REWARD = 10000

local CREATURE_EVENT_ON_QUEST_REWARD = 34

local function IsBot(player)
    if player and player.IsBot then
        return player:IsBot()
    end

    return false
end

local function OnSwashbucklerPathReward(
    event,
    player,
    creature,
    quest,
    opt
)
    if not player or not quest then
        return
    end

    if quest:GetId() ~= QUEST_SWASHBUCKLER_PATH then
        return
    end

    if IsBot(player) then
        return
    end

    local currentReputation = player:GetReputation(
        FACTION_BLOODSAIL_BUCCANEERS
    )

    player:SetReputation(
        FACTION_BLOODSAIL_BUCCANEERS,
        currentReputation + BLOODSAIL_REPUTATION_REWARD
    )

    player:SendBroadcastMessage(
        "You gained 10,000 reputation with the Bloodsail Buccaneers."
    )
end

RegisterCreatureEvent(
    NPC_SWASHBUCKLER_TRAINER,
    CREATURE_EVENT_ON_QUEST_REWARD,
    OnSwashbucklerPathReward
)

print(
    "[Subclass] Swashbuckler Bloodsail reputation reward loaded."
)
