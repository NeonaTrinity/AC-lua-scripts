-- subclass_mail.lua
-- Holy Order reminder mail for subclass progression.
-- Works with Cleric / Templar subclass system.
-- Bots are ignored.

local PLAYER_EVENT_ON_LOGIN = 3
local PLAYER_EVENT_ON_LEVEL_CHANGE = 13

local CLASS_PALADIN = 2
local CLASS_PRIEST = 5

local MAIL_STATIONERY_DEFAULT = 41

local MAIL_KEY_LEVEL_10 = "holy_order_level_10_reminder"
local MAIL_KEY_LEVEL_40 = "holy_order_level_40_reminder"

local function IsBot(player)
    if player.IsBot then
        return player:IsBot()
    end

    return false
end

local function IsHolyOrderClass(player)
    local class = player:GetClass()

    return class == CLASS_PRIEST or class == CLASS_PALADIN
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

local function SendPlayerMail(player, mailKey, subject, body)
    if IsBot(player) then
        return false
    end

    if HasMailBeenSent(player, mailKey) then
        return false
    end

    local guid = player:GetGUIDLow()

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

    MarkMailSent(player, mailKey)
    return true
end

local function TrySendLevel10Mail(player)
    if IsBot(player) then
        return
    end

    if not IsHolyOrderClass(player) then
        return
    end

    if player:GetLevel() < 10 then
        return
    end

    local subject = "Back to the Roots"

    local body = [[You have grown stronger, but strength without purpose is easily wasted.

Return to where your path began. The Holy Order watches those who would serve something greater than themselves.

If you have not yet chosen your path, seek out the proper trainer and begin your service.]]

    local sent = SendPlayerMail(player, MAIL_KEY_LEVEL_10, subject, body)

    if sent then
        player:SendBroadcastMessage("New mail has arrived from the Holy Order.")
    end
end

local function TrySendLevel40Mail(player)
    if IsBot(player) then
        return
    end

    if not IsHolyOrderClass(player) then
        return
    end

    if player:GetLevel() < 40 then
        return
    end

    local subject = "The Holy Order Calls"

    local body = [[The time has come to return to the Holy Order.

Clerics and Templars are called to take up greater duties. New doctrines, sacred mounts, and deeper responsibilities await those who have proven themselves.

Return to your order trainer and continue your path.]]

    local sent = SendPlayerMail(player, MAIL_KEY_LEVEL_40, subject, body)

    if sent then
        player:SendBroadcastMessage("New mail has arrived from the Holy Order.")
    end
end

local function CheckHolyOrderMail(player)
    if IsBot(player) then
        return
    end

    TrySendLevel10Mail(player)
    TrySendLevel40Mail(player)
end

local function OnPlayerLogin(event, player)
    CheckHolyOrderMail(player)
end

local function OnPlayerLevelChange(event, player, oldLevel)
    CheckHolyOrderMail(player)
end

RegisterPlayerEvent(PLAYER_EVENT_ON_LOGIN, OnPlayerLogin)
RegisterPlayerEvent(PLAYER_EVENT_ON_LEVEL_CHANGE, OnPlayerLevelChange)

print("[Subclass] Holy Order mail script loaded.")
