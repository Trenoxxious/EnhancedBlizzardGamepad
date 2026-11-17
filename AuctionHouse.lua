local ADDON, ns = ...
local Data = ns.AuctionData
local Style = ns.AuctionStyle
local Auction = {}
ns.Auction = Auction

-- A persistent, addon-owned controller workspace using auction APIs for queries and trades.
local frame, tooltip, launcher
local tab, page, focus = 1, 1, 1
local pendingPage
local tabs = { "Buy", "Sell", "Recent", "Auctions" }
local categories, categoryPage, categoryRows = {}, 1, {}
local filterMode, firstResult = false, 7
local firstCategory, categoryFocus
local categoryFocusID
local lastCategory, lastResult
local expanded = {}
local CategorySelect, ToggleFilters, EditLevel, SortBy
local controls, rows, buttons = {}, {}, {}
local consumed, closing, capturing = {}, false, false
local releaseAction
local Refresh, Activate, SwitchTab, SearchInput
local function KeyboardOpen() return ns.KB and ns.KB.frame:IsShown() end
-- System buttons the browser never keeps from the game.
local PASS_THROUGH = { PADSYSTEM = true, PADFORWARD = true, PADBACK = true, PADSOCIAL = true }
local function Escape(text) return tostring(text or ""):gsub("|", "||") end
-- Prices with Blizzard's coin icons: gold (with thousands separators), then silver and copper as
-- two digits so columns line up. Leading zero denominations are left out (24s 00c, not 0g 24s 00c).
local COIN = "|TInterface\\MoneyFrame\\UI-%sIcon:12:12:2:0|t"
local GOLD, SILVER, COPPER = COIN:format("Gold"), COIN:format("Silver"), COIN:format("Copper")
local function Money(value)
    if type(value) ~= "number" then return value and tostring(value) or "No buyout" end
    value = math.floor(value)
    local gold, silver, copper = math.floor(value / 10000), math.floor(value / 100) % 100, value % 100
    local goldText = BreakUpLargeNumbers and BreakUpLargeNumbers(gold) or tostring(gold)
    if gold > 0 then return ("%s%s %02d%s %02d%s"):format(goldText, GOLD, silver, SILVER, copper, COPPER) end
    if silver > 0 then return ("%d%s %02d%s"):format(silver, SILVER, copper, COPPER) end
    return ("%d%s"):format(copper, COPPER)
end
Auction.Money = Money
local function Quantity(value)
    if not value then return "" end
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
    local text = tostring(value)
    repeat
        local changed
        text, changed = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
    until changed == 0
    return text
end
local function Capture(want)
    if InCombatLockdown() or not frame or capturing == want then return end
    if ns.NoteAction then ns.NoteAction("auction pad capture " .. (want and "on" or "off")) end
    frame:EnableGamePadButton(want)
    frame:SetPropagateKeyboardInput(true)
    capturing = want
end
local placement
local function PlaceOverNative()
    if not frame or InCombatLockdown() then return end
    local native = Data.backend == "legacy" and _G.AuctionFrame or _G.AuctionHouseFrame
    local scale = math.min(ns.db.scale or 1, UIParent:GetWidth() / 1140, UIParent:GetHeight() / 700)
    local x, y = UIParent:GetWidth() / 2, UIParent:GetHeight() / 2
    if native and not (native.IsForbidden and native:IsForbidden()) and native:IsShown() then
        local left, bottom = native:GetLeft(), native:GetBottom()
        if left and bottom then
            -- Copy geometry into UIParent coordinates; never anchor to or resize a native frame.
            local ratio = native:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local width, height = native:GetWidth() * ratio, native:GetHeight() * ratio
            -- Cover the outer trim and the native tabs below the window. Uniform scaling keeps
            -- our fixed column layout intact; the larger dimension determines the footprint.
            scale = math.max((width + 16) / 1100, (height + 48) / 660)
            scale = math.min(scale, UIParent:GetWidth() / 1100, UIParent:GetHeight() / 660)
            x, y = left * ratio + width / 2, bottom * ratio + height / 2 - 16
        end
    end
    x = math.max(550 * scale, math.min(x, UIParent:GetWidth() - 550 * scale))
    y = math.max(330 * scale, math.min(y, UIParent:GetHeight() - 330 * scale))
    if placement and placement[1] == scale and placement[2] == x and placement[3] == y then return end
    placement = { scale, x, y }
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end
-- Blizzard's own auction window stays open behind the browser (it keeps the auction session
-- alive), so it is faded out rather than hidden. Only its alpha is touched: no scripts, fields
-- or shown state. The alpha is set back whenever the browser closes.
local nativeAlpha = {}
local function SetNativeHidden(hidden)
    if ns.db and ns.db.auctionHideNative == false then hidden = false end
    -- Blizzard's navigation pointer is faded with it, so no cursor floats over the invisible window.
    local nav = _G.SmartNavigation
    local targets = { _G.AuctionHouseFrame, _G.AuctionFrame, type(nav) == "table" and nav.Pointer or nil }
    for i = 1, 3 do
        local native = targets[i]
        if type(native) == "table" and native.GetAlpha and not (native.IsForbidden and native:IsForbidden()) then
            if hidden then
                local a = native:GetAlpha() or 1
                if a > 0.01 then
                    if ns.NoteAction then ns.NoteAction("fade " .. (native.GetName and native:GetName() or "nav pointer")) end
                    -- Keep the highest alpha seen, in case Blizzard was still fading the window in.
                    nativeAlpha[native] = math.max(nativeAlpha[native] or 0, a)
                    pcall(native.SetAlpha, native, 0)
                end
            elseif nativeAlpha[native] then
                if ns.NoteAction then ns.NoteAction("unfade " .. (native.GetName and native:GetName() or "nav pointer")) end
                pcall(native.SetAlpha, native, nativeAlpha[native])
                nativeAlpha[native] = nil
            end
        end
    end
end
local function FinishClose()
    if ns.AuctionTransactions then ns.AuctionTransactions.Close(true) end
    if ns.AuctionTradeUI then ns.AuctionTradeUI.Bind(false) end
    closing = false
    releaseAction = nil
    wipe(consumed)
    Capture(false)
    SetNativeHidden(false)
    if frame then frame:SetAlpha(1) frame:Hide() end
end
function Auction.Close(immediate)
    if KeyboardOpen() and ns.KB.target and ns.KB.target.auctionInput then ns.HideKeyboard() end
    if not frame then return end
    SetNativeHidden(false)
    if not immediate and next(consumed) and not InCombatLockdown() then
        closing = true
        frame:SetAlpha(0)
        frame:EnableMouse(false)
        C_Timer.After(1, function() if closing then FinishClose() end end)
    else FinishClose() end
