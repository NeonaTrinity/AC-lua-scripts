-- subclass_cultist.lua
-- Cultist subclass unlock + Warlock-only trainer gate
-- Three-stage Vampire Ritual quest chain
-- Lost ritual tome recovery + spell learning items

local NPC_CULTIST_TRAINER = 900103

local QUEST_CULTIST_PATH = 980104
local QUEST_VAMPIRE_RITUAL = 980105
local QUEST_BLOOD_BOND = 980106
local QUEST_CRIMSON_COVENANT = 980107
local QUEST_FAIRBANKS_BLOOD = 980108
local QUEST_STILL_NOT_RITUAL = 980109

local ITEM_CULTIST_TRIAL_SIGIL = 990115
local ITEM_VAMPIRIC_EMBRACE_TOME = 990116
local ITEM_IMPROVED_VAMPIRIC_EMBRACE_TOME = 990117
local ITEM_PERFECTED_VAMPIRIC_EMBRACE_TOME = 990118
local ITEM_LICHBORNE_TOME = 990119
local ITEM_RAISE_DEAD_TOME = 990120
local ITEM_RAISE_ALLY_TOME = 990121

local ITEM_CORPSE_DUST = 37201

local SPELL_VAMPIRIC_EMBRACE = 15286
local SPELL_IMPROVED_VAMPIRIC_EMBRACE_RANK_1 = 27839
local SPELL_IMPROVED_VAMPIRIC_EMBRACE_RANK_2 = 27840
local SPELL_LICHBORNE = 49039
local SPELL_RAISE_DEAD = 46584
local SPELL_RAISE_ALLY = 61999

local MIN_LEVEL_VAMPIRE_RITUAL = 10
local MIN_LEVEL_LICHBORNE_QUEST = 40
local MIN_LEVEL_STILL_NOT_RITUAL = 40

local CLASS_WARLOCK = 9

local SUBCLASS_NONE = 0
local SUBCLASS_CULTIST = 4

local CREATURE_EVENT_ON_QUEST_ACCEPT = 31
local CREATURE_EVENT_ON_QUEST_REWARD = 34

local GOSSIP_EVENT_ON_HELLO = 1
local GOSSIP_EVENT_ON_SELECT = 2

local ITEM_EVENT_ON_USE = 2

local GOSSIP_ICON_CHAT = 0

local OPTION_OPEN_CULTIST_TRAINER = 1
local OPTION_CLOSE = 99

local OPTION_REISSUE_VAMPIRIC_EMBRACE_TOME = 2101
local OPTION_REISSUE_IMPROVED_VAMPIRIC_EMBRACE_TOME = 2102
local OPTION_REISSUE_PERFECTED_VAMPIRIC_EMBRACE_TOME = 2103
local OPTION_REISSUE_LICHBORNE_TOME = 2104
local OPTION_REISSUE_RAISE_DEAD_TOME = 2105
local OPTION_REISSUE_RAISE_ALLY_TOME = 2106

