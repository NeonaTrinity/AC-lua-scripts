-- subclass_templar.lua
-- Templar subclass unlock + trainer gate + Holy Specialization/mount recovery + welcome mail

local NPC_TEMPLAR_TRAINER = 900101

local QUEST_TEMPLAR_PATH = 980101
local QUEST_HOLY_SPECIALIZATION = 980141
local QUEST_ARGENT_CHARGER = 980150

local CLASS_PALADIN = 2

local SUBCLASS_NONE = 0
local SUBCLASS_TEMPLAR = 2

local CREATURE_EVENT_ON_QUEST_REWARD = 34
local CREATURE_EVENT_ON_QUEST_ACCEPT = 31

local GOSSIP_EVENT_ON_HELLO = 1
local GOSSIP_EVENT_ON_SELECT = 2

local GOSSIP_ICON_CHAT = 0
local GOSSIP_ICON_TRAINER = 3

local OPTION_OPEN_TEMPLAR_TRAINER = 1
local OPTION_CLOSE = 99
local OPTION_REISSUE_HOLY_SPECIALIZATION = 2101
local OPTION_REISSUE_ARGENT_CHARGER = 2102

local ITEM_TEMPLAR_TRIAL_SIGIL = 990102
local ITEM_HOLY_SPECIALIZATION_MANUSCRIPT = 990103
local SPELL_HOLY_SPECIALIZATION = 14889 -- Holy Specialization
local MIN_LEVEL_HOLY_SPECIALIZATION = 30
local ITEM_EVENT_ON_USE = 2

local ITEM_ARGENT_CHARGER = 47179
local SPELL_ARGENT_CHARGER = 66906
local SPELL_JOURNEYMAN_RIDING = 33391

local ITEM_BLESSED_CHARGER_REINS = 990110
local ITEM_RECOVERED_ARGENT_CHARGER = 990112
local NPC_LOST_ARGENT_CHARGER = 900111
local HORSE_CAPTURE_RANGE = 10

local MAIL_STATIONERY_DEFAULT = 41
local MAIL_KEY_WELCOME_TEMPLAR = "welcome_holy_order_templar"

local function IsBot(player)
    if player.IsBot then
        return player:IsBot()
    end

    return false
end

local function IsPaladin(player)
    return player:GetClass() == CLASS_PALADIN
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

local function IsTemplar(player)
    return GetSubclass(player) == SUBCLASS_TEMPLAR
end

local function SetTemplar(player)
    local guid = player:GetGUIDLow()

    CharDBExecute(string.format(
        "REPLACE INTO character_subclass (guid, subclass_id, subclass_name) VALUES (%u, %u, 'templar')",
        guid,
        SUBCLASS_TEMPLAR
    ))
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

local function SendTemplarWelcomeMail(player)
    if IsBot(player) then
        return
    end

    if HasMailBeenSent(player, MAIL_KEY_WELCOME_TEMPLAR) then
        return
    end

    local guid = player:GetGUIDLow()

    local subject = "Welcome to the Holy Order"

    local body = [[You have taken the Templar path.

The Holy Order welcomes you as shield, oathkeeper, and sacred blade.

Your strength is no longer yours alone.
It belongs to those who cannot stand.
It belongs to the light you have sworn to defend.

Hold the line.
Keep the oath.
Let your discipline become justice.]]

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

    MarkMailSent(player, MAIL_KEY_WELCOME_TEMPLAR)
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
    if not IsPaladin(player) or not IsTemplar(player) then
        player:SendBroadcastMessage("Only Templars may recover this Holy Order reward.")
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
        player:SendBroadcastMessage("The Templar Trainer replaces your lost " .. rewardName .. ".")
    else
        player:SendBroadcastMessage("You need more room in your bags before receiving that item.")
    end
end


local function RemoveAllCopiesOfItem(player, itemId)
    local count = player:GetItemCount(itemId, true)

    if count > 0 then
        player:RemoveItem(itemId, count)
    end
end

local function CleanupTemplarBotQuestItems(player)
    RemoveAllCopiesOfItem(player, ITEM_TEMPLAR_TRIAL_SIGIL)
    RemoveAllCopiesOfItem(player, ITEM_HOLY_SPECIALIZATION_MANUSCRIPT)

    RemoveAllCopiesOfItem(player, ITEM_BLESSED_CHARGER_REINS)
    RemoveAllCopiesOfItem(player, ITEM_RECOVERED_ARGENT_CHARGER)
end

local function IsTemplarSubclassQuest(questId)
    return questId == QUEST_TEMPLAR_PATH
        or questId == QUEST_HOLY_SPECIALIZATION
        or questId == QUEST_ARGENT_CHARGER
end

local function OnTemplarQuestAccept(event, player, creature, quest)
    local questId = quest:GetId()

    if IsBot(player) and IsTemplarSubclassQuest(questId) then
        player:FailQuest(questId)
        CleanupTemplarBotQuestItems(player)
        return false
    end

    return true
end

