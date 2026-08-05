-- subclass_cleric.lua
-- Cleric subclass unlock + trainer gate + Holy Shock/Reckoning/mount recovery + welcome mail

local NPC_CLERIC_TRAINER = 900100

local QUEST_CLERIC_PATH = 980100
local QUEST_HOLY_SHOCK = 980140
local QUEST_RECKONING_CHAPTER_1 = 980142
local QUEST_RECKONING_CHAPTER_2 = 980143
local QUEST_RECKONING_CHAPTER_3 = 980144
local QUEST_RECKONING_CHAPTER_4 = 980145
local QUEST_RECKONING_CHAPTER_5 = 980146
local QUEST_ARGENT_WARHORSE = 980151

local ITEM_CLERIC_TRIAL_SIGIL = 990100
local ITEM_DOCTRINE_HOLY_SHOCK = 990101
local SPELL_HOLY_SHOCK_RANK_1 = 20473
local SPELL_HOLYFORM = 46565

local CLERIC_SHADOW_BREAK_SPELLS = {
    -- Shadow Word: Pain
    [589] = true, [594] = true, [970] = true, [992] = true,
    [2767] = true, [10892] = true, [10893] = true, [10894] = true,
    [25367] = true, [25368] = true, [48124] = true, [48125] = true,

    -- Mind Blast
    [8092] = true, [8102] = true, [8103] = true, [8104] = true,
    [8105] = true, [8106] = true, [10945] = true, [10946] = true,
    [10947] = true, [25372] = true, [25375] = true, [48126] = true,
    [48127] = true,

    -- Mind Flay
    [15407] = true, [17311] = true, [17312] = true, [17313] = true,
    [17314] = true, [18807] = true, [25387] = true, [48155] = true,
    [48156] = true,

    -- Shadow Word: Death
    [32379] = true, [32996] = true, [48157] = true, [48158] = true,

    -- Vampiric Embrace / Vampiric Touch
    [15286] = true,
    [34914] = true, [34916] = true, [34917] = true, [48159] = true,
    [48160] = true,

    -- Devouring Plague
    [2944] = true, [19276] = true, [19277] = true, [19278] = true,
    [19279] = true, [19280] = true, [25467] = true, [48299] = true,
    [48300] = true,

    -- Mind Sear
    [48045] = true, [53023] = true,

    -- Psychic Scream
    [8122] = true, [8124] = true, [10888] = true, [10890] = true,

    -- Shadowform itself
    [15473] = true,
}

local SPELL_SEAL_OF_COMMAND = 20375
local MIN_LEVEL_HOLY_SHOCK = 40

local SPELL_DEVOTION_AURA_RANK_1 = 465
local SPELL_DEVOTION_AURA_RANK_2 = 10290
local SPELL_DEVOTION_AURA_RANK_3 = 643
local SPELL_DEVOTION_AURA_RANK_4 = 10291
local SPELL_DEVOTION_AURA_RANK_5 = 1032
local SPELL_DEVOTION_AURA_RANK_6 = 10292
local SPELL_DEVOTION_AURA_RANK_7 = 10293
local SPELL_DEVOTION_AURA_RANK_8 = 27149
local SPELL_DEVOTION_AURA_RANK_9 = 48941
local SPELL_DEVOTION_AURA_RANK_10 = 48942

local DEVOTION_AURA_RANKS = {
    SPELL_DEVOTION_AURA_RANK_1,
    SPELL_DEVOTION_AURA_RANK_2,
    SPELL_DEVOTION_AURA_RANK_3,
    SPELL_DEVOTION_AURA_RANK_4,
    SPELL_DEVOTION_AURA_RANK_5,
    SPELL_DEVOTION_AURA_RANK_6,
    SPELL_DEVOTION_AURA_RANK_7,
    SPELL_DEVOTION_AURA_RANK_8,
    SPELL_DEVOTION_AURA_RANK_9,
    SPELL_DEVOTION_AURA_RANK_10
}

local ITEM_RECKONING_CHAPTER_1 = 990104
local ITEM_RECKONING_CHAPTER_2 = 990105
local ITEM_RECKONING_CHAPTER_3 = 990106
local ITEM_RECKONING_CHAPTER_4 = 990107
local ITEM_RECKONING_CHAPTER_5 = 990108

