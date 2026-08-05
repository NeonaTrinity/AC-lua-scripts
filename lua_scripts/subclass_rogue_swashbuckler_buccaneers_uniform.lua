-- subclass_rogue_swashbuckler.lua
--
-- Complete Swashbuckler subclass trainer and progression controller.
--
-- Handles:
--   * Swashbuckler path unlock and Rogue-only trainer gate
--   * Thick Hide quest-chain acceptance prerequisites
--   * Thick Hide Rank 1-3 learning items
--   * Scatter Shot learning item
--   * Lost learning-item recovery through trainer gossip
--
-- This file replaces the older subclass_rogue_swashbuckler.lua and the
-- separate Swashbuckler armor/scatter-shot learning scripts.

local NPC_SWASHBUCKLER_TRAINER = 900104

local QUEST_SWASHBUCKLER_PATH = 980110
local QUEST_LIGHT_ARMOR = 980111
local QUEST_MEDIUM_ARMOR = 980112
local QUEST_HEAVY_ARMOR = 980113
local QUEST_SCATTER_SHOT = 980114

local ITEM_SWASHBUCKLER_TRIAL_SIGIL = 990122
local ITEM_BUCCANEERS_UNIFORM = 22746
local ITEM_LIGHT_ARMOR_KIT = 990123
local ITEM_MEDIUM_ARMOR_KIT = 990124
local ITEM_HEAVY_ARMOR_KIT = 990125
local ITEM_SCATTER_SHOT_FORMULA = 990126

local SPELL_THICK_HIDE_RANK_1 = 16929
local SPELL_THICK_HIDE_RANK_2 = 16930
local SPELL_THICK_HIDE_RANK_3 = 16931
local SPELL_SCATTER_SHOT = 19503

local CLASS_ROGUE = 4

local SUBCLASS_NONE = 0
local SUBCLASS_SWASHBUCKLER = 5

local CREATURE_EVENT_ON_QUEST_ACCEPT = 31
local CREATURE_EVENT_ON_QUEST_REWARD = 34

local GOSSIP_EVENT_ON_HELLO = 1
local GOSSIP_EVENT_ON_SELECT = 2

local ITEM_EVENT_ON_USE = 2

local GOSSIP_ICON_CHAT = 0

local OPTION_OPEN_SWASHBUCKLER_TRAINER = 1
local OPTION_CLOSE = 99
local OPTION_REISSUE_ARMOR_BASE = 2200
local OPTION_REISSUE_SCATTER_SHOT = 2301

local ARMOR_RANKS = {
    [1] = {
        quest = QUEST_LIGHT_ARMOR,
        item = ITEM_LIGHT_ARMOR_KIT,
        spell = SPELL_THICK_HIDE_RANK_1,
        required_level = 10,
        previous_rank = 0,
        item_name = "Light Swashbuckler Armor Kit",
        recovery_text = "I lost my Light Swashbuckler Armor Kit."
    },
    [2] = {
        quest = QUEST_MEDIUM_ARMOR,
        item = ITEM_MEDIUM_ARMOR_KIT,
        spell = SPELL_THICK_HIDE_RANK_2,
        required_level = 10,
        previous_rank = 1,
        item_name = "Medium Swashbuckler Armor Kit",
        recovery_text = "I lost my Medium Swashbuckler Armor Kit."
    },
    [3] = {
        quest = QUEST_HEAVY_ARMOR,
        item = ITEM_HEAVY_ARMOR_KIT,
        spell = SPELL_THICK_HIDE_RANK_3,
        required_level = 10,
        previous_rank = 2,
        item_name = "Heavy Swashbuckler Armor Kit",
        recovery_text = "I lost my Heavy Swashbuckler Armor Kit."
    }
}

local function IsBot(player)
    if player and player.IsBot then
        local ok, result = pcall(function()
            return player:IsBot()
        end)

        return ok and result
    end

    return false
end

local function IsRogue(player)
    return player and player:GetClass() == CLASS_ROGUE
end

