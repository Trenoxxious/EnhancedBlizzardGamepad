local ADDON, ns = ...
local Data = ns.AuctionData
local Trade = {}
ns.AuctionTransactions = Trade
-- While a press is being turned into an auction call, the panel is not redrawn: the call is made
-- first, straight from the click, the way TradeSkillMaster's Post button does it.
local quiet = false
local function Changed()
    if Trade.current then Trade.current.version = (Trade.current.version or 0)+1 end
    if not quiet and Trade.changed then Trade.changed() end
end
local function Integer(n, minimum)
    return type(n) == "number" and n == math.floor(n) and n >= (minimum or 0) and n <= 99999999999
end
local function Money(n) return ns.Auction.Money(n or 0) end
local function Error(message)
    if Trade.current then Trade.current.message = message end
    Changed()
    return false
end
local function Available()
    return Data.active and Data.backend == "modern" and not InCombatLockdown() and ns.IsGamepadActive()
end
local function Ready()
    if not Available() then return Error("Visit an auctioneer with gamepad enabled, outside combat.") end
    if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
        return Error("Auction house is busy. Try again shortly.")
    end
    return true
end
-- Hiding a Blizzard popup runs Blizzard code from EBG; it is recorded for blocked-action reports.
local function HidePopup(which)
    if ns.NoteAction then ns.NoteAction("StaticPopup_Hide("..which..")") end
    StaticPopup_Hide(which)
end
-- Posting, buying, bidding and cancelling must run inside the player's click or key press. They
-- are called directly by name (no pcall, no stored reference), as TradeSkillMaster calls them.
local function Invoke(name, ...)
    if type(C_AuctionHouse[name]) ~= "function" then return false, "This auction API is unavailable on this client." end
    if ns.NoteAction then ns.NoteAction("C_AuctionHouse."..name..(Trade.pressing and " (in press)" or " (outside a press)")) end
    return true, C_AuctionHouse[name](...)
end
local function Fail(message)
    local t = Trade.current
    if not t then return false end
    t.phase, t.message = "error", message
    Changed()
    return false
end
function Trade.SearchChanged()
    local t = Trade.current
    if t and t.kind == "buy" and t.phase ~= "sending" and t.phase ~= "done" then
        if t.quoteOwned then Invoke("CancelCommoditiesPurchase") t.quoteOwned=false end
        Fail("The auction search changed in another window. Choose the listing again.")
    end
end
local function Copy(source)
    local result = {}
    for k,v in pairs(source) do result[k] = v end
    return result
end
function Trade.Close(force)
    local t = Trade.current
    if not t then return true end
    if t.phase == "sending" and not force then return Error("Waiting for the auction house. This request cannot be cancelled here.") end
    Trade.current = nil
    if t.quoteOwned and t.phase ~= "sending" then Invoke("CancelCommoditiesPurchase") end
    if t.phase == "warning" then Invoke("CancelSell") end
    if t.nativeWarning and StaticPopup_Hide then HidePopup("AUCTION_HOUSE_POST_WARNING") end
    if t.nativeError and StaticPopup_Hide then HidePopup("AUCTION_HOUSE_POST_ERROR") end
    Changed()
    return true