local SPELL_RECKONING_RANK_1 = 20177
local SPELL_RECKONING_RANK_2 = 20179
local SPELL_RECKONING_RANK_3 = 20181
local SPELL_RECKONING_RANK_4 = 20180
local SPELL_RECKONING_RANK_5 = 20182

local ITEM_ARGENT_WARHORSE = 47180
local SPELL_ARGENT_WARHORSE = 67466
local SPELL_JOURNEYMAN_RIDING = 33391

local ITEM_BLESSED_WARHORSE_REINS = 990109
local ITEM_RECOVERED_ARGENT_WARHORSE = 990111
local NPC_LOST_ARGENT_WARHORSE = 900110
local HORSE_CAPTURE_RANGE = 10

local CLASS_PRIEST = 5

local SUBCLASS_NONE = 0
local SUBCLASS_CLERIC = 1

local CREATURE_EVENT_ON_QUEST_REWARD = 34
local CREATURE_EVENT_ON_QUEST_ACCEPT = 31

local GOSSIP_EVENT_ON_HELLO = 1
local GOSSIP_EVENT_ON_SELECT = 2

local ITEM_EVENT_ON_USE = 2

local GOSSIP_ICON_CHAT = 0
local GOSSIP_ICON_TRAINER = 3

local OPTION_OPEN_CLERIC_TRAINER = 1
local OPTION_CLOSE = 99
local OPTION_REISSUE_RECKONING_BASE = 2000
local OPTION_REISSUE_HOLY_SHOCK = 2101
local OPTION_REISSUE_ARGENT_WARHORSE = 2102

local MAIL_STATIONERY_DEFAULT = 41
local MAIL_KEY_WELCOME_CLERIC = "welcome_holy_order_cleric"

local RECKONING_RANKS = {
    [1] = {
        quest = QUEST_RECKONING_CHAPTER_1,
        item = ITEM_RECKONING_CHAPTER_1,
        spell = SPELL_RECKONING_RANK_1,
        required_level = 20,
        previous_spell = 0,
        chapter_name = "Chapter 1"
    },
    [2] = {
        quest = QUEST_RECKONING_CHAPTER_2,
        item = ITEM_RECKONING_CHAPTER_2,
        spell = SPELL_RECKONING_RANK_2,
        required_level = 22,
        previous_spell = SPELL_RECKONING_RANK_1,
        chapter_name = "Chapter 2"
    },
    [3] = {
        quest = QUEST_RECKONING_CHAPTER_3,
        item = ITEM_RECKONING_CHAPTER_3,
        spell = SPELL_RECKONING_RANK_3,
        required_level = 24,
        previous_spell = SPELL_RECKONING_RANK_2,
        chapter_name = "Chapter 3"
    },
    [4] = {
        quest = QUEST_RECKONING_CHAPTER_4,
        item = ITEM_RECKONING_CHAPTER_4,
        spell = SPELL_RECKONING_RANK_4,
        required_level = 26,
        previous_spell = SPELL_RECKONING_RANK_3,
        chapter_name = "Chapter 4"
    },
    [5] = {
        quest = QUEST_RECKONING_CHAPTER_5,
        item = ITEM_RECKONING_CHAPTER_5,
        spell = SPELL_RECKONING_RANK_5,
        required_level = 28,
        previous_spell = SPELL_RECKONING_RANK_4,
        chapter_name = "Chapter 5"
    }
}

local function IsBot(player)
    if player.IsBot then
        return player:IsBot()
    end

    return false
end

local function IsPriest(player)
    return player:GetClass() == CLASS_PRIEST
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

local function IsCleric(player)
    return GetSubclass(player) == SUBCLASS_CLERIC
end

local function SetCleric(player)
    local guid = player:GetGUIDLow()

    CharDBExecute(string.format(
        "REPLACE INTO character_subclass (guid, subclass_id, subclass_name) VALUES (%u, %u, 'cleric')",
        guid,
        SUBCLASS_CLERIC
    ))
end

local function HasAnyDevotionAuraRank(player)
    for _, spellId in ipairs(DEVOTION_AURA_RANKS) do
        if player:HasSpell(spellId) then
            return true
        end
    end

    return false
end

