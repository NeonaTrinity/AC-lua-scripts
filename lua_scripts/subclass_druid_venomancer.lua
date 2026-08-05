-- DML Venomancer subclass foundation
-- AzerothCore 3.3.5a / ALE
--
-- Owns:
--   Venomancer path quest acceptance and reward
--   Character subclass assignment
--   Venomancer trainer gossip and access gate
--   Level 15 quest 980116: The Serpent's Bite
--   Deviate Adder and Deviate Moccasin damage completion trigger
--   Level 15 quest 980117: Becoming the Serpent
--   Serpent Antivenom learning item and lost-item recovery
--   Serpent Form cast objective for spell 54601
--
-- This is the authoritative Venomancer subclass and progression script.
-- Do not load separate scripts that register these same quest, item, or spell events.

local NPC_VENOMANCER_TRAINER = 900105
local QUEST_VENOMANCER_PATH = 980115
local QUEST_SERPENTS_BITE = 980116
local QUEST_BECOMING_THE_SERPENT = 980117

local ITEM_VENOMANCER_TRIAL_SIGIL = 990127
local ITEM_SERPENT_ANTIVENOM = 990128

local SPELL_SERPENT_FORM = 54601

local NPC_DEVIATE_ADDER = 5048
local NPC_DEVIATE_MOCCASIN = 5762

local CLASS_DRUID = 11

local SUBCLASS_NONE = 0
local SUBCLASS_VENOMANCER = 6
local SUBCLASS_SLUG = "venomancer"

local CREATURE_EVENT_ON_QUEST_ACCEPT = 31
local CREATURE_EVENT_ON_QUEST_REWARD = 34
local CREATURE_EVENT_ON_DEAL_DAMAGE = 46
local GOSSIP_EVENT_ON_HELLO = 1
local GOSSIP_EVENT_ON_SELECT = 2
local ITEM_EVENT_ON_USE = 2
local PLAYER_EVENT_ON_SPELL_CAST = 5

local GOSSIP_ICON_CHAT = 0
local OPTION_OPEN_VENOMANCER_TRAINER = 1
local OPTION_RECOVER_SERPENT_ANTIVENOM = 20
local OPTION_CLOSE = 99

local QUEST_STATUS_INCOMPLETE = 3

local function IsBot(player)
    if player.IsBot then
        return player:IsBot()
    end

    return false
end

local function IsDruid(player)
    return player:GetClass() == CLASS_DRUID
end

local function RemoveAllCopiesOfItem(player, itemId)
    local count = player:GetItemCount(itemId, true)

    if count > 0 then
        player:RemoveItem(itemId, count)
    end
end

local function GetSubclass(player)
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

    return SUBCLASS_NONE
end

local function HasSubclass(player)
    return GetSubclass(player) ~= SUBCLASS_NONE
end

local function IsVenomancer(player)
    return GetSubclass(player) == SUBCLASS_VENOMANCER
end

local function SetVenomancer(player)
    CharDBExecute(string.format(
        "REPLACE INTO character_subclass " ..
        "(guid, subclass_id, subclass_name) " ..
        "VALUES (%u, %u, '%s')",
        player:GetGUIDLow(),
        SUBCLASS_VENOMANCER,
        SUBCLASS_SLUG
    ))
end

local function RejectPathQuest(player, questId, message)
    player:FailQuest(questId)
    RemoveAllCopiesOfItem(player, ITEM_VENOMANCER_TRIAL_SIGIL)

    if message then
        player:SendBroadcastMessage(message)
    end

    return false
end

local function RejectProgressionQuest(player, questId, message, providedItemId)
    player:FailQuest(questId)

    if providedItemId then
        RemoveAllCopiesOfItem(player, providedItemId)
    end

    if message then
        player:SendBroadcastMessage(message)
    end

    return false
end