local RITUALS = {
    [1] = {
        quest = QUEST_VAMPIRE_RITUAL,
        item = ITEM_VAMPIRIC_EMBRACE_TOME,
        spell = SPELL_VAMPIRIC_EMBRACE,
        required_spell = 0,
        reissue_option = OPTION_REISSUE_VAMPIRIC_EMBRACE_TOME,
        quest_name = "Vampire Ritual",
        spell_name = "Vampiric Embrace",
        item_name = "Tome of Vampiric Embrace",
        recovery_text = "I lost the Tome of Vampiric Embrace."
    },

    [2] = {
        quest = QUEST_BLOOD_BOND,
        item = ITEM_IMPROVED_VAMPIRIC_EMBRACE_TOME,
        spell = SPELL_IMPROVED_VAMPIRIC_EMBRACE_RANK_1,
        required_spell = SPELL_VAMPIRIC_EMBRACE,
        reissue_option = OPTION_REISSUE_IMPROVED_VAMPIRIC_EMBRACE_TOME,
        quest_name = "Vampire Ritual: Blood Bond",
        spell_name = "Improved Vampiric Embrace Rank 1",
        item_name = "Tome of Improved Vampiric Embrace",
        recovery_text = "I lost the Tome of Improved Vampiric Embrace."
    },

    [3] = {
        quest = QUEST_CRIMSON_COVENANT,
        item = ITEM_PERFECTED_VAMPIRIC_EMBRACE_TOME,
        spell = SPELL_IMPROVED_VAMPIRIC_EMBRACE_RANK_2,
        required_spell = SPELL_IMPROVED_VAMPIRIC_EMBRACE_RANK_1,
        reissue_option = OPTION_REISSUE_PERFECTED_VAMPIRIC_EMBRACE_TOME,
        quest_name = "Vampire Ritual: Crimson Covenant",
        spell_name = "Improved Vampiric Embrace Rank 2",
        item_name = "Tome of Perfected Vampiric Embrace",
        recovery_text = "I lost the Tome of Perfected Vampiric Embrace."
    }
}

local function IsBot(player)
    if player.IsBot then
        return player:IsBot()
    end

    return false
end

local function IsWarlock(player)
    return player:GetClass() == CLASS_WARLOCK
end

local function GetSubclass(player)
    local guid = player:GetGUIDLow()

    local result = CharDBQuery(
        "SELECT subclass_id FROM character_subclass WHERE guid = " ..
        guid ..
        " LIMIT 1"
    )

    if result then
        return result:GetUInt32(0)
    end

    return SUBCLASS_NONE
end

local function HasSubclass(player)
    return GetSubclass(player) ~= SUBCLASS_NONE
end

local function IsCultist(player)
    return GetSubclass(player) == SUBCLASS_CULTIST
end

local function SetCultist(player)
    local guid = player:GetGUIDLow()

    CharDBExecute(string.format(
        "REPLACE INTO character_subclass " ..
        "(guid, subclass_id, subclass_name) " ..
        "VALUES (%u, %u, 'cultist')",
        guid,
        SUBCLASS_CULTIST
    ))
end

local function PlayerHasItem(player, itemEntry)
    return player:GetItemCount(itemEntry, true) > 0
end

local function RemoveAllCopiesOfItem(player, itemId)
    local count = player:GetItemCount(itemId, true)

    if count > 0 then
        player:RemoveItem(itemId, count)
    end
end

local function GetRitualRankByQuest(questId)
    for rank, ritual in ipairs(RITUALS) do
        if ritual.quest == questId then
            return rank
        end
    end

    return 0
end

local function HasRitualSpellOrHigher(player, rank)
    if rank == 1 then
        return player:HasSpell(SPELL_VAMPIRIC_EMBRACE)
    end

    if rank == 2 then
        return player:HasSpell(
            SPELL_IMPROVED_VAMPIRIC_EMBRACE_RANK_1
        ) or player:HasSpell(
            SPELL_IMPROVED_VAMPIRIC_EMBRACE_RANK_2
        )
    end

    if rank == 3 then
        return player:HasSpell(
            SPELL_IMPROVED_VAMPIRIC_EMBRACE_RANK_2
        )
    end

    return false
end

local function HasRequiredPreviousRitualSpell(player, rank)
    if rank <= 1 then
        return true
    end

    local requiredSpell = RITUALS[rank].required_spell

    return requiredSpell == 0
        or player:HasSpell(requiredSpell)
end

local function ShouldOfferRitualTomeRecovery(player, rank)
    local ritual = RITUALS[rank]

    if not ritual then
        return false
    end

    return player:GetQuestRewardStatus(ritual.quest)
        and not HasRitualSpellOrHigher(player, rank)
        and not PlayerHasItem(player, ritual.item)
end

