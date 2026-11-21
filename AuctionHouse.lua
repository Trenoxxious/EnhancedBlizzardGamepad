local ADDON, ns = ...
local Data = ns.AuctionData
local Style = ns.AuctionStyle
local Auction = {}
ns.Auction = Auction

-- A persistent, addon-owned controller workspace using auction APIs for queries and trades.
local frame, tooltip, launcher
local tab, page, focus = 1, 1, 1
local pendingPage
local tabs = { "Buy", "Sell", "Auctions" } -- tab 1 browses, 2 sells, 3 lists your own auctions
local categories, categoryPage, categoryRows = {}, 1, {}
local filterMode, firstResult = false, 7
local firstCategory, categoryFocus
local categoryFocusID
local lastCategory, lastResult
local expanded = {}
local CategorySelect, ToggleFilters, EditLevel, SortBy
local controls, rows, buttons = {}, {}, {}
local consumed, closing, capturing = {}, false, false
local wasBusy = false -- a search was in progress at the last redraw
local releaseAction
local Refresh, Activate, SwitchTab, SearchInput
-- The keyboard or EBG's settings window is up and has the pad; the browser waits until it closes.
local function KeyboardOpen()
    return (ns.KB and ns.KB.frame:IsShown()) or (ns.Options and ns.Options.IsShown and ns.Options.IsShown()) or false
end
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
-- "Sold" plus the time until the auction's gold reaches the mailbox. The server's countdown was read
-- with the listing (item.mailIn at item.readAt), so it keeps counting down between refreshes.
local function SoldText(item)
    if not item.mailIn then return "Sold" end
    local left = math.max(0, item.mailIn - (GetTime() - (item.readAt or GetTime())))
    if left < 60 then return "Sold" end
    local when = SecondsToTime and SecondsToTime(left, true) or (math.ceil(left / 60) .. " min")
    return "Sold - " .. when
end
Auction.SoldText = SoldText
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
-- Character preview: the focused item tried on a model of your character, in the preview pane in
-- place of its tooltip. R3 switches the pane between the two, and the choice is kept while the
-- browser is open; items that cannot be shown on a character (rings, potions...) always show their
-- tooltip. The model is EBG's own DressUpModel, so Blizzard's dressing room is never opened.
local previewOnCharacter = false
local previewStickX -- right stick turning the model, while the model is shown
local function TryOnLink(item)
    if not item then return end
    local link = item.link
    if type(link) == "string" and link:find("item:%d") then return link end
    if item.itemID then return "item:" .. item.itemID end
end
local function Dressable(item)
    local link = TryOnLink(item)
    if not link then return false end
    local id = item.itemID or tonumber(link:match("item:(%d+)"))
    if C_Item and C_Item.IsDressableItemByID and id then
        local ok, yes = pcall(C_Item.IsDressableItemByID, id)
        if ok then return yes and true or false end
    end
    if IsDressableItem then
        local ok, yes = pcall(IsDressableItem, link)
        if ok then return yes and true or false end
    end
    local equippable = (C_Item and C_Item.IsEquippableItem) or IsEquippableItem
    if equippable then
        local ok, yes = pcall(equippable, link)
        return ok and yes and true or false
    end
    return false
