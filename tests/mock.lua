-- Minimal UI host; protected native frames are deliberately absent. These tests
-- verify addon behavior, not WoW's secure execution / taint implementation.
frames, timers, messages = {}, {}, {}
now, combat = 10, false
local Frame = {}
Frame.__index = Frame
function CreateFrame(kind, name, parent, template)
    if template == "InputIconTextureFrameTemplate" or template == "GamepadPersistentInputLegendEntryTemplate" then error("template absent") end
    local f = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, events = {}, shown = true, w = 500, h = 32, text = "", alpha = 1, points = {} }, Frame)
    frames[#frames + 1] = f
    if name then _G[name] = f end
    return f
end
function Frame:SetScript(name, fn) self.scripts[name] = fn end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, fn) local old = self.scripts[name] self.scripts[name] = function(...) if old then old(...) end fn(...) end end
function Frame:RegisterEvent(name) self.events[name] = true end
function Frame:UnregisterEvent(name) self.events[name] = nil end
function Frame:GetName() return self.name end
function Frame:GetDebugName() return self.name or self.kind end
function Frame:GetParent() return self.parent end
function Frame:SetParent(p) self.parent = p end
function Frame:IsForbidden() return false end
function Frame:GetObjectType() return self.kind end
function Frame:IsObjectType(kind) return kind == self.kind end
function Frame:CreateTexture() return CreateFrame("Texture", nil, self) end
function Frame:CreateFontString() return CreateFrame("FontString", nil, self) end
function Frame:SetText(t) self.text = t end
function Frame:GetText() return self.text end
function Frame:GetStringWidth() return #self.text * 6 end
function Frame:GetStringHeight() return 16 end
function Frame:SetSize(w,h) self.w,self.h=w,h end
function Frame:SetWidth(w) self.w=w end
function Frame:SetHeight(h) self.h=h end
function Frame:GetWidth() return self.w end
function Frame:GetHeight() return self.h end
function Frame:GetLeft() return self.left end
function Frame:GetBottom() return self.bottom end
function Frame:GetEffectiveScale() return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1) end
function Frame:GetSize() return self.w,self.h end
function Frame:GetFrameLevel() return 1 end
function Frame:SetPoint(...) self.points[#self.points + 1] = {...} end
function Frame:ClearAllPoints() self.points = {} end
function Frame:GetNumPoints() return #self.points end
function Frame:GetPoint(i) return unpack(self.points[i or 1] or {}) end
function Frame:Show() self.shown = true end
function Frame:Hide() local shown=self.shown self.shown=false if shown and self.scripts.OnHide then self.scripts.OnHide(self) end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:IsMouseOver() return false end
function Frame:SetAlpha(a) self.alpha=a end
function Frame:GetAlpha() return self.alpha end
function Frame:GetAttribute(k) return self[k] end
function Frame:SetAttribute(k,v) self[k]=v end
function Frame:GetRegions() end
function Frame:GetChildren() end
function Frame:SetBackdrop(b) self.backdrop=b end
function Frame:GetBackdrop() return self.backdrop end
function Frame:SetTexture(t) self.texture=t end
function Frame:GetTexture() return self.texture end
function Frame:GetAtlas() return nil end
function Frame:Clear() end
function Frame:GetDrawLayer() return "BACKGROUND", 0 end
function Frame:GetVertexColor() return 1,1,1,1 end
function Frame:HasFocus() return false end
function Frame:IsNumeric() return false end
function Frame:IsPassword() return false end
function Frame:EnableGamePadButton(v) assert(not combat, "capture changed in combat") self.capture=v end
function Frame:EnableGamePadStick(v) assert(not combat, "stick capture changed in combat") end
function Frame:SetPropagateKeyboardInput(v) assert(not combat, "propagation changed in combat") self.propagate=v end
for _, name in ipairs({ "SetFrameStrata", "SetFrameLevel", "SetToplevel", "SetClampedToScreen", "EnableMouse", "SetAllPoints", "SetJustifyH", "SetJustifyV", "SetWordWrap", "SetColorTexture", "SetTextColor", "SetVertexColor", "SetFontObject", "SetBackdropColor", "SetBackdropBorderColor", "SetBlendMode", "SetTexCoord", "SetHorizTile", "SetVertTile", "SetScale", "SetShadowOffset", "SetClipsChildren", "SetMaxLines", "SetFading", "SetHyperlinksEnabled", "SetOwner", "SetHyperlink", "SetScrollChild", "SetMovable", "RegisterForDrag", "SetAtlas" }) do
    Frame[name] = function() end
end
function Frame:SetScale(v) self.scale = v end
function Frame:EnableMouse(v) self.mouseEnabled = v end
function Emit(event,...)
    for _,f in ipairs(frames) do if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event,...) end end
