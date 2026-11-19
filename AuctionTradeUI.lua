local ADDON, ns = ...
local Trade,Style = ns.AuctionTransactions,ns.AuctionStyle
local UI = {}
ns.AuctionTradeUI = UI

-- Laid out like Blizzard's Post Auctions tab: the form on the left (Quantity / Unit Price /
-- Duration / Deposit / Total Price / Create Auction), current listings on the right. Every
-- value is editable in place, the main action starts focused, and Y (PAD4) performs it from
-- anywhere, so posting at the market price is "choose item, A". Picking a listing on the right
-- copies its price, as clicking a row does in Blizzard's window. Purchases keep one
-- confirmation, as Blizzard's buyout prompt does.
local W,H = 760,560
local LEFT_X,LEFT_W = 20,364
local RIGHT_X,RIGHT_W = 396,344
local PANE_Y,PANE_H = -54,424
local LABEL_X,LABEL_W,FIELD_X = 30,112,152
local LIST_ROWS,LIST_ROW_H = 9,32
local overlay,panel,title,itemIcon,itemName,itemSub,message,legend
local listTitle,listHeadPrice,listHeadQty,listEmpty
local titleBand,rightPane,rightBand
local labels,values,infoLabels,infoValues = {},{},{},{}
local pool,listButtons,controls,selected = {},{},{},1
local lastPhase,lastTrade
local listOffset = 0
local Refresh

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:14:14:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:14:14:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:14:14:2:0|t"
local DURATIONS = { AUCTION_DURATION_ONE or "12 Hours", AUCTION_DURATION_TWO or "24 Hours", AUCTION_DURATION_THREE or "48 Hours" }

