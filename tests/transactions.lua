local count = 0
local function check(v,message) count=count+1 assert(v,message) end
local T,D,api = ns.AuctionTransactions,ns.AuctionData,C_AuctionHouse
local calls = {}
local function record(name,...)
    calls[#calls+1] = {name,...}
end
local money,remaining,deposit,postCount = 10000000,20,100,8
GetMoney=function() return money end
UnitGUID=function() return "player" end
Enum.ItemCommodityStatus={Commodity=2,Item=1}
ItemLocation={CreateFromBagAndSlot=function(_,bag,slot) return {bagID=bag,slotIndex=slot} end}
local link="|Hitem:1|h[Silk]|h"
local bagInfo={itemID=1,hyperlink=link,stackCount=8}
C_Item={GetItemGUID=function() return "item-guid" end}
C_Container.GetContainerItemInfo=function() return bagInfo end
C_Container.GetContainerItemLink=function() return bagInfo and bagInfo.hyperlink end
local commodity=false
api.GetItemCommodityStatus=function() return commodity and 2 or 1 end
api.IsSellItemValid=function() return bagInfo~=nil end
api.GetAvailablePostCount=function() return postCount end
api.CalculateItemDeposit=function() return deposit end
api.CalculateCommodityDeposit=function() return deposit end
api.SupportsCopperValues=function() return true end
api.PlaceBid=function(...) record("bid",...) end
api.StartCommoditiesPurchase=function(...) record("quote",...) end
api.ConfirmCommoditiesPurchase=function(...) record("purchase",...) end
api.CancelCommoditiesPurchase=function() record("cancelQuote") end
api.GetQuoteDurationRemaining=function() return remaining end
local warning=false
api.PostItem=function(...) record("postItem",...) if warning then Emit("AUCTION_HOUSE_POST_WARNING") end return warning end
api.PostCommodity=function(...) record("postCommodity",...) if warning then Emit("AUCTION_HOUSE_POST_WARNING") end return warning end
api.ConfirmPostItem=function(...) record("confirmItem",...) end
api.ConfirmPostCommodity=function(...) record("confirmCommodity",...) end
api.CancelSell=function() record("cancelSell") end
api.GetCancelCost=function() return 500 end
api.CanCancelAuction=function() return true end
api.CancelAuction=function(...) record("cancelAuction",...) end
StaticPopup_Hide=function(name) record("hidePopup",name) end
local key={itemID=1,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0}
local listing={auctionID=123,quantity=1,itemLink=link,minBid=200,buyoutAmount=1000,owners={"Seller"}}
api.GetItemSearchResultInfo=function() return listing end
api.GetNumItemSearchResults=function() return 1 end
api.GetItemKeyFromItem=function() return key end
AuctionFrame:Hide()
ns.Auction.Close(true)
combat=false
ns.Auction.Open()
local function reset()
    T.Close(true)
    D.active,D.backend,D.mode,D.itemKey,D.busy=true,"modern","details",key,false
    D.Read()
end
reset()
local before=#calls
check(T.Open("buy",D.rows[1]),"open item purchase")
check(T.Review() and #calls==before,"review does not spend money")
check(T.Confirm() and calls[#calls][1]=="bid" and calls[#calls][2]==123 and calls[#calls][3]==1000,"buyout uses auction ID and exact amount")
before=#calls
check(not T.Confirm() and #calls==before,"duplicate confirm blocked")
Emit("AUCTION_HOUSE_PURCHASE_COMPLETED",124)
check(T.current.phase=="sending","unrelated purchase event ignored")
Emit("AUCTION_HOUSE_PURCHASE_COMPLETED",123)
check(T.current.phase=="done" and D.mode=="invalid","purchase completes only on matching server response")
reset()
T.Open("buy",D.rows[1]) T.Review()
listing.buyoutAmount=1200
before=#calls
check(not T.Confirm() and #calls==before,"changed buyout cannot be accepted with stale amount")
listing.buyoutAmount=1000
reset()
T.Open("buy",D.rows[1]) T.Update("method","bid") T.Update("bid",1000)
check(not T.Review(),"bid cannot silently become buyout")
T.Update("bid",300) check(T.Review(),"valid bid review")
money=0 before=#calls
check(not T.Confirm() and #calls==before,"funds rechecked at confirmation")
money=10000000
check(T.Confirm() and calls[#calls][3]==300,"bid uses entered amount")
Emit("BID_ADDED",123)
check(T.current.phase=="done","bid acknowledgement handled")
reset()
T.Open("buy",D.rows[1]) T.Review()
C_AuctionHouse.SendBrowseQuery({searchString="outside"})
check(T.current.phase=="error" and not T.Confirm(),"external query invalidates item confirmation")
reset()
local row={name="Silk",itemID=1,itemKey=key,commodity=true,count=20,price=100}
T.Open("buy",row) T.Update("quantity",4)
check(T.Review() and T.current.phase=="quote" and calls[#calls][1]=="quote","commodity first requests a quote")
before=#calls
check(not T.Confirm() and #calls==before,"commodity cannot confirm without quote")
Emit("COMMODITY_PRICE_UPDATED",110,440)
check(T.current.total==440 and T.current.phase=="review","actual quote replaces estimated price")
ns.AuctionTradeUI.Handle("PADDDOWN")
local heldAction=ns.AuctionTradeUI.Handle("PAD1")
Emit("COMMODITY_PRICE_UPDATED",120,480)
before=#calls heldAction()
check(#calls==before and T.current.phase=="review","price update between press/release requires a new selection")
check(T.Confirm() and calls[#calls][1]=="purchase" and calls[#calls][3]==4,"confirmed commodity quantity sent")
Emit("COMMODITY_PURCHASE_SUCCEEDED")
check(T.current.phase=="done","commodity completion acknowledged")
reset()
T.Open("buy",row) T.Review() Emit("COMMODITY_PRICE_UPDATED",100,100)
remaining=0 before=#calls
check(not T.Confirm() and #calls==before,"expired quote cannot spend")
remaining=20
reset()
local item={name="Silk",itemID=1,bag=0,slot=1,link=link}
check(T.Open("sell",item),"open bag sale")
T.Update("buyout",2000) T.Update("bid",1000) T.Update("quantity",2)
check(T.Review() and T.current.deposit==100,"deposit comes from Blizzard")
bagInfo.hyperlink="different"
before=#calls
check(not T.Confirm() and #calls==before,"moved/replaced bag item cannot post")
bagInfo.hyperlink=link
check(T.Confirm() and calls[#calls][1]=="postItem" and calls[#calls][4]==2 and calls[#calls][5]==1000 and calls[#calls][6]==2000,"item posting preserves quantity and prices")
Emit("AUCTION_MULTISELL_START",2) Emit("AUCTION_HOUSE_AUCTION_CREATED",900)
check(T.current.phase=="sending","first item of multisell is not completion")
Emit("AUCTION_MULTISELL_UPDATE",2,2)
check(T.current.phase=="done","multisell completion handled")
reset()
warning=true
T.Open("sell",item) T.Update("buyout",2000) T.Review()
check(T.Confirm() and T.current.phase=="warning","server posting warning requires separate confirmation")
Tick(0.01)
check(calls[#calls][1]=="hidePopup" and calls[#calls][2]=="AUCTION_HOUSE_POST_WARNING","stock pendingPost popup does not compete with custom warning")
check(T.Confirm() and calls[#calls][1]=="confirmItem","posting warning uses ConfirmPostItem")
Emit("AUCTION_HOUSE_AUCTION_CREATED",901)
check(T.current.phase=="done","single post acknowledged")
reset()
commodity=true
T.Open("sell",item) T.Update("buyout",500) T.Review() T.Confirm()
check(T.current.phase=="warning" and calls[#calls-1][1]=="postCommodity","commodity post warning shown")
check(T.Confirm() and calls[#calls][1]=="confirmCommodity","commodity warning uses ConfirmPostCommodity")
Emit("AUCTION_HOUSE_AUCTION_CREATED",902)
check(T.current.phase=="done","commodity posting acknowledged")
reset()
warning=false
T.Open("sell",item) T.Update("buyout",500) T.Update("quantity",postCount+1)
check(not T.Review(),"overselling prevented")
T.Update("quantity",1) T.Review()
deposit=200 before=#calls
check(not T.Confirm() and #calls==before and T.current.phase=="edit","changed deposit requires fresh review")
deposit=100
reset()
T.Open("cancel",{name="Silk",auctionID=444})
check(T.Review() and T.current.total==500,"cancellation fee displayed")
check(T.Confirm() and calls[#calls][1]=="cancelAuction" and calls[#calls][2]==444,"cancel uses owned auction ID")
Emit("AUCTION_CANCELED",444)
check(T.current.phase=="done","cancellation acknowledged")
reset()
T.Open("sell",item) T.Update("buyout",500) T.Review() T.Confirm()
Emit("AUCTION_HOUSE_SHOW_ERROR",1)
check(T.current.phase=="error" and not T.Confirm(),"server error stops repeated submission")
reset()
T.Open("buy",row) T.Review()
now=now+31 Tick(0)
check(T.current.phase=="error","missing quote times out without purchase")
reset()
T.Open("buy",row) T.Review() Emit("COMMODITY_PRICE_UPDATED",100,100)
api.StartCommoditiesPurchase(2,3)
check(T.current.phase=="error" and not T.Confirm(),"another buyer cannot replace the active quote")
before=#calls T.Close()
check(#calls==before,"closing an invalidated trade does not cancel someone else's quote")
reset()
T.Open("sell",item)
Emit("ITEM_SEARCH_RESULTS_UPDATED",key)
check(T.current.marketPrice==1000 and T.current.buyout==1000,"selecting a sell item automatically matches lowest buyout")
reset()
T.Open("sell",item) T.Update("buyout",1500)
Emit("ITEM_SEARCH_RESULTS_UPDATED",key)
check(T.current.buyout==1500 and T.current.marketPrice==1000,"late market response preserves manually edited price")
reset()
T.Open("buy",D.rows[1]) T.Update("method","bid") T.Update("bid",300) T.Review() T.Confirm()
api.GetBids=function() return {{auctionID=123,bidAmount=300,bidder="player"}} end
Emit("BIDS_UPDATED")
check(T.current.phase=="done","existing bid update is acknowledged")
reset()
T.Open("buy",D.rows[1]) T.Review()
combat=true before=#calls
check(not T.Confirm() and #calls==before,"combat prevents commit")
Emit("PLAYER_REGEN_DISABLED")
check(not T.current,"combat clears pending transaction")
combat=false Emit("PLAYER_REGEN_ENABLED")
ns.Auction.Open()
local f=ns.Auction.frame
D.busy=false
f:GetScript("OnGamePadButtonDown")(f,"PAD3") f:GetScript("OnGamePadButtonUp")(f,"PAD3")
ns.HideKeyboard()
check(f.capture and not ns.KB.frame.capture,"keyboard dismissal rearms auction input synchronously")
print("Passed "..count.." transaction assertions")