local function OnVenomancerQuestAccept(event, player, creature, quest)
    local questId = quest:GetId()

    if questId == QUEST_VENOMANCER_PATH then
        if IsBot(player) then
            return RejectPathQuest(player, questId, nil)
        end

        if not IsDruid(player) then
            return RejectPathQuest(
                player,
                questId,
                "Only Druids may walk the Venomancer path."
            )
        end

        if HasSubclass(player) then
            if IsVenomancer(player) then
                return RejectPathQuest(
                    player,
                    questId,
                    "You already walk the Venomancer path."
                )
            end

            return RejectPathQuest(
                player,
                questId,
                "You already walk another subclass path."
            )
        end

        return true
    end

    if questId == QUEST_SERPENTS_BITE then
        if IsBot(player) then
            return RejectProgressionQuest(player, questId, nil)
        end

        if not IsDruid(player) then
            return RejectProgressionQuest(
                player,
                questId,
                "Only Druids may undertake this Venomancer trial."
            )
        end

        if player:GetLevel() < 15 then
            return RejectProgressionQuest(
                player,
                questId,
                "You must reach level 15 before undertaking this trial."
            )
        end

        if not player:GetQuestRewardStatus(QUEST_VENOMANCER_PATH) then
            return RejectProgressionQuest(
                player,
                questId,
                "You must complete The Venomancer Path first."
            )
        end

        if not IsVenomancer(player) then
            return RejectProgressionQuest(
                player,
                questId,
                "Only a true Venomancer may undertake this trial."
            )
        end

        return true
    end

    if questId == QUEST_BECOMING_THE_SERPENT then
        if IsBot(player) then
            return RejectProgressionQuest(
                player,
                questId,
                nil,
                ITEM_SERPENT_ANTIVENOM
            )
        end

        if not IsDruid(player) then
            return RejectProgressionQuest(
                player,
                questId,
                "Only Druids may learn the shape of the serpent.",
                ITEM_SERPENT_ANTIVENOM
            )
        end

        if player:GetLevel() < 15 then
            return RejectProgressionQuest(
                player,
                questId,
                "You must reach level 15 before learning Serpent Form.",
                ITEM_SERPENT_ANTIVENOM
            )
        end

        if not player:GetQuestRewardStatus(QUEST_SERPENTS_BITE) then
            return RejectProgressionQuest(
                player,
                questId,
                "You must survive The Serpent's Bite first.",
                ITEM_SERPENT_ANTIVENOM
            )
        end

        if not IsVenomancer(player) then
            return RejectProgressionQuest(
                player,
                questId,
                "Only a true Venomancer may learn Serpent Form.",
                ITEM_SERPENT_ANTIVENOM
            )
        end

        return true
    end

    return true
end

local function OnVenomancerQuestReward(event, player, creature, quest, opt)
    if quest:GetId() ~= QUEST_VENOMANCER_PATH then
        return
    end

    if IsBot(player) then
        return
    end

    if not IsDruid(player) then
        player:SendBroadcastMessage(
            "Only Druids may become Venomancers."
        )
        return
    end

    if HasSubclass(player) then
        if IsVenomancer(player) then
            player:SendBroadcastMessage(
                "You are already a Venomancer."
            )
        else
            player:SendBroadcastMessage(
                "You already have a subclass."
            )
        end

        return
    end

    SetVenomancer(player)

    player:SendBroadcastMessage(
        "You have taken the Venomancer path."
    )
end

local function ShouldOfferSerpentAntivenomRecovery(player)
    return IsDruid(player)
        and IsVenomancer(player)
        and player:GetQuestStatus(QUEST_BECOMING_THE_SERPENT) == QUEST_STATUS_INCOMPLETE
        and not player:HasSpell(SPELL_SERPENT_FORM)
        and player:GetItemCount(ITEM_SERPENT_ANTIVENOM, true) == 0
end

local function OnVenomancerTrainerHello(event, player, creature)
    player:GossipClearMenu()

    if IsBot(player) then
        player:GossipComplete()
        return
    end

    player:GossipAddQuests(creature)

    if not IsDruid(player) then
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "The Venomancer path is only open to Druids.",
            0,
            OPTION_CLOSE
        )

        player:GossipSendMenu(100, creature)
        return
    end

    local subclassId = GetSubclass(player)

    if subclassId == SUBCLASS_VENOMANCER then
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "Train me as a Venomancer.",
            0,
            OPTION_OPEN_VENOMANCER_TRAINER
        )
    elseif subclassId ~= SUBCLASS_NONE then
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "You already walk another subclass path.",
            0,
            OPTION_CLOSE
        )
    else
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "Complete The Venomancer Path before training as a Venomancer.",
            0,
            OPTION_CLOSE
        )
    end

    if ShouldOfferSerpentAntivenomRecovery(player) then
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "I lost the Serpent Antivenom.",
            0,
            OPTION_RECOVER_SERPENT_ANTIVENOM
        )
    end

    player:GossipSendMenu(100, creature)
end

local function OnVenomancerTrainerSelect(
    event,
    player,
    creature,
    sender,
    intid,
    code,
    menuId
)
    if IsBot(player) then
        player:GossipComplete()
        return
    end

    if intid == OPTION_RECOVER_SERPENT_ANTIVENOM then
        if ShouldOfferSerpentAntivenomRecovery(player) then
            local addedItem = player:AddItem(ITEM_SERPENT_ANTIVENOM, 1)

            if addedItem then
                player:SendBroadcastMessage(
                    "The Venomancer Trainer replaces your lost Serpent Antivenom."
                )
            else
                player:SendBroadcastMessage(
                    "You need more room in your bags before I can replace the antivenom."
                )
            end
        else
            player:SendBroadcastMessage(
                "You do not need another vial of Serpent Antivenom."
            )
        end

        player:GossipComplete()
        return
    end

    if intid == OPTION_OPEN_VENOMANCER_TRAINER then
        if IsDruid(player) and IsVenomancer(player) then
            player:SendTrainerList(creature)
        else
            player:SendBroadcastMessage(
                "You must complete The Venomancer Path first."
            )

            player:GossipComplete()
        end

        return
    end

    player:GossipComplete()