local function TeachClericStartingSkills(player)
    if IsBot(player) then
        return
    end

    if not IsPriest(player) or not IsCleric(player) then
        return
    end

    if not HasAnyDevotionAuraRank(player) then
        player:LearnSpell(SPELL_DEVOTION_AURA_RANK_1)
    end

    if not player:HasSpell(SPELL_SEAL_OF_COMMAND) then
        player:LearnSpell(SPELL_SEAL_OF_COMMAND)
    end
end

local function HasMailBeenSent(player, mailKey)
    local guid = player:GetGUIDLow()

    local result = CharDBQuery(string.format(
        "SELECT 1 FROM custom_mail_log WHERE guid = %u AND mail_key = '%s' LIMIT 1",
        guid,
        mailKey
    ))

    return result ~= nil
end

local function MarkMailSent(player, mailKey)
    local guid = player:GetGUIDLow()

    CharDBExecute(string.format(
        "INSERT IGNORE INTO custom_mail_log (guid, mail_key) VALUES (%u, '%s')",
        guid,
        mailKey
    ))
end

local function SendClericWelcomeMail(player)
    if IsBot(player) then
        return
    end

    if HasMailBeenSent(player, MAIL_KEY_WELCOME_CLERIC) then
        return
    end

    local guid = player:GetGUIDLow()

    local subject = "Welcome to the Holy Order"

    local body = [[You have taken the Cleric path.

The Holy Order welcomes you not as a servant of silence, but as a keeper of mercy, judgment, and sacred resolve.

Where others see wounds, you will see duty.
Where others fear darkness, you will carry light.

Walk with compassion.
Stand with conviction.
Let your faith become action.]]

    SendMail(
        subject,
        body,
        guid,
        0,
        MAIL_STATIONERY_DEFAULT,
        0,
        0,
        0
    )

    MarkMailSent(player, MAIL_KEY_WELCOME_CLERIC)
end

local function PlayerHasItem(player, itemEntry)
    return player:GetItemCount(itemEntry, true) > 0
end

local function ShouldOfferMissingReward(player, questId, itemEntry, spellId)
    return player:GetQuestRewardStatus(questId)
        and not player:HasSpell(spellId)
        and not PlayerHasItem(player, itemEntry)
end

local function ReissueMissingReward(player, questId, itemEntry, spellId, rewardName)
    if not IsPriest(player) or not IsCleric(player) then
        player:SendBroadcastMessage("Only Clerics may recover this Holy Order reward.")
        return
    end

    if not player:GetQuestRewardStatus(questId) then
        player:SendBroadcastMessage("You have not earned that reward yet.")
        return
    end

    if player:HasSpell(spellId) then
        player:SendBroadcastMessage("You already know that reward.")
        return
    end

    if PlayerHasItem(player, itemEntry) then
        player:SendBroadcastMessage("You already have that item.")
        return
    end

    local addedItem = player:AddItem(itemEntry, 1)

    if addedItem then
        player:SendBroadcastMessage("The Cleric Trainer replaces your lost " .. rewardName .. ".")
    else
        player:SendBroadcastMessage("You need more room in your bags before receiving that item.")
    end
end

local function RemoveAllReckoningRanks(player)
    player:RemoveSpell(SPELL_RECKONING_RANK_1)
    player:RemoveSpell(SPELL_RECKONING_RANK_2)
    player:RemoveSpell(SPELL_RECKONING_RANK_3)
    player:RemoveSpell(SPELL_RECKONING_RANK_4)
    player:RemoveSpell(SPELL_RECKONING_RANK_5)
end

local function GetKnownReckoningRank(player)
    if player:HasSpell(SPELL_RECKONING_RANK_5) then
        return 5
    end

    if player:HasSpell(SPELL_RECKONING_RANK_4) then
        return 4
    end

    if player:HasSpell(SPELL_RECKONING_RANK_3) then
        return 3
    end

    if player:HasSpell(SPELL_RECKONING_RANK_2) then
        return 2
    end

    if player:HasSpell(SPELL_RECKONING_RANK_1) then
        return 1
    end

    return 0
end

