local ADDON, ns = ...

-- Read/query adapter. Transactions live in AuctionTransactions.lua.
-- The auction cache is shared with Blizzard and other addons; external queries
-- invalidate our view instead of silently relabeling someone else's results.
local Data = { rows = {}, query = "", page = 0, mode = "browse", active = false }
ns.AuctionData = Data
local ownQuery = false
local hooked = {}
local function Changed()
    if Data.changed then Data.changed() end
end
local function Call(fn, ...)
    ownQuery = true
    local ok, err = pcall(fn, ...)
    ownQuery = false
    if not ok then
        Data.busy, Data.mode, Data.rows, Data.more = false, "invalid", {}, false
        Data.message = "Auction request failed. Retry or use the native window."
        ns.Print("Auction API: " .. tostring(err))
        Changed()
    end
    return ok
end
function Data.Detect()
    if AuctionFrame and AuctionFrame:IsShown() and QueryAuctionItems and GetAuctionItemInfo then return "legacy" end
    if C_AuctionHouse and C_AuctionHouse.SendBrowseQuery and C_AuctionHouse.GetBrowseResults then return "modern" end
    if QueryAuctionItems and GetAuctionItemInfo then return "legacy" end
end
function Data.Ready()
    if not Data.active or InCombatLockdown() then Data.message = "Visit an auctioneer outside combat." Changed() return false end
    if Data.busy then return false end
    if Data.backend == "legacy" and CanSendAuctionQuery and not CanSendAuctionQuery("list") then
        Data.message = "Auction house is busy. Try again shortly." Changed() return false
    end
    if Data.backend == "modern" and C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        Data.message = "Auction house is busy. Try again shortly." Changed() return false
    end
    return Data.backend ~= nil
end
-- A search setting changed without a query being sent: drop the rows that no longer match it
-- and wait for an explicit Search.
function Data.Invalidate(message)
    if Data.busy then return false end
    Data.mode, Data.rows, Data.more, Data.itemKey, Data.page = "browse", {}, false, nil, 0
    Data.message, Data.pending, Data.searched = message, true, false
    Changed()
    return true
end
local function Begin(mode)
    Data.pending = false
    Data.mode, Data.busy, Data.started = mode, true, GetTime()
    Data.message, Data.rows, Data.more = "Searching...", {}, false
    Changed()
end
function Data.Search(text, page)
    if not Data.Ready() then
        -- A changed filter/search must not leave unrelated old rows visible.
        if not Data.busy then Data.mode, Data.rows, Data.more = "invalid", {}, false Changed() end
        return false
    end
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #text > 63 then Data.message = "Search is too long (63 bytes maximum)." Changed() return false end
    Data.query, Data.page, Data.itemKey = text, page or 0, nil
    Data.searched = true
    Begin("browse")
    ns.NoteWrite(nil, "Auction browse query (" .. Data.backend .. ")")
    local ok
    if Data.backend == "modern" then
        ok = Call(C_AuctionHouse.SendBrowseQuery, ns.AuctionFilters.Query(text))
    else
        local usable, exact, classes = ns.AuctionFilters.Legacy()
        ok = Call(QueryAuctionItems, text, ns.AuctionFilters.minLevel, ns.AuctionFilters.maxLevel, Data.page, usable, nil, false, exact, classes)
    end
    return ok
end
function Data.Details(row)
    if not row or not row.itemKey or Data.backend ~= "modern" then return false end
    if not C_AuctionHouse.SendSearchQuery or not Data.Ready() then return false end
    Data.itemKey, Data.itemName = row.itemKey, row.name
    Begin("details")
    ns.NoteWrite(nil, "Auction item listing query")
    return Call(C_AuctionHouse.SendSearchQuery, Data.itemKey, {}, false)