local function ReissueRitualTome(player, rank)
    local ritual = RITUALS[rank]

    if not ritual then
        player:SendBroadcastMessage(
            "That ritual tome could not be found."
        )
        return
    end

    if IsBot(player) then
        return
    end

    if not IsWarlock(player) or not IsCultist(player) then
        player:SendBroadcastMessage(
            "Only Cultists may recover this ritual tome."
        )
        return
    end

    if not player:GetQuestRewardStatus(ritual.quest) then
        player:SendBroadcastMessage(
            "You have not completed " ..
            ritual.quest_name ..
            "."
        )
        return
    end

    if HasRitualSpellOrHigher(player, rank) then
        player:SendBroadcastMessage(
            "You already know " ..
            ritual.spell_name ..
            " or a stronger rank."
        )
        return
    end

    if PlayerHasItem(player, ritual.item) then
        player:SendBroadcastMessage(
            "You already possess the " ..
            ritual.item_name ..
            "."
        )
        return
    end

    local addedItem = player:AddItem(ritual.item, 1)

    if addedItem then
        player:SendBroadcastMessage(
            "The Cultist Trainer restores your lost " ..
            ritual.item_name ..
            "."
        )
    else
        player:SendBroadcastMessage(
            "You need more room in your bags before receiving the tome."
        )
    end
end


local function ShouldOfferLichborneTomeRecovery(player)
    return player:GetQuestRewardStatus(QUEST_FAIRBANKS_BLOOD)
        and not player:HasSpell(SPELL_LICHBORNE)
        and not PlayerHasItem(player, ITEM_LICHBORNE_TOME)
end

local function ReissueLichborneTome(player)
    if IsBot(player) then
        return
    end

    if not IsWarlock(player) or not IsCultist(player) then
        player:SendBroadcastMessage(
            "Only Cultists may recover this forbidden tome."
        )
        return
    end

    if not player:GetQuestRewardStatus(QUEST_FAIRBANKS_BLOOD) then
        player:SendBroadcastMessage(
            "You have not completed Fairbanks' Infected Blood."
        )
        return
    end

    if player:HasSpell(SPELL_LICHBORNE) then
        player:SendBroadcastMessage(
            "You already know Lichborne."
        )
        return
    end

    if PlayerHasItem(player, ITEM_LICHBORNE_TOME) then
        player:SendBroadcastMessage(
            "You already possess the Tome of Lichborne."
        )
        return
    end

    local addedItem = player:AddItem(ITEM_LICHBORNE_TOME, 1)

    if addedItem then
        player:SendBroadcastMessage(
            "The Cultist Trainer restores your lost Tome of Lichborne."
        )
    else
        player:SendBroadcastMessage(
            "You need more room in your bags before receiving the tome."
        )
    end
end


local function ShouldOfferQuestSpellTomeRecovery(
    player,
    questId,
    spellId,
    itemId
)
    return player:GetQuestRewardStatus(questId)
        and not player:HasSpell(spellId)
        and not PlayerHasItem(player, itemId)
end

local function ReissueQuestSpellTome(
    player,
    questId,
    questName,
    spellId,
    spellName,
    itemId,
    itemName
)
    if IsBot(player) then
        return
    end

    if not IsWarlock(player) or not IsCultist(player) then
        player:SendBroadcastMessage(
            "Only Cultists may recover this forbidden tome."
        )
        return
    end

    if not player:GetQuestRewardStatus(questId) then
        player:SendBroadcastMessage(
            "You have not completed " ..
            questName ..
            "."
        )
        return
    end

    if player:HasSpell(spellId) then
        player:SendBroadcastMessage(
            "You already know " .. spellName .. "."
        )
        return
    end

    if PlayerHasItem(player, itemId) then
        player:SendBroadcastMessage(
            "You already possess the " .. itemName .. "."
        )
        return
    end

    local addedItem = player:AddItem(itemId, 1)

    if addedItem then
        player:SendBroadcastMessage(
            "The Cultist Trainer restores your lost " ..
            itemName ..
            "."
        )
    else
        player:SendBroadcastMessage(
            "You need more room in your bags before receiving the tome."
        )
    end
end