end
function Trade.Open(kind, row)
    if Trade.current or not row then return false end
    if not Available() then ns.Print("Trading requires Forever's modern auction APIs, outside combat. Use the native window on legacy clients.") return false end
    if Data.busy then return false end
    local t = { kind = kind, row = Copy(row), phase = "edit", quantity = 1, duration = 1, buyout = 0, bid = 0 }
    Trade.current = t
    if kind == "sell" then
        t.bag, t.slot, t.link = row.bag, row.slot, row.link
        if not ItemLocation or not C_AuctionHouse.IsSellItemValid then return Fail("Selling is unavailable on this client.") end
        t.location = ItemLocation:CreateFromBagAndSlot(t.bag, t.slot)
        local info = C_Container.GetContainerItemInfo(t.bag, t.slot)
        if not info or info.isLocked or (info.hyperlink or C_Container.GetContainerItemLink(t.bag,t.slot)) ~= t.link
            or not C_AuctionHouse.IsSellItemValid(t.location, false) then return Fail("This bag item cannot be auctioned. It may be locked, bound, or moved.") end
        local status = C_AuctionHouse.GetItemCommodityStatus(t.location)
        if status ~= Enum.ItemCommodityStatus.Commodity and status ~= Enum.ItemCommodityStatus.Item then return Fail("Item data is still loading. Choose this item again shortly.") end
        t.commodity = status == Enum.ItemCommodityStatus.Commodity
        t.maximum = C_AuctionHouse.GetAvailablePostCount(t.location)
        -- Commodities are usually sold as a whole stack; gear one at a time.
        if t.commodity and Integer(t.maximum,1) then t.quantity = t.maximum end
        t.duration = ns.db and Integer(ns.db.auctionDuration,1) and ns.db.auctionDuration <= 3 and ns.db.auctionDuration or 2
        t.itemID = info.itemID
        t.guid = C_Item and C_Item.GetItemGUID and C_Item.GetItemGUID(t.location)
    elseif kind == "buy" then
        t.commodity, t.auctionID, t.itemID = row.commodity, row.auctionID, row.itemID
        t.itemKey = row.itemKey and Copy(row.itemKey)
        t.quantity = t.commodity and 1 or row.count
        t.method = row.price and row.price > 0 and "buyout" or "bid"
        t.bid = row.bid or 0
        if not t.commodity and (not t.auctionID or row.owned) then return Fail("This listing is unavailable or belongs to your account.") end
    elseif kind == "cancel" then
        t.auctionID = row.auctionID
        if not t.auctionID or not C_AuctionHouse.CanCancelAuction(t.auctionID) then return Fail("This auction can no longer be cancelled.") end
    end
    Changed()
    if kind == "sell" then Trade.CompareMarket() end
    return true
end
function Trade.Update(key, value)
    local t = Trade.current
    if not t or t.phase ~= "edit" then return false end
    if key == "method" then
        if value ~= "bid" and value ~= "buyout" then return false end
    elseif not Integer(value) then return Error("Enter a valid whole number.") end
    if key == "buyout" or key == "bid" then t.priceEdited = true end
    if key == "quantity" and value < 1 then return Error("Quantity must be at least 1.") end
    if key == "quantity" and t.kind == "sell" and t.maximum and value > t.maximum then value = t.maximum end
    if key == "duration" then
        if value < 1 or value > 3 then return false end
        if ns.db then ns.db.auctionDuration = value end  -- Blizzard remembers the last duration too.
    end
    t[key], t.message, t.deposit, t.total = value, nil, nil, nil
    Changed()
    return true
end
function Trade.CompareMarket()
    local t = Trade.current
    if not t or t.kind ~= "sell" or t.phase ~= "edit" or not Ready() then return end
    if not C_AuctionHouse.GetItemKeyFromItem then return Error("Market comparison is unavailable on this client.") end
    t.marketKey = C_AuctionHouse.GetItemKeyFromItem(t.location)
    t.marketPrice,t.message,t.marketPending = nil,"Looking up the current price...",true
    if not Data.Details({itemKey=t.marketKey,name=t.row.name}) then
        t.marketPending,t.message = false,"Search is busy. Press Refresh price to look up the current price."
    end
    Changed()
end
function Trade.MarketUpdated(rows,key)
    local t = Trade.current
    if not t or not t.marketKey or not key or t.kind ~= "sell" then return end
    for _,field in ipairs({"itemID","itemLevel","itemSuffix","battlePetSpeciesID"}) do
        if (t.marketKey[field] or 0) ~= (key[field] or 0) then return end
    end
    local lowest
    for _,r in ipairs(rows) do
        if r.price and r.price > 0 then lowest=math.min(lowest or r.price,r.price) end
    end
    t.marketPrice,t.marketPending = lowest,false
    if lowest and not t.priceEdited and t.phase == "edit" then
        -- Like Blizzard's sell frame, the price starts at the current lowest buyout.
        t.buyout,t.deposit,t.message = lowest,nil,nil
    else
        t.message = lowest and "Your entered price has been kept." or "None currently listed. Enter a price to post."
    end
    Changed()