local function LearnReckoningRank(player, item, rank)
    local data = RECKONING_RANKS[rank]

    if not data then
        return false
    end

    if IsBot(player) then
        return false
    end

    if not IsPriest(player) then
        player:SendBroadcastMessage("Only Priests may study this doctrine.")
        return false
    end

    if not IsCleric(player) then
        player:SendBroadcastMessage("Only Clerics may learn Reckoning.")
        return false
    end

    if player:GetLevel() < data.required_level then
        player:SendBroadcastMessage("You are not yet ready to study this chapter.")
        return false
    end

    local knownRank = GetKnownReckoningRank(player)

    if knownRank >= rank then
        player:SendBroadcastMessage("You already know that chapter of Reckoning or a stronger one.")
        return false
    end

    if not player:GetQuestRewardStatus(data.quest) then
        player:SendBroadcastMessage("You have not completed this chapter of the Doctrine of Reckoning.")
        return false
    end

    RemoveAllReckoningRanks(player)

    player:LearnSpell(data.spell)
    player:RemoveItem(item, 1)

    player:SendBroadcastMessage("You have learned Reckoning Rank " .. rank .. ".")
    return false
end

local function GetMissingReckoningChapter(player)
    for rank = 5, 1, -1 do
        local data = RECKONING_RANKS[rank]

        if data then
            local questCompleted = player:GetQuestRewardStatus(data.quest)
            local knowsSpell = player:HasSpell(data.spell)
            local hasItem = PlayerHasItem(player, data.item)

            if questCompleted and not knowsSpell and not hasItem then
                return rank
            end
        end
    end

    return 0
end

local function ReissueReckoningChapter(player, rank)
    local data = RECKONING_RANKS[rank]

    if not data then
        player:SendBroadcastMessage("That doctrine chapter could not be found.")
        return
    end

    if IsBot(player) then
        return
    end

    if not IsPriest(player) or not IsCleric(player) then
        player:SendBroadcastMessage("Only Clerics may recover the Doctrine of Reckoning.")
        return
    end

    if not player:GetQuestRewardStatus(data.quest) then
        player:SendBroadcastMessage("You have not earned that chapter yet.")
        return
    end

    if player:HasSpell(data.spell) then
        player:SendBroadcastMessage("You already know that chapter of Reckoning.")
        return
    end

    if PlayerHasItem(player, data.item) then
        player:SendBroadcastMessage("You already have that doctrine chapter.")
        return
    end

    local addedItem = player:AddItem(data.item, 1)

    if addedItem then
        player:SendBroadcastMessage("The Cleric Trainer replaces your lost Doctrine of Reckoning: " .. data.chapter_name .. ".")
    else
        player:SendBroadcastMessage("You need more room in your bags before receiving the doctrine.")
    end
end


local function RemoveAllCopiesOfItem(player, itemId)
    local count = player:GetItemCount(itemId, true)

    if count > 0 then
        player:RemoveItem(itemId, count)
    end
end

local function CleanupClericBotQuestItems(player)
    RemoveAllCopiesOfItem(player, ITEM_CLERIC_TRIAL_SIGIL)
    RemoveAllCopiesOfItem(player, ITEM_DOCTRINE_HOLY_SHOCK)

    RemoveAllCopiesOfItem(player, ITEM_RECKONING_CHAPTER_1)
    RemoveAllCopiesOfItem(player, ITEM_RECKONING_CHAPTER_2)
    RemoveAllCopiesOfItem(player, ITEM_RECKONING_CHAPTER_3)
    RemoveAllCopiesOfItem(player, ITEM_RECKONING_CHAPTER_4)
    RemoveAllCopiesOfItem(player, ITEM_RECKONING_CHAPTER_5)

    RemoveAllCopiesOfItem(player, ITEM_BLESSED_WARHORSE_REINS)
    RemoveAllCopiesOfItem(player, ITEM_RECOVERED_ARGENT_WARHORSE)
end

local function IsClericSubclassQuest(questId)
    return questId == QUEST_CLERIC_PATH
        or questId == QUEST_HOLY_SHOCK
        or questId == QUEST_RECKONING_CHAPTER_1
        or questId == QUEST_RECKONING_CHAPTER_2
        or questId == QUEST_RECKONING_CHAPTER_3
        or questId == QUEST_RECKONING_CHAPTER_4
        or questId == QUEST_RECKONING_CHAPTER_5
        or questId == QUEST_ARGENT_WARHORSE
end

local function OnClericQuestAccept(event, player, creature, quest)
    local questId = quest:GetId()

    if IsBot(player) and IsClericSubclassQuest(questId) then
        player:FailQuest(questId)
        CleanupClericBotQuestItems(player)
        return false
    end

    return true
end