local function LearnQuestSpellTome(
    player,
    item,
    questId,
    questName,
    spellId,
    spellName,
    minLevel
)
    if IsBot(player) then
        return false
    end

    if not IsWarlock(player) then
        player:SendBroadcastMessage(
            "Only Warlocks may study this tome."
        )
        return false
    end

    if not IsCultist(player) then
        player:SendBroadcastMessage(
            "Only Cultists may study this tome."
        )
        return false
    end

    if player:GetLevel() < minLevel then
        player:SendBroadcastMessage(
            "You must be level " ..
            tostring(minLevel) ..
            " to study this tome."
        )
        return false
    end

    if not player:GetQuestRewardStatus(questId) then
        player:SendBroadcastMessage(
            "You have not completed " ..
            questName ..
            "."
        )
        return false
    end

    if player:HasSpell(spellId) then
        player:SendBroadcastMessage(
            "You already know " .. spellName .. "."
        )
        return false
    end

    player:LearnSpell(spellId)
    player:RemoveItem(item, 1)

    player:SendBroadcastMessage(
        "You have learned " .. spellName .. "."
    )

    return false
end

local function LearnRitualSpell(player, item, rank)
    local ritual = RITUALS[rank]

    if not ritual then
        return false
    end

    if IsBot(player) then
        return false
    end

    if not IsWarlock(player) then
        player:SendBroadcastMessage(
            "Only Warlocks may study this ritual."
        )
        return false
    end

    if not IsCultist(player) then
        player:SendBroadcastMessage(
            "Only Cultists may study this ritual."
        )
        return false
    end

    if player:GetLevel() < MIN_LEVEL_VAMPIRE_RITUAL then
        player:SendBroadcastMessage(
            "You must be level 10 to study this ritual."
        )
        return false
    end

    if not player:GetQuestRewardStatus(ritual.quest) then
        player:SendBroadcastMessage(
            "You have not completed " ..
            ritual.quest_name ..
            "."
        )
        return false
    end

    if HasRitualSpellOrHigher(player, rank) then
        player:SendBroadcastMessage(
            "You already know " ..
            ritual.spell_name ..
            " or a stronger rank."
        )
        return false
    end

    if not HasRequiredPreviousRitualSpell(player, rank) then
        if rank == 2 then
            player:SendBroadcastMessage(
                "You must first learn Vampiric Embrace."
            )
        elseif rank == 3 then
            player:SendBroadcastMessage(
                "You must first learn Improved Vampiric Embrace Rank 1."
            )
        else
            player:SendBroadcastMessage(
                "You have not learned the previous ritual spell."
            )
        end

        return false
    end

    player:LearnSpell(ritual.spell)
    player:RemoveItem(item, 1)

    player:SendBroadcastMessage(
        "You have learned " ..
        ritual.spell_name ..
        "."
    )

    return false
end


local function LearnLichborne(player, item)
    if IsBot(player) then
        return false
    end

    if not IsWarlock(player) then
        player:SendBroadcastMessage(
            "Only Warlocks may study this tome."
        )
        return false
    end

    if not IsCultist(player) then
        player:SendBroadcastMessage(
            "Only Cultists may study this tome."
        )
        return false
    end

    if player:GetLevel() < MIN_LEVEL_LICHBORNE_QUEST then
        player:SendBroadcastMessage(
            "You must be level 40 to study this tome."
        )
        return false
    end

    if not player:GetQuestRewardStatus(QUEST_FAIRBANKS_BLOOD) then
        player:SendBroadcastMessage(
            "You have not completed Fairbanks' Infected Blood."
        )
        return false
    end

    if player:HasSpell(SPELL_LICHBORNE) then
        player:SendBroadcastMessage(
            "You already know Lichborne."
        )
        return false
    end

    player:LearnSpell(SPELL_LICHBORNE)
    player:RemoveItem(item, 1)

    player:SendBroadcastMessage(
        "You have learned Lichborne."
    )

    return false
end