end
-- Comparison: under an equipment tooltip, the item(s) you wear in that slot, each headed
-- "Equipped" and ending with what would change if you swapped (stats from GetItemStats). The
-- slots come from the item's equip location: both rings, both trinkets, both hands for a one-hand
-- weapon, main and off hand for a two-hander.
local COMPARE_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 }, INVTYPE_TABARD = { 19 },
}
local function EquippedFor(item)
    local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local id = item and (item.itemID or (type(item.link) == "string" and tonumber(item.link:match("item:(%d+)"))))
    if not info or not id or not GetInventoryItemLink then return {} end
    local ok, _, _, _, equipLoc = pcall(info, id)
    local out = {}
    for _, slot in ipairs(ok and COMPARE_SLOTS[equipLoc] or {}) do
        local link = GetInventoryItemLink("player", slot)
        if link then out[#out + 1] = { slot = slot, link = link } end
    end
    return out
end
-- What changes if the equipped item is replaced by the new one: stat name and difference, gains
-- first. Stats without a display name (internal keys) are left out.
local function StatDiff(newLink, oldLink)
    local get = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not get or not newLink or not oldLink then return nil end
    local ok1, new = pcall(get, newLink)
    local ok2, old = pcall(get, oldLink)
    if not ok1 or not ok2 then return nil end
    new, old = type(new) == "table" and new or {}, type(old) == "table" and old or {}
    local keys, out = {}, {}
    for k in pairs(new) do keys[k] = true end
    for k in pairs(old) do keys[k] = true end
    for k in pairs(keys) do
        local delta, name = (new[k] or 0) - (old[k] or 0), _G[k]
        if math.abs(delta) > 0.05 and type(name) == "string" then out[#out + 1] = { name = name, delta = delta } end
    end
    table.sort(out, function(a, b)
        if (a.delta > 0) ~= (b.delta > 0) then return a.delta > 0 end
        return a.name < b.name
    end)
    return out
end
Auction.StatDiff = StatDiff
-- The sticks are taken only while the character model is on screen and the browser has the pad:
-- the right stick turns the model, and the left stick is passed on so it still moves you.
local sticks = false
local function StickCapture(want)
    want = want and capturing and frame and frame.model and frame.model:IsShown() and true or false
    if not want then previewStickX = nil end
    if not InCombatLockdown() and frame and sticks ~= want then
        if pcall(frame.EnableGamePadStick, frame, want) then sticks = want end
    end
    -- The turn indicator on the model shows exactly while the right stick can turn it. Its glyph
    -- is bound each time it appears, so it follows the controller in use.
    local hint = frame and frame.model and frame.model.turnHint
    if hint and hint:IsShown() ~= sticks then
        if sticks then
            -- The chat copy's right stick glyph (same atlas, same call). Where the atlas cannot be
            -- found, Blizzard's own icon frame draws the stick instead, as the legend bar's do;
            -- text is the very last resort (Inline still tries Blizzard's drawn icon first).
            local glyph = ns.Glyphs.Apply(hint.stick, "RSTICKMOVE")
            local native = false
            if hint.native then
                native = not glyph and ns.Glyphs.BindNativeIcon(hint.native, "PADRSTICK") or false
                hint.native:SetShown(native)
            end
            hint.text:SetShown(not glyph and not native)
            if not glyph and not native then hint.text:SetText(ns.Glyphs.Inline("PADRSTICK", 24)) end
            hint.lit = nil
        end
        hint:SetShown(sticks)
    end
end
local function Capture(want)
    if InCombatLockdown() or not frame then return end
    if capturing ~= want then
        if ns.NoteAction then ns.NoteAction("auction pad capture " .. (want and "on" or "off")) end
        frame:EnableGamePadButton(want)
        frame:SetPropagateKeyboardInput(true)
        capturing = want
    end
    StickCapture(true)
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
-- While the whole auction house is being closed (Auction.Exit), Blizzard's window stays faded until
-- Blizzard has hidden it, so it never flashes into view on the way out.
local exiting = false
-- Counts browser openings. Delayed work from one visit checks it, so a timer started while leaving
-- the auction house can never act on the browser after the player has walked back and reopened it.
local opened = 0
local function RestoreNative()
    if exiting then
        local visit = opened
        C_Timer.After(0.3, function() if visit == opened then SetNativeHidden(false) end end)
    else SetNativeHidden(false) end
end
local function FinishClose()
    if ns.AuctionTransactions then ns.AuctionTransactions.Close(true) end
    if ns.AuctionTradeUI then ns.AuctionTradeUI.Bind(false) end
    closing = false
    releaseAction = nil
    wipe(consumed)
    Capture(false)
    RestoreNative()
    if frame then frame:SetAlpha(1) frame:Hide() end
end
function Auction.Close(immediate)
    if KeyboardOpen() and ns.KB.target and ns.KB.target.auctionInput then ns.HideKeyboard() end
    if not frame then return end
    RestoreNative()
    if not immediate and next(consumed) and not InCombatLockdown() then
        closing = true
        frame:SetAlpha(0)
        frame:EnableMouse(false)
        local visit = opened
        C_Timer.After(1, function() if closing and visit == opened then FinishClose() end end)
    else FinishClose() end
end
-- Leaving the browser ends the auction house visit: the auctioneer interaction is closed, and
-- Blizzard closes its own window in response (EBG never hides Blizzard's frame itself). In gamepad
-- mode Blizzard's window is therefore never left on screen.
function Auction.Exit()
    -- Never walk away from an auction request the server is still answering.
    local t = ns.AuctionTransactions and ns.AuctionTransactions.current
    if t and t.phase == "sending" then return end
    exiting = true
    local closed = false
    if C_AuctionHouse and C_AuctionHouse.CloseAuctionHouse then closed = pcall(C_AuctionHouse.CloseAuctionHouse) end
    if not closed and C_PlayerInteractionManager and C_PlayerInteractionManager.ClearInteraction
        and Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Auctioneer then
        closed = pcall(C_PlayerInteractionManager.ClearInteraction, Enum.PlayerInteractionType.Auctioneer)
    end
    if not closed and CloseAuctionHouse then closed = pcall(CloseAuctionHouse) end
    if ns.NoteAction then ns.NoteAction("close auction house" .. (closed and "" or " (failed)")) end
    -- AUCTION_HOUSE_CLOSED normally closes the browser; this covers a client that sends no event.
    -- If the auction house was reopened within that second, the new visit is left alone.
    local visit = opened
    C_Timer.After(1, function()
        if visit ~= opened then return end
        if frame and frame:IsShown() and not closing then Auction.Close(true) end
        exiting = false
    end)
    if not closed then exiting = false Auction.Close() end
end
local function Select(index)
    focus = math.max(1, math.min(index, #controls))
    for i, b in ipairs(controls) do
        Style.Paint(b, i == focus)
    end
    local b = controls[focus]
    local item = not filterMode and b and b.item or nil
    -- The preview pane shows the focused item's tooltip (with the equipped item(s) for its slot
    -- underneath, to compare), or (R3) the item on your character, and its quantity; with no item
    -- it fades to a faint outline. The stack of tooltips is scaled down together to fit the pane.
    tooltip:Hide()
    for _, t in ipairs(frame.compare) do t:Hide() end
    local shown, onModel = false, false
    local last = tooltip -- the lowest tooltip shown, for the quantity line
    -- Tooltips draw above every other frame, so the preview's is left out while a trade panel
    -- (sell, buy or cancel) is open over the browser; it returns when the panel closes. The
    -- character model steps aside with it.
    local trading = ns.AuctionTransactions and ns.AuctionTransactions.current
    local dressable = item and not trading and Dressable(item) or false
    if dressable and previewOnCharacter then onModel = Auction.ShowOnCharacter(item) end
    if not onModel and frame.model then frame.model:Hide() frame.model.link = nil end
    StickCapture(true)
    if item and (item.link or item.itemID) and not trading and not onModel then
        tooltip:SetOwner(frame, "ANCHOR_NONE")
        tooltip:SetScale(1)
        tooltip:ClearAllPoints()
        tooltip:SetPoint("TOPLEFT", frame, "TOPLEFT", 790, -104)
        local link = item.link or ("item:" .. item.itemID)
        local ok = pcall(tooltip.SetHyperlink, tooltip, link)
        if ok and (not tooltip.NumLines or tooltip:NumLines() > 0) then
            tooltip:Show()
            shown = true
            local stack = { tooltip }
            -- Equipped item(s) for the same slot, each under an "Equipped" heading, ending with the
            -- stat changes a swap would make (green gains, red losses).
            for i, worn in ipairs(EquippedFor(item)) do
                local t = frame.compare[i]
                if not t then break end
                t:SetOwner(frame, "ANCHOR_NONE")
                t:SetScale(1)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", frame, "TOPLEFT", 790, -104)
                if pcall(t.SetInventoryItem, t, "player", worn.slot) and (not t.NumLines or t:NumLines() > 0) then
                    local diff = StatDiff(TryOnLink(item) or link, worn.link)
                    if diff and #diff > 0 then
                        pcall(t.AddLine, t, " ")
                        pcall(t.AddLine, t, "If you replace this item:", 1, 0.82, 0)
                        for _, d in ipairs(diff) do
                            local amount = d.delta == math.floor(d.delta) and ("%+d"):format(d.delta) or ("%+.1f"):format(d.delta)
                            local r, g, bl = 0.1, 1, 0.1
                            if d.delta < 0 then r, g, bl = 1, 0.15, 0.15 end
                            pcall(t.AddLine, t, amount .. " " .. d.name, r, g, bl)
                        end
                    end
                    t:Show()
                    stack[#stack + 1] = t
                end
            end
            -- One scale for the whole stack, so it fits the pane (280 wide, about 400 tall with the
            -- headings and the gaps between tooltips).
            local GAP = 22 -- room for an "Equipped" heading above each comparison tooltip
            local width, height = 0, 0
            for i, t in ipairs(stack) do
                width = math.max(width, t:GetWidth() or 0)
                height = height + (t:GetHeight() or 0) + (i > 1 and GAP or 0)
            end
            local scale = math.min(1, width > 0 and 280 / width or 1, height > 0 and 400 / height or 1)
            for i, t in ipairs(stack) do
                t:SetScale(scale)
                t:ClearAllPoints()
                if i == 1 then t:SetPoint("TOPLEFT", frame, "TOPLEFT", 790 / scale, -104 / scale)
                else t:SetPoint("TOPLEFT", stack[i - 1], "BOTTOMLEFT", 0, -GAP) end
            end
            last = stack[#stack]
        end
    end
    frame.detailIcon:SetShown(item and not shown and not onModel and item.icon ~= nil or false)
    if item and item.icon then frame.detailIcon:SetTexture(item.icon) end
    frame.previewQuantity:SetText(item and item.count and ("Quantity: " .. Quantity(item.count)) or "")
    frame.previewQuantity:ClearAllPoints()
    if onModel then frame.previewQuantity:SetPoint("TOPLEFT", 798, -500)
    elseif shown then frame.previewQuantity:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 6, -8)
    else frame.previewQuantity:SetPoint("TOPLEFT", 798, item and item.icon and -170 or -112) end
    -- R3 is offered only for an item that can be shown on a character (turning is shown on the model).
    local legend = { { "PAD1", "Select" }, { "PADDPAD", "Navigate" } }
    if dressable then legend[#legend + 1] = { "PADRSTICK", onModel and "Tooltip" or "On character" } end
    local key = (dressable and "d" or "") .. (onModel and "m" or "")
    if frame.legendKey ~= key then frame.legendKey = key frame.legendBar:SetItems(legend) end
    frame.detailPane:SetAlpha(item and 1 or 0.25)
end
-- R3, or the middle mouse button (for testing with a mouse; not shown anywhere): the focused item
-- on your character, or back to its tooltip. Only for an item that can be shown on a character,
-- so the switch never happens unseen.
local function CanPreview()
    local b = controls[focus]
    return not filterMode and b and b.item and Dressable(b.item) or false
end
local function TogglePreview()
    if not CanPreview() then return end
    previewOnCharacter = not previewOnCharacter
    Select(focus)
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
        if not InCombatLockdown() and not KeyboardOpen() and not closing and not self.disabled then Style.Press(self) self.action() end
    end)
    -- Middle-clicking a row does what R3 does. (OnClick only hears the left button.)
    b:SetScript("OnMouseUp", function(self, button)
        if button ~= "MiddleButton" or not self.item or InCombatLockdown() or KeyboardOpen() or closing then return end
        for i, control in ipairs(controls) do if control == self then Select(i) break end end
        TogglePreview()
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
    -- The title bar runs flush along the top inner edge of the border.
    frame.titleBand = Style.Band(frame, 0, 0, 1, 32)
    ns.Skin.DockBar(frame.titleBand, frame, "TOP", 32)
    frame.categoryPane = Style.Pane(frame, 18, -92, 184, 448, "categories")
    frame.resultPane = Style.Pane(frame, 214, -174, 548, 304, "results")
    frame.detailPane = Style.ShowcasePane(frame, 778, -92, 304, 448)
    Style.Band(frame, 215, -175, 546, 26)
    local function Label(font, x, y, width, text)
        local label = frame:CreateFontString(nil, "OVERLAY", font)
        label:SetPoint("TOPLEFT", x, y)
        label:SetWidth(width)
        label:SetJustifyH("LEFT")
        label:SetText(text or "")
        return label
    end
    frame.title = Label("GameFontNormalLarge", 28, -20, 600, "Auction House")
    frame.title:ClearAllPoints()
    frame.title:SetPoint("LEFT", frame.titleBand, "LEFT", 14, 0)
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
    -- The bumpers that switch tabs, right of the last tab (filled in by Refresh).
    frame.tabHint = Label("GameFontHighlight", 22 + #tabs * 142 - 2, -563, 80, "")
    frame.tabHint:SetHeight(26)
    frame.tabHint:SetJustifyV("MIDDLE")
    frame.search = Button("Search", 222, -134, 294, 30, function() SearchInput() end, "search", "toolbar")
    frame.search.text:SetJustifyH("LEFT")
    frame.search.text:SetFontObject(GameFontHighlightMedium)
    -- The field is drawn like the keyboard's text strip: the same skin art sits just below the button.
    frame.search:SetFrameLevel(frame:GetFrameLevel() + 4)
    frame.search.inset = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    -- Sized explicitly: the skin reads the height to size its art, before any layout pass.
    frame.search.inset:SetPoint("TOPLEFT", frame.search, "TOPLEFT")
    frame.search.inset:SetSize(294, 30)
    frame.search.inset:SetFrameLevel(frame:GetFrameLevel() + 3)
    -- The Square glyph is a real icon at the left of the field, not inline text, so it can be large
    -- (bound in Refresh, so it follows controller changes).
    frame.search.glyphNative = ns.Glyphs.CreateNativeIcon(frame.search) or nil
    if frame.search.glyphNative then
        frame.search.glyphNative:SetSize(28, 27)
        frame.search.glyphNative:SetPoint("LEFT", 6, 0)
    end
    frame.search.glyphIcon = frame.search:CreateTexture(nil, "OVERLAY")
    frame.search.glyphIcon:SetSize(26, 26)
    frame.search.glyphIcon:SetPoint("LEFT", 7, 0)
    frame.search.glyphIcon:Hide()
    frame.refresh = Button("Search", 642, -134, 112, 30, function()
        if filterMode then filterMode, page = false, 1 end
        if tab == 3 then Data.Owned() elseif tab == 1 then Data.Search(Data.query, Data.page) else Refresh() end
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
    -- The preview pane holds only the item's tooltip and its quantity. Its icon stands in for the
    -- tooltip when the client cannot build one for the item.
    frame.detailIcon = frame:CreateTexture(nil, "OVERLAY")
    frame.detailIcon:SetPoint("TOPLEFT", 798, -112)
    frame.detailIcon:SetSize(48, 48)
    frame.detailIcon:Hide()
    frame.previewQuantity = Label("GameFontNormalLarge", 794, -170, 272)
    frame.previewQuantity:SetHeight(28)
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
        -- Second line under the name: "Sold" and when the gold reaches the mailbox.
        b.note = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        b.note:SetPoint("LEFT", 180, -8)
        b.note:SetWidth(262)
        b.note:SetJustifyH("LEFT")
        b.note:SetWordWrap(false)
        b.note:Hide()
        buttons[i] = b
    end
    -- The character preview (R3): EBG's own DressUpModel over the preview pane, hidden until asked
    -- for. Dragging it with the mouse or holding the right stick turns it.
    local okModel, model = pcall(CreateFrame, "DressUpModel", nil, frame)
    if okModel and model then
        model:SetPoint("TOPLEFT", 786, -100)
        model:SetSize(288, 390)
        model:SetFrameLevel(frame:GetFrameLevel() + 2)
        model:EnableMouse(true)
        model:Hide()
        model.facing = 0
        model:SetScript("OnMouseDown", function(self, button) if button == "LeftButton" then self.dragX = GetCursorPosition() end end)
        model:SetScript("OnMouseUp", function(self, button)
            self.dragX = nil
            -- Middle-clicking the model itself also returns to the tooltip, as R3 does.
            if button == "MiddleButton" and not InCombatLockdown() and not KeyboardOpen() then TogglePreview() end
        end)
        model:SetScript("OnHide", function(self) self.dragX = nil end)
        model:SetScript("OnUpdate", function(self, dt)
            local turn = 0
            if self.dragX then
                local x = GetCursorPosition()
                turn, self.dragX = (x - self.dragX) * 0.015, x
            end
            if previewStickX then turn = turn + previewStickX * dt * 3 end
            -- The indicator's arrow on the side being turned toward lights up.
            local hint = self.turnHint
            if hint and hint:IsShown() then
                local lit = previewStickX and (previewStickX < 0 and -1 or 1) or 0
                if hint.lit ~= lit then
                    hint.lit = lit
                    for side, arrow in pairs({ [-1] = hint.left, [1] = hint.right }) do
                        if side == lit then arrow:SetVertexColor(1, 0.82, 0.35) arrow:SetAlpha(1)
                        else arrow:SetVertexColor(1, 1, 1) arrow:SetAlpha(0.7) end
                    end
                end
            end
            if turn ~= 0 then
                self.facing = self.facing + turn
                pcall(self.SetFacing, self, self.facing)
            end
        end)
        -- The model loads after SetUnit; the item is tried on again once it has.
        pcall(model.SetScript, model, "OnModelLoaded", function(self)
            pcall(self.SetFacing, self, self.facing)
            if self.link then pcall(self.Dress, self) pcall(self.TryOn, self, self.link) end
        end)
        -- Turn indicator, bottom centre of the model: the right stick glyph between a left and a
        -- right arrow. Shown only while the right stick turns the model (see StickCapture).
        local hint = CreateFrame("Frame", nil, model, "BackdropTemplate")
        hint:SetSize(92, 32)
        hint:SetPoint("BOTTOM", model, "BOTTOM", 0, 4)
        hint:SetFrameLevel(model:GetFrameLevel() + 2)
        hint.bg = hint:CreateTexture(nil, "BACKGROUND")
        hint.bg:SetAllPoints()
        hint.bg:SetColorTexture(0, 0, 0, 0.55)
        hint.stick = hint:CreateTexture(nil, "ARTWORK")
        hint.stick:SetSize(26, 26)
        hint.stick:SetPoint("CENTER")
        hint.native = ns.Glyphs.CreateNativeIcon(hint) or nil
        if hint.native then
            hint.native:SetSize(26, 25)
            hint.native:SetPoint("CENTER")
            hint.native:Hide()
        end
        hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint.text:SetPoint("CENTER")
        hint.left = hint:CreateTexture(nil, "ARTWORK")
        hint.left:SetSize(24, 24)
        hint.left:SetPoint("RIGHT", hint.stick, "LEFT", -4, 0)
        hint.left:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
        hint.right = hint:CreateTexture(nil, "ARTWORK")
        hint.right:SetSize(24, 24)
        hint.right:SetPoint("LEFT", hint.stick, "RIGHT", 4, 0)
        hint.right:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        hint:Hide()
        model.turnHint = hint
        frame.model = model
    end
    -- Sortable column headers, as in Blizzard's results list: press one to sort by it, press it
    -- again to reverse. Req. Level (the level required to use the item) appears for gear.
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
    frame.sortLevel = Header("Level", "Req. Level", 584, 74, "RIGHT") -- the level required to use the item
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
    frame.native = Button("Close auction house", 898, -558, 178, 34, function() Auction.Exit() end, "secondary", "utility")
    -- Settings: a small gear key beside Close, reached by moving left from Close. The window
    -- takes the pad while it is open; the browser takes it back on its next tick after it closes.
    frame.settings = Button("", 854, -558, 36, 34, function()
        if not ns.Options or not ns.Options.Open then return end
        Capture(false)
        wipe(consumed)
        releaseAction = nil
        ns.Options.Open()
    end, "secondary", "utility")
    frame.settings.icon = frame.settings:CreateTexture(nil, "OVERLAY")
    frame.settings.icon:SetSize(20, 20)
    frame.settings.icon:SetPoint("CENTER", 0, 0)
    if not (ns.SetGearIcon and ns.SetGearIcon(frame.settings.icon)) then
        frame.settings.icon:Hide()
        frame.settings.text:SetText("Set")
    end
    frame.page = Label("GameFontDisableSmall", 434, -518, 322)
    -- frame.note = Label("GameFontDisableSmall", 30, -638, 1030,
    --     "Select a listing to buy or bid. Sell lists auctionable bag items. Every transaction requires confirmation.")
    -- The same legend bar as the keyboard's. Shortcuts that belong to a button are shown on that
    -- button (Search, tabs, paging, Back...); the bar keeps only inputs with no button of their own.
    -- It runs flush along the bottom inner edge of the border.
    frame.legendBar = ns.Glyphs.CreateLegendBar(frame)
    ns.Skin.DockBar(frame.legendBar, frame, "BOTTOM")
    tooltip = CreateFrame("GameTooltip", "EBGAuctionItemTooltip", frame, "GameTooltipTemplate")
    tooltip:SetClampedToScreen(true)
    -- The comparison tooltips under the item's own (see Select), each with its "Equipped" heading
    -- drawn just above its top edge.
    frame.compare = {}
    for i = 1, 2 do
        local t = CreateFrame("GameTooltip", "EBGAuctionCompareTooltip" .. i, frame, "GameTooltipTemplate")
        t:SetClampedToScreen(true)
        t.heading = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t.heading:SetPoint("BOTTOMLEFT", t, "TOPLEFT", 6, 3)
        t.heading:SetText("Equipped")
        t:Hide()
        frame.compare[i] = t
    end
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
            releaseAction = b and not b.disabled and { key, function() Style.Press(b) b.action() end } or nil
        elseif key == "PAD3" then releaseAction = { key, SearchInput }
        elseif key == "PAD4" then releaseAction = { key, frame.refresh.action }
        elseif key == "PADRSTICK" then
            if CanPreview() then releaseAction = { key, TogglePreview } end
        elseif key == "PAD2" then
            releaseAction = { key, function()
                if filterMode then filterMode, page = false, 1 Refresh()
                elseif tab == 1 and Data.mode == "details" then Data.Search(Data.query) else Auction.Exit() end
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
    -- Sticks reach the browser only while the character model is shown (StickCapture): the right
    -- stick turns the model; the left stick goes on to the game, so it still moves you.
    -- Only the left stick (and the "Movement" stick the game derives from it) is passed on; the
    -- right stick and anything the game derives from it (camera) stay here, so turning the model
    -- never swings the camera as well.
    frame:SetScript("OnGamePadStick", function(self, stick, x)
        if InCombatLockdown() then return end
        if stick == "Left" or stick == "Movement" then self:SetPropagateKeyboardInput(true) return end
        self:SetPropagateKeyboardInput(false)
        if stick == "Right" then
            previewStickX = self.model and self.model:IsShown() and math.abs(x or 0) >= 0.2 and x or nil
        end
    end)
    frame:SetScript("OnHide", function() Auction.HidePreview() end)
end
-- The focused item on a model of your character: dressed in what you wear, then the item tried on.
-- The model is set to your character once per browser opening (so gear changed since is shown).
function Auction.ShowOnCharacter(item)
    local m = frame and frame.model
    local link = TryOnLink(item)
    if not m or not link then return false end
    if not m.unitSet then
        m:Show() -- a hidden model may not load its unit
        if not pcall(m.SetUnit, m, "player") then m:Hide() return false end
        m.unitSet = true
        pcall(m.SetFacing, m, m.facing)
    elseif m:IsShown() and m.link == link then
        return true -- already wearing it (a redraw, not a new item): no re-dress flicker
    end
    m:Show()
    m.link = link
    pcall(m.Dress, m)
    return pcall(m.TryOn, m, link) and true or false
end
-- The glyph family changed (Button glyphs setting): redraw the glyphs on the browser's keys, its
-- legend and search field (Refresh), and the turn indicator the next time it shows.
function Auction.RefreshGlyphs()
    if not frame then return end
    for _, b in ipairs({ frame.refresh, frame.back, frame.filterApply, frame.previous, frame.next, frame.native }) do
        if b and b.glyphButton then Style.Glyph(b, b.glyphButton) end
    end
    local hint = frame.model and frame.model.turnHint
    if hint and hint:IsShown() then hint:Hide() StickCapture(true) end
    Refresh()
end
-- Hides the tooltip and the character model (a trade panel opening over the browser, or closing).
function Auction.HidePreview()
    if tooltip then tooltip:Hide() end
    for _, t in ipairs(frame and frame.compare or {}) do t:Hide() end
    if frame and frame.model then frame.model:Hide() frame.model.link = nil end
    StickCapture(false)
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
    elseif (tab == 3 and Data.mode == "owned") or (tab == 1 and Data.mode ~= "owned") then rows = Data.rows end
    if pendingPage and not Data.busy then page, pendingPage = pendingPage, nil end
    page = math.max(1, math.min(page, math.max(1, math.ceil(#rows / 7))))
    controls = {}
    for i, b in ipairs(frame.tabButtons) do b.active = tab == i controls[#controls + 1] = b end
    frame.back:SetShown(filterMode or details)
    if filterMode or details then controls[#controls + 1] = frame.back end
    frame.search:SetShown(tab == 1 and not filterMode)
    frame.search.inset:SetShown(frame.search:IsShown())
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
        (filterMode and "Change the options you need, then Apply search.\n\nFilters affect auction searches. Level means the level required to use the item; 0 means any." or
        (tab == 2 and "Auctionable items in your bags.\n\nChoose an item, set quantity and price, then review its deposit before posting." or
        "Your listed auctions.\n\nSelect a listing to review cancellation and any fee.\n\nSold auctions are greyed out until their gold reaches your mailbox.")))
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
    frame.legendKey = nil -- the legend bar is redrawn by Select below (glyphs follow controller changes)
    -- Glyphs on the buttons their controller shortcut presses.
    local function Mark(b, button) if b.glyphButton ~= button then Style.Glyph(b, button) end end
    -- LB / RB switch tabs: shown once, beside the tab row, so the tabs themselves never shift.
    frame.tabHint:SetText(ns.Glyphs.Inline("PADLSHOULDER", 26) .. " " .. ns.Glyphs.Inline("PADRSHOULDER", 26))
    Mark(frame.previous, "PADLTRIGGER")
    Mark(frame.next, "PADRTRIGGER")
    -- B closes the browser (showing Blizzard's window) unless a Back button is on screen.
    Mark(frame.native, not (filterMode or details) and "PAD2" or nil)
    frame.categorySummary:SetText(ns.Glyphs.Legend("PADDRIGHT", "Results") .. "\n" .. ns.Glyphs.Legend({ "PADLTRIGGER", "PADRTRIGGER" }, "Result pages"))
    -- Sort headers: browse results on the modern auction house, which sorts on the server.
    local sortable = tab == 1 and not filterMode and not details and Data.backend == "modern"
    local showLevel = false
    if sortable then
        showLevel = ns.AuctionFilters.IsEquipment() or ns.AuctionFilters.sort == "Level"
        for _, r in ipairs(rows) do if r.level then showLevel = true break end end
    end
    frame.sortLevel.hidden = not showLevel
    frame.sortName:SetWidth(showLevel and 220 or 300)
    frame.sortName.w = showLevel and 220 or 300
    for _, h in ipairs(frame.sortHeaders) do
        local shown = sortable and not h.hidden
        h:SetShown(shown)
        if shown then
            h.active = ns.AuctionFilters.sort == h.sortKey
            h.text:SetText(h.label)
            h.arrow:SetShown(h.active)
            if ns.AuctionFilters.Descending() then h.arrow:SetTexCoord(0, 0.5625, 1, 0) else h.arrow:SetTexCoord(0, 0.5625, 0, 1) end
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
        local headings = { { "Required level", 226, -186 } }
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
    local search = frame.search
    search.placeholder = Data.query == ""
    -- Same art as the keyboard's text strip; re-applied only when the skin choice changes.
    local skinKey = tostring(ns.db and ns.db.skin) .. "/" .. tostring(ns.db and ns.db.entryBox)
    if search.skinKey ~= skinKey and ns.Skin and ns.Skin.Inset then
        search.skinKey = skinKey
        search.insetKind = ns.Skin.Inset(search.inset)
    end
    -- Square: a native icon when the client has one, else the glyph atlas, else inline text.
    local hasGlyph = search.glyphNative and ns.Glyphs.BindNativeIcon(search.glyphNative, "PAD3")
    if search.glyphNative then search.glyphNative:SetShown(hasGlyph and true or false) end
    if hasGlyph then search.glyphIcon:Hide()
    else hasGlyph = ns.Glyphs.Apply(search.glyphIcon, "PAD3") end
    local text = Data.query == "" and "Search by item name..." or Escape(Data.query)
    search.text:SetText(hasGlyph and text or ns.Glyphs.Legend("PAD3", text, 26))
    search.text:ClearAllPoints()
    search.text:SetPoint("LEFT", hasGlyph and 40 or 12, 0)
    search.text:SetWidth(hasGlyph and 242 or 270)
    search.text:SetWordWrap(false)
    local status = (tab == 2 and (#rows .. " auctionable item types - select to sell")) or Data.message or "Ready"
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
        ({"Browse auctions", "Sell an item", "Your auctions"})[tab]))
    local hint = filterMode and "Choose options, then apply your search" or
        (details and "Compare individual listings • Back returns to your search" or
        (tab == 1 and (Data.query ~= "" and ('Results for "' .. Escape(Data.query) .. '"') or "Browse a category or search by item name") or
        ({"", "Choose an item to set price, quantity, and duration", "Review your active and sold listings"})[tab]))
    frame.viewHint:SetText(hint)
    frame.emptyTitle:SetShown(#rows == 0 and not filterMode)
    frame.emptyHelp:SetShown(#rows == 0 and not filterMode)
    frame.emptyTitle:SetText(Data.busy and "Searching auctions..." or (Data.mode == "invalid" and tab == 1 and "Search unavailable" or
        (Data.message == "No results." and tab == 1 and "No auctions found" or (Data.pending and tab == 1 and "Ready to search" or "Start browsing"))))
    frame.emptyHelp:SetText(tab == 2 and "Unlocked, auctionable items in your bags will appear here." or
        (tab == 3 and "No auctions to display." or (Data.busy and "Results will appear here when the auction house responds." or
        (Data.mode == "invalid" and Data.message or (Data.pending and ("Press Search to list auctions in " .. Escape(CategoryPath()) .. ".") or
        "Choose a category on the left, or enter an item name above.")))))
    frame.quantityHeader:SetText(tab == 2 and "Carried" or
        (tab == 3 and "Listed" or (Data.backend == "legacy" and "Stack" or "Available")))
    -- Plain labels where the list cannot be re-sorted; the sort headers replace them otherwise.
    frame.priceHeader:SetShown(not filterMode and not sortable and (tab == 1 or tab == 3))
    frame.quantityHeader:SetShown(not filterMode)
    frame.nameHeader:SetShown(not filterMode and not sortable)
    frame.nameHeader:ClearAllPoints()
    frame.nameHeader:SetPoint("TOPLEFT", tab == 2 and 232 or 400, -182)
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
            b.price:SetText(item.price and Money(item.price) or ((tab == 1 or tab == 3) and "No buyout" or ""))
            b.quantity:SetText(Quantity(item.count))
            if filterMode then
                b.text:ClearAllPoints()
                b.text:SetPoint("LEFT", 12, 0)
                b.text:SetWidth(516)
            end
            if tab == 2 then
                b.text:ClearAllPoints()
                b.text:SetPoint("LEFT", 44, 0)
                b.text:SetWidth(390)
                b.icon:ClearAllPoints()
                b.icon:SetPoint("LEFT", 10, 0)
            else b.icon:ClearAllPoints() b.icon:SetPoint("LEFT", 146, 0) end
            -- A sold auction stays listed, greyed out like Blizzard's, with the time until its gold
            -- reaches the mailbox under the name.
            b.sold = tab == 3 and item.sold or nil
            if b.sold then
                b.text:ClearAllPoints()
                b.text:SetPoint("LEFT", 180, 7)
                b.note:SetText(SoldText(item))
            end
            b.note:SetShown(b.sold and true or false)
            b.icon:SetDesaturated(b.sold and true or false)
            b.icon:SetAlpha(b.sold and 0.6 or 1)
            local shade = b.sold and 0.5 or 1
            b.price:SetTextColor(shade, shade, shade)
            b.quantity:SetTextColor(shade, shade, shade)
            b.role = filterMode and "option" or "row"
            b.icon:SetShown(not filterMode)
            b.price:SetShown(not filterMode and (tab == 1 or tab == 3))
            b.quantity:SetShown(not filterMode)
            b.action = function() Activate(item) end
            controls[#controls + 1] = b
            if oldIdentity and (item.identity or item.link or item.name) == oldIdentity then focus = #controls end
        end
    end
    lastResult = #controls
    -- The filter page fits on one page, so it has no paging.
    local paged = not filterMode
    frame.previous:SetShown(paged)
    frame.next:SetShown(paged)
    frame.page:SetShown(paged)
    -- Paging keys are greyed out when there is no page in that direction (the same tests as Auction.Page).
    local pages = math.max(1, math.ceil(#rows / 7))
    frame.previous.disabled = Data.busy or not (page > 1 or (tab == 1 and Data.backend == "legacy" and (Data.page or 0) > 0))
    frame.next.disabled = Data.busy or not (page < pages or (tab == 1 and Data.more))
    if paged then
        controls[#controls + 1] = frame.previous
        controls[#controls + 1] = frame.next
    end
    controls[#controls + 1] = frame.settings
    controls[#controls + 1] = frame.native
    frame.page:SetText(("Page %d / %d%s"):format(page, math.max(1, math.ceil(#rows / 7)),
        tab == 1 and not filterMode and Data.more and " - Next loads more" or ""))
    -- When a search finishes, focus moves to the first result (if any), ready for A. A sort header
    -- that was just pressed keeps focus, so it can be pressed again to reverse.
    local justLoaded = wasBusy and not Data.busy
    wasBusy = Data.busy
    local onHeader = controls[focus] and controls[focus].group == "header"
    if justLoaded and not filterMode and not onHeader and (tab == 1 or tab == 3) and lastResult >= firstResult then
        focus = firstResult
    end
    Select(focus)
end
Activate = function(item)
    if filterMode then return -- the filter page uses its own controls
    elseif tab == 2 then
        Auction.HidePreview()
        ns.AuctionTransactions.Open("sell",item)
    elseif tab == 1 and Data.mode == "browse" and item.itemKey then
        if Data.Details(item) then page, focus = 1, firstResult end
        Refresh()
    elseif tab == 1 and Data.mode == "details" then
        Auction.HidePreview()
        ns.AuctionTransactions.Open("buy",item)
    elseif tab == 3 and not item.sold then
        -- A sold auction cannot be cancelled; it only waits for its gold to be mailed.
        Auction.HidePreview()
        ns.AuctionTransactions.Open("cancel",item)
    end
end
SwitchTab = function(index)
    if Data.busy then return end
    pendingPage = nil
    filterMode = false
    tab, page, focus = index, 1, index
    if tab == 3 then Data.Owned()
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
-- Price and Name are sorted by the server, so a new sort re-runs the current search (as Blizzard's
-- headers do). Level (the required level) is sorted here: with every result already loaded the
-- rows are simply re-sorted, with no new query; otherwise the search is re-run, so the server's
-- first loads lean the right way, and the rows are sorted as they are read (see AuctionData).
SortBy = function(key)
    if Data.busy then return end
    local f = ns.AuctionFilters
    if f.sort == key then f.reverse = not f.reverse else f.sort, f.reverse = key, false end
    if tab == 1 and Data.mode == "browse" and #Data.rows > 0 then
        if key == "Level" and not Data.more then
            f.SortByLevel(Data.rows)
            page = 1
        elseif Data.Search(Data.query) then page = 1 end
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
    -- Entry starts at 0 (= any level); the first digit typed replaces it.
    local buffer = ns.Input.NewBuffer(key == "minLevel" and "Minimum required level" or "Maximum required level", "0", function(text)
        local level = tonumber(text == "" and "0" or text)
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
    if frame.model then frame.model.unitSet = nil end -- dress the model in your current gear
    opened = opened + 1
    closing, exiting = false, false
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
            -- Keep the "gold arrives in ..." countdowns on sold auctions current.
            for _, b in ipairs(buttons) do
                if b.sold and b.item and b:IsShown() then b.note:SetText(SoldText(b.item)) end
            end
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