local function OnTemplarQuestReward(event, player, creature, quest, opt)
    local questId = quest:GetId()

    if questId == QUEST_ARGENT_CHARGER then
        if IsBot(player) then
            return
        end

        if IsPaladin(player) and IsTemplar(player) then
            if not player:HasSpell(SPELL_JOURNEYMAN_RIDING) then
                player:LearnSpell(SPELL_JOURNEYMAN_RIDING)
                player:SendBroadcastMessage("You have learned Journeyman Riding.")
            end

            player:RemoveItem(ITEM_BLESSED_CHARGER_REINS, 1)
        end

        return
    end

    if questId ~= QUEST_TEMPLAR_PATH then
        return
    end

    if IsBot(player) then
        return
    end

    if not IsPaladin(player) then
        player:SendBroadcastMessage("Only Paladins may become Templars.")
        return
    end

    if HasSubclass(player) then
        if IsTemplar(player) then
            player:SendBroadcastMessage("You are already a Templar.")
        else
            player:SendBroadcastMessage("You already have a subclass.")
        end

        return
    end

    SetTemplar(player)
    SendTemplarWelcomeMail(player)
    player:SendBroadcastMessage("You have taken the Templar path.")
end

local function OnTemplarTrainerHello(event, player, creature)
    player:GossipClearMenu()

    if IsBot(player) then
        player:GossipComplete()
        return
    end

    player:GossipAddQuests(creature)

    if not IsPaladin(player) then
        player:GossipMenuAddItem(
            GOSSIP_ICON_CHAT,
            "The Templar path is only open to Paladins.",
            0,
            OPTION_CLOSE
        )

        player:GossipSendMenu(100, creature)
        return
    end

    if IsTemplar(player) then
        player:GossipMenuAddItem(
            GOSSIP_ICON_TRAINER,
            "Train me as a Templar.",
            0,
            OPTION_OPEN_TEMPLAR_TRAINER
        )

        if ShouldOfferMissingReward(player, QUEST_HOLY_SPECIALIZATION, ITEM_HOLY_SPECIALIZATION_MANUSCRIPT, SPELL_HOLY_SPECIALIZATION) then
            player:GossipMenuAddItem(
                GOSSIP_ICON_CHAT,
                "I lost the Holy Specialization Manuscript.",
                0,
                OPTION_REISSUE_HOLY_SPECIALIZATION
            )
        end

        if ShouldOfferMissingReward(player, QUEST_ARGENT_CHARGER, ITEM_ARGENT_CHARGER, SPELL_ARGENT_CHARGER) then
            player:GossipMenuAddItem(
                GOSSIP_ICON_CHAT,
                "I lost my Argent Charger item.",
                0,
                OPTION_REISSUE_ARGENT_CHARGER
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
            "Complete The Templar Path before training as a Templar.",
            0,
            OPTION_CLOSE
        )
    end

    player:GossipSendMenu(100, creature)
end

local function OnTemplarTrainerSelect(event, player, creature, sender, intid, code, menu_id)
    if IsBot(player) then
        player:GossipComplete()
        return
    end

    if intid == OPTION_OPEN_TEMPLAR_TRAINER then
        if IsPaladin(player) and IsTemplar(player) then
            player:SendTrainerList(creature)
        else
            player:SendBroadcastMessage("You must complete The Templar Path first.")
            player:GossipComplete()
        end

        return
    end

    if intid == OPTION_REISSUE_HOLY_SPECIALIZATION then
        ReissueMissingReward(player, QUEST_HOLY_SPECIALIZATION, ITEM_HOLY_SPECIALIZATION_MANUSCRIPT, SPELL_HOLY_SPECIALIZATION, "Holy Specialization Manuscript")
        player:GossipComplete()
        return
    end

    if intid == OPTION_REISSUE_ARGENT_CHARGER then
        ReissueMissingReward(player, QUEST_ARGENT_CHARGER, ITEM_ARGENT_CHARGER, SPELL_ARGENT_CHARGER, "Argent Charger item")
        player:GossipComplete()
        return
    end

    player:GossipComplete()
end

local function OnBlessedChargerReinsUse(event, player, item, target)
    if IsBot(player) then
        return false
    end

    if not IsPaladin(player) then
        player:SendBroadcastMessage("Only Paladins may use these reins.")
        return false
    end

    if not IsTemplar(player) then
        player:SendBroadcastMessage("Only Templars may recover this charger.")
        return false
    end

    if not player:HasQuest(QUEST_ARGENT_CHARGER) then
        player:SendBroadcastMessage("You do not need to recover an Argent Charger right now.")
        return false
    end

    if player:GetItemCount(ITEM_RECOVERED_ARGENT_CHARGER, true) > 0 then
        player:SendBroadcastMessage("You have already recovered the Argent Charger.")
        return false
    end

    local horse = player:GetNearestCreature(HORSE_CAPTURE_RANGE, NPC_LOST_ARGENT_CHARGER)

    if not horse then
        player:SendBroadcastMessage("You need to be closer to a Lost Argent Charger.")
        return false
    end

    local addedItem = player:AddItem(ITEM_RECOVERED_ARGENT_CHARGER, 1)

    if addedItem then
        player:SendBroadcastMessage("You calm the Lost Argent Charger and prepare it for the journey home.")
    else
        player:SendBroadcastMessage("You need more room in your bags before recovering the charger.")
    end

    return false