end
local function SellValid(t)
    local info = C_Container.GetContainerItemInfo(t.bag, t.slot)
    if not info or info.isLocked or (info.hyperlink or C_Container.GetContainerItemLink(t.bag,t.slot)) ~= t.link
        or (t.guid and C_Item.GetItemGUID(t.location) ~= t.guid)
        or not C_AuctionHouse.IsSellItemValid(t.location, false) then
        return Error("The selected bag item changed or is locked. Choose it again.")
    end
    if not Integer(t.quantity,1) or t.quantity > C_AuctionHouse.GetAvailablePostCount(t.location) then return Error("That quantity is no longer available in your bags.") end
    if not Integer(t.duration,1) or t.duration > 3 then return Error("Choose an auction duration.") end
    if not Integer(t.buyout) or not Integer(t.bid) then return Error("Enter a valid price.") end
    if t.commodity and t.buyout == 0 then return Error("Set a price per item.") end
    if not t.commodity and (t.buyout == 0 and t.bid == 0 or t.buyout > 0 and t.bid > 0 and t.buyout <= t.bid) then
        return Error("Set a buyout or starting bid. A buyout must exceed the starting bid.")
    end
    if C_AuctionHouse.SupportsCopperValues and not C_AuctionHouse.SupportsCopperValues()
        and (t.buyout % 100 ~= 0 or t.bid % 100 ~= 0) then return Error("This auction house accepts whole silver prices only.") end
    local deposit = t.commodity and C_AuctionHouse.CalculateCommodityDeposit(t.itemID,t.duration,t.quantity)
        or C_AuctionHouse.CalculateItemDeposit(t.location,t.duration,t.quantity)
    if not Integer(deposit) then return Error("Deposit is not available yet. Try again.") end
    if GetMoney() < deposit then return Error("Not enough money for the deposit.") end
    return true, deposit
end
local function Listing(t)
    if Data.mode ~= "details" or not Data.itemKey or not t.itemKey then return end
    for _,field in ipairs({"itemID","itemLevel","itemSuffix","battlePetSpeciesID"}) do
        if (Data.itemKey[field] or 0) ~= (t.itemKey[field] or 0) then return end
    end
    for i=1,C_AuctionHouse.GetNumItemSearchResults(t.itemKey) do
        local r = C_AuctionHouse.GetItemSearchResultInfo(t.itemKey,i)
        if r and r.auctionID == t.auctionID then return r end
    end
end
local function BuyValid(t)
    local r = Listing(t)
    if not r or r.containsOwnerItem or r.containsAccountItem then return Error("Listing changed or is unavailable. Search again.") end
    if r.quantity ~= t.row.count or r.itemLink ~= t.row.link then return Error("Listing contents changed. Search again.") end
    local price = t.method == "buyout" and r.buyoutAmount or t.bid
    if not Integer(price,1) then return Error("This listing has no valid price for that action.") end
    if t.method == "buyout" and price ~= t.row.price then return Error("The buyout changed. Search again before buying.") end
    if t.method == "bid" then
        if not r.minBid or price < r.minBid then return Error("The minimum bid changed. Search again.") end
        if r.buyoutAmount and r.buyoutAmount > 0 and price >= r.buyoutAmount then return Error("Use Buyout to buy this auction immediately.") end
        if r.bidder and UnitGUID and r.bidder == UnitGUID("player") then return Error("You are already the highest bidder.") end
    end
    if GetMoney() < price then return Error("Not enough money for this purchase or bid.") end
    return true,price
end
function Trade.Review()
    local t = Trade.current
    if not t or t.phase ~= "edit" or not Ready() then return false end
    t.message = nil
    if t.kind == "sell" then
        local valid,deposit = SellValid(t)
        if not valid then return false end
        t.deposit = deposit
    elseif t.kind == "buy" and t.commodity then
        if not C_AuctionHouse.GetQuoteDurationRemaining then return Error("Commodity price confirmation is unavailable on this client.") end
        if Data.mode ~= "details" or not Data.itemKey or Data.itemKey.itemID ~= t.itemID then return Error("Search changed. Choose the item again.") end
        if not Integer(t.quantity,1) then return Error("Enter a quantity of at least one.") end
        local ok,err = Invoke("StartCommoditiesPurchase",t.itemID,t.quantity)
        if not ok then return Fail(tostring(err)) end
        t.phase,t.started,t.quoteOwned = "quote",GetTime(),true
        Changed()
        return true
    elseif t.kind == "buy" then
        local valid,price = BuyValid(t)
        if not valid then return false end
        t.total = price
        if AuctionHouseUtil and AuctionHouseUtil.IsAuctionIDUniqueShadowlandsCrafted then
            local unique,category = AuctionHouseUtil.IsAuctionIDUniqueShadowlandsCrafted(t.auctionID)
            if unique then
                t.uniqueReady = GetTime()+3
                t.message = PURCHASE_UNIQUE_AUCTION_CONFIRMATION and PURCHASE_UNIQUE_AUCTION_CONFIRMATION:format(category or "") or "This item has a unique-item restriction. Review before buying."
            end
        end
    else
        if not C_AuctionHouse.CanCancelAuction(t.auctionID) then return Error("This auction can no longer be cancelled.") end
        t.total = C_AuctionHouse.GetCancelCost(t.auctionID)
        if not Integer(t.total) or GetMoney() < t.total then return Error("Not enough money for the cancellation fee.") end
    end
    t.phase = "review"
    Changed()
    return true