local function Money(n) return ns.Auction.Money(n or 0) end
local function Select(index)
    selected = math.max(1,math.min(index,#controls))
    for i,b in ipairs(controls) do Style.Paint(b,i==selected) end
end
local function Text(font,x,y,w,h,justify)
    local label = panel:CreateFontString(nil,"OVERLAY",font)
    label:SetPoint("TOPLEFT",x,y)
    label:SetSize(w,h)
    label:SetJustifyH(justify or "LEFT")
    label:SetJustifyV("MIDDLE")
    return label
end
local function Create()
    overlay = CreateFrame("Frame",nil,ns.Auction.frame,"BackdropTemplate")
    UI.frame = overlay
    overlay:SetAllPoints()
    overlay:SetFrameLevel(ns.Auction.frame:GetFrameLevel()+20)
    overlay:EnableMouse(true)
    local shade = overlay:CreateTexture(nil,"BACKGROUND")
    shade:SetAllPoints()
    shade:SetColorTexture(0,0,0,0.8)
    panel = CreateFrame("Frame",nil,overlay,"BackdropTemplate")
    panel:SetSize(W,H)
    panel:SetPoint("CENTER")
    ns.Skin.Panel(panel)
    -- Title bar flush along the top inner edge of the border.
    titleBand = Style.Band(panel,0,0,1,30)
    ns.Skin.DockBar(titleBand,panel,"TOP",30)
    title = Text("GameFontNormal",16,-14,W-32,30,"CENTER")
    title:ClearAllPoints()
    title:SetAllPoints(titleBand)
    -- Left: item card and form.
    Style.Pane(panel,LEFT_X,PANE_Y,LEFT_W,PANE_H,"detail")
    itemIcon = panel:CreateTexture(nil,"ARTWORK")
    itemIcon:SetPoint("TOPLEFT",LEFT_X+14,PANE_Y-14)
    itemIcon:SetSize(42,42)
    itemName = Text("GameFontHighlightLarge",LEFT_X+66,PANE_Y-14,LEFT_W-80,24)
    itemName:SetWordWrap(false)
    itemSub = Text("GameFontHighlightSmall",LEFT_X+66,PANE_Y-38,LEFT_W-80,18)
    Style.Rule(panel,LEFT_X+12,PANE_Y-66,LEFT_W-24)
    for i = 1,7 do
        labels[i] = Text("GameFontNormal",LABEL_X,0,LABEL_W,32,"RIGHT")
        values[i] = Text("GameFontHighlight",FIELD_X,0,LEFT_X+LEFT_W-FIELD_X-12,32)
    end
    message = Text("GameFontHighlightSmall",LEFT_X+14,0,LEFT_W-28,44,"CENTER")
    message:SetJustifyV("TOP")
    -- Right: current listings (selling) or the listing's details (buying, cancelling).
    rightPane = Style.Pane(panel,RIGHT_X,PANE_Y,RIGHT_W,PANE_H,"results")
    listTitle = Text("GameFontNormal",RIGHT_X+12,PANE_Y-8,200,26)
    rightBand = Style.Band(panel,RIGHT_X+1,PANE_Y-40,RIGHT_W-2,22)
    listHeadPrice = Text("GameFontNormalSmall",RIGHT_X+12,PANE_Y-40,170,22,"RIGHT")
    listHeadPrice:SetText("Unit Price")
    listHeadQty = Text("GameFontNormalSmall",RIGHT_X+200,PANE_Y-40,120,22,"RIGHT")
    listHeadQty:SetText("Quantity")
    listEmpty = Text("GameFontDisable",RIGHT_X+20,PANE_Y-150,RIGHT_W-40,60,"CENTER")
    for i = 1,LIST_ROWS do
        local b = Style.Control(panel,"row")
        b:SetPoint("TOPLEFT",RIGHT_X+2,PANE_Y-64-(i-1)*LIST_ROW_H)
        b:SetSize(RIGHT_W-4,LIST_ROW_H)
        b.stripe = i%2==0
        b.text:ClearAllPoints()
        b.text:SetPoint("RIGHT",b,"LEFT",180,0)
        b.text:SetJustifyH("RIGHT")
        b.qty = b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        b.qty:SetPoint("RIGHT",b,"LEFT",318,0)
        b.qty:SetJustifyH("RIGHT")
        b:SetScript("OnEnter",function(self) for n,c in ipairs(controls) do if c==self then Select(n) end end end)
        b:SetScript("OnClick",function(self) if self.action then Style.Press(self) self.action() end end)
        listButtons[i] = b
    end
    for i = 1,8 do
        infoLabels[i] = Text("GameFontNormalSmall",RIGHT_X+14,PANE_Y-48-(i-1)*28,150,24)
        infoValues[i] = Text("GameFontHighlight",RIGHT_X+150,PANE_Y-48-(i-1)*28,RIGHT_W-164,24,"RIGHT")
    end
    -- The same legend bar as the keyboard's, flush along the bottom inner edge of the border; the
    -- Back key sits inside it at the left. It stays below the keys.
    legend = ns.Glyphs.CreateLegendBar(panel)
    ns.Skin.DockBar(legend,panel,"BOTTOM")
    legend:SetFrameLevel(panel:GetFrameLevel())
end
-- Footer geometry: the legend bar's top edge, and the Back key centred inside the bar.
local function FooterTop() return -(H-ns.Skin.ContentInset(panel)-legend:GetHeight()) end
local BACK_W,BACK_H = 124,30
-- Cancelling has nothing to show beside the form (the fee and quantity are on it), so its window
-- is just the left pane; selling and buying keep the right pane.
local function SetCompact(compact)
    local width = compact and LEFT_X*2+LEFT_W or W
    panel:SetWidth(width) -- the title and legend bars are anchored to both sides, so they follow
    rightPane:SetShown(not compact)
    rightBand:SetShown(not compact)
    listTitle:SetShown(not compact)
    if compact then
        listHeadPrice:Hide() listHeadQty:Hide() listEmpty:Hide()
        for i = 1,#infoLabels do infoLabels[i]:Hide() infoValues[i]:Hide() end
    end
end

local function Bind(b,action)
    local t,phase,version = Trade.current,Trade.current.phase,Trade.current.version
    -- A quote/result arriving between pad down/up cannot turn an old press into a new action.
    b.action = action and function() if Trade.current==t and t.phase==phase and t.version==version then action() end end
end
local function Key(text,x,y,width,action,role,glyph,height)
    local index = #controls+1
    local b = pool[index]
    if not b then
        b = Style.Control(panel,"secondary")
        b:SetScript("OnEnter",function(self) for n,c in ipairs(controls) do if c==self then Select(n) end end end)
        b:SetScript("OnClick",function(self,button)
            if not self.action or self.disabled then return end
            if ns.NoteAction then ns.NoteAction(("click %s (%s)"):format(tostring(self.text:GetText()),tostring(button))) end
            self.action() Style.Press(self)
        end)
        pool[index] = b
    end
    b.role = role or "secondary"
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT",x,y)
    b:SetSize(width,height or 32)
    b.text:SetFontObject(width<80 and GameFontHighlightSmall or GameFontHighlight)
    b.text:SetText(text)
    b.text:SetWordWrap(false)
    b.active,b.disabled = nil,nil
    Style.Glyph(b,glyph)
    b.x,b.y,b.w,b.h = x,y,width,height or 32
    Bind(b,action)
    b:Show()
    controls[#controls+1] = b
    return b
end

-- Form rows: right-aligned label, controls beside it.
local row,rowY = 0,0
local function Row(label,sub)
    row = row+1
    rowY = PANE_Y-80-(row-1)*40
    labels[row]:ClearAllPoints()
    labels[row]:SetPoint("TOPLEFT",LABEL_X,rowY)
    labels[row]:SetText(sub and (label.."\n|cff9a9a9a"..sub.."|r") or label)
    labels[row]:Show()
    values[row]:ClearAllPoints()
    values[row]:SetPoint("TOPLEFT",FIELD_X,rowY)
    values[row]:SetText("")
    values[row]:Show()
    return rowY
end
local function Value(label,text)
    Row(label)
    values[row]:SetText(text)
end
local function Info(i,label,value,r,g,b)
    infoLabels[i]:SetText(label)
    infoValues[i]:SetText(value or "")
    infoValues[i]:SetTextColor(r or 1,g or 1,b or 1)
end
local function ActionKeys(list)
    -- Centered under the form, like Blizzard's Create Auction button.
    local total = 0
    for i,k in ipairs(list) do total = total+k[2]+(i>1 and 8 or 0) end
    local x,y,made = LEFT_X+(LEFT_W-total)/2,rowY-56,{}
    for i,k in ipairs(list) do
        made[i] = Key(k[1],x,y,k[2],k[3],k[4],k[5],36)
        x = x+k[2]+8
    end
    message:ClearAllPoints()
    message:SetPoint("TOPLEFT",LEFT_X+14,y-44)
    return made[#list]
end

local function Number(titleText,value,accept)
    local t = Trade.current
    -- Entry starts at 0 (the first digit typed replaces it); the current value is in the title.
    if value and value>0 then titleText = titleText.." (now "..value..")" end
    local buffer = ns.Input.NewBuffer(titleText,"0",function(text)
        if Trade.current~=t or t.phase~="edit" then return end
        if text=="" then text="0" end
        local n = tonumber(text)
        if not n or n<0 or n~=math.floor(n) or n>99999999999 then
            t.message="Enter a whole number." Refresh() return
        end
        accept(n)
    end)
    buffer.numeric,buffer.auctionInput,buffer.submitLabel = true,true,"Apply"
    ns.Auction.EditInput(buffer)
end
local function CopperAllowed()
    return not (C_AuctionHouse and C_AuctionHouse.SupportsCopperValues) or C_AuctionHouse.SupportsCopperValues()
end
-- Gold / silver / copper boxes: press one, type the amount, done.
local function MoneyKeys(field,label,y)
    local t = Trade.current
    local value = t[field] or 0
    local copper = CopperAllowed()
    local units = { {10000,"Gold",GOLD_ICON,copper and 86 or 112}, {100,"Silver",SILVER_ICON,copper and 62 or 92}, {1,"Copper",COPPER_ICON,62} }
    local x = FIELD_X
    for _,part in ipairs(units) do
        local unit,name,icon,width = part[1],part[2],part[3],part[4]
        if unit>1 or copper then
            local amount = unit==10000 and math.floor(value/unit) or math.floor(value/unit)%100
            Key(amount..icon,x,y,width,function()
                Number(label.." - "..name,amount,function(n)
                    if unit<10000 and n>99 then t.message=name.." must be 0 to 99." Refresh() return end
                    Trade.Update(field,value-amount*unit+n*unit)
                end)
            end,"gold")
            x = x+width+4
        end
    end
end
local function QuantityKeys(maximum,y)
    local t = Trade.current
    Key(tostring(t.quantity),FIELD_X,y,118,function()
        Number("Quantity",t.quantity,function(n) Trade.Update("quantity",n) end)
    end,"gold")
    local max = Key("Max",FIELD_X+126,y,88,(maximum or 0)>1 and function() Trade.Update("quantity",maximum) end or nil)
    max.disabled = not maximum or maximum<=1 or t.quantity==maximum
end
local function DurationKeys(y)
    local t = Trade.current
    for i = 1,3 do
        local k = Key(DURATIONS[i],FIELD_X+(i-1)*72,y,68,function() Trade.Update("duration",i) end,"segment")
        k.active = t.duration==i
    end
end

-- Current listings for the item being sold, from the market lookup.
local function MarketRows(t)
    local data = ns.AuctionData
    if t.marketPending or data.mode~="details" or not data.itemKey or not t.marketKey or data.itemKey.itemID~=t.marketKey.itemID then return nil end
    local rows = {}
    for _,r in ipairs(data.rows) do if r.price and r.price>0 then rows[#rows+1] = r end end
    return rows
end
local function ListingsPane(t)
    for i = 1,#infoLabels do infoLabels[i]:Hide() infoValues[i]:Hide() end
    listTitle:SetText("Current listings")
    listHeadPrice:Show() listHeadQty:Show()
    local rows = MarketRows(t)
    listEmpty:SetText(t.marketPending and "Looking up current listings..." or (rows and "None currently listed.\nEnter your own price." or "Press Refresh to see current listings."))
    listEmpty:SetShown(not rows or #rows==0)
    rows = rows or {}
    listOffset = math.max(0,math.min(listOffset,#rows-LIST_ROWS))
    UI.listCount = #rows
    for i,b in ipairs(listButtons) do
        local r = rows[listOffset+i]
        b:SetShown(r~=nil)
        if r then
            b.text:SetText(Money(r.price))
            b.qty:SetText(r.owned and ((r.count or "").."  (yours)") or tostring(r.count or ""))
            b.active = r.price==t.buyout
            b.x,b.y,b.w,b.h = RIGHT_X+2,PANE_Y-64-(i-1)*LIST_ROW_H,RIGHT_W-4,LIST_ROW_H
            b.listIndex = listOffset+i
            local price = r.price
            Bind(b,function() Trade.Update("buyout",price) end)
            controls[#controls+1] = b
        end
    end
    local refresh = Key("Refresh",RIGHT_X+RIGHT_W-100,PANE_Y-6,92,Trade.CompareMarket,"secondary",nil,28)
    refresh.disabled = t.marketPending
end
local function InfoPane(lines)
    listTitle:SetText("Details")
    listHeadPrice:Hide() listHeadQty:Hide() listEmpty:Hide()
    for _,b in ipairs(listButtons) do b:Hide() end
    UI.listCount = 0
    for i = 1,#infoLabels do
        local line = lines[i]
        infoLabels[i]:SetShown(line~=nil) infoValues[i]:SetShown(line~=nil)
        if line then Info(i,line[1],line[2],line[3],line[4],line[5]) end
    end
end

local TITLES = { sell="Post Auction", buy="Buy", cancel="Cancel Auction" }
local function Header(t)
    local phaseTitle = ({quote="Getting the current price...",review="Confirm",warning="Confirm posting",sending="Waiting for the auction house...",done="Done",error="Not completed"})[t.phase]
    local verb = TITLES[t.kind] or "Auction"
    title:SetText(phaseTitle and (verb.." - "..phaseTitle) or verb)
    itemIcon:SetTexture(t.row.icon or 134400)
    itemName:SetText((t.row.name or "Item"):gsub("|","||"))
    local color = t.row.quality and ns.Inventory.Color(t.row.quality)
    if color then itemName:SetTextColor(color[1],color[2],color[3]) else itemName:SetTextColor(1,1,1) end
    if t.kind=="sell" then itemSub:SetText(("%d available"):format(t.maximum or 0))
    elseif t.kind=="buy" then itemSub:SetText(t.commodity and "Buys the cheapest available first" or ("Listing of %d"):format(t.row.count or 1))
    else itemSub:SetText(("Your listing of %d"):format(t.row.count or 1)) end
end

local function SellForm(t)
    QuantityKeys(t.maximum,Row("Quantity"))
    MoneyKeys("buyout","Unit price",Row(t.commodity and "Unit Price" or "Buyout","per item"))
    if not t.commodity then MoneyKeys("bid","Starting bid",Row("Starting Bid","optional")) end
    DurationKeys(Row("Duration"))
    local deposit = Trade.EstimateDeposit()
    local poor = deposit and GetMoney and GetMoney()<deposit
    Value("Deposit",deposit and ((poor and "|cffff5a4d" or "")..Money(deposit)..(poor and "|r" or "")) or "-")
    Value("Total Price",t.buyout>0 and Money(t.buyout*t.quantity) or "|cff9a9a9aSet a price|r")
    local primary = ActionKeys({{"Create Auction",240,Trade.Commit,"primary","PAD4"}})
    ListingsPane(t)
    return primary
end

local function BuyForm(t)
    if t.commodity then
        local available,data = 0,ns.AuctionData
        if data.mode=="details" then for _,r in ipairs(data.rows) do if r.itemID==t.itemID and not r.owned then available = available+(r.count or 0) end end end
        if available==0 then available = t.row.count or 1 end
        QuantityKeys(available,Row("Quantity"))
        Value("Unit Price",t.row.price and Money(t.row.price) or "-")
        Value("Total Price",t.row.price and ("~ "..Money(t.row.price*t.quantity)) or "-")
        local primary = ActionKeys({{"Buy Now",240,function() Trade.Buy() end,"primary","PAD4"}})
        InfoPane({ {"Available",tostring(available)}, {"Lowest unit price",t.row.price and Money(t.row.price) or "-"},
            {"Your money",Money(GetMoney and GetMoney() or 0)} })
        message:SetText(t.message or "The final price is quoted before you confirm.")
        return primary
    end
    local canBid,canBuy = (t.row.bid or 0)>0,(t.row.price or 0)>0
    if canBid then
        if t.bid<(t.row.bid or 0) then t.bid = t.row.bid end
        MoneyKeys("bid","Bid",Row("Your Bid"))
    end
    Value("Buyout",canBuy and Money(t.row.price) or "None")
    local keys = {}
    if canBid then keys[#keys+1] = {"Bid",130,function() Trade.Buy("bid") end,"gold",not canBuy and "PAD4" or nil} end
    if canBuy then keys[#keys+1] = {"Buyout",170,function() Trade.Buy("buyout") end,"primary","PAD4"} end
    local lines = { {"Quantity",tostring(t.row.count or 1)}, {"Buyout",canBuy and Money(t.row.price) or "None"} }
    if canBid then lines[#lines+1] = {"Minimum bid",Money(t.row.bid)} end
    lines[#lines+1] = {"Your money",Money(GetMoney and GetMoney() or 0)}
    InfoPane(lines)
    return #keys>0 and ActionKeys(keys) or nil
end

local function CancelForm(t)
    local fee = Trade.EstimateCancelCost()
    Value("Buyout",t.row.price and Money(t.row.price) or "None")
    Value("Fee",fee and Money(fee) or "-")
    local primary = ActionKeys({{"Cancel Auction",240,Trade.Commit,"danger","PAD4"}})
    message:SetText(t.message or "Items return by mail. The deposit is not refunded.")
    InfoPane({ {"Quantity",tostring(t.row.count or 1)}, {"Buyout",t.row.price and Money(t.row.price) or "None"},
        {"Cancellation fee",fee and Money(fee) or "-",1,0.82,0.35} })
    return primary
end

local function ReviewForm(t)
    local lines = {}
    if t.kind=="buy" then
        Value("Quantity",tostring(t.quantity or t.row.count or 1))
        if t.commodity and t.unitPrice then Value("Unit Price",Money(t.unitPrice)) end
        Value(t.method=="bid" and not t.commodity and "Your Bid" or "Total Price",Money(t.total))
        lines = { {"Your money",Money(GetMoney and GetMoney() or 0)} }
        if not t.message then message:SetText("Check the total, then confirm.") end
    elseif t.kind=="sell" then
        Value("Quantity",tostring(t.quantity))
        Value("Unit Price",Money(t.buyout))
        Value("Deposit",t.deposit and Money(t.deposit) or "-")
    else
        Value("Fee",t.total and Money(t.total) or "-")
    end
    InfoPane(lines)
    local label = t.phase=="warning" and "Post Anyway" or t.kind=="sell" and "Create Auction"
        or t.kind=="cancel" and "Cancel Auction" or (t.method=="bid" and not t.commodity and "Place Bid" or "Confirm Purchase")
    return ActionKeys({{label,240,Trade.Confirm,t.kind=="cancel" and "danger" or "primary","PAD4"}})
end

Refresh = function()
    local t = Trade.current
    if not t then
        if overlay then overlay:Hide() end
        local closed = lastTrade~=nil
        lastTrade,lastPhase = nil,nil
        UI.SyncBindings()
        -- The browser redraws once the panel has closed, which brings back its preview tooltip.
        if closed and ns.AuctionData and ns.AuctionData.changed then ns.AuctionData.changed() end
        return
    end
    if not ns.Auction or not ns.Auction.frame then return end
    if not overlay then Create() end
    overlay:Show()
    UI.SyncBindings()
    local reset = lastTrade~=t or lastPhase~=t.phase
    if lastTrade~=t then listOffset = 0 end
    local old = controls[selected]
    lastTrade,lastPhase = t,t.phase
    Header(t)
    controls,row,rowY = {},0,PANE_Y-80
    for i = 1,#labels do labels[i]:Hide() values[i]:Hide() end
    message:SetText(t.message or "")
    message:ClearAllPoints()
    message:SetPoint("TOPLEFT",LEFT_X+14,-400)
    message:SetTextColor(t.phase=="error" and 1 or 0.85,t.phase=="error" and 0.35 or 0.83,t.phase=="error" and 0.3 or 0.75)
    local primary
    if t.phase=="edit" then
        primary = t.kind=="sell" and SellForm(t) or t.kind=="buy" and BuyForm(t) or CancelForm(t)
    elseif t.phase=="review" or t.phase=="warning" then
        primary = ReviewForm(t)
    else
        InfoPane({})
        if t.phase=="quote" then
            ActionKeys({{"Cancel",160,Trade.Back,"secondary"}})
        elseif t.phase=="sending" then
            if not t.message then message:SetText("Waiting for the server. Do not repeat the transaction.") end
            message:ClearAllPoints() message:SetPoint("TOPLEFT",LEFT_X+14,rowY-40)
        else
            primary = ActionKeys({{t.phase=="done" and "Done" or "Close",240,function() Trade.Close() end,t.phase=="done" and "primary" or "secondary","PAD4"}})
        end
    end
    -- Back sits in the footer; B does the same from anywhere.
    local back
    if t.phase~="sending" then
        local finished = t.phase=="done" or t.phase=="error"
        back = Key(finished and "Close" or "Back",LEFT_X,FooterTop()-(legend:GetHeight()-BACK_H)/2,BACK_W,
            finished and function() Trade.Close() end or Trade.Back,"secondary","PAD2",BACK_H)
    end
    local used = {}
    for _,b in ipairs(controls) do used[b] = true end
    for _,b in ipairs(pool) do if not used[b] then b:Hide() end end
    for _,b in ipairs(listButtons) do if not used[b] then b:Hide() end end
    UI.primary = primary
    -- New screens start on the main action; edits keep focus on the key that was pressed.
    selected = 1
    if reset then
        -- Confirmations start on Back so a doubled A press never spends money; Y confirms.
        local start = (t.phase=="review" or t.phase=="warning" or (t.kind=="cancel" and t.phase=="edit")) and back or primary
        for i,b in ipairs(controls) do if b==start then selected = i end end
    else
        for i,b in ipairs(controls) do if b==old then selected = i end end
    end
    SetCompact(t.kind=="cancel")
    -- Y and B are shown on the keys they press (the main action and Back); the legend bar keeps
    -- only inputs with no key of their own, centred in the space right of Back. While there is
    -- nothing to press (waiting for the server) the bar is empty.
    local items = {}
    if #controls>0 then items = { {"PAD1","Select"} } end
    if #controls>1 then items[#items+1] = {"PADDPAD","Move"} end
    if (UI.listCount or 0)>0 and t.kind~="cancel" then items[#items+1] = {"PADLTRIGGER","Scroll listings","PADRTRIGGER"} end
    legend:SetContentLeft(back and (LEFT_X-ns.Skin.ContentInset(panel)+BACK_W+8) or 0)
    legend:SetItems(items)
    Select(selected)
end

-- Spatial D-pad movement: go to the nearest control in the pressed direction.
local function Move(dx,dy)
    local b = controls[selected]
    if not b then return Select(1) end
    -- Scroll the listing column before leaving it.
    if b.listIndex and dx==0 then
        local first,last = listOffset+1,math.min(UI.listCount or 0,listOffset+LIST_ROWS)
        if dy>0 and b.listIndex==last and last<(UI.listCount or 0) then listOffset = listOffset+1 Refresh() return end
        if dy<0 and b.listIndex==first and listOffset>0 then listOffset = listOffset-1 Refresh() return end
    end
    local cx,cy = b.x+b.w/2,b.y-b.h/2
    local best,bestScore
    for i,c in ipairs(controls) do
        if c~=b and not c.disabled then
            local ox,oy = c.x+c.w/2-cx,(c.y-c.h/2)-cy
            local along,across = dx~=0 and ox*dx or -oy*dy,dx~=0 and math.abs(oy) or math.abs(ox)
            if along>4 then
                local score = along+across*(dx~=0 and 2.5 or 1.5)
                if not bestScore or score<bestScore then best,bestScore = i,score end
            end
        end
    end
    if best then Select(best) end
end
local function Scroll(direction)
    local count = UI.listCount or 0
    if count<=LIST_ROWS then return end
    listOffset = math.max(0,math.min(count-LIST_ROWS,listOffset+direction*LIST_ROWS))
    Refresh()
end
-- Posting, buying, bidding and cancelling only work inside a hardware input event. A raw
-- OnGamePadButtonDown/Up script is not one, so while the form is open A, B and Y are bound
-- (override bindings, out of combat only) to hidden buttons; a binding click is a hardware event,
-- so the auction call runs inside it. The browser lets those three buttons through to the binding.
local proxies,bindOwner = {},nil
local BOUND = { PAD1 = "EBGAuctionTradeSelect", PAD2 = "EBGAuctionTradeBack", PAD4 = "EBGAuctionTradeAction" }
UI.bound = false
function UI.Bind(want)
    want = want and SetOverrideBindingClick ~= nil and not InCombatLockdown()
    if want == UI.bound or InCombatLockdown() then return end
    if not bindOwner then
        bindOwner = CreateFrame("Frame")
        for key,name in pairs(BOUND) do
            local b = CreateFrame("Button",name,UIParent)
            b:RegisterForClicks("AnyDown")
            b:SetScript("OnClick",function()
                if not Trade.current or not overlay or not overlay:IsShown() then return end
                if ns.NoteAction then ns.NoteAction("binding click "..key) end
                local action = UI.Handle(key)
                if action then action() end
            end)
            proxies[key] = b
        end
    end
    if want then
        for key,name in pairs(BOUND) do SetOverrideBindingClick(bindOwner,true,key,name,"LeftButton") end
    else
        ClearOverrideBindings(bindOwner)
    end
    if ns.NoteAction then ns.NoteAction("trade bindings "..(want and "on" or "off")) end
    UI.bound = want
end
function UI.SyncBindings()
    local keyboard = ns.KB and ns.KB.frame and ns.KB.frame:IsShown()
    UI.Bind(Trade.current ~= nil and overlay ~= nil and overlay:IsShown() and not keyboard)
end
function UI.Handle(key)
    if key=="PADDUP" then Move(0,-1)
    elseif key=="PADDDOWN" then Move(0,1)
    elseif key=="PADDLEFT" then Move(-1,0)
    elseif key=="PADDRIGHT" then Move(1,0)
    elseif key=="PADLTRIGGER" then Scroll(-1)
    elseif key=="PADRTRIGGER" then Scroll(1)
    elseif key=="PAD1" then
        local b = controls[selected]
        return b and b.action and not b.disabled and function() b.action() Style.Press(b) end
    elseif key=="PAD4" then
        local b = UI.primary
        return b and b:IsShown() and b.action and function() b.action() Style.Press(b) end
    elseif key=="PAD2" then
        local t,phase=Trade.current,Trade.current.phase
        return function()
            if Trade.current~=t or t.phase~=phase or phase=="sending" then return end
            if phase=="done" or phase=="error" then Trade.Close() else Trade.Back() end
        end
    end
end
Trade.changed = Refresh