end

local function OnHolySpecializationManuscriptUse(event, player, item, target)
    if IsBot(player) then
        return false
    end

    if not IsPaladin(player) then
        player:SendBroadcastMessage("Only Paladins may study this doctrine.")
        return false
    end

    if not IsTemplar(player) then
        player:SendBroadcastMessage("Only Templars may learn Holy Specialization.")
        return false
    end

    if player:GetLevel() < MIN_LEVEL_HOLY_SPECIALIZATION then
        player:SendBroadcastMessage("You must be level 30 to learn Holy Specialization.")
        return false
    end

    if player:HasSpell(SPELL_HOLY_SPECIALIZATION) then
        player:SendBroadcastMessage("You already know Holy Specialization.")
        return false
    end

    if not player:GetQuestRewardStatus(QUEST_HOLY_SPECIALIZATION) then
        player:SendBroadcastMessage("You have not completed the Holy Specialization Manuscript quest.")
        return false
    end

    player:LearnSpell(SPELL_HOLY_SPECIALIZATION)
    player:RemoveItem(item, 1)

    player:SendBroadcastMessage("You have learned Holy Specialization.")
    return false
end



local recoveredChargerMountedByGuid = {}
local recoveredChargerCooldownByGuid = {}

local function OnRecoveredChargerUse(event, player, item, target)
    if IsBot(player) then
        return false
    end

    if not IsPaladin(player) then
        player:SendBroadcastMessage("Only Paladins may ride this recovered Argent Charger.")
        return false
    end

    if not IsTemplar(player) then
        player:SendBroadcastMessage("Only Templars may ride this recovered Argent Charger.")
        return false
    end

    if not player:HasQuest(QUEST_ARGENT_CHARGER) then
        player:SendBroadcastMessage("You do not need to ride this Argent Charger right now.")
        return false
    end

    if player:GetItemCount(ITEM_RECOVERED_ARGENT_CHARGER, true) <= 0 then
        player:SendBroadcastMessage("You do not have a recovered Argent Charger.")
        return false
    end

    local guid = player:GetGUIDLow()

    if recoveredChargerMountedByGuid[guid] or player:IsMounted() or player:HasAura(SPELL_ARGENT_CHARGER) then
        recoveredChargerMountedByGuid[guid] = nil

        if player:IsMounted() then
            player:Dismount()
        end

        if player:HasAura(SPELL_ARGENT_CHARGER) then
            player:RemoveAura(SPELL_ARGENT_CHARGER)
        end

        CreateLuaEvent(function()
            if player:IsMounted() then
                player:Dismount()
            end

            if player:HasAura(SPELL_ARGENT_CHARGER) then
                player:RemoveAura(SPELL_ARGENT_CHARGER)
            end
        end, 250, 1)

        CreateLuaEvent(function()
            if player:IsMounted() then
                player:Dismount()
            end

            if player:HasAura(SPELL_ARGENT_CHARGER) then
                player:RemoveAura(SPELL_ARGENT_CHARGER)
            end
        end, 750, 1)

        player:SendBroadcastMessage("You dismount the recovered Argent Charger.")
        return false
    end

    if recoveredChargerCooldownByGuid[guid] then
        player:SendBroadcastMessage("The recovered Argent Charger needs a moment before it can be ridden again.")
        return false
    end

    recoveredChargerCooldownByGuid[guid] = true

    CreateLuaEvent(function()
        recoveredChargerCooldownByGuid[guid] = nil
    end, 5000, 1)

    recoveredChargerMountedByGuid[guid] = true
    player:CastSpell(player, SPELL_ARGENT_CHARGER, true)
    player:SendBroadcastMessage("You mount the recovered Argent Charger and ride for the Holy Order.")

    return false
end

RegisterCreatureEvent(NPC_TEMPLAR_TRAINER, CREATURE_EVENT_ON_QUEST_ACCEPT, OnTemplarQuestAccept)


RegisterCreatureEvent(NPC_TEMPLAR_TRAINER, CREATURE_EVENT_ON_QUEST_REWARD, OnTemplarQuestReward)

RegisterCreatureGossipEvent(NPC_TEMPLAR_TRAINER, GOSSIP_EVENT_ON_HELLO, OnTemplarTrainerHello)
RegisterCreatureGossipEvent(NPC_TEMPLAR_TRAINER, GOSSIP_EVENT_ON_SELECT, OnTemplarTrainerSelect)

RegisterItemEvent(ITEM_HOLY_SPECIALIZATION_MANUSCRIPT, ITEM_EVENT_ON_USE, OnHolySpecializationManuscriptUse)
RegisterItemEvent(ITEM_BLESSED_CHARGER_REINS, ITEM_EVENT_ON_USE, OnBlessedChargerReinsUse)
RegisterItemEvent(ITEM_RECOVERED_ARGENT_CHARGER, ITEM_EVENT_ON_USE, OnRecoveredChargerUse)

print("[Subclass] Templar unlock script loaded.")
