-- subclass_shaman_warden.lua
-- Warden subclass unlock + Shaman-only trainer gate
-- Frost Warden Initiation + Frost Warden Totem toggle

local NPC_WARDEN_TRAINER = 900102
local QUEST_WARDEN_PATH = 980102
local QUEST_FROST_WARDEN_INITIATION = 980103

local ITEM_WARDEN_TRIAL_SIGIL = 990113
local ITEM_FROST_WARDEN_TOTEM = 990114
local ITEM_ANKH = 17030

local SPELL_FROST_PRESENCE = 48263

local CLASS_SHAMAN = 7

local SUBCLASS_NONE = 0
local SUBCLASS_WARDEN = 3

local MIN_LEVEL_FROST_WARDEN = 10

local CREATURE_EVENT_ON_QUEST_ACCEPT = 31
local CREATURE_EVENT_ON_QUEST_REWARD = 34

local GOSSIP_EVENT_ON_HELLO = 1
local GOSSIP_EVENT_ON_SELECT = 2

local ITEM_EVENT_ON_USE = 2

local GOSSIP_ICON_CHAT = 0

local OPTION_OPEN_WARDEN_TRAINER = 1
local OPTION_RESTORE_FROST_WARDEN_TOTEM = 20
local OPTION_CLOSE = 99

local function IsBot(player)
    if player.IsBot then
        return player:IsBot()
    end

    return false
end

local function IsShaman(player)
    return player:GetClass() == CLASS_SHAMAN
end

local function GetSubclass(player)
    local guid = player:GetGUIDLow()

    local result = CharDBQuery(
        "SELECT subclass_id FROM character_subclass WHERE guid = " .. guid .. " LIMIT 1"
    )

    if result then
        return result:GetUInt32(0)
    end

    return SUBCLASS_NONE
end

local function HasSubclass(player)
    return GetSubclass(player) ~= SUBCLASS_NONE
end

local function IsWarden(player)
    return GetSubclass(player) == SUBCLASS_WARDEN
end

local function SetWarden(player)
    local guid = player:GetGUIDLow()

    CharDBExecute(string.format(
        "REPLACE INTO character_subclass (guid, subclass_id, subclass_name) VALUES (%u, %u, 'Warden')",
        guid,
        SUBCLASS_WARDEN
    ))
end

local function PlayerHasItem(player, itemId)
    return player:GetItemCount(itemId, true) > 0
end

local function RemoveAllCopiesOfItem(player, itemId)
    local count = player:GetItemCount(itemId, true)

    if count > 0 then
        player:RemoveItem(itemId, count)
    end
end

local function HasCompletedQuest(player, questId)
    if player.GetQuestRewardStatus then
        return player:GetQuestRewardStatus(questId)
    end

    return false
end

local function ShouldOfferFrostTotemRestore(player)
    return IsShaman(player)
        and IsWarden(player)
        and HasCompletedQuest(player, QUEST_FROST_WARDEN_INITIATION)
        and not PlayerHasItem(player, ITEM_FROST_WARDEN_TOTEM)
end

local function RestoreFrostWardenTotem(player)
    if not IsShaman(player) or not IsWarden(player) then
        player:SendBroadcastMessage("Only Wardens may recover this totem.")
        return
    end

    if not HasCompletedQuest(player, QUEST_FROST_WARDEN_INITIATION) then
        player:SendBroadcastMessage("You have not completed Frost Warden Initiation yet.")
        return
    end

    if PlayerHasItem(player, ITEM_FROST_WARDEN_TOTEM) then
        player:SendBroadcastMessage("You already have your Frost Warden Totem.")
        return
    end

    player:AddItem(ITEM_FROST_WARDEN_TOTEM, 1)
    player:SendBroadcastMessage("Your Frost Warden Totem has been restored.")
end

local function OnWardenQuestAccept(event, player, creature, quest)
    local questId = quest:GetId()

    if questId == QUEST_WARDEN_PATH then
        if IsBot(player) then
            player:FailQuest(questId)
            RemoveAllCopiesOfItem(player, ITEM_WARDEN_TRIAL_SIGIL)
            return false
        end

        if not IsShaman(player) then
            player:FailQuest(questId)
            RemoveAllCopiesOfItem(player, ITEM_WARDEN_TRIAL_SIGIL)
            player:SendBroadcastMessage("Only Shamans may walk the Warden path.")
            return false
        end

        if HasSubclass(player) then
            player:FailQuest(questId)
            RemoveAllCopiesOfItem(player, ITEM_WARDEN_TRIAL_SIGIL)
            player:SendBroadcastMessage("You already walk another subclass path.")
            return false
        end

        return true
    end

    if questId == QUEST_FROST_WARDEN_INITIATION then
        if IsBot(player) then
            player:FailQuest(questId)
            return false
        end

        if not IsShaman(player) then
            player:FailQuest(questId)
            player:SendBroadcastMessage("Only Shamans may begin Frost Warden Initiation.")
            return false
        end

        if not IsWarden(player) then
            player:FailQuest(questId)
            player:SendBroadcastMessage("You must complete The Warden Path first.")
            return false
        end

        if player:GetLevel() < MIN_LEVEL_FROST_WARDEN then
            player:FailQuest(questId)
            player:SendBroadcastMessage("You must be level 10 to begin Frost Warden Initiation.")
            return false
        end

        return true
    end

    return true