end
function Data.More()
    if not Data.more or not Data.Ready() then return false end
    if Data.backend == "legacy" then return Data.Search(Data.query, Data.page + 1) end
    if Data.mode ~= "browse" or not C_AuctionHouse.RequestMoreBrowseResults then return false end
    Data.busy, Data.started, Data.message = true, GetTime(), "Loading more results..."
    Changed()
    return Call(C_AuctionHouse.RequestMoreBrowseResults)
end
function Data.Owned()
    if not Data.Ready() then return false end
    Data.itemKey = nil
    Begin("owned")
    ns.NoteWrite(nil, "Owned auction query")
    if Data.backend == "modern" then
        if not C_AuctionHouse.QueryOwnedAuctions then Data.busy = false Data.message = "Owned auctions unavailable on this client." Changed() return false end
        return Call(C_AuctionHouse.QueryOwnedAuctions, {})
    end
    if GetOwnerAuctionItems then return Call(GetOwnerAuctionItems) end
    Data.busy = false
    Data.message = "Owned auctions unavailable on this client."
    Changed()
    return false
end
local function ItemName(link, fallback)
    return link and link:match("%[(.-)%]") or fallback or "Loading item..."
end
local function ModernRows()
    local api, rows = C_AuctionHouse, {}
    if Data.mode == "browse" then
        -- Each result's required level: the Level column, its sort, and the level range filter
        -- (see AuctionFilters.Query). With the range set, an item whose data is not loaded yet is
        -- left out until it arrives (levelWaiting); without it, the item is listed with its level
        -- blank (levelMissing). Either way the results are read again as the data arrives.
        local filters = ns.AuctionFilters
        local byLevel = filters.LevelActive()
        Data.levelWaiting, Data.levelMissing = 0, 0
        for _, r in ipairs(api.GetBrowseResults() or {}) do
            local keep = true
            local required = filters.RequiredLevel(r.itemKey.itemID)
            if required == nil then
                if byLevel then Data.levelWaiting = Data.levelWaiting + 1 keep = false
                else Data.levelMissing = Data.levelMissing + 1 end
            elseif byLevel then keep = filters.LevelMatches(required) end
            local info = keep and api.GetItemKeyInfo(r.itemKey)
            if keep then rows[#rows + 1] = { name = info and info.itemName or ("Item " .. r.itemKey.itemID),
                itemKey = r.itemKey, link = info and (info.battlePetLink or info.appearanceLink),
                itemID = r.itemKey.itemID, icon = info and info.iconFileID, quality = info and info.quality,
                count = r.totalQuantity, price = r.minPrice, priceLabel = "From", summary = "Select to view listings.",
                required = required, level = required and required > 0 and required or nil,
                itemLevel = (r.itemKey.itemLevel or 0) > 0 and r.itemKey.itemLevel or nil }
            rows[#rows].identity = table.concat({ r.itemKey.itemID, r.itemKey.itemLevel or 0, r.itemKey.itemSuffix or 0, r.itemKey.battlePetSpeciesID or 0 }, ":")
            end
        end
        if filters.sort == "Level" then filters.SortByLevel(rows) end
        Data.more = api.HasFullBrowseResults and not api.HasFullBrowseResults() or false
    elseif Data.mode == "details" and Data.itemKey then
        local key = Data.itemKey
        local info = api.GetItemKeyInfo(key)
        if not info then return rows end
        local commodity = info.isCommodity
        local count = commodity and api.GetNumCommoditySearchResults(key.itemID) or api.GetNumItemSearchResults(key)
        for i = 1, count do
            local r = commodity and api.GetCommoditySearchResultInfo(key.itemID, i) or api.GetItemSearchResultInfo(key, i)
            if r then
                rows[#rows + 1] = { name = info.itemName, link = r.itemLink, itemID = key.itemID,
                    icon = info.iconFileID, quality = info.quality, count = r.quantity,
                    price = commodity and r.unitPrice or r.buyoutAmount,
                    priceLabel = commodity and "Each" or "Buyout", bid = r.minBid,
                    auctionID = r.auctionID, commodity = commodity, itemKey = key,
                    owned = r.containsOwnerItem or r.containsAccountItem,
                    summary = "Seller: " .. table.concat(r.owners or {}, ", "), identity = r.auctionID }
            end
        end
    elseif Data.mode == "owned" then
        for i = 1, api.GetNumOwnedAuctions() do
            local r = api.GetOwnedAuctionInfo(i)
            if r then
                local info = api.GetItemKeyInfo(r.itemKey)
                -- Sold auctions stay in the list until their gold is mailed; timeLeftSeconds then
                -- counts down to that delivery.
                local sold = r.status == (Enum and Enum.AuctionStatus and Enum.AuctionStatus.Sold or 1)
                rows[#rows + 1] = { name = ItemName(r.itemLink, info and info.itemName), link = r.itemLink,
                    itemID = r.itemKey.itemID, icon = info and info.iconFileID, quality = info and info.quality,
                    count = r.quantity, price = r.buyoutAmount, priceLabel = sold and "Sold for" or "Buyout", bid = r.bidAmount,
                    auctionID = r.auctionID, status = r.status, sold = sold or nil,
                    mailIn = sold and r.timeLeftSeconds or nil, readAt = GetTime(),
                    summary = sold and "This auction has sold. Its gold is being sent to your mailbox." or
                        "Your auction. Select to review cancellation and any fee.", identity = r.auctionID }
            end
        end
    end
    return rows
end
local function LegacyRows()
    local kind = Data.mode == "owned" and "owner" or "list"
    local count, total = GetNumAuctionItems(kind)
    Data.more = kind == "list" and (Data.page + 1) * 50 < (total or count)
    local rows = {}
    for i = 1, count do
        local name, icon, quantity, quality, _, _, _, minBid, _, buyout, bid, _, _, owner, _, saleStatus = GetAuctionItemInfo(kind, i)
        local link = GetAuctionItemLink and GetAuctionItemLink(kind, i)
        -- The old auction house marks a sold listing of yours with saleStatus 1; it gives no mail time.
        local sold = kind == "owner" and saleStatus == 1 or nil
        rows[#rows + 1] = { name = name or ItemName(link), link = link, icon = icon, quality = quality,
            count = quantity, price = buyout and buyout > 0 and buyout or nil, priceLabel = "Stack buyout",
            bid = bid and bid > 0 and bid or minBid, sold = sold,
            summary = sold and "This auction has sold. Its gold is being sent to your mailbox." or ("Seller: " .. (owner or "unknown")),
            identity = kind .. ":" .. i .. ":" .. (link or name or "") }
    end
    return rows
end
function Data.Read()
    local ok, rows = pcall(Data.backend == "modern" and ModernRows or LegacyRows)
    Data.busy = false
    if ok then
        Data.rows = rows
        Data.message = #rows == 0 and "No results." or (#rows .. " results loaded")
        if Data.mode == "browse" and (Data.levelWaiting or 0) > 0 then
            Data.message = (#rows == 0 and "Checking" or (#rows .. " results loaded, checking")) .. " required levels..."
        end
        if ns.AuctionTransactions and Data.mode == "details" then ns.AuctionTransactions.MarketUpdated(rows,Data.itemKey) end
    else
        Data.rows, Data.message = {}, "This client returned an unsupported auction result. Use the native window."
        ns.Print("Auction results: " .. tostring(rows))
    end
    Changed()
end
local function Invalidate()
    if ownQuery or not Data.active then return end
    -- Nothing searched here yet (e.g. Blizzard's own query as its window opens): nothing to invalidate.
    if Data.mode == "browse" and not Data.searched and not Data.busy then return end
    if ns.AuctionTransactions then ns.AuctionTransactions.SearchChanged() end
    Data.busy, Data.mode, Data.rows, Data.more = false, "invalid", {}, false
    Data.message = "Search changed in another window. Search again here."
    Changed()
end
function Data.HookQueries()
    if not hooksecurefunc then return end
    for _, name in ipairs({ "QueryAuctionItems", "GetOwnerAuctionItems" }) do
        if _G[name] and not hooked[name] then hooksecurefunc(name, Invalidate) hooked[name] = true end
    end
    for _, name in ipairs({ "SendBrowseQuery", "SendSearchQuery", "SendSellSearchQuery", "SearchForItemKeys", "SearchForFavorites", "QueryOwnedAuctions" }) do
        if C_AuctionHouse and C_AuctionHouse[name] and not hooked[name] then
            hooksecurefunc(C_AuctionHouse, name, Invalidate) hooked[name] = true
        end
    end
end
local events = CreateFrame("Frame")
for _, event in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_ITEM_LIST_UPDATE", "AUCTION_OWNED_LIST_UPDATE",
    "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED", "OWNED_AUCTIONS_UPDATED", "ITEM_KEY_ITEM_INFO_RECEIVED",
    "GET_ITEM_INFO_RECEIVED" }) do
    pcall(events.RegisterEvent, events, event)
end
-- Item data arriving for a required level: the browse results are read again once the burst
-- settles (one item arrives per event, often dozens in a row).
local levelReadPending = false
local function LevelsPending() return (Data.levelWaiting or 0) + (Data.levelMissing or 0) > 0 end
local function LevelDataArrived()
    if levelReadPending or not LevelsPending() then return end
    levelReadPending = true
    C_Timer.After(0.25, function()
        levelReadPending = false
        if Data.active and not Data.busy and Data.mode == "browse" and Data.searched and LevelsPending() then
            Data.Read()
        end
    end)
end
events:SetScript("OnEvent", function(_, event, key)
    if event == "GET_ITEM_INFO_RECEIVED" then LevelDataArrived() return end
    if event == "AUCTION_HOUSE_SHOW" then
        Data.active, Data.backend = true, Data.Detect()
        Data.busy, Data.mode, Data.rows, Data.searched, Data.pending = false, "browse", {}, false, false
        Data.message = "Type a name or pick a category to the left to view listed items."
        Data.HookQueries()
        if ns.Auction then ns.Auction.OnVisit() end
        return
    elseif event == "AUCTION_HOUSE_CLOSED" then
        Data.active, Data.busy, Data.rows = false, false, {}
        if ns.Auction then ns.Auction.Close(true) end
        return
    end
    if not Data.active then return end
    -- Browse results are shown only for a search the player made here. Blizzard's window runs its
    -- own browse query when it opens; those results are not this browser's to show.
    if Data.mode == "browse" and (event == "AUCTION_ITEM_LIST_UPDATE" or event:find("AUCTION_HOUSE_BROWSE_RESULTS_", 1, true)) then
        if Data.searched then Data.Read() end
    elseif Data.mode == "owned" and (event == "OWNED_AUCTIONS_UPDATED" or event == "AUCTION_OWNED_LIST_UPDATE") then
        Data.Read()
    elseif Data.mode == "details" and Data.itemKey then
        local sameKey = type(key) == "table" and key.itemID == Data.itemKey.itemID and key.itemLevel == Data.itemKey.itemLevel
            and key.itemSuffix == Data.itemKey.itemSuffix and key.battlePetSpeciesID == Data.itemKey.battlePetSpeciesID
        if (event:find("COMMODITY_SEARCH_RESULTS_", 1, true) and key == Data.itemKey.itemID)
            or (event:find("ITEM_SEARCH_RESULTS_", 1, true) and sameKey) then Data.Read() end
    end
    if event == "ITEM_KEY_ITEM_INFO_RECEIVED" and not Data.busy and Data.mode ~= "invalid"
        and (Data.mode ~= "browse" or Data.searched) then Data.Read() end
end)
events:SetScript("OnUpdate", function()
    if Data.busy and GetTime() - Data.started > 15 then
        Data.busy, Data.mode, Data.rows = false, "invalid", {}
        Data.message = "Search timed out. Try again."
        Changed()
    end
end)