end

local function OnDeviateSerpentDealDamage(
    event,
    creature,
    target,
    damage,
    damageType
)
    if not target or damage <= 0 or not target:IsPlayer() then
        return
    end

    local player = target:ToPlayer()

    if not player or IsBot(player) or not IsDruid(player) then
        return
    end

    if player:GetQuestStatus(QUEST_SERPENTS_BITE) ~= QUEST_STATUS_INCOMPLETE then
        return
    end

    if not IsVenomancer(player) then
        return
    end

    player:AreaExploredOrEventHappens(QUEST_SERPENTS_BITE)
    player:SendBroadcastMessage(
        "The Deviate serpent's venom courses through your blood. Return to the Venomancer Trainer."
    )
end

local function OnSerpentAntivenomUse(event, player, item, target)
    if IsBot(player) then
        return false
    end

    if not IsDruid(player) then
        player:SendBroadcastMessage(
            "Only Druids can understand the Venomancer's antivenom ritual."
        )
        return false
    end

    if not IsVenomancer(player) then
        player:SendBroadcastMessage(
            "Only a Venomancer can learn the shape hidden within this antivenom."
        )
        return false
    end

    if player:GetLevel() < 15 then
        player:SendBroadcastMessage(
            "You must reach level 15 before using the Serpent Antivenom."
        )
        return false
    end

    if player:GetQuestStatus(QUEST_BECOMING_THE_SERPENT) ~= QUEST_STATUS_INCOMPLETE then
        player:SendBroadcastMessage(
            "You must be undertaking Becoming the Serpent to use this antivenom."
        )
        return false
    end

    if not player:GetQuestRewardStatus(QUEST_SERPENTS_BITE) then
        player:SendBroadcastMessage(
            "You must survive The Serpent's Bite before using this antivenom."
        )
        return false
    end

    if player:HasSpell(SPELL_SERPENT_FORM) then
        player:SendBroadcastMessage(
            "You already know Serpent Form."
        )
        return false
    end

    player:LearnSpell(SPELL_SERPENT_FORM)

    if player:HasSpell(SPELL_SERPENT_FORM) then
        player:RemoveItem(ITEM_SERPENT_ANTIVENOM, 1)
        player:SendBroadcastMessage(
            "Serpent Form has entered your mind. Cast it now and become the serpent."
        )
    else
        player:SendBroadcastMessage(
            "The antivenom failed to transfer its knowledge. The item was not consumed."
        )
    end

    return false
end

local function OnVenomancerSpellCast(event, player, spell, skipCheck)
    if not spell or spell:GetEntry() ~= SPELL_SERPENT_FORM then
        return
    end

    if IsBot(player) or not IsDruid(player) or not IsVenomancer(player) then
        return
    end

    if player:GetQuestStatus(QUEST_BECOMING_THE_SERPENT) ~= QUEST_STATUS_INCOMPLETE then
        return
    end

    if not player:HasSpell(SPELL_SERPENT_FORM) then
        return
    end

    player:AreaExploredOrEventHappens(QUEST_BECOMING_THE_SERPENT)
    player:SendBroadcastMessage(
        "You have taken the shape of the serpent. Return to the Venomancer Trainer."
    )
end

RegisterCreatureEvent(
    NPC_VENOMANCER_TRAINER,
    CREATURE_EVENT_ON_QUEST_ACCEPT,
    OnVenomancerQuestAccept
)

RegisterCreatureEvent(
    NPC_VENOMANCER_TRAINER,
    CREATURE_EVENT_ON_QUEST_REWARD,
    OnVenomancerQuestReward
)

RegisterCreatureGossipEvent(
    NPC_VENOMANCER_TRAINER,
    GOSSIP_EVENT_ON_HELLO,
    OnVenomancerTrainerHello
)

RegisterCreatureGossipEvent(
    NPC_VENOMANCER_TRAINER,
    GOSSIP_EVENT_ON_SELECT,
    OnVenomancerTrainerSelect
)

RegisterCreatureEvent(
    NPC_DEVIATE_ADDER,
    CREATURE_EVENT_ON_DEAL_DAMAGE,
    OnDeviateSerpentDealDamage
)

RegisterCreatureEvent(
    NPC_DEVIATE_MOCCASIN,
    CREATURE_EVENT_ON_DEAL_DAMAGE,
    OnDeviateSerpentDealDamage
)

RegisterItemEvent(
    ITEM_SERPENT_ANTIVENOM,
    ITEM_EVENT_ON_USE,
    OnSerpentAntivenomUse
)

RegisterPlayerEvent(
    PLAYER_EVENT_ON_SPELL_CAST,
    OnVenomancerSpellCast
)

print("[Subclass] Venomancer unlock, trainer, serpent-bite, and Serpent Form quest script loaded.")