local function GetSubclass(player)
    if not player then
        return SUBCLASS_NONE
    end

    local result = CharDBQuery(
        "SELECT subclass_id " ..
        "FROM character_subclass " ..
        "WHERE guid = " .. player:GetGUIDLow() .. " " ..
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

local function IsSwashbuckler(player)
    return IsRogue(player)
        and GetSubclass(player) == SUBCLASS_SWASHBUCKLER
end

local function SetSwashbuckler(player)
    CharDBExecute(string.format(
        "REPLACE INTO character_subclass " ..
        "(guid, subclass_id, subclass_name) " ..
        "VALUES (%u, %u, 'swashbuckler')",
        player:GetGUIDLow(),
        SUBCLASS_SWASHBUCKLER
    ))
end

local function PlayerHasItem(player, itemEntry)
    return player:GetItemCount(itemEntry, true) > 0
end

local function RemoveAllCopiesOfItem(player, itemEntry)
    local count = player:GetItemCount(itemEntry, true)

    if count > 0 then
        player:RemoveItem(itemEntry, count)
    end
end

local function CleanupSwashbucklerBotQuestItems(player)
    RemoveAllCopiesOfItem(player, ITEM_SWASHBUCKLER_TRIAL_SIGIL)
    RemoveAllCopiesOfItem(player, ITEM_BUCCANEERS_UNIFORM)
    RemoveAllCopiesOfItem(player, ITEM_LIGHT_ARMOR_KIT)
    RemoveAllCopiesOfItem(player, ITEM_MEDIUM_ARMOR_KIT)
    RemoveAllCopiesOfItem(player, ITEM_HEAVY_ARMOR_KIT)
    RemoveAllCopiesOfItem(player, ITEM_SCATTER_SHOT_FORMULA)
end

local function GetKnownThickHideRank(player)
    if player:HasSpell(SPELL_THICK_HIDE_RANK_3) then
        return 3
    end

    if player:HasSpell(SPELL_THICK_HIDE_RANK_2) then
        return 2
    end

    if player:HasSpell(SPELL_THICK_HIDE_RANK_1) then
        return 1
    end

    return 0
end

local function RemoveAllThickHideRanks(player)
    player:RemoveSpell(SPELL_THICK_HIDE_RANK_1)
    player:RemoveSpell(SPELL_THICK_HIDE_RANK_2)
    player:RemoveSpell(SPELL_THICK_HIDE_RANK_3)
end

local function IsSwashbucklerQuest(questId)
    return questId == QUEST_SWASHBUCKLER_PATH
        or questId == QUEST_LIGHT_ARMOR
        or questId == QUEST_MEDIUM_ARMOR
        or questId == QUEST_HEAVY_ARMOR
        or questId == QUEST_SCATTER_SHOT
end

local function RejectAcceptedQuest(player, questId, message)
    player:FailQuest(questId)

    if message and message ~= "" then
        player:SendBroadcastMessage(message)
    end

    return false
end

local function OnSwashbucklerQuestAccept(event, player, creature, quest)
    local questId = quest:GetId()

    if not IsSwashbucklerQuest(questId) then
        return true
    end

    if IsBot(player) then
        CleanupSwashbucklerBotQuestItems(player)
        return RejectAcceptedQuest(player, questId, nil)
    end

    if questId == QUEST_SWASHBUCKLER_PATH then
        if not IsRogue(player) then
            RemoveAllCopiesOfItem(
                player,
                ITEM_SWASHBUCKLER_TRIAL_SIGIL
            )

            return RejectAcceptedQuest(
                player,
                questId,
                "Only Rogues may walk the Swashbuckler path."
            )
        end

        if HasSubclass(player) then
            RemoveAllCopiesOfItem(
                player,
                ITEM_SWASHBUCKLER_TRIAL_SIGIL
            )

            return RejectAcceptedQuest(
                player,
                questId,
                "You already walk another subclass path."
            )
        end

        -- Give the path applicant their Swashbuckler attire immediately.
        -- Duplicate protection also makes abandoning and reaccepting safe.
        if not PlayerHasItem(player, ITEM_BUCCANEERS_UNIFORM) then
            local addedUniform = player:AddItem(
                ITEM_BUCCANEERS_UNIFORM,
                1
            )

            if not addedUniform then
                return RejectAcceptedQuest(
                    player,
                    questId,
                    "You need more room in your bags to receive the Buccaneer's Uniform."
                )
            end

            player:SendBroadcastMessage(
                "You receive a Buccaneer's Uniform for your Swashbuckler trial."
            )
        end

        return true
    end

    if not IsSwashbuckler(player) then
        return RejectAcceptedQuest(
            player,
            questId,
            "Only Swashbucklers may undertake this quest."
        )
    end

    local knownRank = GetKnownThickHideRank(player)

    if questId == QUEST_LIGHT_ARMOR then
        if not player:GetQuestRewardStatus(
            QUEST_SWASHBUCKLER_PATH
        ) then
            return RejectAcceptedQuest(
                player,
                questId,
                "Complete The Swashbuckler Path first."
            )
        end

        return true
    end

    if questId == QUEST_MEDIUM_ARMOR then
        if not player:GetQuestRewardStatus(
            QUEST_LIGHT_ARMOR
        ) then
            return RejectAcceptedQuest(
                player,
                questId,
                "Complete Light Reinforcement first."
            )
        end

        if knownRank < 1 then
            return RejectAcceptedQuest(
                player,
                questId,
                "Use your Light Swashbuckler Armor Kit and learn Thick Hide Rank 1 before continuing."
            )
        end

        return true
    end

    if questId == QUEST_HEAVY_ARMOR then
        if not player:GetQuestRewardStatus(
            QUEST_MEDIUM_ARMOR
        ) then
            return RejectAcceptedQuest(
                player,
                questId,
                "Complete Medium Reinforcement first."
            )
        end

        if knownRank < 2 then
            return RejectAcceptedQuest(
                player,
                questId,
                "Use your Medium Swashbuckler Armor Kit and learn Thick Hide Rank 2 before continuing."
            )
        end

        return true
    end

    if questId == QUEST_SCATTER_SHOT then
        if not player:GetQuestRewardStatus(
            QUEST_HEAVY_ARMOR
        ) then
            return RejectAcceptedQuest(
                player,
                questId,
                "Complete Heavy Reinforcement first."
            )
        end

        if knownRank < 3 then
            return RejectAcceptedQuest(
                player,
                questId,
                "Use your Heavy Swashbuckler Armor Kit and learn Thick Hide Rank 3 before pursuing Scatter Shot."
            )
        end

        return true
    end

    return true
end

local function OnSwashbucklerQuestReward(
    event,
    player,
    creature,
    quest,
    opt
)
    if quest:GetId() ~= QUEST_SWASHBUCKLER_PATH then
        return
    end

    if IsBot(player) then
        return
    end

    if not IsRogue(player) then
        player:SendBroadcastMessage(
            "Only Rogues may become Swashbucklers."
        )
        return
    end

    if HasSubclass(player) then
        if IsSwashbuckler(player) then
            player:SendBroadcastMessage(
                "You are already a Swashbuckler."
            )
        else
            player:SendBroadcastMessage(
                "You already have a subclass."
            )
        end

        return
    end

    SetSwashbuckler(player)

    player:SendBroadcastMessage(
        "You have taken the Swashbuckler path."
    )
end

local function LearnThickHideRank(player, rank)
    local data = ARMOR_RANKS[rank]

    if not data then
        return false
    end

    if IsBot(player) then
        return false
    end

    if not IsRogue(player) then
        player:SendBroadcastMessage(
            "Only Rogues may use this armor kit."
        )
        return false
    end

    if not IsSwashbuckler(player) then
        player:SendBroadcastMessage(
            "Only Swashbucklers may learn Thick Hide."
        )
        return false
    end

    if player:GetLevel() < data.required_level then
        player:SendBroadcastMessage(
            "You are not yet ready to use this armor kit."
        )
        return false
    end

    if not player:GetQuestRewardStatus(data.quest) then
        player:SendBroadcastMessage(
            "You have not completed the quest that rewards this armor kit."
        )
        return false
    end

    local knownRank = GetKnownThickHideRank(player)

    if knownRank >= rank then
        player:SendBroadcastMessage(
            "You already know this rank of Thick Hide or a stronger one."
        )
        return false
    end

    if data.previous_rank > 0
        and knownRank < data.previous_rank
    then
        player:SendBroadcastMessage(
            "You must learn Thick Hide Rank " ..
            data.previous_rank ..
            " first."
        )
        return false
    end

    RemoveAllThickHideRanks(player)
    player:LearnSpell(data.spell)

    if not player:HasSpell(data.spell) then
        if knownRank > 0 then
            player:LearnSpell(ARMOR_RANKS[knownRank].spell)
        end

        player:SendBroadcastMessage(
            "The armor reinforcement failed to teach Thick Hide. The item was not consumed."
        )
        return false
    end

    player:RemoveItem(data.item, 1)

    player:SendBroadcastMessage(
        "You have learned Thick Hide Rank " .. rank .. "."
    )

    -- ITEM_EVENT_ON_USE returns false to suppress the item's normal spell.
    return false
end

local function OnLightArmorKitUse(event, player, item, target)
    return LearnThickHideRank(player, 1)
end

local function OnMediumArmorKitUse(event, player, item, target)
    return LearnThickHideRank(player, 2)
end

local function OnHeavyArmorKitUse(event, player, item, target)
    return LearnThickHideRank(player, 3)
end

local function OnScatterShotFormulaUse(
    event,
    player,
    item,
    target
)
    if IsBot(player) then
        return false
    end

    if not IsRogue(player) then
        player:SendBroadcastMessage(
            "Only Rogues may study this formula."
        )
        return false
    end

    if not IsSwashbuckler(player) then
        player:SendBroadcastMessage(
            "Only Swashbucklers may learn Scatter Shot."
        )
        return false
    end

    if player:GetLevel() < 20 then
        player:SendBroadcastMessage(
            "You must be level 20 to study this formula."
        )
        return false
    end

    if not player:GetQuestRewardStatus(
        QUEST_SCATTER_SHOT
    ) then
        player:SendBroadcastMessage(
            "You have not completed A Shot Across the Bow."
        )
        return false
    end

    if GetKnownThickHideRank(player) < 3 then
        player:SendBroadcastMessage(
            "You must learn Thick Hide Rank 3 before studying Scatter Shot."
        )
        return false
    end

    if player:HasSpell(SPELL_SCATTER_SHOT) then
        player:SendBroadcastMessage(
            "You already know Scatter Shot."
        )
        return false
    end

    player:LearnSpell(SPELL_SCATTER_SHOT)

    if not player:HasSpell(SPELL_SCATTER_SHOT) then
        player:SendBroadcastMessage(
            "The formula failed to teach Scatter Shot. The item was not consumed."
        )
        return false
    end

    player:RemoveItem(ITEM_SCATTER_SHOT_FORMULA, 1)

    player:SendBroadcastMessage(
        "You have learned Scatter Shot."
    )

    return false
end

local function GetMissingArmorRank(player)
    local knownRank = GetKnownThickHideRank(player)

    -- Return the lowest missing earned rank so a character who lost several
    -- items can rebuild the chain in the correct order.
    for rank = 1, 3 do
        local data = ARMOR_RANKS[rank]

        if player:GetQuestRewardStatus(data.quest)
            and knownRank < rank
            and not PlayerHasItem(player, data.item)
        then
            return rank
        end
    end

    return 0
end

local function ReissueArmorRank(player, rank)
    local data = ARMOR_RANKS[rank]

    if not data then
        player:SendBroadcastMessage(
            "That armor reinforcement could not be found."
        )
        return
    end

    if IsBot(player) then
        return
    end

    if not IsSwashbuckler(player) then
        player:SendBroadcastMessage(
            "Only Swashbucklers may recover these armor kits."
        )
        return
    end

    if not player:GetQuestRewardStatus(data.quest) then
        player:SendBroadcastMessage(
            "You have not earned that armor kit yet."
        )
        return
    end

    local knownRank = GetKnownThickHideRank(player)

    if knownRank >= rank then
        player:SendBroadcastMessage(
            "You already know that rank of Thick Hide or a stronger one."
        )
        return
    end

    if PlayerHasItem(player, data.item) then
        player:SendBroadcastMessage(
            "You already have that armor kit."
        )
        return
    end

    if data.previous_rank > 0
        and knownRank < data.previous_rank
    then
        player:SendBroadcastMessage(
            "Recover and learn the previous Thick Hide rank first."
        )
        return
    end

    local addedItem = player:AddItem(data.item, 1)

    if addedItem then
        player:SendBroadcastMessage(
            "The Swashbuckler Trainer replaces your lost " ..
            data.item_name ..
            "."
        )
    else
        player:SendBroadcastMessage(
            "You need more room in your bags before receiving the armor kit."
        )
    end
end

local function ShouldOfferScatterRecovery(player)
    return player:GetQuestRewardStatus(
            QUEST_SCATTER_SHOT
        )
        and GetKnownThickHideRank(player) >= 3
        and not player:HasSpell(SPELL_SCATTER_SHOT)
        and not PlayerHasItem(
            player,
            ITEM_SCATTER_SHOT_FORMULA
        )
end

local function ReissueScatterShotFormula(player)
    if IsBot(player) then
        return
    end

    if not IsSwashbuckler(player) then
        player:SendBroadcastMessage(
            "Only Swashbucklers may recover the Scatter Shot formula."
        )
        return
    end

    if not player:GetQuestRewardStatus(
        QUEST_SCATTER_SHOT
    ) then
        player:SendBroadcastMessage(
            "You have not earned the Scatter Shot formula."
        )
        return
    end

    if GetKnownThickHideRank(player) < 3 then
        player:SendBroadcastMessage(
            "Learn Thick Hide Rank 3 before recovering the Scatter Shot formula."
        )
        return
    end

    if player:HasSpell(SPELL_SCATTER_SHOT) then
        player:SendBroadcastMessage(
            "You already know Scatter Shot."
        )
        return
    end

    if PlayerHasItem(
        player,
        ITEM_SCATTER_SHOT_FORMULA
    ) then
        player:SendBroadcastMessage(
            "You already have Greenskin's Scatter Shot Formula."
        )
        return
    end

    local addedItem = player:AddItem(
        ITEM_SCATTER_SHOT_FORMULA,
        1
    )

    if addedItem then
        player:SendBroadcastMessage(
            "The Swashbuckler Trainer replaces your lost Greenskin's Scatter Shot Formula."
        )
    else
        player:SendBroadcastMessage(
            "You need more room in your bags before receiving the formula."
        )
    end
end

local function OnSwashbucklerTrainerHello(
    event,
    player,
    creature
)
    player:GossipClearMenu()

    if IsBot(player) then
        player:GossipComplete()
        return
    end

    player:GossipAddQuests(creature)

    if not IsRogue(player) then
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "The Swashbuckler path is only open to Rogues.",
            0,
            OPTION_CLOSE
        )

        player:GossipSendMenu(100, creature)
        return
    end

    if IsSwashbuckler(player) then
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "Train me as a Swashbuckler.",
            0,
            OPTION_OPEN_SWASHBUCKLER_TRAINER
        )

        local missingArmorRank = GetMissingArmorRank(player)

        if missingArmorRank > 0 then
            local data = ARMOR_RANKS[missingArmorRank]

            player:GossipMenuAddItem(
                GOSSIP_ICON_CHAT,
                data.recovery_text,
                0,
                OPTION_REISSUE_ARMOR_BASE +
                    missingArmorRank
            )
        end

        if ShouldOfferScatterRecovery(player) then
            player:GossipMenuAddItem(
                GOSSIP_ICON_CHAT,
                "I lost Greenskin's Scatter Shot Formula.",
                0,
                OPTION_REISSUE_SCATTER_SHOT
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
            "Complete The Swashbuckler Path before training as a Swashbuckler.",
            0,
            OPTION_CLOSE
        )
    end

    player:GossipSendMenu(100, creature)