end

local function OnWardenQuestReward(event, player, creature, quest, opt)
    local questId = quest:GetId()

    if questId == QUEST_WARDEN_PATH then
        if IsBot(player) then
            return
        end

        if not IsShaman(player) then
            player:SendBroadcastMessage("Only Shamans may become Wardens.")
            return
        end

        if HasSubclass(player) then
            if IsWarden(player) then
                player:SendBroadcastMessage("You are already a Warden.")
            else
                player:SendBroadcastMessage("You already have a subclass.")
            end

            return
        end

        SetWarden(player)
        player:SendBroadcastMessage("You have taken the Warden path.")
        return
    end

    if questId == QUEST_FROST_WARDEN_INITIATION then
        if IsBot(player) then
            return
        end

        if not IsShaman(player) or not IsWarden(player) then
            player:SendBroadcastMessage("Only Wardens may complete Frost Warden Initiation.")
            return
        end

        player:SendBroadcastMessage("You have earned the Frost Warden Totem. Use it to learn or unlearn Frost Presence.")
        return
    end
end

local function OnWardenTrainerHello(event, player, creature)
    player:GossipClearMenu()

    if IsBot(player) then
        player:GossipComplete()
        return
    end

    player:GossipAddQuests(creature)

    if not IsShaman(player) then
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "The Warden path is only open to Shamans.",
            0,
            OPTION_CLOSE
        )

        player:GossipSendMenu(100, creature)
        return
    end

    if IsWarden(player) then
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "Train me as a Warden.",
            0,
            OPTION_OPEN_WARDEN_TRAINER
        )

        if ShouldOfferFrostTotemRestore(player) then
            player:GossipMenuAddItem(
                GOSSIP_ICON_CHAT,
                "I lost my Frost Warden Totem.",
                0,
                OPTION_RESTORE_FROST_WARDEN_TOTEM
            )
        end
    elseif HasSubclass(player) then
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "You already walk another subclass path.",
            0,
            OPTION_CLOSE
        )
    else
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "Complete The Warden Path before training as a Warden.",
            0,
            OPTION_CLOSE
        )
    end

    player:GossipSendMenu(100, creature)
end

local function OnWardenTrainerSelect(event, player, creature, sender, intid, code, menuId)
    if IsBot(player) then
        player:GossipComplete()
        return
    end

    if intid == OPTION_OPEN_WARDEN_TRAINER then
        if IsShaman(player) and IsWarden(player) then
            player:SendTrainerList(creature)
        else
            player:SendBroadcastMessage("You must complete The Warden Path first.")
            player:GossipComplete()
        end

        return
    end

    if intid == OPTION_RESTORE_FROST_WARDEN_TOTEM then
        RestoreFrostWardenTotem(player)
        player:GossipComplete()
        return
    end

    player:GossipComplete()
end

local function OnFrostWardenTotemUse(event, player, item, target)
    if IsBot(player) then
        return false
    end

    if not IsShaman(player) then
        player:SendBroadcastMessage("Only Shamans may use the Frost Warden Totem.")
        return false
    end

    if not IsWarden(player) then
        player:SendBroadcastMessage("Only Wardens may use the Frost Warden Totem.")
        return false
    end

    if player:GetLevel() < MIN_LEVEL_FROST_WARDEN then
        player:SendBroadcastMessage("You must be level 10 to use the Frost Warden Totem.")
        return false
    end

    if not HasCompletedQuest(player, QUEST_FROST_WARDEN_INITIATION) then
        player:SendBroadcastMessage("You have not completed Frost Warden Initiation yet.")
        return false
    end

    if player:HasSpell(SPELL_FROST_PRESENCE) then
        if player.RemoveAura then
            pcall(function()
                player:RemoveAura(SPELL_FROST_PRESENCE)
            end)
        end

        local ok, err = pcall(function()
            player:RemoveSpell(SPELL_FROST_PRESENCE)
        end)

        if ok then
            player:SendBroadcastMessage("You release Frost Presence.")
        else
            player:SendBroadcastMessage("Frost Presence could not be removed. Check server console.")
            print("[Subclass] Frost Warden Totem RemoveSpell failed: " .. tostring(err))
        end

        return false
    end

    player:LearnSpell(SPELL_FROST_PRESENCE)
    player:SendBroadcastMessage("You attune to Frost Presence.")
    return false
end

RegisterCreatureEvent(
    NPC_WARDEN_TRAINER,
    CREATURE_EVENT_ON_QUEST_ACCEPT,
    OnWardenQuestAccept
)

RegisterCreatureEvent(
    NPC_WARDEN_TRAINER,
    CREATURE_EVENT_ON_QUEST_REWARD,
    OnWardenQuestReward
)

RegisterCreatureGossipEvent(
    NPC_WARDEN_TRAINER,
    GOSSIP_EVENT_ON_HELLO,
    OnWardenTrainerHello
)

RegisterCreatureGossipEvent(
    NPC_WARDEN_TRAINER,
    GOSSIP_EVENT_ON_SELECT,
    OnWardenTrainerSelect
)

RegisterItemEvent(
    ITEM_FROST_WARDEN_TOTEM,
    ITEM_EVENT_ON_USE,
    OnFrostWardenTotemUse
)

print("[Subclass] Warden unlock + Frost Warden Totem script loaded.")
