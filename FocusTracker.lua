local ADDON, ns = ...

-- Tracks which EditBox has keyboard focus using two layers

local hooked = setmetatable({}, { __mode = "k" })
local current = nil
local POLL = 0.1
local LOSS_GRACE = 0.2

local function IsUsable(box)
    if not box or box:IsForbidden() then return false end
    if box:GetObjectType() ~= "EditBox" then return false end
    if box.ebgIgnore then return false end
    return true
end

-- Target description -----------------------------------------------------------

local CONTEXTS = {
    AuctionHouseFrame = "Auction House",
    MailFrame = "Mail",
    SendMailFrame = "Mail",
    ProfessionsFrame = "Professions",
    TradeSkillFrame = "Professions",
    CollectionsJournal = "Collections",
    WardrobeFrame = "Transmog",
    WardrobeCollectionFrame = "Transmog",
    TransmogrifyFrame = "Transmog",
    ContainerFrameCombinedBags = "Bags",
    BagItemSearchBox = "Bags",
    BankFrame = "Bank",
    GuildBankFrame = "Guild Bank",
    MacroFrame = "Macros",
    FriendsFrame = "Friends",
    CommunitiesFrame = "Communities",
    EncounterJournal = "Adventure Guide",
    SettingsPanel = "Settings",
    LFGListFrame = "Group Finder",
    PVEFrame = "Group Finder",
    TalentFrame = "Talents",
    PlayerSpellsFrame = "Talents",
    QuestMapFrame = "Map",
    WorldMapFrame = "Map",
    GossipFrame = "Dialog",
    StaticPopup1 = "Dialog",
    StaticPopup2 = "Dialog",
    StaticPopup3 = "Dialog",
    StaticPopup4 = "Dialog",
    TradeFrame = "Trade",
    MerchantFrame = "Vendor",
    ItemTextFrame = "Book",
    CharacterFrame = "Character",
}

local function ChatDescription(box)
    local chatType = box:GetAttribute("chatType") or "SAY"
    if chatType == "WHISPER" or chatType == "BN_WHISPER" then
        local target = box:GetAttribute("tellTarget") or ""
        return "Whisper: " .. target
    elseif chatType == "CHANNEL" then
        local id = box:GetAttribute("channelTarget")
        local name = id and select(2, GetChannelName(id))
        return "Channel: " .. (name or tostring(id or "?"))
    end
    local label = _G["CHAT_MSG_" .. chatType] or chatType
    return "Chat: " .. label:gsub("^%l", string.upper)
end

function ns.IsChatBox(box)
    if box.isEBGInput then return false end
    if box.isComposer then return true end
    if ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow() == box then return true end
    local name = box:GetName()
    return name and name:match("^ChatFrame%d+EditBox$") ~= nil
end

function ns.DescribeTarget(box)
    if box and box.isEBGInput then return box.title end
    if not IsUsable(box) then return "Text field" end
    if ns.IsChatBox(box) then return ChatDescription(box) end
    local f = box
    for _ = 1, 12 do
        if not f or f:IsForbidden() then break end
        local name = f:GetName()
        if name and CONTEXTS[name] then return CONTEXTS[name] end
        f = f:GetParent()
    end
    local name = box:GetName()
    if name then
        name = name:gsub("EditBox$", ""):gsub("SearchBox$", " Search"):gsub("(%l)(%u)", "%1 %2")
        return name
    end
    return "Text field"
end

-- Focus events --

local lossTimer

local function SetCurrent(box)
    if box == current then return end
    current = box
    if box then
        if ns.OnTargetFocused then ns.OnTargetFocused(box) end
    else
        if ns.OnTargetLost then ns.OnTargetLost() end
    end
end

local function OnGained(box)
    if lossTimer then lossTimer:Cancel(); lossTimer = nil end
    if IsUsable(box) then SetCurrent(box) end
end

local function OnLost(box)
    if box ~= current then return end

    if lossTimer then lossTimer:Cancel() end
    lossTimer = C_Timer.NewTimer(LOSS_GRACE, function()
        lossTimer = nil
        local live = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if IsUsable(live) then SetCurrent(live) else SetCurrent(nil) end
    end)
end

local function Hook(box)
    if hooked[box] then return end
    hooked[box] = true
    box:HookScript("OnEditFocusGained", OnGained)
    box:HookScript("OnEditFocusLost", OnLost)
end

local function Scan()
    local f = EnumerateFrames()
    local n = 0
    while f do
        if not f:IsForbidden() and f:GetObjectType() == "EditBox" then
            Hook(f)
            n = n + 1
        end
        f = EnumerateFrames(f)
    end
    return n
end

local scanPending
local function ScheduleScan(delay)
    if scanPending then return end
    scanPending = true
    C_Timer.After(delay or 1, function()
        scanPending = false
        Scan()
    end)
end

-- Poll -------------------------------------------------------------------------

local poller = CreateFrame("Frame")
local elapsed = 0
poller:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < POLL then return end
    elapsed = 0
    if not GetCurrentKeyBoardFocus then return end
    local live = GetCurrentKeyBoardFocus()
    if live and not live:IsForbidden() then
        if live:GetObjectType() == "EditBox" then
            Hook(live)
            if live ~= current and not lossTimer then SetCurrent(live) end
        end
    elseif current and not lossTimer then
        OnLost(current)
    end
end)

function ns.GetTarget()
    return current
end

function ns.OnLogin()
    Scan()
    if hooksecurefunc and ChatEdit_ActivateChat then
        hooksecurefunc("ChatEdit_ActivateChat", function(editBox) OnGained(editBox) end)
    end
end

function ns.OnAddonLoaded(name)
    if name ~= ADDON then ScheduleScan(1) end
end