local function OnClericQuestReward(event, player, creature, quest, opt)
    local questId = quest:GetId()

    if questId == QUEST_ARGENT_WARHORSE then
        if IsBot(player) then
            return
        end

        if IsPriest(player) and IsCleric(player) then
            if not player:HasSpell(SPELL_JOURNEYMAN_RIDING) then
                player:LearnSpell(SPELL_JOURNEYMAN_RIDING)
                player:SendBroadcastMessage("You have learned Journeyman Riding.")
            end

            player:RemoveItem(ITEM_BLESSED_WARHORSE_REINS, 1)
        end

        return
    end

    if questId ~= QUEST_CLERIC_PATH then
        return
    end

    if IsBot(player) then
        return
    end

    if not IsPriest(player) then
        player:SendBroadcastMessage("Only Priests may become Clerics.")
        return
    end

    if HasSubclass(player) then
        if IsCleric(player) then
            player:SendBroadcastMessage("You are already a Cleric.")
        else
            player:SendBroadcastMessage("You already have a subclass.")
        end

        return
    end

    SetCleric(player)
    TeachClericStartingSkills(player)
    SendClericWelcomeMail(player)
    player:SendBroadcastMessage("You have taken the Cleric path.")
end

local function OnClericTrainerHello(event, player, creature)
    player:GossipClearMenu()

    if IsBot(player) then
        player:GossipComplete()
        return
    end

    player:GossipAddQuests(creature)

    if not IsPriest(player) then
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "The Cleric path is only open to Priests.",
            0,
            OPTION_CLOSE
        )

        player:GossipSendMenu(100, creature)
        return
    end

    if IsCleric(player) then
        TeachClericStartingSkills(player)

        player:GossipMenuAddItem(
            GOSSIP_ICON_TRAINER,
            "Train me as a Cleric.",
            0,
            OPTION_OPEN_CLERIC_TRAINER
        )

        if ShouldOfferMissingReward(player, QUEST_HOLY_SHOCK, ITEM_DOCTRINE_HOLY_SHOCK, SPELL_HOLY_SHOCK_RANK_1) then
            player:GossipMenuAddItem(
                GOSSIP_ICON_CHAT,
                "I lost the Doctrine of Holy Shock.",
                0,
                OPTION_REISSUE_HOLY_SHOCK
            )
        end

        local missingReckoningRank = GetMissingReckoningChapter(player)

        if missingReckoningRank > 0 then
            player:GossipMenuAddItem(
                GOSSIP_ICON_CHAT,
                "I lost part of the Doctrine of Reckoning.",
                0,
                OPTION_REISSUE_RECKONING_BASE + missingReckoningRank
            )
        end

        if ShouldOfferMissingReward(player, QUEST_ARGENT_WARHORSE, ITEM_ARGENT_WARHORSE, SPELL_ARGENT_WARHORSE) then
            player:GossipMenuAddItem(
                GOSSIP_ICON_CHAT,
                "I lost my Argent Warhorse item.",
                0,
                OPTION_REISSUE_ARGENT_WARHORSE
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
            "Complete The Cleric Path before training as a Cleric.",
            0,
            OPTION_CLOSE
        )
    end

    player:GossipSendMenu(100, creature)
end

local function OnClericTrainerSelect(event, player, creature, sender, intid, code, menu_id)
    if IsBot(player) then
        player:GossipComplete()
        return
    end

    if intid == OPTION_OPEN_CLERIC_TRAINER then
        if IsPriest(player) and IsCleric(player) then
            player:SendTrainerList(creature)
        else
            player:SendBroadcastMessage("You must complete The Cleric Path first.")
            player:GossipComplete()
        end

        return
    end

    if intid == OPTION_REISSUE_HOLY_SHOCK then
        ReissueMissingReward(player, QUEST_HOLY_SHOCK, ITEM_DOCTRINE_HOLY_SHOCK, SPELL_HOLY_SHOCK_RANK_1, "Doctrine of Holy Shock")
        player:GossipComplete()
        return
    end

    if intid == OPTION_REISSUE_ARGENT_WARHORSE then
        ReissueMissingReward(player, QUEST_ARGENT_WARHORSE, ITEM_ARGENT_WARHORSE, SPELL_ARGENT_WARHORSE, "Argent Warhorse item")
        player:GossipComplete()
        return
    end

    if intid > OPTION_REISSUE_RECKONING_BASE and intid <= OPTION_REISSUE_RECKONING_BASE + 5 then
        local rank = intid - OPTION_REISSUE_RECKONING_BASE
        ReissueReckoningChapter(player, rank)
        player:GossipComplete()
        return
    end

    player:GossipComplete()
