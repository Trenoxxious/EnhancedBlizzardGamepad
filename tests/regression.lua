local checks = 0
local function check(v,msg) checks=checks+1 assert(v,msg) end
Emit("ADDON_LOADED","EnhancedBlizzardGamepad")
Emit("PLAYER_LOGIN")
check(ns.loadingQuiet,"keyboard never opens by itself while the game is loading")
AuctionCategories = { { name="Weapons", filters={{classID=2}}, subCategories={
    {name="One-Handed", filters={{classID=2,subClassID=0}}, subCategories={
        {name="Axes", filters={{classID=2,subClassID=0}}, implicitFilter=2}
    }}
} }, { name="Armor", filters={{classID=4}} } }
local categories=ns.AuctionFilters.Categories()
check(categories[1].children[1].children[1].name=="Axes","copy native category hierarchy")
local chosen=categories[1].children[1].children[1]
chosen.filters[1].classID=99
check(AuctionCategories[1].subCategories[1].subCategories[1].filters[1].classID==2,"category snapshot never mutates native data")
chosen.filters[1].classID=2
ns.AuctionFilters.category=chosen
ns.AuctionFilters.minLevel=10 ns.AuctionFilters.maxLevel=20
ns.AuctionFilters.selected[5]=true
local query=ns.AuctionFilters.Query("axe")
check(query.itemClassFilters[1].subClassID==0 and query.minLevel==10 and query.maxLevel==20,"category and levels enter query")
check(#query.filters==2 and query.sorts[1].sortOrder==0,"explicit and implicit filters with price sort")
query.itemClassFilters[1].classID=88
check(chosen.filters[1].classID==2,"query receives independent filter tables")
ns.AuctionFilters.category=nil ns.AuctionFilters.Reset()
local bag=CreateFrame("EditBox","BagItemSearchBox",UIParent)
bag:SetText("")
local bank=CreateFrame("Frame","BankFrame",UIParent)
local search=CreateFrame("EditBox",nil,bank) bank.SearchBox=search
local amount=CreateFrame("EditBox","BankDepositAmount",bank)
local native=CreateFrame("Frame","AuctionHouseFrame",UIParent)
local ahInput=CreateFrame("EditBox",nil,native)
check(ns.Input.IsSearch(bag),"named bag search")
check(ns.Input.IsSearch(search),"anonymous bank search identity")
check(not ns.Input.IsSearch(amount),"bank amount must not become a filter")
check(not ns.Input.Allows(amount),"unverified bank input blocked")
check(not ns.Input.Allows(ahInput),"native auction input blocked")
local pointer=CreateFrame("Frame",nil,UIParent)
pointer.Icon=CreateFrame("Texture",nil,pointer)
pointer:SetPoint("CENTER",UIParent,"CENTER",30,40)
SmartNavigation={Pointer=pointer}
ns.SetNavPointerHidden(true)
local _,relative=pointer:GetPoint(1)
check(relative==ns.KB.frame.preview,"native arrow parks beside keyboard")
ns.SetNavPointerHidden(false)
local point,parent,relativePoint,x,y=pointer:GetPoint(1)
check(point=="CENTER" and parent==UIParent and x==30 and y==40,"arrow restores original anchor")
local proxy=ns.Input.SearchTarget(bag)
proxy:Insert("silk")
check(filterText=="silk" and bag:GetText()=="","filter does not write native box")
C_Container.SetItemSearch("ore")
check(proxy:GetText()=="ore","native changes sync proxy")
check(ns.Input.SearchTarget(search)==proxy,"bank and bag share live query")
local original=C_Container.SetItemSearch
C_Container.SetItemSearch=function() error("API unavailable") end
proxy:SetText("bad")
check(proxy:GetText()=="ore","failed writes keep last applied query")
C_Container.SetItemSearch=original
combat=true proxy:SetText("bad") combat=false
check(proxy:GetText()=="ore","combat does not apply filter")
ns.db.directBagSearch=false
check(ns.Input.IsSearch(bag),"old setting cannot reenable native writes")
ns.ShowKeyboard(true,bag)
ns.KB:Insert("!")
check(filterText=="ore!","keyboard uses proxy")
ns.KB:RunAction("clearsearch")
check(filterText=="","controller clear action")
ns.db.submitEnter=true
bag:SetScript("OnEnterPressed",function() error("native enter called") end)
ns.KB:Submit()
check(not ns.KB.frame:IsShown(),"Done closes without native Enter")
ns.ShowKeyboard(true,ahInput)
check(not ns.KB.frame:IsShown(),"native AH cannot enter generic writer")
local link="|cff1eff00|Hitem:1:2|h[Silk]|h|r"
NUM_BAG_SLOTS=1
C_Container.GetContainerNumSlots=function(b) return b==0 and 2 or 1 end
C_Container.GetContainerItemInfo=function(b,s) return {hyperlink=link,stackCount=s,quality=2,iconFileID=1,itemID=1} end
local inventory=ns.Inventory.Read()
check(#inventory==1 and inventory[1].count==4,"identical stacks group")
local buffer=ns.Input.NewBuffer("Test","",function() end)
buffer.isComposer=true buffer.isEBGInput=nil buffer.attr={chatType="SAY"}
function buffer:GetAttribute(k) return self.attr[k] end
function buffer:SetAttribute(k,v) self.attr[k]=v end
ns.ShowKeyboard(true,buffer)
ns.KB:RunAction("items")
check(ns.KB.page=="items" and ns.KB.rows[1][1].link==link,"item picker shows actual link")
ns.KB:PressKey(ns.KB.rows[1][1])
check(buffer:GetText()==link.." " and ns.KB.page=="letters","item selection inserts and returns")
ns.KB:RunAction("items")
ns.KB:RunAction("close")
check(ns.KB.page=="letters" and buffer:GetText()==link.." ","Back preserves draft")
ns.HideKeyboard()
local submitted
local owned=ns.Input.NewBuffer("Auction search","ore",function(t) submitted=t end)
owned.auctionInput=true
ns.ShowKeyboard(true,owned)
ns.OnTargetLost()
check(ns.KB.frame:IsShown(),"owned composer survives native focus loss")
ns.OnTargetFocused(bag)
check(ns.KB.target==owned,"native focus cannot steal auction composer")
ns.KB:Submit()
check(submitted=="ore","owned submission callback")
ns.db.auctionAuto=false
Emit("AUCTION_HOUSE_SHOW")
local d=ns.AuctionData
check(d.active and d.backend=="modern","modern adapter detection")
browseResults={{itemKey={itemID=9,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0},minPrice=1,totalQuantity=1}}
Emit("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(#d.rows==0 and d.mode=="browse","Blizzard's opening query is not shown as a search")
check(d.Search("silk"),"query sent")
check(not d.Search("ore"),"one outstanding query")
browseResults={{itemKey={itemID=1,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0},minPrice=500,totalQuantity=3081}}
Emit("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
check(not d.busy and #d.rows==1 and d.rows[1].price==500,"browse results")
C_InputInterfaceStyle.GetCurrentStyle=function() return 0 end
ns.Auction.Open()
check(not (ns.Auction.frame and ns.Auction.frame:IsShown()),"browser does not open while the gamepad interface is off")
C_InputInterfaceStyle.GetCurrentStyle=function() return 1 end
native:Show()
ns.Auction.Open()
check(native:GetAlpha()==0 and native:IsShown(),"native auction window is faded, not hidden, behind the browser")
ns.Auction.Close(true)
check(native:GetAlpha()==1,"closing the browser restores the native window")
ns.Auction.Open()
ns.Auction.Exit()
ns.Auction.Open()
Tick(1) Tick(1)
check(ns.Auction.frame:IsShown() and native:GetAlpha()==0,"leaving and quickly reopening keeps the new browser open")
local available
for _,f in ipairs(frames) do
    if f.item and f.item.itemKey and f.quantity and f:IsVisible() then available=f.quantity:GetText() end
end
check(available=="3,081","available quantity is visible and grouped before selecting item")
check(ns.Auction.frame.quantityHeader:GetText()=="Available","modern quantity label")
check(ns.Auction.frame.search.role=="search" and ns.Auction.frame.refresh.role=="primary","search entry and primary action have distinct roles")
check(ns.Auction.frame.tabButtons[1].role=="tab","main views use separate tab styling")
check(ns.Auction.frame.viewTitle:GetText()=="Browse auctions","browse heading identifies view")
local categoryButton=ns.Auction.frame.categoryButtons[2]
local callsBeforeCategory=#auctionCalls
categoryButton:GetScript("OnClick")(categoryButton)
check(#auctionCalls==callsBeforeCategory,"category click does not send a query")
check(#d.rows==0 and d.pending,"category change clears stale results and waits for Search")
ns.Auction.frame.refresh:GetScript("OnClick")(ns.Auction.frame.refresh)
check(#auctionCalls==callsBeforeCategory+1 and auctionCalls[#auctionCalls].itemClassFilters[1].classID==2,"Search sends the chosen category's query filter")
Emit("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
-- A picked category replaces the list with its own path and subcategories.
categoryButton=ns.Auction.frame.categoryButtons[1]
check(categoryButton.text:GetText():find("Weapons",1,true) and categoryButton.active,"picked category heads the list")
check(ns.Auction.frame.categoryButtons[2].text:GetText():find("One-Handed",1,true),"selecting native category shows its subcategories")
check(not ns.Auction.frame.categoryButtons[3]:IsShown(),"other categories are hidden while one is picked")
check(ns.Auction.frame.categoryBack:IsShown() and ns.Auction.frame.categoryBack.text:GetText():find("All categories",1,true),"Back names the level it returns to")
check(AuctionCategories[1].expanded==nil,"expansion state stays addon-owned")
check(ns.Auction.frame.breadcrumb:GetText():find("Weapons",1,true),"breadcrumb shows applied category")
check(ns.Auction.frame.categoryButtons[2].depth==1,"subcategory indentation is structural")
local rowButton
for _,control in ipairs(frames) do if control.item and control.quantity and control:IsVisible() then rowButton=control break end end
categoryButton:GetScript("OnEnter")(categoryButton)
check(categoryButton.focusRing:IsShown() and categoryButton.active,"category focus and active filter both visible")
rowButton:GetScript("OnEnter")(rowButton)
check(categoryButton.active and not categoryButton.focusRing:IsShown(),"moving focus retains category selection without focus glow")
check(rowButton.role=="row" and rowButton.focusRing:IsShown(),"result focus uses row styling")
ns.Auction.frame.tabButtons[2]:GetScript("OnClick")(ns.Auction.frame.tabButtons[2])
check(not ns.Auction.frame.categoryButtons[1]:IsShown() and ns.Auction.frame.sidebarHelp:IsShown(),"bag lookup does not imply category filters apply")
check(ns.Auction.frame.viewTitle:GetText()=="Sell an item","sell context is explicit")
check(#ns.Auction.frame.tabButtons==3,"Buy, Sell and Auctions tabs only (no Recent)")
-- A sold auction of yours is listed greyed out with its mail countdown, and cannot be cancelled.
local api=C_AuctionHouse
local oldNum,oldInfo=api.GetNumOwnedAuctions,api.GetOwnedAuctionInfo
api.GetNumOwnedAuctions=function() return 1 end
api.GetOwnedAuctionInfo=function() return {itemKey={itemID=9,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0},itemLink="[Ore]",
    quantity=5,buyoutAmount=900,auctionID=77,status=1,timeLeftSeconds=3000} end
ns.Auction.frame.tabButtons[3]:GetScript("OnClick")(ns.Auction.frame.tabButtons[3])
Emit("OWNED_AUCTIONS_UPDATED")
local soldRow
for _,b in ipairs(frames) do if b.item and b.item.auctionID==77 and b:IsVisible() then soldRow=b end end
check(soldRow and soldRow.sold and soldRow.note:IsShown() and soldRow.note:GetText():find("mailbox",1,true),"sold auction is greyed with its mail time")
soldRow.action()
check(not (ns.AuctionTransactions.current and ns.AuctionTransactions.current.kind=="cancel"),"a sold auction does not open cancellation")
check(ns.Auction.frame.previous.disabled and ns.Auction.frame.next.disabled,"paging keys are greyed out with a single page")
api.GetNumOwnedAuctions,api.GetOwnedAuctionInfo=oldNum,oldInfo
ns.Auction.frame.tabButtons[1]:GetScript("OnClick")(ns.Auction.frame.tabButtons[1])
Emit("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") -- leaving Auctions re-runs the browse search
ns.Auction.frame.filter:GetScript("OnClick")(ns.Auction.frame.filter)
check(ns.Auction.frame.status:GetText():find("Choose filters",1,true),"controller filter page opens")
check(ns.Auction.frame.viewTitle:GetText()=="Search filters" and ns.Auction.frame.back:IsShown(),"filters show distinct context and back affordance")
ns.Auction.frame.filter:GetScript("OnClick")(ns.Auction.frame.filter)
ns.AuctionFilters.category=nil
fullResults=false
check(d.Search("silk"),"repeat search")
Emit("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
ns.Auction.Page(1)
check(d.busy and auctionCalls[#auctionCalls]=="more","next requests additional modern results")
for i=2,8 do browseResults[i]={itemKey={itemID=i,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0},minPrice=500,totalQuantity=i} end
fullResults=true
Emit("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
check(ns.Auction.frame.page:GetText():find("Page 2 / 2",1,true),"newly loaded page becomes visible")
check(d.Details(d.rows[1]),"detail query")
Emit("ITEM_SEARCH_RESULTS_UPDATED",{itemID=99})
check(d.busy,"ignore unrelated detail event")
Emit("ITEM_SEARCH_RESULTS_UPDATED",browseResults[1].itemKey)
check(not d.busy and d.rows[1].price==10000,"listing details")
check(ns.Auction.frame.viewTitle:GetText():find("Listings:",1,true) and ns.Auction.frame.back:IsShown(),"listing drilldown has heading and explicit return")
check(not ns.Auction.frame.categoryButtons[1]:IsShown(),"listing view does not mix browse categories with offers")
C_AuctionHouse.SendBrowseQuery({searchString="external"})
check(d.mode=="invalid" and #d.rows==0,"external query invalidates stale results")
throttle=false
check(not d.Search("ore"),"respect throttle") throttle=true
check(d.Search("ore"),"retry")
now=now+16 Tick(0)
check(not d.busy and d.mode=="invalid","timeout recovers")
ns.Auction.Open()
check(ns.Auction.frame:IsShown(),"auction frame builds")
local f=ns.Auction.frame
f:GetScript("OnGamePadButtonDown")(f,"PAD3")
f:GetScript("OnGamePadButtonUp")(f,"PAD3")
check(ns.KB.target and ns.KB.target.auctionInput,"auction opens owned search")
ns.HideKeyboard()
combat=true Emit("PLAYER_REGEN_DISABLED")
f:GetScript("OnGamePadButtonDown")(f,"PAD1")
check(not d.busy,"combat ignores auction input")
Emit("AUCTION_HOUSE_CLOSED")
combat=false Emit("PLAYER_REGEN_ENABLED")
check(not f:IsShown() and not f.capture,"close during combat releases capture after combat")
check(not d.Search("ore"),"no queries away from auctioneer")
-- Legacy branch and native-cache invalidation use the same public model.
AuctionFrame=CreateFrame("Frame","AuctionFrame",UIParent)
QueryAuctionItems=function(...) legacyQuery={...} end
GetNumAuctionItems=function() return 1,51 end
GetAuctionItemInfo=function() return "Silk",1,20,1,nil,nil,nil,100,nil,20000,0,nil,nil,"Seller" end
GetAuctionItemLink=function() return link end
CanSendAuctionQuery=function() return true end
Emit("AUCTION_HOUSE_SHOW")
check(d.backend=="legacy","legacy visible window takes precedence")
check(d.Search("silk",0),"legacy search")
Emit("AUCTION_ITEM_LIST_UPDATE")
check(d.rows[1].count==20 and d.rows[1].price==20000 and d.more,"legacy stack price and paging")
ns.Auction.Open()
check(ns.Auction.frame.quantityHeader:GetText()=="Stack","legacy quantity does not claim market total")
check(d.More() and legacyQuery[4]==1,"legacy requests next server page")
QueryAuctionItems("outside")
check(d.mode=="invalid","legacy external query invalidates")
-- The custom window must cover native hit targets even with differing frame/UI scales.
local function browserBounds()
    local f=ns.Auction.frame
    local _,relative,point,x,y=f:GetPoint(1)
    check(relative==UIParent and point=="BOTTOMLEFT","placement does not anchor to native frames")
    return x*f.scale-550*f.scale,y*f.scale-330*f.scale,x*f.scale+550*f.scale,y*f.scale+330*f.scale
end
UIParent:SetScale(0.8)
AuctionFrame:SetScale(0.9)
AuctionFrame:SetSize(800,500)
AuctionFrame.left,AuctionFrame.bottom=100,200
ns.Auction.Open()
local left,bottom,right,top=browserBounds()
check(left<=90-8 and right>=810+8 and bottom<=180-40 and top>=630+8,"browser covers scaled native trim and tabs")
check(ns.Auction.frame.mouseEnabled,"browser background intercepts mouse clicks")
AuctionFrame.left,AuctionFrame.bottom=300,250
Tick(0.15)
left,bottom,right,top=browserBounds()
check(left<=270-8 and right>=990+8 and bottom<=225-40 and top>=675+8,"browser follows native window movement")
check(AuctionFrame:GetWidth()==800 and AuctionFrame.scale==0.9,"native geometry remains unchanged")
UIParent:SetScale(1)
print("Passed "..checks.." regression assertions")