local function OnCultistQuestAccept(
    event,
    player,
    creature,
    quest
)
    local questId = quest:GetId()

    if questId == QUEST_CULTIST_PATH then
        if IsBot(player) then
            player:FailQuest(questId)

            RemoveAllCopiesOfItem(
                player,
                ITEM_CULTIST_TRIAL_SIGIL
            )

            return false
        end

        if not IsWarlock(player) then
            player:FailQuest(questId)

            RemoveAllCopiesOfItem(
                player,
                ITEM_CULTIST_TRIAL_SIGIL
            )

            player:SendBroadcastMessage(
                "Only Warlocks may walk the Cultist path."
            )

            return false
        end

        if HasSubclass(player) then
            player:FailQuest(questId)

            RemoveAllCopiesOfItem(
                player,
                ITEM_CULTIST_TRIAL_SIGIL
            )

            player:SendBroadcastMessage(
                "You already walk another subclass path."
            )

            return false
        end

        return true
    end

    local ritualRank = GetRitualRankByQuest(questId)

    if ritualRank > 0 then
        if IsBot(player) then
            player:FailQuest(questId)
            return false
        end

        if not IsWarlock(player) or not IsCultist(player) then
            player:FailQuest(questId)

            player:SendBroadcastMessage(
                "Only Cultists may perform this ritual."
            )

            return false
        end

        if not HasRequiredPreviousRitualSpell(
            player,
            ritualRank
        ) then
            player:FailQuest(questId)

            if ritualRank == 2 then
                player:SendBroadcastMessage(
                    "You must learn Vampiric Embrace " ..
                    "before beginning Blood Bond."
                )
            elseif ritualRank == 3 then
                player:SendBroadcastMessage(
                    "You must learn Improved Vampiric Embrace " ..
                    "Rank 1 before beginning the Crimson Covenant."
                )
            end

            return false
        end

        return true
    end

    if questId == QUEST_FAIRBANKS_BLOOD then
        if IsBot(player) then
            player:FailQuest(questId)
            return false
        end

        if not IsWarlock(player) or not IsCultist(player) then
            player:FailQuest(questId)

            player:SendBroadcastMessage(
                "Only Cultists may seek Fairbanks' infected blood."
            )

            return false
        end

        if player:GetLevel() < MIN_LEVEL_LICHBORNE_QUEST then
            player:FailQuest(questId)

            player:SendBroadcastMessage(
                "You must be level 40 to accept this task."
            )

            return false
        end

        return true
    end

    if questId == QUEST_STILL_NOT_RITUAL then
        if IsBot(player) then
            player:FailQuest(questId)
            return false
        end

        if not IsWarlock(player) or not IsCultist(player) then
            player:FailQuest(questId)

            player:SendBroadcastMessage(
                "Only Cultists may gather reagents for this spell."
            )

            return false
        end

        if player:GetLevel() < MIN_LEVEL_STILL_NOT_RITUAL then
            player:FailQuest(questId)

            player:SendBroadcastMessage(
                "You must be level 40 to accept this task."
            )

            return false
        end

        if not player:GetQuestRewardStatus(QUEST_FAIRBANKS_BLOOD) then
            player:FailQuest(questId)

            player:SendBroadcastMessage(
                "You must complete Fairbanks' Infected Blood first."
            )

            return false
        end

        return true
    end

    return true
end