end

local function OnSwashbucklerTrainerSelect(
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

    if intid == OPTION_OPEN_SWASHBUCKLER_TRAINER then
        if IsSwashbuckler(player) then
            player:SendTrainerList(creature)
        else
            player:SendBroadcastMessage(
                "You must complete The Swashbuckler Path first."
            )

            player:GossipComplete()
        end

        return
    end

    if intid > OPTION_REISSUE_ARMOR_BASE
        and intid <= OPTION_REISSUE_ARMOR_BASE + 3
    then
        ReissueArmorRank(
            player,
            intid - OPTION_REISSUE_ARMOR_BASE
        )

        player:GossipComplete()
        return
    end

    if intid == OPTION_REISSUE_SCATTER_SHOT then
        ReissueScatterShotFormula(player)
        player:GossipComplete()
        return
    end

    player:GossipComplete()
end

RegisterCreatureEvent(
    NPC_SWASHBUCKLER_TRAINER,
    CREATURE_EVENT_ON_QUEST_ACCEPT,
    OnSwashbucklerQuestAccept
)

RegisterCreatureEvent(
    NPC_SWASHBUCKLER_TRAINER,
    CREATURE_EVENT_ON_QUEST_REWARD,
    OnSwashbucklerQuestReward
)

RegisterCreatureGossipEvent(
    NPC_SWASHBUCKLER_TRAINER,
    GOSSIP_EVENT_ON_HELLO,
    OnSwashbucklerTrainerHello
)

RegisterCreatureGossipEvent(
    NPC_SWASHBUCKLER_TRAINER,
    GOSSIP_EVENT_ON_SELECT,
    OnSwashbucklerTrainerSelect
)

RegisterItemEvent(
    ITEM_LIGHT_ARMOR_KIT,
    ITEM_EVENT_ON_USE,
    OnLightArmorKitUse
)

RegisterItemEvent(
    ITEM_MEDIUM_ARMOR_KIT,
    ITEM_EVENT_ON_USE,
    OnMediumArmorKitUse
)

RegisterItemEvent(
    ITEM_HEAVY_ARMOR_KIT,
    ITEM_EVENT_ON_USE,
    OnHeavyArmorKitUse
)

RegisterItemEvent(
    ITEM_SCATTER_SHOT_FORMULA,
    ITEM_EVENT_ON_USE,
    OnScatterShotFormulaUse
)

print(
    "[Subclass] Swashbuckler unlock, progression, recovery, and learning-item script loaded."
)
