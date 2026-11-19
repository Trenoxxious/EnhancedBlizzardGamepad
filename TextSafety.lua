local ADDON, ns = ...

-- EBG owns these buffers. Never store state on native fields or invoke their scripts.
local Input = {}
ns.Input = Input
local searchNames = { BagItemSearchBox = true, BankItemSearchBox = true }
local roots = {
    ContainerFrameCombinedBags = "Bags", BankFrame = "Bank", BankPanel = "Bank",
    GuildBankFrame = "Guild Bank", AuctionHouseFrame = "Auction House", AuctionFrame = "Auction House",
}
function Input.Context(box)
    local f = box
    for _ = 1, 16 do
        if not f or (f.IsForbidden and f:IsForbidden()) then break end
        local name = f.GetName and f:GetName() or ""
        if roots[name] then return roots[name] end
        if name:match("^ContainerFrame%d+$") or searchNames[name] then
            return name == "BankItemSearchBox" and "Bank" or "Bags"
        end
        f = f.GetParent and f:GetParent()
    end
end
function Input.IsSearch(box)
    if not box or box.isEBGInput then return false end
    if searchNames[box:GetName() or ""] then return true end
    local parent = box:GetParent()
    local context = Input.Context(box)
    if context ~= "Bags" and context ~= "Bank" then return false end
    return parent and (parent.SearchBox == box or parent.searchBox == box or parent.SearchBar == box) or false
end
function Input.Allows(box)
    if not box or (box.IsForbidden and box:IsForbidden()) then return false end
    if box.isEBGInput or box.isComposer then return true end
    if Input.IsSearch(box) then return C_Container and type(C_Container.SetItemSearch) == "function" end
    return Input.Context(box) == nil
end

local Buffer = {}
Buffer.__index = Buffer
function Buffer:IsForbidden() return false end
function Buffer:GetObjectType() return "EditBox" end
function Buffer:GetName() return "EBGTextBuffer" end
function Buffer:GetParent() return nil end
function Buffer:HasFocus() return false end
function Buffer:GetAttribute() return nil end
function Buffer:IsNumeric() return self.numeric or false end
function Buffer:GetText() return self.text end
function Buffer:GetCursorPosition() return self.pos end
function Buffer:SetCursorPosition(p) self.pos = math.max(0, math.min(p, #self.text)) end
function Buffer:SetText(text)
    if self.apply and not self.apply(text) then return false end
    self.text, self.pos = text, #text
    return true
end
function Buffer:Insert(text)
    -- A number field showing just "0" is replaced by the first digit typed, not appended to.
    if self.numeric and self.text == "0" and text:match("^%d") then self.text, self.pos = "", 0 end
    local pos = self.pos + #text
    if self:SetText(self.text:sub(1, self.pos) .. text .. self.text:sub(self.pos + 1)) then self:SetCursorPosition(pos) end
end
function Input.NewBuffer(title, text, submit)
    return setmetatable({ isEBGInput = true, title = title, text = text or "", pos = #(text or ""), submit = submit }, Buffer)
end

local query, source, filterBuffer, status
local function ObserveSearch(text)
    query = type(text) == "string" and text or ""
    if filterBuffer and filterBuffer.text ~= query then filterBuffer.text, filterBuffer.pos = query, #query end
end
function Input.SetSearch(text)
    if InCombatLockdown() then ns.Print("Item search is paused during combat.") return false end
    if not (C_Container and C_Container.SetItemSearch) then return false end
    if ns.NoteWrite then ns.NoteWrite(source, "C_Container.SetItemSearch") end
    local ok, err = pcall(C_Container.SetItemSearch, text)
    if not ok then ns.Print("Item search failed: " .. tostring(err)) return false end
    ObserveSearch(text)
    return true
end
function Input.SearchTarget(box)
    source = box
    if query == nil then query = box:GetText() or "" end
    if not filterBuffer then
        filterBuffer = Input.NewBuffer("Item search", query)
        filterBuffer.apply = Input.SetSearch
    end
    return filterBuffer
end
function Input.SearchText() return query or "" end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:SetScript("OnEvent", function()
    if C_Container and C_Container.SetItemSearch and hooksecurefunc then
        hooksecurefunc(C_Container, "SetItemSearch", ObserveSearch)
    end
end)
local elapsed = 0
watcher:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.2 then return end
    elapsed = 0
    local visible = source and not source:IsForbidden() and source:IsVisible() and query and query ~= ""
    if not visible or not ns.db or not ns.db.enabled then if status then status:Hide() end return end
    if not status then
        status = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        status:SetFrameStrata("DIALOG")
        status:SetClampedToScreen(true)
        status:SetSize(350, 48)
        ns.Skin.Panel(status)
        status.text = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status.text:SetPoint("LEFT", 16, 0)
        status.text:SetPoint("RIGHT", -86, 0)
        status.text:SetWordWrap(false)
        local clear = ns.Skin.CreateKey(status)
        clear:SetSize(64, 28)
        clear:SetPoint("RIGHT", -12, 0)
        clear.text:SetText("Clear")
        ns.Skin.StyleKey(clear, "fn")
        clear:SetScript("OnEnter", function() ns.Skin.StyleKey(clear, "selected") end)
        clear:SetScript("OnLeave", function() ns.Skin.StyleKey(clear, "fn") end)
        clear:SetScript("OnClick", function() Input.SetSearch("") end)
    end
    status:ClearAllPoints()
    status:SetPoint("TOPLEFT", source, "BOTTOMLEFT", -8, -4)
    status.text:SetText("Item filter: " .. query:gsub("|", "||"))
    status:Show()
end)