end
function Tick(dt)
    now=now+dt
    local pending=timers timers={}
    for _,timer in ipairs(pending) do if not timer.cancelled then timer.fn() end end
    for _,f in ipairs(frames) do if f:IsShown() and f.scripts.OnUpdate then f.scripts.OnUpdate(f,dt) end end
end
C_Timer={}
function C_Timer.NewTimer(delay,fn) local t={fn=fn,Cancel=function(self) self.cancelled=true end} timers[#timers+1]=t return t end
C_Timer.After=C_Timer.NewTimer
function hooksecurefunc(target,name,callback)
    if type(target)=="string" then callback,name,target=name,target,_G end
    local old=target[name]
    target[name]=function(...) local result={old(...)} callback(...) return unpack(result) end
end
function GetTime() return now end
function InCombatLockdown() return combat end
function GetLocale() return "enUS" end
function GetCurrentKeyBoardFocus() return nil end
function EnumerateFrames() return nil end
function print(msg) messages[#messages+1]=msg end
function wipe(t) for k in pairs(t) do t[k]=nil end return t end
date=os.date
bit={band=function(a,b) local n,p=0,1 while a>0 and b>0 do if a%2==1 and b%2==1 then n=n+p end a=math.floor(a/2) b=math.floor(b/2) p=p*2 end return n end}
UIParent=CreateFrame("Frame","UIParent") UIParent:SetSize(1920,1080)
GameFontHighlightMedium="medium" GameFontHighlightSmall="small"
GameFontNormal="normal" GameFontNormalSmall="small"
SlashCmdList={}
C_Texture={GetAtlasInfo=function() return nil end}
C_InputInterfaceStyle={GetCurrentStyle=function() return 1 end}
Enum={AuctionHouseSortOrder={Price=0,Name=1},AuctionHouseFilter={UsableOnly=2,ExactMatch=5}}
ITEM_QUALITY_COLORS={[1]={r=1,g=1,b=1},[2]={r=0.1,g=1,b=0.1}}
C_Container={SetItemSearch=function(t) filterText=t end,GetContainerNumSlots=function() return 0 end,GetContainerItemInfo=function() end,GetContainerItemLink=function() end}
auctionCalls={}
C_AuctionHouse={
    SendBrowseQuery=function(q) auctionCalls[#auctionCalls+1]=q end,
    SendSearchQuery=function(key) auctionCalls[#auctionCalls+1]=key end,
    QueryOwnedAuctions=function() auctionCalls[#auctionCalls+1]="owned" end,
    GetBrowseResults=function() return browseResults or {} end,
    HasFullBrowseResults=function() return fullResults~=false end,
    RequestMoreBrowseResults=function() auctionCalls[#auctionCalls+1]="more" end,
    IsThrottledMessageSystemReady=function() return throttle~=false end,
    GetItemKeyInfo=function(k) return {itemName="Silk",quality=1,iconFileID=134400,isCommodity=false} end,
    GetNumItemSearchResults=function() return 1 end,
    GetItemSearchResultInfo=function() return {quantity=2,buyoutAmount=10000,itemLink="|Hitem:1|h[Silk]|h",owners={"Seller"}} end,
    GetNumOwnedAuctions=function() return 0 end,
    GetOwnedAuctionInfo=function() end,
}