end
-- Live figures for the form, so nothing waits for a review screen (read-only API calls).
function Trade.EstimateDeposit()
    local t = Trade.current
    if not t or t.kind ~= "sell" or not Integer(t.quantity,1) then return nil end
    local ok,deposit
    if t.commodity then ok,deposit = pcall(C_AuctionHouse.CalculateCommodityDeposit,t.itemID,t.duration,t.quantity)
    else ok,deposit = pcall(C_AuctionHouse.CalculateItemDeposit,t.location,t.duration,t.quantity) end
    return ok and Integer(deposit) and deposit or nil
end
function Trade.EstimateCancelCost()
    local t = Trade.current
    if not t or t.kind ~= "cancel" or not C_AuctionHouse.GetCancelCost then return nil end
    local ok,cost = pcall(C_AuctionHouse.GetCancelCost,t.auctionID)
    return ok and Integer(cost) and cost or nil
end
-- One press, as in Blizzard's window: posting and cancelling validate and submit together.
-- (Purchases keep a confirmation step, as Blizzard's buyout and bid prompts do.)
function Trade.Commit()
    local t = Trade.current
    if not t or t.phase ~= "edit" then return false end
    if t.kind == "sell" or t.kind == "cancel" then
        if not Trade.Review() then return false end
        return Trade.Confirm()
    end
    return Trade.Review()
end
function Trade.Buy(method)
    local t = Trade.current
    if not t or t.kind ~= "buy" or t.phase ~= "edit" then return false end
    if not t.commodity then
        if method ~= "bid" and method ~= "buyout" then return false end
        t.method = method
    end
    return Trade.Review()
end
function Trade.Back()
    local t = Trade.current
    if not t then return end
    if t.phase == "review" or t.phase == "quote" or t.phase == "warning" then
        if t.quoteOwned then Invoke("CancelCommoditiesPurchase") t.quoteOwned=false end
        if t.phase == "warning" then Invoke("CancelSell") end
        if t.nativeWarning and StaticPopup_Hide then HidePopup("AUCTION_HOUSE_POST_WARNING") t.nativeWarning=false end
        t.phase,t.message = "edit",nil
        Changed()
    else Trade.Close() end
end
function Trade.Confirm()
    local t = Trade.current
    if not t or (t.phase ~= "review" and t.phase ~= "warning") or not Ready() then return false end
    if t.uniqueReady and GetTime()<t.uniqueReady then return Error("Please finish reviewing the unique-item warning (3 seconds).") end
    local fn,args,n
    if t.kind == "sell" then
        local valid,deposit = SellValid(t)
        if not valid then return false end
        if deposit ~= t.deposit then t.phase = "edit" return Error("The deposit changed. Review this sale again.") end
        local warning = t.phase == "warning"
        fn = t.commodity and (warning and "ConfirmPostCommodity" or "PostCommodity")
            or (warning and "ConfirmPostItem" or "PostItem")
        if t.commodity then args,n = {t.location,t.duration,t.quantity,t.buyout},4
        else args,n = {t.location,t.duration,t.quantity,t.bid > 0 and t.bid or nil,t.buyout > 0 and t.buyout or nil},5 end
    elseif t.kind == "buy" and t.commodity then
        if not C_AuctionHouse.GetQuoteDurationRemaining or C_AuctionHouse.GetQuoteDurationRemaining() <= 0 then return Fail("The price quote expired. Request a new quote.") end
        if not Integer(t.total,1) or GetMoney() < t.total then return Error("Not enough money for this quote.") end
        fn,args,n = "ConfirmCommoditiesPurchase",{t.itemID,t.quantity},2
    elseif t.kind == "buy" then
        local valid,price = BuyValid(t)
        if not valid then return false end
        if price ~= t.total then return Error("The price changed. Review again.") end
        fn,args,n = "PlaceBid",{t.auctionID,price},2
    else
        if not C_AuctionHouse.CanCancelAuction(t.auctionID) or C_AuctionHouse.GetCancelCost(t.auctionID) ~= t.total then return Error("The auction or cancellation fee changed. Review again.") end
        if GetMoney() < t.total then return Error("Not enough money for the cancellation fee.") end
        fn,args,n = "CancelAuction",{t.auctionID},1
    end
    -- The call comes first; the panel shows "sending" once it has been made.
    local ok,needsConfirmation = Invoke(fn,unpack(args,1,n))
    if not ok then return Fail(tostring(needsConfirmation)) end
    t.phase,t.started,t.message = "sending",GetTime(),"Waiting for the auction house..."
    Changed()
    if Trade.current == t and t.kind == "sell" and needsConfirmation == true and t.phase == "sending" then
        t.phase,t.message = "warning",CONFIRM_AUCTION_POSTING_TEXT or "Blizzard requires an additional confirmation for this posting. Review the price and deposit before continuing."
        t.nativeWarning = true
        if StaticPopup_Hide then HidePopup("AUCTION_HOUSE_POST_WARNING") end
        Changed()
    end
    return true
end
-- Entry points the player's press runs: no redraw until the auction call has been made, then
-- one redraw. (The OnUpdate below also clears these, should a press ever end in a Lua error.)
local function Pressed(fn)
    return function(...)
        if quiet then return fn(...) end
        quiet,Trade.pressing = true,true
        local result = fn(...)
        quiet,Trade.pressing = false,false
        Changed()
        return result
    end
end
Trade.Commit,Trade.Buy,Trade.Confirm = Pressed(Trade.Commit),Pressed(Trade.Buy),Pressed(Trade.Confirm)
function Trade.Summary()
    local t = Trade.current
    if not t then return "" end
    if t.kind == "sell" then
        return ("Quantity: %d\nDuration: %s\n%s: %s\nStarting bid per item: %s\nDeposit: %s"):format(t.quantity,
            ({AUCTION_DURATION_ONE or "12 hours",AUCTION_DURATION_TWO or "24 hours",AUCTION_DURATION_THREE or "48 hours"})[t.duration],
            t.commodity and "Price per item" or "Buyout per item",Money(t.buyout),t.commodity and "Not applicable" or Money(t.bid),t.deposit and Money(t.deposit) or "Calculated on review")
            .. (t.marketPrice and ("\nLowest market buyout: "..Money(t.marketPrice)) or "")
    elseif t.kind == "cancel" then return "Cancel this auction and return its items by mail.\nThe original deposit is not refunded.\nCancellation fee: "..(t.total and Money(t.total) or "Calculated on review") end
    return ("Quantity: %s\nAction: %s\n%s: %s"):format(t.quantity or "?",t.commodity and "Buy commodities" or (t.method == "bid" and "Place bid" or "Buyout"),
        t.commodity and "Quoted total" or "Total",t.total and Money(t.total) or (t.commodity and "Request a current price quote" or Money(t.method == "bid" and t.bid or t.row.price)))
end
local events = CreateFrame("Frame")
for _,event in ipairs({"COMMODITY_PRICE_UPDATED","COMMODITY_PRICE_UNAVAILABLE","COMMODITY_PURCHASE_SUCCEEDED","COMMODITY_PURCHASE_FAILED",
    "AUCTION_HOUSE_PURCHASE_COMPLETED","BID_ADDED","BIDS_UPDATED","AUCTION_CANCELED","AUCTION_HOUSE_AUCTION_CREATED","AUCTION_MULTISELL_START","AUCTION_MULTISELL_UPDATE",
    "AUCTION_MULTISELL_FAILURE","AUCTION_HOUSE_POST_WARNING","AUCTION_HOUSE_POST_ERROR","AUCTION_HOUSE_SHOW_ERROR","UI_ERROR_MESSAGE",
    "AUCTION_HOUSE_CLOSED","PLAYER_REGEN_DISABLED"}) do pcall(events.RegisterEvent,events,event) end
events:SetScript("OnEvent",function(_,event,a,b)
    local t = Trade.current
    if not t then return end
    if event == "AUCTION_HOUSE_CLOSED" or event == "PLAYER_REGEN_DISABLED" then Trade.Close(true) return end
    if event == "COMMODITY_PRICE_UPDATED" and t.kind == "buy" and t.commodity and (t.phase == "quote" or t.phase == "review") then
        if not Integer(a,1) or not Integer(b,1) then Fail("No valid price quote was returned.") return end
        t.phase,t.unitPrice,t.total,t.message = "review",a,b,"Confirm the server's current total price."
        Changed()
    elseif event == "COMMODITY_PRICE_UNAVAILABLE" and t.commodity and t.kind == "buy" then Fail("The requested quantity or price is unavailable. Search again.")
    elseif event == "AUCTION_HOUSE_POST_WARNING" and t.kind == "sell" and t.phase == "sending" then
        -- The stock popup's accept handler belongs to the stock sell frame's pendingPost.
        -- Replace only this notification for our in-flight post, without changing its scripts.
        t.nativeWarning = true
        C_Timer.After(0,function()
            if Trade.current == t and t.nativeWarning and StaticPopup_Hide then HidePopup("AUCTION_HOUSE_POST_WARNING") end
        end)
    elseif t.phase == "sending" or t.phase == "quote" then
        local success = t.phase == "sending" and (t.kind == "buy" and ((t.commodity and event == "COMMODITY_PURCHASE_SUCCEEDED") or
            (not t.commodity and a == t.auctionID and (event == "AUCTION_HOUSE_PURCHASE_COMPLETED" or event == "BID_ADDED")))
            or t.kind == "cancel" and event == "AUCTION_CANCELED" and a == t.auctionID)
        if t.kind == "buy" and not t.commodity and t.method == "bid" and event == "BIDS_UPDATED" and C_AuctionHouse.GetBids then
            for _,bid in ipairs(C_AuctionHouse.GetBids() or {}) do
                if bid.auctionID == t.auctionID and bid.bidAmount == t.total and bid.bidder == UnitGUID("player") then success=true break end
            end
        end
        if t.kind == "sell" then
            if event == "AUCTION_MULTISELL_START" then t.multisell = true
            elseif event == "AUCTION_MULTISELL_UPDATE" then t.message = ("Posted %d / %d auctions"):format(a,b) success = a >= b Changed()
            elseif event == "AUCTION_HOUSE_AUCTION_CREATED" and (t.commodity or t.quantity == 1) then success = true end
        end
        if success then
            t.phase,t.message = "done",t.kind == "sell" and "Auction posted." or t.kind == "cancel" and "Auction cancelled. Items will arrive by mail." or
                (t.method == "bid" and not t.commodity and "Bid placed." or "Purchase complete. Collect your items from the mailbox.")
            Data.mode,Data.rows,Data.more,Data.message = "invalid",{},false,"Auction changed. Search or refresh for current results."
            if Data.changed then Data.changed() end
            Changed()
        elseif event == "AUCTION_HOUSE_POST_ERROR" or event == "AUCTION_MULTISELL_FAILURE" or event == "COMMODITY_PURCHASE_FAILED" or event == "AUCTION_HOUSE_SHOW_ERROR" or event == "UI_ERROR_MESSAGE" then
            if event == "AUCTION_HOUSE_POST_ERROR" and t.kind == "sell" then
                t.nativeError = true
                C_Timer.After(0,function() if Trade.current==t and StaticPopup_Hide then HidePopup("AUCTION_HOUSE_POST_ERROR") end end)
            end
            local message = event == "UI_ERROR_MESSAGE" and b or event == "AUCTION_HOUSE_POST_ERROR" and AUCTION_POSTING_ERROR_TEXT
            if event == "AUCTION_HOUSE_SHOW_ERROR" and AuctionHouseUtil and AuctionHouseUtil.GetErrorText then message = AuctionHouseUtil.GetErrorText(a) end
            Fail(message and message ~= "" and message or "The auction request failed. Check your auctions and bags before retrying.")
        end
    end
end)
events:SetScript("OnUpdate",function()
    if quiet then quiet,Trade.pressing = false,false Changed() end
    local t = Trade.current
    if not t then return end
    if t.phase == "review" and t.kind == "buy" and t.commodity and C_AuctionHouse.GetQuoteDurationRemaining() <= 0 then
        Fail("The price quote expired. Request a new quote.")
    elseif (t.phase == "sending" or t.phase == "quote") and GetTime() - t.started > 30 then
        Fail("No response yet. Check your auctions, bags, and mailbox before trying again; this request will not be repeated automatically.")
    end
end)