local function OnCultistQuestReward(
    event,
    player,
    creature,
    quest,
    opt
)
    local questId = quest:GetId()

    local ritualRank = GetRitualRankByQuest(questId)

    if ritualRank > 0 then
        if IsBot(player) then
            return
        end

        if not IsWarlock(player) or not IsCultist(player) then
            player:SendBroadcastMessage(
                "Only Cultists may complete this ritual."
            )
        end

        return
    end

    if questId == QUEST_FAIRBANKS_BLOOD then
        if IsBot(player) then
            return
        end

        if not IsWarlock(player) or not IsCultist(player) then
            player:SendBroadcastMessage(
                "Only Cultists may complete this task."
            )
        end

        return
    end

    if questId == QUEST_STILL_NOT_RITUAL then
        if IsBot(player) then
            return
        end

        if not IsWarlock(player) or not IsCultist(player) then
            player:SendBroadcastMessage(
                "Only Cultists may complete this task."
            )
        end

        return
    end

    if questId ~= QUEST_CULTIST_PATH then
        return
    end

    if IsBot(player) then
        return
    end

    if not IsWarlock(player) then
        player:SendBroadcastMessage(
            "Only Warlocks may become Cultists."
        )
        return
    end

    if HasSubclass(player) then
        if IsCultist(player) then
            player:SendBroadcastMessage(
                "You are already a Cultist."
            )
        else
            player:SendBroadcastMessage(
                "You already have a subclass."
            )
        end

        return
    end

    SetCultist(player)

    player:SendBroadcastMessage(
        "You have taken the Cultist path."
    )
end

local function OnCultistTrainerHello(
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

    if not IsWarlock(player) then
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "The Cultist path is only open to Warlocks.",
            0,
            OPTION_CLOSE
        )

        player:GossipSendMenu(100, creature)
        return
    end

    if IsCultist(player) then
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "Train me as a Cultist.",
            0,
            OPTION_OPEN_CULTIST_TRAINER
        )

        -- Check every ritual independently.
        -- This restores the exact completed quest reward
        -- when its tome is missing and its spell is unknown.
        for rank, ritual in ipairs(RITUALS) do
            if ShouldOfferRitualTomeRecovery(
                player,
                rank
            ) then
                player:GossipMenuAddItem(
                    GOSSIP_ICON_CHAT,
                    ritual.recovery_text,
                    0,
                    ritual.reissue_option
                )
            end
        end

        if ShouldOfferLichborneTomeRecovery(player) then
            player:GossipMenuAddItem(
                GOSSIP_ICON_CHAT,
                "I lost the Tome of Lichborne.",
                0,
                OPTION_REISSUE_LICHBORNE_TOME
            )
        end


        if ShouldOfferQuestSpellTomeRecovery(
            player,
            QUEST_STILL_NOT_RITUAL,
            SPELL_RAISE_DEAD,
            ITEM_RAISE_DEAD_TOME
        ) then
            player:GossipMenuAddItem(
                GOSSIP_ICON_CHAT,
                "I lost the Tome of Raise Dead.",
                0,
                OPTION_REISSUE_RAISE_DEAD_TOME
            )
        end

        if ShouldOfferQuestSpellTomeRecovery(
            player,
            QUEST_STILL_NOT_RITUAL,
            SPELL_RAISE_ALLY,
            ITEM_RAISE_ALLY_TOME
        ) then
            player:GossipMenuAddItem(
                GOSSIP_ICON_CHAT,
                "I lost the Tome of Raise Ally.",
                0,
                OPTION_REISSUE_RAISE_ALLY_TOME
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
            "Complete The Cultist Path before training as a Cultist.",
            0,
            OPTION_CLOSE
        )
    end

    player:GossipSendMenu(100, creature)
end