end
local function Select(index)
    focus = math.max(1, math.min(index, #controls))
    for i, b in ipairs(controls) do
        Style.Paint(b, i == focus)
    end
    local b = controls[focus]
    local item = b and b.item
    local isListing = tab == 1 and Data.mode == "details" and not filterMode
    frame.detailHeading:SetText(filterMode and "SEARCH OPTIONS" or (b and b.category and "CATEGORY" or "ITEM PREVIEW"))
    frame.detailTitle:SetText(item and Escape(item.name) or (b and b.category and b.categoryLabel) or (filterMode and "Refine your search" or "Item details"))
    frame.detailIcon:SetShown(item and item.icon ~= nil or false)
    frame.detailTitle:ClearAllPoints()
    frame.detailTitle:SetPoint("TOPLEFT", item and item.icon and 844 or 794, -132)
    frame.detailTitle:SetWidth(item and item.icon and 222 or 272)
    if item and item.icon then frame.detailIcon:SetTexture(item.icon) end
    -- "Select to..." summaries repeat the action line at the bottom of the pane, so they are left out.
    local summary = item and item.summary or ""
    if summary:find("^Select") then summary = "" end
    local description = item and summary or (filterMode and "Set your options, then choose Apply and search." or
        "Highlight an item to see its price, quantity, and tooltip.")
    if b and b.category then description = "Select to choose this category, then press Search.\n\nIndented rows narrow the category further. Back below the list steps up a level.\n\n" .. ns.Glyphs.Legend("PADDRIGHT", "moves to results.", 14) end
    if item and item.price then description = description .. (description ~= "" and "\n\n" or "") .. (item.priceLabel or "Price") .. ": " .. Money(item.price) end
    if item and item.bid then description = description .. "\nBid: " .. Money(item.bid) end
    if item and item.count then description = description .. "\nQuantity: " .. item.count end
    if item and type(item.price) == "number" and (item.count or 0) > 1 and item.priceLabel == "Stack buyout" then
        description = description .. "\nPer item: " .. Money(math.ceil(item.price / item.count))
    end
    frame.detail:SetText(description)
    local nextAction = ""
    if item then
        if filterMode then nextAction = "Select to change this option"
        elseif tab == 2 then nextAction = "Select to prepare a sale"
        elseif tab == 3 then nextAction = "Select to repeat this search"
        elseif Data.backend == "legacy" then nextAction = "Purchase using the native window"
        elseif isListing then nextAction = "Select to buy or bid"
        elseif tab == 4 then nextAction = "Select to review cancellation"
        else nextAction = "Select to view listings" end
    end
    frame.detailAction:SetText(nextAction ~= "" and ns.Glyphs.Legend("PAD1", nextAction, 16) or "")
    -- The item's tooltip is the preview itself: drawn inside the pane in place of the title, with the
    -- price and quantity beneath it. A tall or wide tooltip is scaled down to fit the pane.
    tooltip:Hide()
    local shown = false
    if item and (item.link or item.itemID) then
        tooltip:SetOwner(frame, "ANCHOR_NONE")
        tooltip:SetScale(1)
        tooltip:ClearAllPoints()
        tooltip:SetPoint("TOPLEFT", frame, "TOPLEFT", 784, -126)
        local ok = pcall(tooltip.SetHyperlink, tooltip, item.link or ("item:" .. item.itemID))
        if ok and (not tooltip.NumLines or tooltip:NumLines() > 0) then
            tooltip:Show()
            local w, h = tooltip:GetWidth() or 0, tooltip:GetHeight() or 0
            local textHeight = description ~= "" and 80 or 0
            local scale = math.min(1, w > 0 and 292 / w or 1, h > 0 and (370 - textHeight) / h or 1)
            tooltip:SetScale(scale)
            tooltip:ClearAllPoints()
            tooltip:SetPoint("TOPLEFT", frame, "TOPLEFT", 784 / scale, -126 / scale)
            shown = true
        end
    end
    frame.detailTitle:SetShown(not shown)
    frame.detailIcon:SetShown(not shown and item and item.icon ~= nil or false)
    frame.detail:ClearAllPoints()
    if shown then frame.detail:SetPoint("TOPLEFT", tooltip, "BOTTOMLEFT", 10, -6)
    else frame.detail:SetPoint("TOPLEFT", 794, -184) end
end
local function Button(label, x, y, w, h, action, role, group)
    local b = Style.Control(frame, role)
    b:SetPoint("TOPLEFT", x, y)
    b:SetSize(w, h)
    b.x, b.y, b.w, b.h = x, y, w, h
    b.text:SetText(label)
    b.action = action
    b.group = group or "toolbar"
    b:SetScript("OnEnter", function(self)
        for i, control in ipairs(controls) do if control == self then Select(i) break end end
    end)
    b:SetScript("OnClick", function(self)
        if not InCombatLockdown() and not KeyboardOpen() and not closing then Style.Press(self) self.action() end
    end)
    return b
end
local function Prompt(parent, button, label, x)
    local p = ns.Glyphs.CreateNativePrompt(parent)
    if p and ns.Glyphs.BindNativePrompt(p, button, label, "GameFontHighlightSmall") then
        p:SetPoint("LEFT", x, 0)
        p:Show()
    else
        if p then p:Hide() end
        local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", x, 0)
        text:SetText(ns.Glyphs.Legend(button, label))
    end
end
local function CategoryPath()
    local names, node = {}, ns.AuctionFilters.category
    while node do table.insert(names,1,node.name) node = node.parent end
    return #names > 0 and table.concat(names, " > ") or "All categories"
end
local function IndexOf(control)
    for i, c in ipairs(controls) do if c == control then return i end end
end
-- The filter page is a grid, so the D-pad moves to the nearest control in that direction.
-- Leaving its top edge returns to the Filter button.
local function MoveSpatial(dx, dy)
    local b = controls[focus]
    local cx, cy = b.x + b.w / 2, b.y - b.h / 2
    local best, bestScore
    for i, c in ipairs(controls) do
        if c ~= b and c.group == "filters" and c:IsShown() then
            local ox, oy = c.x + c.w / 2 - cx, (c.y - c.h / 2) - cy
            local along = dx ~= 0 and ox * dx or -oy * dy
            local across = dx ~= 0 and math.abs(oy) or math.abs(ox)
            if along > 4 then
                local score = along + across * (dx ~= 0 and 2.5 or 1.5)
                if not bestScore or score < bestScore then best, bestScore = i, score end
            end
        end
    end
    if best then Select(best)
    elseif dy < 0 then Select(IndexOf(frame.filter) or 1) end
end
local function FirstHeader()
    for _, h in ipairs(frame.sortHeaders) do if h:IsShown() then return IndexOf(h) end end
end
local function MoveVertical(direction)
    local b = controls[focus]
    if not b then return end
    if b.group == "filters" then return MoveSpatial(0, direction) end
    if b.group == "header" then
        if direction > 0 then Select(firstResult) else Select(IndexOf(frame.search) or 1) end
    elseif b.group == "toolbar" then
        if direction > 0 and filterMode then
            for i, c in ipairs(controls) do if c.group == "filters" then Select(i) return end end
        end
        Select(direction > 0 and (FirstHeader() or firstResult) or 1)
    elseif b.group == "results" and direction < 0 and focus == firstResult then
        if FirstHeader() then Select(FirstHeader()) return end
        for i, control in ipairs(controls) do if control == frame.search then Select(i) return end end
        Select(1)
    elseif b.category then
        if direction > 0 and focus == lastCategory and categoryPage < math.ceil(#categoryRows / 11) then
            categoryPage = categoryPage + 1 Refresh() Select(firstCategory)
        elseif direction < 0 and focus == firstCategory and categoryPage > 1 then
            categoryPage = categoryPage - 1 Refresh() Select(lastCategory)
        elseif direction < 0 and focus == firstCategory then
            for i, control in ipairs(controls) do if control == frame.search then Select(i) return end end
        else Select(focus + direction) end
    elseif b.group == "tabs" then Select(direction < 0 and firstResult or focus)
    else Select(focus + direction) end
end
local function Create()
    frame = CreateFrame("Frame", "EBGAuctionBrowser", UIParent, "BackdropTemplate")
    Auction.frame = frame
    frame:SetSize(1100, 660)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()
    ns.Skin.Panel(frame)
    Style.Band(frame, 14, -12, 1072, 32)
    frame.categoryPane = Style.Pane(frame, 18, -92, 184, 448, "categories")
    frame.resultPane = Style.Pane(frame, 214, -174, 548, 304, "results")
    frame.detailPane = Style.Pane(frame, 778, -92, 304, 448, "detail")
    Style.Band(frame, 215, -175, 546, 26)
    Style.Band(frame, 14, -602, 1072, 44)
    local function Label(font, x, y, width, text)
        local label = frame:CreateFontString(nil, "OVERLAY", font)
        label:SetPoint("TOPLEFT", x, y)
        label:SetWidth(width)
        label:SetJustifyH("LEFT")
        label:SetText(text or "")
        return label
    end
    frame.title = Label("GameFontNormalLarge", 28, -20, 600, "Auction House")
    frame.breadcrumb = Label("GameFontHighlightSmall", 222, -58, 850)
    frame.breadcrumb:SetWordWrap(false)
    frame.viewTitle = Label("GameFontNormalLarge", 222, -94, 540)
    frame.viewHint = Label("GameFontDisableSmall", 222, -116, 540)
    frame.viewHint:SetWordWrap(false)
    frame.back = Button("Results", 222, -50, 104, 26, function()
        if Data.busy then return end
        filterMode, page = false, 1
        if tab == 1 and Data.mode == "details" then Data.Search(Data.query) else Refresh() end
    end, "secondary", "toolbar")
    frame.tabButtons = {}
    for i, name in ipairs(tabs) do
        local index = i
        frame.tabButtons[i] = Button(name, 22 + (i - 1) * 142, -558, 132, 34,
            function() SwitchTab(index) end, "tab", "tabs")
    end
    frame.search = Button("Search", 222, -134, 294, 30, function() SearchInput() end, "search", "toolbar")
    frame.search.text:SetJustifyH("LEFT")
    frame.refresh = Button("Search", 642, -134, 112, 30, function()
        if filterMode then filterMode, page = false, 1 end
        if tab == 4 then Data.Owned() elseif tab == 1 then Data.Search(Data.query, Data.page) else Refresh() end
    end, "primary", "toolbar")
    frame.filter = Button("Filter", 528, -134, 102, 30, function() ToggleFilters() end, "secondary", "toolbar")
    -- Shortcut keys carry their controller glyph, as on the keyboard.
    Style.Glyph(frame.refresh, "PAD4")
    Style.Glyph(frame.back, "PAD2")
    frame.categoryTitle = Label("GameFontNormal", 30, -104, 160, "Categories")
    frame.categoryHint = Label("GameFontDisableSmall", 30, -126, 160, "Pick a category, then Search")
    frame.categoryButtons = {}
    for i = 1, 11 do
        local b = Button("", 24, -148 - (i - 1) * 26, 172, 25, function() end, "category", "categories")
        b.text:SetWordWrap(false)
        b.disclosure = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        b.disclosure:SetPoint("RIGHT", -8, 0)
        frame.categoryButtons[i] = b
    end
    frame.categoryPrev = Button("< Previous", 26, -448, 80, 24, function()
        categoryPage = math.max(1, categoryPage - 1) Refresh()
    end, "secondary", "categories")
    frame.categoryNext = Button("More >", 112, -448, 80, 24, function()
        categoryPage = math.min(math.max(1, math.ceil(#categoryRows / 11)), categoryPage + 1) Refresh()
    end, "secondary", "categories")
    frame.categoryBack = Button("< Back", 26, -476, 166, 24, function()
        local picked = ns.AuctionFilters.category
        if picked then CategorySelect(picked.parent) end
    end, "secondary", "categories")
    frame.categoryBack.text:SetWordWrap(false)
    frame.categorySummary = Label("GameFontHighlightSmall", 30, -506, 160)
    frame.categorySummary:SetHeight(30)
    frame.sidebarHelp = Label("GameFontHighlightSmall", 30, -154, 160)
    frame.sidebarHelp:SetJustifyV("TOP")
    frame.sidebarHelp:SetHeight(210)
    frame.browseReturn = Button("Browse auctions", 30, -390, 160, 30, function() SwitchTab(1) end, "secondary", "categories")
    frame.status = Label("GameFontHighlightSmall", 222, -488, 530)
    frame.status:SetWordWrap(false)
    frame.quantityHeader = Label("GameFontNormalSmall", 670, -182, 72)
    frame.quantityHeader:SetJustifyH("RIGHT")
    frame.priceHeader = Label("GameFontNormalSmall", 230, -182, 130, "Price")
    frame.nameHeader = Label("GameFontNormalSmall", 400, -182, 258, "Name")
    frame.detailHeading = Label("GameFontNormalSmall", 794, -106, 270, "ITEM PREVIEW")
    frame.detailTitle = Label("GameFontNormalLarge", 794, -132, 272)
    frame.detailTitle:SetHeight(42)
    frame.detailIcon = frame:CreateTexture(nil, "OVERLAY")
    frame.detailIcon:SetPoint("TOPLEFT", 794, -132)
    frame.detailIcon:SetSize(40,40)
    frame.detail = Label("GameFontHighlightSmall", 794, -184, 272)
    frame.detail:SetJustifyV("TOP")
    frame.detail:SetHeight(110)
    frame.detailAction = Label("GameFontNormalSmall", 794, -510, 272)
    frame.detailAction:SetHeight(24)
    frame.emptyTitle = Label("GameFontNormalLarge", 244, -286, 488)
    frame.emptyTitle:SetJustifyH("CENTER")
    frame.emptyHelp = Label("GameFontHighlightSmall", 254, -318, 468)
    frame.emptyHelp:SetJustifyH("CENTER")
    for i = 1, 7 do
        local b = Button("", 216, -202 - (i - 1) * 39, 544, 39, function() end, "row", "results")
        b.stripe = i % 2 == 0
        b.icon = b:CreateTexture(nil, "OVERLAY")
        b.icon:SetSize(24, 24)
        b.icon:SetPoint("LEFT", 146, 0)
        b.price = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.price:SetPoint("LEFT", 8, 0)
        b.price:SetWidth(130)
        b.price:SetJustifyH("RIGHT")
        b.quantity = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.quantity:SetPoint("RIGHT", -18, 0)
        b.quantity:SetWidth(72)
        b.quantity:SetJustifyH("RIGHT")
        b.level = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.level:SetPoint("LEFT", 384, 0)
        b.level:SetWidth(54)
        b.level:SetJustifyH("RIGHT")
        buttons[i] = b
    end
    -- Sortable column headers, as in Blizzard's results list: press one to sort by it, press it
    -- again to reverse. Level appears for gear.
    frame.sortHeaders = {}
    local function Header(key, label, x, w, justify)
        local h = Button(label, x, -175, w, 26, function() SortBy(key) end, "header", "header")
        h.sortKey, h.label = key, label
        h.text:ClearAllPoints()
        h.arrow = h:CreateTexture(nil, "OVERLAY")
        h.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
        h.arrow:SetSize(9, 8)
        if justify == "RIGHT" then
            h.text:SetPoint("RIGHT", -8, 0)
            h.arrow:SetPoint("RIGHT", h.text, "LEFT", -4, 0)
        else
            h.text:SetPoint("LEFT", 8, 0)
            h.arrow:SetPoint("LEFT", h.text, "RIGHT", 4, 0)
        end
        frame.sortHeaders[#frame.sortHeaders + 1] = h
        return h
    end
    frame.sortPrice = Header("Price", "Price", 216, 144, "RIGHT")
    frame.sortName = Header("Name", "Name", 362, 300, "LEFT")
    frame.sortLevel = Header("Level", "Level", 594, 64, "RIGHT")
    -- One-page filters: level range, then checkboxes grouped as in Blizzard's filter menu.
    frame.filterHeadings = {}
    for i = 1, 3 do
        local heading = Label("GameFontNormal", 0, 0, 250)
        frame.filterHeadings[i] = heading
    end
    frame.levelMin = Button("", 226, -208, 124, 28, function() EditLevel("minLevel") end, "secondary", "filters")
    frame.levelMax = Button("", 358, -208, 124, 28, function() EditLevel("maxLevel") end, "secondary", "filters")
    frame.filterChecks = {}
    frame.filterReset = Button("Reset filters", 226, -440, 132, 28, function()
        ns.AuctionFilters.Reset() Refresh()
    end, "secondary", "filters")
    frame.filterApply = Button("Apply and search", 584, -440, 170, 28, function()
        filterMode, tab, page = false, 1, 1
        Data.Search(Data.query)
        Refresh()
    end, "primary", "filters")
    Style.Glyph(frame.filterApply, "PAD4")
    frame.filterNote = Label("GameFontDisableSmall", 370, -448, 206, "")
    frame.previous = Button("Previous", 222, -510, 94, 26, function() Auction.Page(-1) end, "secondary", "paging")
    frame.next = Button("Next", 326, -510, 94, 26, function() Auction.Page(1) end, "secondary", "paging")
    frame.native = Button("Open native window", 898, -558, 178, 34, function() Auction.Close() end, "secondary", "utility")
    frame.page = Label("GameFontDisableSmall", 434, -518, 322)
    -- frame.note = Label("GameFontDisableSmall", 30, -638, 1030,
    --     "Select a listing to buy or bid. Sell lists auctionable bag items. Every transaction requires confirmation.")
    local legend = CreateFrame("Frame", nil, frame)
    legend:SetPoint("TOPLEFT", 28, -610)
    legend:SetSize(1040, 20)
    -- Shortcuts that belong to a button are shown on that button (Search, tabs, paging, Back...).
    -- The footer keeps only the inputs that have no button of their own.
    Prompt(legend, "PAD1", "Select", 0)
    frame.padHint = Label("GameFontHighlightSmall", 150, -614, 300, "")
    tooltip = CreateFrame("GameTooltip", "EBGAuctionItemTooltip", frame, "GameTooltipTemplate")
    tooltip:SetClampedToScreen(true)
    frame:SetScript("OnGamePadButtonDown", function(self, key)
        if InCombatLockdown() or KeyboardOpen() then return end
        self:SetPropagateKeyboardInput(false)
        consumed[key] = true
        if closing then return end
        if ns.NoteAction then ns.NoteAction("pad " .. key) end
        if ns.AuctionTransactions.current then
            -- A, B and Y go on to the trade panel's override bindings, so the auction call runs
            -- inside a hardware event (see AuctionTradeUI.Bind).
            if ns.AuctionTradeUI.bound and (key == "PAD1" or key == "PAD2" or key == "PAD4") then
                consumed[key] = nil
                self:SetPropagateKeyboardInput(true)
                return
            end
            local action = ns.AuctionTradeUI.Handle(key)
            if action then releaseAction = {key,action} end
            return
        end
        if key == "PADDUP" then MoveVertical(-1)
        elseif key == "PADDDOWN" then MoveVertical(1)
        elseif key == "PADDLEFT" or key == "PADDRIGHT" then
            local b = controls[focus]
            if b and b.group == "filters" then MoveSpatial(key == "PADDLEFT" and -1 or 1, 0)
            elseif b and b.category and key == "PADDRIGHT" then categoryFocus = focus Select(firstResult)
            elseif b and b.item and key == "PADDLEFT" then
                if lastCategory >= firstCategory then
                    local target = math.max(firstCategory, math.min(categoryFocus or firstCategory, lastCategory))
                    Select(target)
                else
                    for i, control in ipairs(controls) do
                        if control == frame.back or control == frame.browseReturn then Select(i) return end
                    end
                    Select(1)
                end
            else Select(focus + (key == "PADDLEFT" and -1 or 1)) end
        elseif key == "PADLTRIGGER" then Auction.Page(-1)
        elseif key == "PADRTRIGGER" then Auction.Page(1)
        elseif key == "PADLSHOULDER" then SwitchTab((tab - 2) % #tabs + 1)
        elseif key == "PADRSHOULDER" then SwitchTab(tab % #tabs + 1)
        elseif key == "PAD1" then
            local b = controls[focus]
            releaseAction = b and { key, function() Style.Press(b) b.action() end } or nil
        elseif key == "PAD3" then releaseAction = { key, SearchInput }
        elseif key == "PAD4" then releaseAction = { key, frame.refresh.action }
        elseif key == "PAD2" then
            releaseAction = { key, function()
                if filterMode then filterMode, page = false, 1 Refresh()
                elseif tab == 1 and Data.mode == "details" then Data.Search(Data.query) else Auction.Close() end
            end }
        elseif PASS_THROUGH[key] then consumed[key] = nil self:SetPropagateKeyboardInput(true) end
        -- Every other button is swallowed: anything that reached the game here would act on
        -- Blizzard's faded auction window underneath.
    end)
    frame:SetScript("OnGamePadButtonUp", function(self, key)
        if InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(not consumed[key])
        consumed[key] = nil
        if releaseAction and releaseAction[1] == key then
            local action = releaseAction[2]
            releaseAction = nil
            if not closing then action() end
        end
        if closing and not next(consumed) then FinishClose() end
    end)
    frame:SetScript("OnHide", function() tooltip:Hide() end)
end
Refresh = function()
    if not frame or not frame:IsShown() or closing then return end
    local old = controls[focus]
    local oldIdentity = old and old.item and (old.item.identity or old.item.link or old.item.name)
    local oldCategory = old and old.category and old.categoryID
    local browsing = tab == 1 and not filterMode and Data.mode ~= "details"
    local details = tab == 1 and not filterMode and Data.mode == "details"
    rows = {}
    if filterMode then
        rows = {} -- the filter page is laid out below, not as list rows
    elseif tab == 2 then
        rows = ns.Inventory.Sellable()
        for _, r in ipairs(rows) do r.summary = "Select to set quantity, price, and duration. Review the deposit before posting." end
    elseif tab == 3 then
        for _, text in ipairs(ns.db.auctionRecent or {}) do rows[#rows + 1] = { name = text, recent = true, summary = "Select to search again." } end
    elseif (tab == 4 and Data.mode == "owned") or (tab == 1 and Data.mode ~= "owned") then rows = Data.rows end
    if pendingPage and not Data.busy then page, pendingPage = pendingPage, nil end
    page = math.max(1, math.min(page, math.max(1, math.ceil(#rows / 7))))
    controls = {}
    for i, b in ipairs(frame.tabButtons) do b.active = tab == i controls[#controls + 1] = b end
    frame.back:SetShown(filterMode or details)
    if filterMode or details then controls[#controls + 1] = frame.back end
    frame.search:SetShown(tab == 1 and not filterMode)
    frame.filter:SetShown(tab == 1 and not details)
    frame.refresh:SetShown(not details and not filterMode)
    if frame.search:IsShown() then controls[#controls + 1] = frame.search end
    if frame.filter:IsShown() then controls[#controls + 1] = frame.filter end
    if frame.refresh:IsShown() then controls[#controls + 1] = frame.refresh end
    frame.refresh.text:SetText(filterMode and "Apply search" or (tab == 1 and "Search" or "Refresh"))
    local active = ns.AuctionFilters.ActiveCount and ns.AuctionFilters.ActiveCount() or 0
    frame.filter.text:SetText(filterMode and "Back" or (active > 0 and ("Filter (" .. active .. ")") or "Filter"))
    frame.categoryTitle:SetText(browsing and "Categories" or (details and "Item listings" or (filterMode and "Search filters" or tabs[tab])))
    frame.categoryHint:SetShown(browsing)
    frame.sidebarHelp:SetShown(not browsing)
    frame.browseReturn:SetShown(not browsing and tab ~= 1)
    frame.sidebarHelp:SetText(details and "You are viewing listings for one item.\n\nUse < Results to return to your search.\n\nPrices and quantities belong to each listing." or
        (filterMode and "Change the options you need, then Apply search.\n\nFilters affect auction searches. Level 0 means any level." or
        (tab == 2 and "Auctionable items in your bags.\n\nChoose an item, set quantity and price, then review its deposit before posting." or
        (tab == 3 and "Your recent searches.\n\nChoose a name to run that search again." or "Your listed auctions.\n\nSelect a listing to review cancellation and any fee."))))
    -- With a category picked the list shows only its own path and its subcategories; the Back
    -- button below the list steps up one level. Nothing picked shows the top level.
    local picked = ns.AuctionFilters.category
    categoryRows = {}
    if picked then
        local chain, node = {}, picked
        while node do table.insert(chain, 1, node) node = node.parent end
        for depth, ancestor in ipairs(chain) do
            categoryRows[#categoryRows + 1] = { name = ancestor.name, node = ancestor, depth = depth - 1 }
        end
        for _, child in ipairs(picked.children) do
            categoryRows[#categoryRows + 1] = { name = child.name, node = child, depth = #chain }
        end
    else
        categoryRows[1] = { name = "All categories" }
        for _, node in ipairs(categories) do
            categoryRows[#categoryRows + 1] = { name = node.name, node = node, depth = 0 }
        end
    end
    if categoryFocusID then
        oldCategory = categoryFocusID
        for i, entry in ipairs(categoryRows) do
            if entry.node and entry.node.id == categoryFocusID then categoryPage = math.ceil(i / 11) break end
        end
        categoryFocusID = nil
    end
    categoryPage = math.max(1, math.min(categoryPage, math.max(1, math.ceil(#categoryRows / 11))))
    firstCategory = #controls + 1
    for i, b in ipairs(frame.categoryButtons) do
        local entry = categoryRows[(categoryPage - 1) * 11 + i]
        b:SetShown(browsing and entry ~= nil)
        if browsing and entry then
            local node = entry.node
            b.active = ns.AuctionFilters.category == node
            b.depth = entry.depth or 0
            b.text:ClearAllPoints()
            b.text:SetPoint("LEFT", 10 + b.depth * 12, 0)
            b.text:SetWidth(138 - b.depth * 12)
            b.text:SetJustifyH("LEFT")
            b.text:SetText(Escape(entry.name))
            b.disclosure:SetText(node and #node.children > 0 and (expanded[node.id] and "v" or ">") or "")
            b.action = function() CategorySelect(node) end
            b.category = true
            b.categoryLabel, b.categoryID = Escape(entry.name), node and node.id or "all"
            controls[#controls + 1] = b
            if oldCategory and oldCategory == b.categoryID then focus = #controls end
        end
    end
    lastCategory = #controls
    frame.categoryPrev:SetShown(browsing and categoryPage > 1)
    frame.categoryNext:SetShown(browsing and categoryPage * 11 < #categoryRows)
    if frame.categoryPrev:IsShown() then controls[#controls + 1] = frame.categoryPrev end
    if frame.categoryNext:IsShown() then controls[#controls + 1] = frame.categoryNext end
    frame.categoryBack:SetShown(browsing and picked ~= nil)
    if frame.categoryBack:IsShown() then
        frame.categoryBack.text:SetText("< " .. Escape(picked.parent and picked.parent.name or "All categories"))
        controls[#controls + 1] = frame.categoryBack
    end
    if frame.browseReturn:IsShown() then controls[#controls + 1] = frame.browseReturn end
    frame.categorySummary:SetShown(browsing)
    frame.padHint:SetText(ns.Glyphs.Legend("PADDPAD", "Navigate", 16))
    -- Glyphs on the buttons their controller shortcut presses.
    local function Mark(b, button) if b.glyphButton ~= button then Style.Glyph(b, button) end end
    for i, b in ipairs(frame.tabButtons) do
        Mark(b, (i == (tab - 2) % #tabs + 1 and "PADLSHOULDER") or (i == tab % #tabs + 1 and "PADRSHOULDER") or nil)
    end
    Mark(frame.previous, "PADLTRIGGER")
    Mark(frame.next, "PADRTRIGGER")
    -- B closes the browser (showing Blizzard's window) unless a Back button is on screen.
    Mark(frame.native, not (filterMode or details) and "PAD2" or nil)
    frame.categorySummary:SetText(ns.Glyphs.Legend("PADDRIGHT", "Results", 16) .. "\n" .. ns.Glyphs.Legend({ "PADLTRIGGER", "PADRTRIGGER" }, "Result pages", 16))
    -- Sort headers: browse results on the modern auction house, which sorts on the server.
    local sortable = tab == 1 and not filterMode and not details and Data.backend == "modern"
    local showLevel = false
    if sortable then
        showLevel = ns.AuctionFilters.IsEquipment() or ns.AuctionFilters.sort == "Level"
        for _, r in ipairs(rows) do if r.level then showLevel = true break end end
    end
    frame.sortLevel.hidden = not showLevel
    frame.sortName:SetWidth(showLevel and 230 or 300)
    frame.sortName.w = showLevel and 230 or 300
    for _, h in ipairs(frame.sortHeaders) do
        local shown = sortable and not h.hidden
        h:SetShown(shown)
        if shown then
            h.active = ns.AuctionFilters.sort == h.sortKey
            h.text:SetText(h.label)
            h.arrow:SetShown(h.active)
            if ns.AuctionFilters.reverse then h.arrow:SetTexCoord(0, 0.5625, 1, 0) else h.arrow:SetTexCoord(0, 0.5625, 0, 1) end
            controls[#controls + 1] = h
        end
    end
    -- The one-page filter view.
    local filterControls = {}
    if filterMode then
        local f = ns.AuctionFilters
        frame.levelMin.text:SetText("Min: " .. (f.minLevel > 0 and f.minLevel or "Any"))
        frame.levelMax.text:SetText("Max: " .. (f.maxLevel > 0 and f.maxLevel or "Any"))
        filterControls[#filterControls + 1] = frame.levelMin
        filterControls[#filterControls + 1] = frame.levelMax
        local groups = f.Groups(Data.backend ~= "modern")
        local headings = { { "Level range", 226, -186 } }
        -- General options under the level range on the left; rarity in its own column.
        local columns = { { x = 226, y = -270 }, { x = 498, y = -208 } }
        local used = 0
        for g, group in ipairs(groups) do
            local col = columns[(group.rarity or g > 1) and 2 or 1]
            headings[#headings + 1] = { group.name, col.x, col.y + 22 }
            for _, option in ipairs(group.options) do
                used = used + 1
                local c = frame.filterChecks[used]
                if not c then
                    c = Button("", 0, 0, 256, 26, function() end, "check", "filters")
                    c.text:ClearAllPoints()
                    c.text:SetPoint("LEFT", 32, 0)
                    c.text:SetPoint("RIGHT", -6, 0)
                    c.text:SetJustifyH("LEFT")
                    c.text:SetWordWrap(false)
                    frame.filterChecks[used] = c
                end
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", col.x, col.y)
                c.x, c.y = col.x, col.y
                c.text:SetText(option.name)
                c.checked = f.selected[option.id] == true
                c.textColor = option.quality and ns.Inventory.Color(option.quality) or nil
                local id = option.id
                c.action = function() f.selected[id] = not f.selected[id] Refresh() end
                c:Show()
                filterControls[#filterControls + 1] = c
                col.y = col.y - 29
            end
        end
        for i, heading in ipairs(frame.filterHeadings) do
            local h = headings[i]
            heading:SetShown(h ~= nil)
            if h then heading:ClearAllPoints() heading:SetPoint("TOPLEFT", h[2], h[3]) heading:SetText(h[1]) end
        end
        for i = used + 1, #frame.filterChecks do frame.filterChecks[i]:Hide() end
        filterControls[#filterControls + 1] = frame.filterReset
        filterControls[#filterControls + 1] = frame.filterApply
        frame.filterNote:SetText("Changes apply on the next search.")
    else
        for _, heading in ipairs(frame.filterHeadings) do heading:Hide() end
        for _, c in ipairs(frame.filterChecks) do c:Hide() end
    end
    for _, c in ipairs({ frame.levelMin, frame.levelMax, frame.filterReset, frame.filterApply }) do c:SetShown(filterMode) end
    frame.filterNote:SetShown(filterMode)
    local oldFilter = old and old.group == "filters" and old
    for _, c in ipairs(filterControls) do
        controls[#controls + 1] = c
        if c == oldFilter then focus = #controls end
    end
    firstResult = #controls + 1
    frame.search.placeholder = Data.query == ""
    frame.search.text:SetText(Data.query == "" and (ns.Glyphs.Legend("PAD3", "Search by item name...", 16)) or ns.Glyphs.Legend("PAD3", Escape(Data.query), 16))
    frame.search.text:ClearAllPoints()
    frame.search.text:SetPoint("LEFT", 12, 0)
    frame.search.text:SetWidth(270)
    frame.search.text:SetWordWrap(false)
    local status = (tab == 2 and (#rows .. " auctionable item types - select to sell")) or
        (tab == 3 and (#rows == 0 and "Your searches will appear here." or "Choose a recent search")) or Data.message or "Ready"
    if InCombatLockdown() then status = "Combat: auction controls paused." end
    if filterMode and not InCombatLockdown() then status = "Choose filters, then Apply and search. Level 0 means any." end
    frame.status:SetText(status)
    local path = filterMode and "Buy > Search filters" or (tab == 1 and ("Buy > " .. CategoryPath()) or tabs[tab])
    if details then path = path .. " > " .. (Data.itemName or "Listings") end
    frame.breadcrumb:ClearAllPoints()
    frame.breadcrumb:SetPoint("TOPLEFT", (filterMode or details) and 338 or 222, -58)
    frame.breadcrumb:SetWidth((filterMode or details) and 730 or 850)
    frame.breadcrumb:SetText(Escape(path))
    frame.viewTitle:SetText(filterMode and "Search filters" or (details and ("Listings: " .. Escape(Data.itemName or "Item")) or
        ({"Browse auctions", "Sell an item", "Recent searches", "Your auctions"})[tab]))
    local hint = filterMode and "Choose options, then apply your search" or
        (details and "Compare individual listings • Back returns to your search" or
        (tab == 1 and (Data.query ~= "" and ('Results for "' .. Escape(Data.query) .. '"') or "Browse a category or search by item name") or
        ({"", "Choose an item to set price, quantity, and duration", "Select a search to run it again", "Review your active and sold listings"})[tab]))
    frame.viewHint:SetText(hint)
    frame.emptyTitle:SetShown(#rows == 0 and not filterMode)
    frame.emptyHelp:SetShown(#rows == 0 and not filterMode)
    frame.emptyTitle:SetText(Data.busy and "Searching auctions..." or (Data.mode == "invalid" and tab == 1 and "Search unavailable" or
        (Data.message == "No results." and tab == 1 and "No auctions found" or (Data.pending and tab == 1 and "Ready to search" or "Start browsing"))))
    frame.emptyHelp:SetText(tab == 2 and "Unlocked, auctionable items in your bags will appear here." or (tab == 3 and "Search for an item to add it to this list." or
        (tab == 4 and "No auctions to display." or (Data.busy and "Results will appear here when the auction house responds." or
        (Data.mode == "invalid" and Data.message or (Data.pending and ("Press Search to list auctions in " .. Escape(CategoryPath()) .. ".") or
        "Choose a category on the left, or enter an item name above."))))))
    frame.quantityHeader:SetText(tab == 3 and "" or (tab == 2 and "Carried" or
        (tab == 4 and "Listed" or (Data.backend == "legacy" and "Stack" or "Available"))))
    -- Plain labels where the list cannot be re-sorted; the sort headers replace them otherwise.
    frame.priceHeader:SetShown(not filterMode and not sortable and (tab == 1 or tab == 4))
    frame.quantityHeader:SetShown(not filterMode)
    frame.nameHeader:SetShown(not filterMode and not sortable)
    frame.nameHeader:ClearAllPoints()
    frame.nameHeader:SetPoint("TOPLEFT", (tab == 2 or tab == 3) and 232 or 400, -182)
    for i, b in ipairs(buttons) do
        local item = rows[(page - 1) * 7 + i]
        b.item = item
        b:SetShown(item ~= nil)
        if item then
            b.text:ClearAllPoints()
            b.text:SetPoint("LEFT", 180, 0)
            b.text:SetWidth(showLevel and 200 or 262)
            b.level:SetShown(showLevel)
            b.level:SetText(showLevel and item.level and tostring(item.level) or "")
            b.text:SetJustifyH("LEFT")
            b.text:SetWordWrap(false)
            b.text:SetText(Escape(item.name))
            b.icon:SetTexture(item.icon or 134400)
            b.price:SetText(item.price and Money(item.price) or ((tab == 1 or tab == 4) and "No buyout" or ""))
            b.quantity:SetText(Quantity(item.count))
            if filterMode then
                b.text:ClearAllPoints()
                b.text:SetPoint("LEFT", 12, 0)
                b.text:SetWidth(516)
            end
            if tab == 2 or tab == 3 then
                b.text:ClearAllPoints()
                b.text:SetPoint("LEFT", tab == 2 and 44 or 12, 0)
                b.text:SetWidth(tab == 2 and 390 or 516)
                b.icon:ClearAllPoints()
                b.icon:SetPoint("LEFT", 10, 0)
            else b.icon:ClearAllPoints() b.icon:SetPoint("LEFT", 146, 0) end
            b.role = filterMode and "option" or "row"
            b.icon:SetShown(not filterMode and tab ~= 3)
            b.price:SetShown(not filterMode and (tab == 1 or tab == 4))
            b.quantity:SetShown(not filterMode)
            b.action = function() Activate(item) end
            controls[#controls + 1] = b
            if oldIdentity and (item.identity or item.link or item.name) == oldIdentity then focus = #controls end
        end
    end
    lastResult = #controls
    -- The filter page fits on one page, so it has no paging.
    frame.previous:SetShown(not filterMode)
    frame.next:SetShown(not filterMode)
    frame.page:SetShown(not filterMode)
    if not filterMode then
        controls[#controls + 1] = frame.previous
        controls[#controls + 1] = frame.next
    end
    controls[#controls + 1] = frame.native
    frame.page:SetText(("Page %d / %d%s"):format(page, math.max(1, math.ceil(#rows / 7)),
        tab == 1 and not filterMode and Data.more and " - Next loads more" or ""))
    Select(focus)
end
Activate = function(item)
    if filterMode then return -- the filter page uses its own controls
    elseif tab == 2 then
        tooltip:Hide()
        ns.AuctionTransactions.Open("sell",item)
    elseif tab == 3 then
        ns.AuctionFilters.category = nil
        if Data.Search(item.name) then tab, page, focus = 1, 1, firstResult end
        Refresh()
    elseif tab == 1 and Data.mode == "browse" and item.itemKey then
        if Data.Details(item) then page, focus = 1, firstResult end
        Refresh()
    elseif tab == 1 and Data.mode == "details" then
        tooltip:Hide()
        ns.AuctionTransactions.Open("buy",item)
    elseif tab == 4 then
        tooltip:Hide()
        ns.AuctionTransactions.Open("cancel",item)
    end
end
SwitchTab = function(index)
    if Data.busy then return end
    pendingPage = nil
    filterMode = false
    tab, page, focus = index, 1, index
    if tab == 4 then Data.Owned()
    elseif tab == 1 and Data.mode == "owned" then Data.Search(Data.query) end
    Refresh()
end
SearchInput = function()
    if InCombatLockdown() or Data.busy then return end
    local buffer = ns.Input.NewBuffer("Auction search", Data.query, function(text)
        filterMode = false
        if Data.Search(text) then tab, page, focus = 1, 1, firstResult end
        Refresh()
    end)
    buffer.submitLabel, buffer.auctionInput = "Search", true
    Capture(false)
    wipe(consumed)
    ns.ShowKeyboard(true, buffer)
end
function Auction.EditInput(buffer)
    -- The keyboard owns A/B/Y while it is open.
    if ns.AuctionTradeUI then ns.AuctionTradeUI.Bind(false) end
    Capture(false)
    wipe(consumed)
    ns.ShowKeyboard(true,buffer)
end
function Auction.ResumeInput()
    if frame and frame:IsShown() and not closing then Capture(ns.IsGamepadActive() and not KeyboardOpen()) end
end
-- Sorting is done by the server, so a new sort re-runs the current search (as Blizzard's headers do).
SortBy = function(key)
    if Data.busy then return end
    local f = ns.AuctionFilters
    if f.sort == key then f.reverse = not f.reverse else f.sort, f.reverse = key, false end
    if tab == 1 and Data.mode == "browse" and #Data.rows > 0 then
        if Data.Search(Data.query) then page = 1 end
    end
    Refresh()
end
ToggleFilters = function()
    if Data.busy then return end
    filterMode, page, focus = not filterMode, 1, firstResult
    Refresh()
    -- Opening the filter page starts on its first option; closing it returns to the Filter button.
    local target = filterMode and frame.levelMin or frame.filter
    for i, c in ipairs(controls) do if c == target then Select(i) break end end
end
EditLevel = function(key)
    local buffer = ns.Input.NewBuffer(key == "minLevel" and "Minimum level" or "Maximum level", tostring(ns.AuctionFilters[key]), function(text)
        local level = tonumber(text)
        local f = ns.AuctionFilters
        if not level or level < 0 or level > 999 or level ~= math.floor(level) then ns.Print("Enter a whole level from 0 to 999.") return end
        if (key == "minLevel" and f.maxLevel > 0 and level > f.maxLevel) or (key == "maxLevel" and level > 0 and level < f.minLevel) then
            ns.Print("Minimum level cannot exceed maximum level.") return
        end
        f[key] = level
        Refresh()
    end)
    buffer.numeric, buffer.auctionInput, buffer.submitLabel = true, true, "Apply"
    Capture(false)
    ns.ShowKeyboard(true, buffer)
end
CategorySelect = function(node)
    if Data.busy then return end
    local previous = ns.AuctionFilters.category
    if node and previous == node then node = node.parent end
    -- Stepping up puts focus on the category just left; picking one keeps focus on it.
    categoryFocusID = previous and previous.parent == node and previous.id or (node and node.id) or nil
    categoryPage = 1
    expanded = {}
    local ancestor = node
    while ancestor do expanded[ancestor.id] = true ancestor = ancestor.parent end
    ns.AuctionFilters.category = node
    filterMode, tab, page, pendingPage = false, 1, 1, nil
    -- Choosing a category only records it; the query is sent when the player presses Search.
    Data.Invalidate("Category set. Press Search to list auctions.")
    Refresh()
end
function Auction.Page(direction)
    if Data.busy then return end
    local pages = math.max(1, math.ceil(#rows / 7))
    if direction > 0 and page == pages and tab == 1 and not filterMode and Data.more then
        if Data.More() then pendingPage, focus = Data.backend == "legacy" and 1 or pages + 1, firstResult end
    elseif direction < 0 and page == 1 and tab == 1 and not filterMode and Data.backend == "legacy" and Data.page > 0 then
        if Data.Search(Data.query, Data.page - 1) then page, focus = 1, firstResult end
    else page, focus = math.max(1, math.min(page + direction, pages)), firstResult end
    Refresh()
end
function Auction.Open()
    if not ns.db or not ns.db.enabled then return end
    if not ns.IsGamepadActive() then ns.Print("The auction browser is only available while the gamepad interface is enabled.") return end
    if InCombatLockdown() then ns.Print("Open the auction browser after combat.") return end
    if not Data.active then ns.Print("Visit an auctioneer, then use /ebg ah.") return end
    Data.backend = Data.Detect()
    if not Data.backend then ns.Print("No supported auction query API was found on this client.") return end
    if not frame then Create() end
    if #categories == 0 then categories = ns.AuctionFilters.Categories() ns.AuctionFilters.Reset() end
    closing = false
    frame:SetAlpha(1)
    frame:EnableMouse(true)
    PlaceOverNative()
    frame:Show()
    SetNativeHidden(true)
    Capture(ns.IsGamepadActive() and not KeyboardOpen())
    Refresh()
end
function Auction.OnVisit()
    if ns.db and ns.db.auctionAuto ~= false and ns.IsGamepadActive() then
        C_Timer.After(0, function() if Data.active then Auction.Open() end end)
    end
end
Data.changed = Refresh
-- Snapshot for blocked-action records.
ns.blockedContext.auction = function()
    local t = ns.AuctionTransactions and ns.AuctionTransactions.current
    local native = _G.AuctionHouseFrame or _G.AuctionFrame
    return ("browser %s, tab %s, query %s%s, trade %s, native %s alpha %.2f, capture %s"):format(
        frame and frame:IsShown() and "open" or "closed", tostring(tabs[tab]), tostring(Data.mode), Data.busy and " (busy)" or "",
        t and (t.kind .. "/" .. t.phase) or "none",
        native and native:IsShown() and "shown" or "hidden", native and native:GetAlpha() or 0, tostring(capturing))
end
local listener = CreateFrame("Frame")
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do listener:RegisterEvent(event) end
listener:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        wipe(consumed)
        releaseAction = nil
        -- Pad input cannot be held back from the game in combat, so the browser steps aside and
        -- Blizzard's window is visible again instead of being navigated blind.
        if closing or (frame and frame:IsShown()) then FinishClose() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- The frame may have been closed during lockdown, so release capture too.
        Capture(frame and frame:IsShown() and not KeyboardOpen() and ns.IsGamepadActive() or false)
    end
    Refresh()
end)
local elapsed = 0
listener:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.15 then return end
    elapsed = 0
    local pad = ns.IsGamepadActive()
    if frame and frame:IsShown() and not closing then
        -- The browser is a gamepad-only view: it closes if the gamepad interface is switched off.
        if not pad then Auction.Close(true)
        else
            PlaceOverNative()
            Capture(not KeyboardOpen())
            SetNativeHidden(true)
            ns.AuctionTradeUI.SyncBindings()
        end
    end
    if not pad or not Data.active or not ns.db or not ns.db.enabled then if launcher then launcher:Hide() end return end
    if not launcher then
        launcher = ns.Skin.CreateKey(UIParent)
        launcher:SetFrameStrata("DIALOG")
        launcher:SetSize(210, 32)
        launcher:SetPoint("TOP", UIParent, "TOP", 0, -110)
        launcher.text:SetText("Gamepad auction browser")
        ns.Skin.StyleKey(launcher, "fn")
        launcher:SetScript("OnClick", Auction.Open)
    end
    launcher:SetShown(not (frame and frame:IsShown()))
end)