end

local function OnHolyShockDoctrineUse(event, player, item, target)
    if IsBot(player) then
        return false
    end

    if not IsPriest(player) then
        player:SendBroadcastMessage("Only Priests may study this doctrine.")
        return false
    end

    if not IsCleric(player) then
        player:SendBroadcastMessage("Only Clerics may learn Holy Shock.")
        return false
    end

    if player:GetLevel() < MIN_LEVEL_HOLY_SHOCK then
        player:SendBroadcastMessage("You must be level 40 to learn Holy Shock.")
        return false
    end

    if player:HasSpell(SPELL_HOLY_SHOCK_RANK_1) then
        player:SendBroadcastMessage("You already know Holy Shock.")
        return false
    end

    if not player:GetQuestRewardStatus(QUEST_HOLY_SHOCK) then
        player:SendBroadcastMessage("You have not completed the Doctrine of Holy Shock quest.")
        return false
    end

    player:LearnSpell(SPELL_HOLY_SHOCK_RANK_1)
    player:RemoveItem(item, 1)

    player:SendBroadcastMessage("You have learned Holy Shock.")
    return false
end

local function OnBlessedWarhorseReinsUse(event, player, item, target)
    if IsBot(player) then
        return false
    end

    if not IsPriest(player) then
        player:SendBroadcastMessage("Only Priests may use these reins.")
        return false
    end

    if not IsCleric(player) then
        player:SendBroadcastMessage("Only Clerics may recover this warhorse.")
        return false
    end

    if not player:HasQuest(QUEST_ARGENT_WARHORSE) then
        player:SendBroadcastMessage("You do not need to recover an Argent Warhorse right now.")
        return false
    end

    if player:GetItemCount(ITEM_RECOVERED_ARGENT_WARHORSE, true) > 0 then
        player:SendBroadcastMessage("You have already recovered the Argent Warhorse.")
        return false
    end

    local horse = player:GetNearestCreature(HORSE_CAPTURE_RANGE, NPC_LOST_ARGENT_WARHORSE)

    if not horse then
        player:SendBroadcastMessage("You need to be closer to a Lost Argent Warhorse.")
        return false
    end

    local addedItem = player:AddItem(ITEM_RECOVERED_ARGENT_WARHORSE, 1)

    if addedItem then
        player:SendBroadcastMessage("You calm the Lost Argent Warhorse and prepare it for the journey home.")
    else
        player:SendBroadcastMessage("You need more room in your bags before recovering the warhorse.")
    end

    return false
end



local function OnReckoningChapter1Use(event, player, item, target)
    return LearnReckoningRank(player, item, 1)
end

local function OnReckoningChapter2Use(event, player, item, target)
    return LearnReckoningRank(player, item, 2)
end

local function OnReckoningChapter3Use(event, player, item, target)
    return LearnReckoningRank(player, item, 3)
end

local function OnReckoningChapter4Use(event, player, item, target)
    return LearnReckoningRank(player, item, 4)
end

local function OnReckoningChapter5Use(event, player, item, target)
    return LearnReckoningRank(player, item, 5)
end

local recoveredWarhorseMountedByGuid = {}
local recoveredWarhorseCooldownByGuid = {}