local function OnCultistTrainerSelect(
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

    if intid == OPTION_OPEN_CULTIST_TRAINER then
        if IsWarlock(player) and IsCultist(player) then
            player:SendTrainerList(creature)
        else
            player:SendBroadcastMessage(
                "You must complete The Cultist Path first."
            )

            player:GossipComplete()
        end

        return
    end

    for rank, ritual in ipairs(RITUALS) do
        if intid == ritual.reissue_option then
            ReissueRitualTome(player, rank)

            player:GossipComplete()
            return
        end
    end

    if intid == OPTION_REISSUE_LICHBORNE_TOME then
        ReissueLichborneTome(player)

        player:GossipComplete()
        return
    end


    if intid == OPTION_REISSUE_RAISE_DEAD_TOME then
        ReissueQuestSpellTome(
            player,
            QUEST_STILL_NOT_RITUAL,
            "It's still not a ritual...",
            SPELL_RAISE_DEAD,
            "Raise Dead",
            ITEM_RAISE_DEAD_TOME,
            "Tome of Raise Dead"
        )

        player:GossipComplete()
        return
    end

    if intid == OPTION_REISSUE_RAISE_ALLY_TOME then
        ReissueQuestSpellTome(
            player,
            QUEST_STILL_NOT_RITUAL,
            "It's still not a ritual...",
            SPELL_RAISE_ALLY,
            "Raise Ally",
            ITEM_RAISE_ALLY_TOME,
            "Tome of Raise Ally"
        )

        player:GossipComplete()
        return
    end

    player:GossipComplete()
end

local function OnVampiricEmbraceTomeUse(
    event,
    player,
    item,
    target
)
    return LearnRitualSpell(player, item, 1)
end

local function OnImprovedVampiricEmbraceTomeUse(
    event,
    player,
    item,
    target
)
    return LearnRitualSpell(player, item, 2)
end

local function OnPerfectedVampiricEmbraceTomeUse(
    event,
    player,
    item,
    target
)
    return LearnRitualSpell(player, item, 3)
end


local function OnLichborneTomeUse(
    event,
    player,
    item,
    target
)
    return LearnLichborne(player, item)
end


local function OnRaiseDeadTomeUse(
    event,
    player,
    item,
    target
)
    return LearnQuestSpellTome(
        player,
        item,
        QUEST_STILL_NOT_RITUAL,
        "It's still not a ritual...",
        SPELL_RAISE_DEAD,
        "Raise Dead",
        MIN_LEVEL_STILL_NOT_RITUAL
    )
end

local function OnRaiseAllyTomeUse(
    event,
    player,
    item,
    target
)
    return LearnQuestSpellTome(
        player,
        item,
        QUEST_STILL_NOT_RITUAL,
        "It's still not a ritual...",
        SPELL_RAISE_ALLY,
        "Raise Ally",
        MIN_LEVEL_STILL_NOT_RITUAL
    )
end

RegisterCreatureEvent(
    NPC_CULTIST_TRAINER,
    CREATURE_EVENT_ON_QUEST_ACCEPT,
    OnCultistQuestAccept
)

RegisterCreatureEvent(
    NPC_CULTIST_TRAINER,
    CREATURE_EVENT_ON_QUEST_REWARD,
    OnCultistQuestReward
)

RegisterCreatureGossipEvent(
    NPC_CULTIST_TRAINER,
    GOSSIP_EVENT_ON_HELLO,
    OnCultistTrainerHello
)

RegisterCreatureGossipEvent(
    NPC_CULTIST_TRAINER,
    GOSSIP_EVENT_ON_SELECT,
    OnCultistTrainerSelect
)

RegisterItemEvent(
    ITEM_VAMPIRIC_EMBRACE_TOME,
    ITEM_EVENT_ON_USE,
    OnVampiricEmbraceTomeUse
)

RegisterItemEvent(
    ITEM_IMPROVED_VAMPIRIC_EMBRACE_TOME,
    ITEM_EVENT_ON_USE,
    OnImprovedVampiricEmbraceTomeUse
)

RegisterItemEvent(
    ITEM_PERFECTED_VAMPIRIC_EMBRACE_TOME,
    ITEM_EVENT_ON_USE,
    OnPerfectedVampiricEmbraceTomeUse
)

RegisterItemEvent(
    ITEM_LICHBORNE_TOME,
    ITEM_EVENT_ON_USE,
    OnLichborneTomeUse
)


RegisterItemEvent(
    ITEM_RAISE_DEAD_TOME,
    ITEM_EVENT_ON_USE,
    OnRaiseDeadTomeUse
)

RegisterItemEvent(
    ITEM_RAISE_ALLY_TOME,
    ITEM_EVENT_ON_USE,
    OnRaiseAllyTomeUse
)

print(
    "[Subclass] Cultist unlock + Vampire Ritual + Lichborne/Raise Dead quest script loaded."
)