local function OnRecoveredWarhorseUse(event, player, item, target)
    if IsBot(player) then
        return false
    end

    if not IsPriest(player) then
        player:SendBroadcastMessage("Only Priests may ride this recovered Argent Warhorse.")
        return false
    end

    if not IsCleric(player) then
        player:SendBroadcastMessage("Only Clerics may ride this recovered Argent Warhorse.")
        return false
    end

    if not player:HasQuest(QUEST_ARGENT_WARHORSE) then
        player:SendBroadcastMessage("You do not need to ride this Argent Warhorse right now.")
        return false
    end

    if player:GetItemCount(ITEM_RECOVERED_ARGENT_WARHORSE, true) <= 0 then
        player:SendBroadcastMessage("You do not have a recovered Argent Warhorse.")
        return false
    end

    local guid = player:GetGUIDLow()

    if recoveredWarhorseMountedByGuid[guid] or player:IsMounted() or player:HasAura(SPELL_ARGENT_WARHORSE) then
        recoveredWarhorseMountedByGuid[guid] = nil

        if player:IsMounted() then
            player:Dismount()
        end

        if player:HasAura(SPELL_ARGENT_WARHORSE) then
            player:RemoveAura(SPELL_ARGENT_WARHORSE)
        end

        CreateLuaEvent(function()
            if player:IsMounted() then
                player:Dismount()
            end

            if player:HasAura(SPELL_ARGENT_WARHORSE) then
                player:RemoveAura(SPELL_ARGENT_WARHORSE)
            end
        end, 250, 1)

        CreateLuaEvent(function()
            if player:IsMounted() then
                player:Dismount()
            end

            if player:HasAura(SPELL_ARGENT_WARHORSE) then
                player:RemoveAura(SPELL_ARGENT_WARHORSE)
            end
        end, 750, 1)

        player:SendBroadcastMessage("You dismount the recovered Argent Warhorse.")
        return false
    end

    if recoveredWarhorseCooldownByGuid[guid] then
        player:SendBroadcastMessage("The recovered Argent Warhorse needs a moment before it can be ridden again.")
        return false
    end

    recoveredWarhorseCooldownByGuid[guid] = true

    CreateLuaEvent(function()
        recoveredWarhorseCooldownByGuid[guid] = nil
    end, 5000, 1)

    recoveredWarhorseMountedByGuid[guid] = true
    player:CastSpell(player, SPELL_ARGENT_WARHORSE, true)
    player:SendBroadcastMessage("You mount the recovered Argent Warhorse and ride for the Holy Order.")

    return false
end


local function GetCastSpellId(spell)
    if not spell then
        return 0
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

local function OnClericShadowSpellCast(event, player, spell, skipCheck)
    if IsBot(player) then
        return
    end

    if not IsCleric(player) then
        return
    end

    if not player:HasAura(SPELL_HOLYFORM) then
        return
    end

    local spellId = GetCastSpellId(spell)

    if CLERIC_SHADOW_BREAK_SPELLS[spellId] then
        player:RemoveAura(SPELL_HOLYFORM)
        player:SendBroadcastMessage("Your Holyform fades as you call upon Shadow.")
    end
end

RegisterCreatureEvent(NPC_CLERIC_TRAINER, CREATURE_EVENT_ON_QUEST_ACCEPT, OnClericQuestAccept)
RegisterCreatureEvent(NPC_CLERIC_TRAINER, CREATURE_EVENT_ON_QUEST_REWARD, OnClericQuestReward)

RegisterCreatureGossipEvent(NPC_CLERIC_TRAINER, GOSSIP_EVENT_ON_HELLO, OnClericTrainerHello)
RegisterCreatureGossipEvent(NPC_CLERIC_TRAINER, GOSSIP_EVENT_ON_SELECT, OnClericTrainerSelect)

RegisterItemEvent(ITEM_DOCTRINE_HOLY_SHOCK, ITEM_EVENT_ON_USE, OnHolyShockDoctrineUse)
RegisterItemEvent(ITEM_BLESSED_WARHORSE_REINS, ITEM_EVENT_ON_USE, OnBlessedWarhorseReinsUse)
RegisterItemEvent(ITEM_RECOVERED_ARGENT_WARHORSE, ITEM_EVENT_ON_USE, OnRecoveredWarhorseUse)

RegisterItemEvent(ITEM_RECKONING_CHAPTER_1, ITEM_EVENT_ON_USE, OnReckoningChapter1Use)
RegisterItemEvent(ITEM_RECKONING_CHAPTER_2, ITEM_EVENT_ON_USE, OnReckoningChapter2Use)
RegisterItemEvent(ITEM_RECKONING_CHAPTER_3, ITEM_EVENT_ON_USE, OnReckoningChapter3Use)
RegisterItemEvent(ITEM_RECKONING_CHAPTER_4, ITEM_EVENT_ON_USE, OnReckoningChapter4Use)
RegisterItemEvent(ITEM_RECKONING_CHAPTER_5, ITEM_EVENT_ON_USE, OnReckoningChapter5Use)

RegisterPlayerEvent(5, OnClericShadowSpellCast)

print("[Subclass] Cleric unlock script loaded.")
