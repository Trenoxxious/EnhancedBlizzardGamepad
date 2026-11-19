local ADDON, ns = ...

local KB = {}
ns.KB = KB

local TextTarget

local UNIT, GAP, PAD = 40, 6, 14
local HEADER_H, PREVIEW_H, LEGEND_H = 32, 32, 22
local REPEAT_DELAY, REPEAT_RATE = 0.35, 0.06
local STICK_DEADZONE = 0.5

-- Pad button -> action. PAD1..PAD4 are A/B/X/Y on Xbox, Cross/Circle/Square/Triangle on PlayStation.
-- Console on-screen keyboard conventions. PAD1..PAD4 = Cross/Circle/Square/Triangle (A/B/X/Y).
local BUTTON_ACTIONS = {
    PAD1 = "select", PAD2 = "close", PAD3 = "backspace", PAD4 = "space",
    PADDUP = "up", PADDDOWN = "down", PADDLEFT = "left", PADDRIGHT = "right",
    PADLSHOULDER = "caretleft", PADRSHOULDER = "caretright",
    PADLTRIGGER = "shift", PADRTRIGGER = "submit",
    PADLSTICK = "symbols", PADRSTICK = "deleteword",
    PADFORWARD = "submit", PADBACK = "channel", PADSOCIAL = "close",
}
local REPEATABLE = { up = true, down = true, left = true, right = true, backspace = true, caretleft = true, caretright = true }

-- Frame -----------------------------------------------------------------------

local frame = CreateFrame("Frame", "EnhancedBlizzardGamepadFrame", UIParent, "BackdropTemplate")
frame:SetFrameStrata("FULLSCREEN_DIALOG")
frame:SetToplevel(true)
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 60)
frame:Hide()
KB.frame = frame

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
frame.title:SetPoint("TOPLEFT", PAD, -(PAD - 2))
frame.title:SetJustifyH("LEFT")

frame.layoutName = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
frame.layoutName:SetPoint("TOPRIGHT", -PAD, -(PAD - 2))
frame.layoutName:SetJustifyH("RIGHT")

frame.preview = CreateFrame("Frame", nil, frame, "BackdropTemplate")
frame.preview:SetPoint("TOPLEFT", PAD, -(PAD + HEADER_H))
frame.preview:SetPoint("TOPRIGHT", -PAD, -(PAD + HEADER_H))
frame.preview:SetHeight(PREVIEW_H)

frame.previewPrefix = frame.preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
frame.previewPrefix:SetPoint("LEFT", 14, 0)
frame.previewPrefix:SetJustifyH("LEFT")

frame.previewText = frame.preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
frame.previewText:SetPoint("LEFT", frame.previewPrefix, "RIGHT", 0, 0)
frame.previewText:SetPoint("RIGHT", -14, 0)
frame.previewText:SetJustifyH("LEFT")
frame.previewText:SetWordWrap(false)

frame.combat = frame.preview:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
frame.combat:SetPoint("RIGHT", -10, 0)
frame.combat:SetText("Combat: pad locked, use mouse")
frame.combat:Hide()

local faded = {}

local function FadeRegion(region)
    if not region or (region.IsForbidden and region:IsForbidden()) then return end
    if faded[region] == nil then
        local a = region:GetAlpha() or 1
        faded[region] = a > 0.01 and a or 1
    end
    pcall(region.SetAlpha, region, 0)
end

local function RestoreFaded()
    for region, a in pairs(faded) do pcall(region.SetAlpha, region, a) end
    wipe(faded)
end

local function ReapplyFaded()
    for region in pairs(faded) do
        if region:GetAlpha() > 0 then pcall(region.SetAlpha, region, 0) end
    end
end

-- Chat edit boxes -------------------------------------------------------------------
local chatBoxes, chatBoxHooked, chatBoxGuard = {}, {}, false

-- Whether a field gaining focus right now would open the keyboard by itself. The chat box fade
-- below asks the same question, so the box is never faded while no keyboard is coming.
function ns.AutoOpenAllowed()
    local db = ns.db
    if not db or not db.enabled or not db.autoShow then return false end
    if db.requirePad and not ns.IsGamepadActive() then return false end
    return not ns.loadingQuiet
end

local function ChatBoxShouldHide(box)
    if ns.db and ns.db.hideChatBox == false then return false end
    if not (ns.db and ns.db.enabled) then return false end
    if box:HasFocus() and ns.dismissedBox == box then return false end
    if box:HasFocus() and (not frame:IsShown() or KB.closing) then return ns.AutoOpenAllowed() end
    return true
end

function ns.ApplyChatBoxVisibility()
    for _, box in ipairs(chatBoxes) do
        if not box:IsForbidden() then
            pcall(box.SetAlpha, box, ChatBoxShouldHide(box) and 0 or 1)
        end
    end
end

local function SetupChatBoxes()
    local n = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        local box = _G["ChatFrame" .. i .. "EditBox"]
        if box and not chatBoxHooked[box] and not box:IsForbidden() then
            chatBoxHooked[box] = true
            chatBoxes[#chatBoxes + 1] = box
            pcall(hooksecurefunc, box, "SetAlpha", function(self, a)
                if chatBoxGuard or not a or a <= 0 or not ChatBoxShouldHide(self) then return end
                chatBoxGuard = true
                pcall(self.SetAlpha, self, 0)
                chatBoxGuard = false
            end)
            box:HookScript("OnEditFocusGained", function() C_Timer.After(0, ns.ApplyChatBoxVisibility) end)
            box:HookScript("OnEditFocusLost", function(self)
                if ns.dismissedBox == self then ns.dismissedBox = nil end
                C_Timer.After(0, ns.ApplyChatBoxVisibility)
            end)
        end
    end
    ns.ApplyChatBoxVisibility()
end

-- From addon load until a few seconds after each loading screen, automatic opening is held off
-- (see ns.OnTargetFocused). A manual open (key binding, /ebg show) still works.
-- Every way in ends with a timer that lifts it: the end of a loading screen, entering the world,
-- and, for a loading screen whose end is never reported, a 30 second backstop. Left on, the
-- keyboard would never open by itself again until the next loading screen.
ns.loadingQuiet = true
local quietToken = 0
local function QuietFor(seconds)
    quietToken = quietToken + 1
    local token = quietToken
    ns.loadingQuiet = true
    C_Timer.After(seconds, function()
        if token ~= quietToken then return end
        ns.loadingQuiet = false
        ns.ApplyChatBoxVisibility()
    end)
end
QuietFor(30)
local setup = CreateFrame("Frame")
setup:RegisterEvent("PLAYER_LOGIN")
setup:RegisterEvent("PLAYER_ENTERING_WORLD")
setup:RegisterEvent("LOADING_SCREEN_ENABLED")
setup:RegisterEvent("LOADING_SCREEN_DISABLED")
setup:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        local ok, err = pcall(SetupChatBoxes)
        if not ok then ns.Print("Chat box setup failed: " .. tostring(err)) end
    elseif event == "LOADING_SCREEN_ENABLED" then QuietFor(30)
    else QuietFor(3) end
end)

-- Tabs (channel selector and chat window tabs) use the same button art as the keys.
local function CreateTab(parent, height, onClick)
    local b = ns.Skin.CreateKey(parent)
    b:SetHeight(height)
    b.text:SetFontObject(GameFontHighlightSmall)
    b.underline = b:CreateTexture(nil, "OVERLAY")
    b.underline:SetPoint("BOTTOMLEFT", 5, 3)
    b.underline:SetPoint("BOTTOMRIGHT", -5, 3)
    b.underline:SetHeight(2)
    b.underline:Hide()
    b:SetScript("OnClick", onClick)
    return b
end

local function StyleTab(b, state, r, g, bl)
    ns.Skin.StyleKey(b, state == "active" and "selected" or "normal")
    b.text:SetFontObject(GameFontHighlightSmall)
    b:SetAlpha(state == "unavailable" and 0.4 or 1)
    b.underline:Hide()
    if state == "active" then
        b.text:SetTextColor(math.min(1, r + 0.3), math.min(1, g + 0.3), math.min(1, bl + 0.3))
        local lit = false
        for _, t in ipairs(b.glowParts or {}) do
            if t:IsShown() then
                local _, _, _, a = t:GetVertexColor()
                t:SetVertexColor(r, g, bl, a)
                lit = true
            end
        end
        -- Skins without button art: tint the flat key instead.
        if not lit and b.SetBackdropColor and not b.templated then
            b:SetBackdropColor(r * 0.45, g * 0.45, bl * 0.45, 1)
            b:SetBackdropBorderColor(r, g, bl, 1)
        end
    elseif state == "available" then
        b.text:SetTextColor(r, g, bl)
    else
        b.text:SetTextColor(0.55, 0.55, 0.55)
    end
end

-- Chat mirror ------------------------------------------------------------------------
local mirror, mirrorSource
local mirrorHooked = {}
local MIRROR_H, MIRROR_BACKFILL, MIRROR_TAB_H = 176, 40, 22

local function MirrorFrame()
    if mirror then return mirror end
    local holder = CreateFrame("Frame", "EnhancedBlizzardGamepadChatMirror", frame)
    holder:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 6, 2)
    holder:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -6, 2)
    holder:SetHeight(MIRROR_H)
    holder.bg = holder:CreateTexture(nil, "BACKGROUND")
    holder.bg:SetAllPoints()
    holder.bg:SetColorTexture(0, 0, 0, 0.62)
    holder.line = holder:CreateTexture(nil, "BORDER")
    holder.line:SetPoint("TOPLEFT"); holder.line:SetPoint("TOPRIGHT")
    holder.line:SetHeight(1)
    holder.line:SetColorTexture(0.55, 0.45, 0.22, 0.9)
    local ok, msg = pcall(CreateFrame, "ScrollingMessageFrame", nil, holder)
    if not ok or not msg then holder:Hide() mirror = false return false end
    msg:SetPoint("TOPLEFT", 10, -(MIRROR_TAB_H + 10))
    msg:SetPoint("BOTTOMRIGHT", -40, 6)
    -- Tab row: R2 + D-pad left/right switches which chat window the copy shows.
    holder.tabRow = CreateFrame("Frame", nil, holder)
    holder.tabRow:SetPoint("TOPLEFT", 8, -5)
    holder.tabRow:SetPoint("TOPRIGHT", -8, -5)
    holder.tabRow:SetHeight(MIRROR_TAB_H)
    holder.tabRow.tabs = {}
    holder.tabRow.glyphs = {}
    holder.tabRow.plus = holder.tabRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    holder.tabRow.plus:SetText("+")
    holder.tabSep = holder:CreateTexture(nil, "BORDER")
    holder.tabSep:SetPoint("TOPLEFT", 8, -(MIRROR_TAB_H + 6))
    holder.tabSep:SetPoint("TOPRIGHT", -8, -(MIRROR_TAB_H + 6))
    holder.tabSep:SetHeight(1)
    holder.tabSep:SetColorTexture(0.55, 0.45, 0.22, 0.45)
    -- Right stick scroll hint on the right edge.
    holder.stick = holder:CreateTexture(nil, "ARTWORK")
    holder.stick:SetSize(24, 24)
    holder.stick:SetPoint("RIGHT", -8, 0)
    holder.up = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    holder.up:SetPoint("BOTTOM", holder.stick, "TOP", 0, 1)
    holder.up:SetText("^")
    holder.down = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    holder.down:SetPoint("TOP", holder.stick, "BOTTOM", 0, -1)
    holder.down:SetText("v")
    msg:SetFontObject(ChatFontNormal)
    msg:SetJustifyH("LEFT")
    msg:SetFading(false)
    msg:SetMaxLines(120)
    if msg.SetInsertMode then pcall(msg.SetInsertMode, msg, "BOTTOM") end
    msg:SetHyperlinksEnabled(true)
    msg:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if SetItemRef then pcall(SetItemRef, link, text, button, self) end
    end)
    holder.msg = msg
    holder:Hide()
    mirror = holder
    return mirror
end

local function HookChatFrame(cf)
    if not cf or mirrorHooked[cf] or (cf.IsForbidden and cf:IsForbidden()) then return end
    mirrorHooked[cf] = true
    pcall(hooksecurefunc, cf, "AddMessage", function(self, text, r, g, b)
        if mirror and mirror:IsShown() and self == mirrorSource then
            pcall(mirror.msg.AddMessage, mirror.msg, text, r, g, b)
        end
    end)
end

-- Chat windows that have a tab (docked or shown), excluding the combat log.
local function MirrorWindows()
    local list = {}
    local n = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, n do
        local cf = _G["ChatFrame" .. i]
        if cf and not (cf.IsForbidden and cf:IsForbidden()) and cf ~= _G.COMBATLOG then
            local ok, name, _, _, _, _, _, shown, _, docked = pcall(GetChatWindowInfo, i)
            if ok and name and name ~= "" and (shown or docked) then
                list[#list + 1] = { frame = cf, name = name }
            end
        end
    end
    return list
end

-- Small native glyph (Blizzard icon frame, atlas fallback) parented to the tab row.
local function TabRowGlyph(row, i, button)
    local g = row.glyphs[i]
    if not g then
        g = { native = ns.Glyphs.CreateNativeIcon(row) or false, tex = row:CreateTexture(nil, "ARTWORK") }
        if g.native then g.native:SetSize(18, 17) end
        g.tex:SetSize(18, 18)
        row.glyphs[i] = g
    end
    if g.native and ns.Glyphs.BindNativeIcon(g.native, button) then
        g.tex:Hide()
        g.native:Show()
        return g.native
    end
    if g.native then g.native:Hide() end
    if ns.Glyphs.Apply(g.tex, button) then return g.tex end
    return nil
end

local function MirrorTab(row, i)
    local b = row.tabs[i]
    if b then return b end
    b = CreateTab(row, MIRROR_TAB_H - 2, function(self) ns.SetChatMirrorSource(self.chatFrame) end)
    row.tabs[i] = b
    return b
end

local function RefreshMirrorTabs()
    local m = mirror
    if not m then return end
    local row = m.tabRow
    local windows = MirrorWindows()
    local multi = #windows > 1
    local x = 0
    local function place(region, w, gap)
        region:ClearAllPoints()
        region:SetPoint("LEFT", row, "LEFT", x, 0)
        x = x + w + (gap or 4)
    end
    for _, g in ipairs(row.glyphs) do
        if g.native then g.native:Hide() end
        g.tex:Hide()
    end
    row.plus:Hide()
    if multi then
        local r2 = TabRowGlyph(row, 1, "PADRTRIGGER")
        if r2 then place(r2, 18, 1) end
        row.plus:Show()
        place(row.plus, row.plus:GetStringWidth(), 1)
        local left = TabRowGlyph(row, 2, "PADDLEFT")
        if left then place(left, 18, 6) end
    end
    for i, win in ipairs(windows) do
        local b = MirrorTab(row, i)
        b.chatFrame = win.frame
        b.text:SetText(win.name)
        local w = math.max(48, b.text:GetStringWidth() + 22)
        b:SetWidth(w)
        place(b, w, 6)
        if win.frame == mirrorSource then
            StyleTab(b, "active", 1, 0.82, 0.25)
        else
            StyleTab(b, "available", 0.85, 0.80, 0.65)
        end
        b:Show()
    end
    for i = #windows + 1, #row.tabs do row.tabs[i]:Hide() end
    if multi then
        x = x + 3
        local right = TabRowGlyph(row, 3, "PADDRIGHT")
        if right then place(right, 18) end
    end
    m.windows = windows
end

-- Fades Blizzard's chat tabs and dock while the copy (with its own tabs) is up.
local function FadeChatTabs()
    if ns.db and ns.db.fadeChatFrame == false then return end
    FadeRegion(_G.GeneralDockManager)
    local n = _G.NUM_CHAT_WINDOWS or 10
    for i = 1, n do FadeRegion(_G["ChatFrame" .. i .. "Tab"]) end
end

local function Backfill(m, source)
    m.msg:Clear()
    -- Copy the recent history so the mirror does not start empty.
    pcall(function()
        local n = source:GetNumMessages()
        for i = math.max(1, n - MIRROR_BACKFILL + 1), n do
            local text, r, g, b = source:GetMessageInfo(i)
            if text then m.msg:AddMessage(text, r, g, b) end
        end
    end)
end

-- Switches the copy to another chat window. View only: Blizzard's selected tab is not changed.
function ns.SetChatMirrorSource(cf)
    local m = mirror
    if not m or not m:IsShown() or not cf or cf == mirrorSource then return end
    mirrorSource = cf
    HookChatFrame(cf)
    Backfill(m, cf)
    RefreshMirrorTabs()
    ns.PlayClick()
end

function ns.CycleChatMirror(dir)
    local m = mirror
    if not m or not m:IsShown() then return false end
    local windows = m.windows or MirrorWindows()
    if #windows < 2 then return true end
    local idx = 1
    for i, w in ipairs(windows) do if w.frame == mirrorSource then idx = i break end end
    local nextIdx = ((idx - 1 + dir) % #windows) + 1
    ns.SetChatMirrorSource(windows[nextIdx].frame)
    return true
end

function ns.ShowChatMirror()
    if ns.db and ns.db.chatMirror == false then return end
    local m = MirrorFrame()
    if not m then return end
    local source = _G.SELECTED_CHAT_FRAME or _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
    if not source or (source.IsForbidden and source:IsForbidden()) then return end
    if m:IsShown() and mirrorSource == source then return end
    mirrorSource = source
    HookChatFrame(source)
    FadeChatTabs()
    local scroll = not (ns.db and ns.db.mirrorScroll == false)
    local hasIcon = scroll and ns.Glyphs.Apply(m.stick, "RSTICKMOVE")
    if not hasIcon then m.stick:Hide() end
    m.up:SetShown(hasIcon and true or false)
    m.down:SetShown(hasIcon and true or false)
    -- The copy replaces the real window while typing; its alpha is put back on close.
    if not (ns.db and ns.db.fadeChatFrame == false) then FadeRegion(source) end
    Backfill(m, source)
    m:Show()
    RefreshMirrorTabs()
end

function ns.HideChatMirror()
    if not mirror then return end
    mirror:Hide()
    mirror.msg:Clear()
    mirrorSource = nil
    RestoreFaded()
end

-- dir > 0 scrolls back through history, dir < 0 toward the newest line.
function ns.ScrollChatMirror(dir)
    if not mirror or not mirror:IsShown() then return false end
    local msg = mirror.msg
    if dir > 0 then msg:ScrollUp() else msg:ScrollDown() end
    return true
end

function ns.ChatMirrorShown()
    return mirror and mirror:IsShown() or false
end

function ns.ChatMirrorScrollable()
    return mirror and mirror:IsShown() and not (ns.db and ns.db.mirrorScroll == false) or false
end

-- Chat channels ---------------------------------------------------------------------

local BASE_ORDER = { "SAY", "INSTANCE_CHAT", "PARTY", "RAID", "GUILD", "YELL" }
local CHANNEL_LABEL = {
    SAY = _G.SAY or "Say", INSTANCE_CHAT = _G.INSTANCE or "Instance", PARTY = _G.PARTY or "Party",
    RAID = _G.RAID or "Raid", GUILD = _G.GUILD or "Guild", YELL = _G.YELL or "Yell",
    WHISPER = _G.WHISPER or "Whisper", OFFICER = _G.OFFICER or "Officer",
}
-- Shown greyed out when unavailable; the rest only appear when usable.
local ALWAYS_LISTED = { SAY = true, PARTY = true, RAID = true, GUILD = true, YELL = true }
local FALLBACK_COLOR = {
    SAY = { 1, 1, 1 }, YELL = { 1, 0.25, 0.25 }, PARTY = { 0.67, 0.67, 1 }, RAID = { 1, 0.5, 0 },
    GUILD = { 0.25, 1, 0.25 }, WHISPER = { 1, 0.5, 1 }, BN_WHISPER = { 0, 1, 0.96 },
    INSTANCE_CHAT = { 1, 0.5, 0 }, CHANNEL = { 1, 0.75, 0.75 },
}

local function ChannelColor(chatType, channel)
    local info = ChatTypeInfo and ((channel and ChatTypeInfo["CHANNEL" .. channel]) or ChatTypeInfo[chatType])
    if info and info.r then return info.r, info.g, info.b end
    local c = FALLBACK_COLOR[chatType] or FALLBACK_COLOR.SAY
    return c[1], c[2], c[3]
end

local function ChannelAvailable(chatType)
    if chatType == "SAY" or chatType == "YELL" then return true end
    if chatType == "INSTANCE_CHAT" then return IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) or false end
    if chatType == "PARTY" then return IsInGroup and IsInGroup(LE_PARTY_CATEGORY_HOME) or false end
    if chatType == "RAID" then return IsInRaid and IsInRaid(LE_PARTY_CATEGORY_HOME) or false end
    if chatType == "GUILD" then return IsInGuild and IsInGuild() or false end
    return false
end

-- Numbered channels the player has joined: { id, name }.
local function JoinedChannels()
    local out = {}
    if not GetChannelList then return out end
    local ok, t = pcall(function() return { GetChannelList() } end)
    if not ok then return out end
    for i = 1, #t, 3 do
        local id, name, disabled = t[i], t[i + 1], t[i + 2]
        if type(id) == "number" and type(name) == "string" and not disabled then
            -- "General - Elwynn Forest" -> "General"
            local short = name:match("^(.-)%s+%-%s") or name
            out[#out + 1] = { id = id, name = short }
        end
    end
    return out
end

local function ShortName(name)
    if type(name) ~= "string" then return tostring(name) end
    return Ambiguate and Ambiguate(name, "short") or name
end

local function ChannelList(box)
    local cur = box:GetAttribute("chatType") or "SAY"
    local curTell = box:GetAttribute("tellTarget")
    local curChannel = box:GetAttribute("channelTarget")
    local pending = KB.whisperPending
    local list, found = {}, pending and true or false
    local function add(e)
        if pending then e.active = false end
        if e.active then found = true end
        list[#list + 1] = e
    end
    for _, t in ipairs(BASE_ORDER) do
        local avail = ChannelAvailable(t)
        if avail or ALWAYS_LISTED[t] or t == cur then
            add({ type = t, label = CHANNEL_LABEL[t], available = avail or t == cur, active = t == cur })
        end
    end
    for _, ch in ipairs(JoinedChannels()) do
        add({ type = "CHANNEL", channel = ch.id, label = ch.id .. ". " .. ch.name, available = true,
            active = cur == "CHANNEL" and tostring(curChannel) == tostring(ch.id) })
    end
    local whisperActive = (cur == "WHISPER" or cur == "BN_WHISPER") and curTell and curTell ~= ""
    if whisperActive then
        add({ type = cur, tell = curTell, label = "To " .. ShortName(curTell), available = true, active = true })
    end
    -- Reply to the most recent whisper received.
    if ChatEdit_GetLastTellTarget then
        local ok, name, tellType = pcall(ChatEdit_GetLastTellTarget)
        if ok and name and name ~= "" and not (whisperActive and name == curTell) then
            add({ type = tellType or "WHISPER", tell = name, label = "Reply " .. ShortName(name), available = true, active = false })
        end
    end
    list[#list + 1] = { type = "WHISPER", pending = true, label = CHANNEL_LABEL.WHISPER, available = true, active = pending and true or false }
    if not found then
        -- Officer and anything else not listed: show as an extra active tab.
        local label = CHANNEL_LABEL[cur] or ns.DescribeTarget(box):gsub("^%a+: ", "")
        list[#list + 1] = { type = cur, label = label, available = true, active = true, extra = true }
    end
    return list, cur
end

-- Channel tabs in the header: bright and filled = typing here, colored = available, grey = not available.
frame.tabs = CreateFrame("Frame", nil, frame)
frame.tabs:SetPoint("TOPLEFT", PAD, -(PAD + 4))
frame.tabs:SetHeight(24)
frame.tabs.buttons = {}
frame.tabs.hintIcon = frame.tabs:CreateTexture(nil, "ARTWORK")
frame.tabs.hintIcon:SetSize(18, 18)
frame.tabs.hintIcon:SetPoint("LEFT", 0, 0)

local TAB_H, TAB_GAP, TAB_ROW_GAP = 24, 6, 5

local function ChannelTab(i)
    local b = frame.tabs.buttons[i]
    if b then return b end
    b = CreateTab(frame.tabs, TAB_H, function(self)
        if self.entry and self.entry.available and not self.entry.extra then KB:SetChannel(self.entry) end
    end)
    frame.tabs.buttons[i] = b
    return b
end

function KB:RefreshTabs()
    local box = self.target
    local isChat = box and not box:IsForbidden() and ns.IsChatBox(box)
    frame.tabs:SetShown(isChat and true or false)
    frame.title:SetShown(not isChat)
    if not isChat then
        frame.tabs:SetSize(1, TAB_H)
        self.tabRows = 0
        return
    end
    local wrap = self.tabWrap or 560
    local x, row = 0, 0
    local tabs = frame.tabs
    if tabs.hintNative == nil then
        tabs.hintNative = ns.Glyphs.CreateNativeIcon(tabs) or false
        if tabs.hintNative then tabs.hintNative:SetSize(22, 21) end
    end
    local hint
    if tabs.hintNative and ns.Glyphs.BindNativeIcon(tabs.hintNative, "PADBACK") then
        tabs.hintNative:Show()
        tabs.hintIcon:Hide()
        hint = tabs.hintNative
        x = 28
    else
        if tabs.hintNative then tabs.hintNative:Hide() end
        if ns.Glyphs.Apply(tabs.hintIcon, "PADBACK") then hint = tabs.hintIcon x = 24 else tabs.hintIcon:Hide() end
    end
    if hint then
        hint:ClearAllPoints()
        hint:SetPoint("LEFT", tabs, "TOPLEFT", 0, -TAB_H / 2)
    end
    local indent = x
    local widest = x
    local list = ChannelList(box)
    for i, ch in ipairs(list) do
        local b = ChannelTab(i)
        local r, g, bl = ChannelColor(ch.type, ch.channel)
        b.entry = ch
        b.text:SetText(ch.label)
        local w = math.max(50, b.text:GetStringWidth() + 24)
        if x > indent and x + w > wrap then
            row = row + 1
            x = indent
        end
        b:SetWidth(w)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", tabs, "TOPLEFT", x, -row * (TAB_H + TAB_ROW_GAP))
        StyleTab(b, ch.active and "active" or (ch.available and "available" or "unavailable"), r, g, bl)
        b:Show()
        x = x + w + TAB_GAP
        widest = math.max(widest, x - TAB_GAP)
    end
    for i = #list + 1, #tabs.buttons do tabs.buttons[i]:Hide() end
    self.tabRows = row + 1
    tabs:SetSize(math.max(1, widest), self.tabRows * TAB_H + row * TAB_ROW_GAP)
end

function KB:RefreshChannelColor()
    local box = self.target
    local isChat = box and not box:IsForbidden() and ns.IsChatBox(box)
    local r, g, b = 1, 1, 1
    if isChat then
        local list, cur = ChannelList(box)
        local active
        for _, ch in ipairs(list) do if ch.active then active = ch end end
        r, g, b = ChannelColor(active and active.type or cur, active and active.channel)
        local label = active and active.label or cur
        if active and active.pending then label = "Whisper to" end
        frame.previewPrefix:SetText(label .. ":  ")
        frame.previewPrefix:SetTextColor(r, g, b)
        self.channelKey = cur .. "|" .. tostring(box:GetAttribute("tellTarget") or "") .. "|" .. tostring(box:GetAttribute("channelTarget") or "")
    else
        frame.previewPrefix:SetText("")
        self.channelKey = nil
    end
    frame.previewPrefix:SetWidth(math.max(0.01, frame.previewPrefix:GetStringWidth()))
    frame.previewText:SetTextColor(r, g, b)
    if frame.preview.tintArt then
        local tr, tg, tb = 0.5 + r * 0.5, 0.5 + g * 0.5, 0.5 + b * 0.5
        for _, t in ipairs(frame.preview.tintArt) do t:SetVertexColor(tr, tg, tb) end
    end
end

frame.tabs:RegisterEvent("GROUP_ROSTER_UPDATE")
frame.tabs:RegisterEvent("PLAYER_GUILD_UPDATE")
frame.tabs:RegisterEvent("BAG_UPDATE_DELAYED")
pcall(frame.tabs.RegisterEvent, frame.tabs, "CHANNEL_UI_UPDATE")
frame.tabs:SetScript("OnEvent", function(_, event)
    if event == "BAG_UPDATE_DELAYED" and KB.page ~= "items" then return end
    if frame:IsShown() and not KB.closing then KB:Build() end
end)

frame.legendBar = CreateFrame("Frame", nil, frame)
frame.legendBar:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 4, -2)
frame.legendBar:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", -4, -2)
frame.legendBar:SetHeight(LEGEND_H + 16)
frame.legendBar.bg = frame.legendBar:CreateTexture(nil, "BACKGROUND")
frame.legendBar.bg:SetAllPoints()
frame.legendBar.bg:SetColorTexture(0, 0, 0, 0.62)
frame.legendBar.line = frame.legendBar:CreateTexture(nil, "BORDER")
frame.legendBar.line:SetPoint("TOPLEFT", 0, 0)
frame.legendBar.line:SetPoint("TOPRIGHT", 0, 0)
frame.legendBar.line:SetHeight(1)
frame.legendBar.line:SetColorTexture(0.55, 0.45, 0.22, 0.9)
frame.legendBar.lineBottom = frame.legendBar:CreateTexture(nil, "BORDER")
frame.legendBar.lineBottom:SetPoint("BOTTOMLEFT", 0, 0)
frame.legendBar.lineBottom:SetPoint("BOTTOMRIGHT", 0, 0)
frame.legendBar.lineBottom:SetHeight(1)
frame.legendBar.lineBottom:SetColorTexture(0.55, 0.45, 0.22, 0.6)

frame.legend = CreateFrame("Frame", nil, frame.legendBar)
frame.legend:SetPoint("CENTER", 0, 0)
frame.legend:SetHeight(LEGEND_H)
frame.legend.entries = {}

local LEGEND_BASE = {
    { "PAD1", "Type" }, { "PADLSHOULDER", "Cursor", "PADRSHOULDER" }, { "PADLSTICK", "?123" },
}
local LEGEND_QUESTS = {
    { "PAD1", "Link quest" }, { "PADLSHOULDER", "Page", "PADRSHOULDER" }, { "PAD2", "Back" },
}
local function LegendItems(isChat, page)
    if page == "quests" then return LEGEND_QUESTS end
    if page == "items" then return { { "PAD1", "Link item" }, { "PADLSHOULDER", "Page", "PADRSHOULDER" }, { "PAD2", "Back" } } end
    local items = {}
    for i, v in ipairs(LEGEND_BASE) do items[i] = v end
    if isChat then items[#items + 1] = { "PADBACK", "Channel" } end
    items[#items + 1] = { "PAD2", "Close" }
    return items
end

local function LegendEntry(i)
    local e = frame.legend.entries[i]
    if e then return e end
    e = CreateFrame("Frame", nil, frame.legend)
    e:SetHeight(LEGEND_H)
    e.icon = e:CreateTexture(nil, "ARTWORK")
    e.icon:SetSize(18, 18)
    e.icon:SetPoint("LEFT", 0, 0)
    e.icon2 = e:CreateTexture(nil, "ARTWORK")
    e.icon2:SetSize(18, 18)
    e.icon2:SetPoint("LEFT", e.icon, "RIGHT", -2, 0)
    -- Blizzard's full legend entry (icon + text) when its template resolves.
    e.prompt = ns.Glyphs.CreateNativePrompt(e)
    if e.prompt then e.prompt:SetPoint("LEFT", 0, 0) end
    -- Blizzard's own icon frames when the template resolves; they pick art per controller.
    e.native = ns.Glyphs.CreateNativeIcon(e)
    if e.native then
        e.native:SetSize(18, 17)
        e.native:SetPoint("LEFT", 0, 0)
        e.native2 = ns.Glyphs.CreateNativeIcon(e)
        if e.native2 then
            e.native2:SetSize(18, 17)
            e.native2:SetPoint("LEFT", e.native, "RIGHT", -2, 0)
        end
    end
    e.key = e:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    e.key:SetPoint("LEFT", 0, 0)
    e.label = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.legend.entries[i] = e
    return e
end

-- Key buttons -----------------------------------------------------------------

local pool = {}

local function AcquireKey(i)
    local b = pool[i]
    if b then return b end
    b = ns.Skin.CreateKey(frame)
    b:SetScript("OnClick", function(self)
        KB:SelectKey(self.row, self.col)
        KB:PressKey(self.key)
    end)
    b:SetScript("OnEnter", function(self) KB:SelectKey(self.row, self.col) end)
    pool[i] = b
    return b
end

local function KeyWidth(key)
    local w = type(key) == "table" and key.w or 1
    return w * UNIT + (w - 1) * GAP
end

local function RowWidth(row)
    local w = 0
    for i, key in ipairs(row) do
        w = w + KeyWidth(key)
        if i > 1 then w = w + GAP end
    end
    return w
end

function KB:CurrentRows()
    local layout = ns.CurrentLayout()
    if self.page == "numpad" then return ns.NumpadRows end
    if self.page == "symbols" then return ns.SymbolRows end
    if self.page == "accents" then return ns.AccentRows(layout) end
    if self.page == "quests" then return self:QuestRows() end
    if self.page == "items" then return self:ItemRows() end
    local box = self.target
    if box and not box:IsForbidden() and ns.IsChatBox(box) then return layout.rows end
    self.plainRows = self.plainRows or {}
    local cached = self.plainRows[layout.id]
    if not cached then
        cached = {}
        for r, row in ipairs(layout.rows) do
            local out, freed = {}, 0
            for _, k in ipairs(row) do
                if type(k) == "table" and k.chatOnly then freed = freed + (k.w or 1) else out[#out + 1] = k end
            end
            if freed > 0 then
                for i, k in ipairs(out) do
                    if type(k) == "table" and k.action == "space" then
                        out[i] = { label = k.label, w = k.w + freed, action = "space", pad = k.pad }
                    end
                end
            end
            cached[r] = out
        end
        self.plainRows[layout.id] = cached
    end
    if ns.Input.IsSearch(box) then
        local rows = {}
        for i, row in ipairs(cached) do rows[i] = row end
        rows[#rows + 1] = { h = 28, { label = "Clear item filter", w = 12, action = "clearsearch" } }
        return rows
    end
    return cached
end

-- The inventory model also feeds the auction price-lookup tab.
function KB:ItemRows()
    local items = ns.Inventory.Read()
    self.itemPages = math.max(1, math.ceil(#items / 8))
    self.itemPage = math.max(1, math.min(self.itemPage or 1, self.itemPages))
    local rows = {}
    for i = (self.itemPage - 1) * 8 + 1, math.min(#items, self.itemPage * 8) do
        local item = items[i]
        rows[#rows + 1] = { h = 32, gap = 4,
            { label = item.name .. (item.count > 1 and ("  x" .. item.count) or ""), w = 12,
                action = "itemlink", link = item.link, texture = item.icon, color = ns.Inventory.Color(item.quality), small = true } }
    end
    if #rows == 0 then rows[1] = { { label = "No carried items to link", w = 12, action = "letters" } } end
    rows[#rows + 1] = {
        { label = "Prev", w = 3, action = "itemprev", pad = "PADLSHOULDER" },
        { label = "Back", w = 6, action = "letters", pad = "PAD2" },
        { label = "Next", w = 3, action = "itemnext", pad = "PADRSHOULDER" },
    }
    return rows
end

local itemTooltip
function KB:RefreshItemTooltip()
    if self.page ~= "items" then if itemTooltip then itemTooltip:Hide() end return end
    local b = self.grid[self.sel[1]] and self.grid[self.sel[1]][self.sel[2]]
    local link = b and type(b.key) == "table" and b.key.link
    if not link then if itemTooltip then itemTooltip:Hide() end return end
    itemTooltip = itemTooltip or CreateFrame("GameTooltip", "EBGItemLinkTooltip", frame, "GameTooltipTemplate")
    itemTooltip:SetOwner(frame, "ANCHOR_NONE")
    itemTooltip:ClearAllPoints()
    itemTooltip:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 8, 0)
    itemTooltip:SetClampedToScreen(true)
    itemTooltip:SetHyperlink(link)
    itemTooltip:Show()
end

-- Quest link picker ---------------------------------------------------------------

local QUESTS_PER_PAGE = 8
local QUEST_ROW_H, QUEST_ROW_GAP = 24, 4

local function QuestLogEntries()
    local list = {}
    if not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries then return list end
    local n = C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and not info.isHidden and info.questID and info.title then
            list[#list + 1] = { id = info.questID, title = info.title, level = info.level, difficulty = info.difficultyLevel, index = i }
        end
    end
    return list
end

-- Quest difficulty color (grey / green / yellow / orange / red)
local function QuestColor(q)
    local ok, c = pcall(function()
        if C_PlayerInfo and C_PlayerInfo.GetContentDifficultyQuestForPlayer and GetDifficultyColor then
            return GetDifficultyColor(C_PlayerInfo.GetContentDifficultyQuestForPlayer(q.id))
        end
        local level = q.difficulty or q.level
        if GetQuestDifficultyColor and level and level > 0 then return GetQuestDifficultyColor(level) end
    end)
    if ok and type(c) == "table" and c.r then return { c.r, c.g, c.b } end
    return { 1, 0.82, 0 }
end

function KB:QuestRows()
    local quests = QuestLogEntries()
    local pages = math.max(1, math.ceil(#quests / QUESTS_PER_PAGE))
    self.questPage = math.max(1, math.min(self.questPage or 1, pages))
    self.questPages = pages
    local rows = {}
    if #quests == 0 then
        rows[1] = { { label = "No quests in your log", w = 12, action = "letters" } }
    end
    self.questTextCache = {}
    local first = (self.questPage - 1) * QUESTS_PER_PAGE + 1
    for i = first, math.min(#quests, first + QUESTS_PER_PAGE - 1) do
        local q = quests[i]
        local label = q.title
        if q.level and q.level > 0 then label = "[" .. q.level .. "] " .. label end
        -- A second quest's log index lets the details pane check that quest text is read per quest.
        local other = quests[i == 1 and 2 or 1]
        rows[#rows + 1] = {
            h = QUEST_ROW_H, gap = QUEST_ROW_GAP,
            { label = label, w = 12, action = "questlink", questID = q.id, title = q.title, small = true, color = QuestColor(q),
              level = q.level, logIndex = q.index, otherIndex = other and other ~= q and other.index or nil },
        }
    end
    rows[#rows + 1] = {
        { label = "Prev", w = 3, action = "questprev", pad = "PADLSHOULDER" },
        { label = "Back to keyboard", w = 6, action = "letters", pad = "PAD2" },
        { label = "Next", w = 3, action = "questnext", pad = "PADRSHOULDER" },
    }
    return rows
end

local function QuestLink(questID, title)
    local link = GetQuestLink and GetQuestLink(questID)
    if not link and C_QuestLog and C_QuestLog.GetQuestLink then link = C_QuestLog.GetQuestLink(questID) end
    return link or ("[" .. title .. "]")
end

-- Quest details pane ----------------------------------------------------------------
-- Sits to the right of the quest picker and shows the highlighted quest's name, description
-- and objectives, so the player can see what they are about to link.

local QUEST_PANE_ATLAS = "AdventureMapQuest-QuestPane"
local QUEST_PANE_W, QUEST_PANE_H = 351, 438
-- Where the visible art sits inside the atlas: transparent margins, and the two metal bars.
-- titleY / footerY: distance of each bar's text centre from the pane's top / bottom edge.
local QUEST_PANE_ART = { left = 28, right = 28, top = 44, bottom = 24, topBar = 25, bottomBar = 23, titleY = 9, footerY = 19.5 }
local questPane

-- Quest text is read by log index without changing the selected quest. Some clients ignore the
-- index and return the selected quest's text instead; that shows up as another quest returning
-- the very same text, and then no description is shown rather than a wrong one.
local function QuestText(key)
    if not GetQuestLogQuestText or not key.logIndex then return nil, nil end
    local ok, desc, objective = pcall(GetQuestLogQuestText, key.logIndex)
    if not ok or type(desc) ~= "string" then return nil, nil end
    if key.otherIndex then
        local ok2, desc2, objective2 = pcall(GetQuestLogQuestText, key.otherIndex)
        if ok2 and desc2 == desc and objective2 == objective then return nil, nil end
    end
    if desc == "" then desc = nil end
    if type(objective) ~= "string" or objective == "" then objective = nil end
    return desc, objective
end

local function QuestObjectiveLines(key)
    local lines = {}
    local ok, list = pcall(function()
        return C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(key.questID)
    end)
    if ok and type(list) == "table" then
        for _, o in ipairs(list) do
            if type(o) == "table" and type(o.text) == "string" and o.text ~= "" then
                lines[#lines + 1] = { text = o.text, finished = o.finished and true or false }
            end
        end
    elseif GetNumQuestLeaderBoards and GetQuestLogLeaderBoard and key.logIndex then
        local okN, n = pcall(GetNumQuestLeaderBoards, key.logIndex)
        for i = 1, okN and tonumber(n) or 0 do
            local okL, text, _, finished = pcall(GetQuestLogLeaderBoard, i, key.logIndex)
            if okL and type(text) == "string" and text ~= "" then
                lines[#lines + 1] = { text = text, finished = finished and true or false }
            end
        end
    end
    return lines
end

local function QuestDetails(self, key)
    local cache = self.questTextCache
    local d = cache and cache[key.questID]
    if not d then
        local desc, objective = QuestText(key)
        d = { desc = desc, objective = objective, lines = QuestObjectiveLines(key) }
        if cache then cache[key.questID] = d end
    end
    return d
end

local function CreateQuestPane()
    -- The frame is the size of the visible art; the atlas's transparent margins hang outside it.
    local art = QUEST_PANE_ART
    local p = CreateFrame("Frame", nil, frame)
    p:SetSize(QUEST_PANE_W - art.left - art.right, QUEST_PANE_H - art.top - art.bottom)
    p:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 6, 0)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.parchment = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(QUEST_PANE_ATLAS) ~= nil
    if p.parchment then
        p.bg:SetAtlas(QUEST_PANE_ATLAS, false)
        p.bg:SetSize(QUEST_PANE_W, QUEST_PANE_H)
        p.bg:SetPoint("TOPLEFT", -art.left, art.top)
    else
        p.bg:SetAllPoints()
        p.bg:SetColorTexture(0, 0, 0, 0.85)
    end

    -- Quest name in the top metal bar, quest level in the bottom one.
    local function BarText(point, y)
        local fs = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", p, point .. "LEFT", 16, y)
        fs:SetPoint("RIGHT", p, point .. "RIGHT", -16, y)
        fs:SetJustifyH("CENTER")
        fs:SetWordWrap(false)
        return fs
    end
    p.title = BarText("TOP", -art.titleY)
    p.footer = BarText("BOTTOM", art.footerY)
    p.footer:SetFontObject(GameFontNormalSmall)
    p.title:SetJustifyV("MIDDLE")
    p.footer:SetJustifyV("MIDDLE")

    -- Text area on the parchment between the two bars.
    p.body = CreateFrame("Frame", nil, p)
    p.body:SetPoint("TOPLEFT", 22, -(art.topBar + 16))
    p.body:SetPoint("BOTTOMRIGHT", -22, art.bottomBar + 14)
    p.body:SetClipsChildren(true)

    local function Text()
        local fs = p.body:CreateFontString(nil, "OVERLAY", _G.QuestFont and "QuestFont" or "GameFontHighlight")
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        fs:SetWordWrap(true)
        fs:SetShadowOffset(0, 0)
        -- Dark ink on parchment; light text on the plain fallback background.
        if p.parchment then fs:SetTextColor(0.16, 0.1, 0.04) else fs:SetTextColor(1, 1, 1) end
        return fs
    end
    p.summary = Text()
    p.obj = Text()
    p.rule = p.body:CreateTexture(nil, "ARTWORK")
    p.rule:SetHeight(1)
    if p.parchment then p.rule:SetColorTexture(0.25, 0.1, 0, 0.35) else p.rule:SetColorTexture(1, 1, 1, 0.25) end
    p.doneColor = p.parchment and "|cff1d5c1d" or "|cff40d040"
    p:Hide()
    return p
end

-- Lays out one text block under the previous one, cut off (with an ellipsis) at maxH.
local function PlaceQuestText(fs, width, y, maxH)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 0, -y)
    fs:SetWidth(width)
    fs:SetHeight(0)
    local h = fs:GetStringHeight() or 0
    if maxH and h > maxH then
        h = math.max(0, maxH)
        fs:SetHeight(h)
    end
    fs:Show()
    return h
end

function KB:RefreshQuestPane()
    if self.page ~= "quests" then
        if questPane then questPane:Hide() end
        self.questPaneKey = nil
        return
    end
    -- On the Prev/Back/Next row the pane keeps the last quest shown.
    local b = self.sel and self.grid[self.sel[1]] and self.grid[self.sel[1]][self.sel[2]]
    local key = b and type(b.key) == "table" and b.key.action == "questlink" and b.key or self.questPaneKey
    if not key then
        if questPane then questPane:Hide() end
        return
    end
    questPane = questPane or CreateQuestPane()
    local p = questPane
    if key == p.shownKey and p:IsShown() then return end
    self.questPaneKey, p.shownKey = key, key
    p:Show()

    local d = QuestDetails(self, key)
    local width, height = p.body:GetWidth(), p.body:GetHeight()
    if not width or width <= 0 then width, height = p:GetWidth() - 44, p:GetHeight() - 78 end

    p.title:SetText(((key.title or ""):gsub("|", "||")))
    if key.level and key.level > 0 then
        p.footer:SetText((LEVEL or "Level") .. " " .. key.level)
        local c = key.color or { 1, 0.82, 0 }
        p.footer:SetTextColor(c[1], c[2], c[3])
    else
        p.footer:SetText("")
    end

    local parts = {}
    for _, line in ipairs(d.lines) do
        parts[#parts + 1] = line.finished and (p.doneColor .. "- " .. line.text .. "|r") or ("- " .. line.text)
    end
    local hasLines = #parts > 0
    p.obj:SetText(table.concat(parts, "\n"))
    p.summary:SetText(d.objective or (hasLines and "" or "No objectives listed for this quest."))

    -- Progress lines are measured first so a long summary cannot push them out of the pane.
    local gap = 10
    local linesH = hasLines and PlaceQuestText(p.obj, width, 0, height * 0.6) or 0
    local y = 0
    if d.objective or not hasLines then
        y = PlaceQuestText(p.summary, width, 0, height - (hasLines and (linesH + gap * 2 + 1) or 0))
    else
        p.summary:Hide()
    end
    if hasLines and y > 0 then
        p.rule:ClearAllPoints()
        p.rule:SetPoint("TOPLEFT", 0, -(y + gap))
        p.rule:SetPoint("TOPRIGHT", 0, -(y + gap))
        p.rule:Show()
        y = y + gap * 2 + 1
    else
        p.rule:Hide()
    end
    if hasLines then PlaceQuestText(p.obj, width, y, linesH) else p.obj:Hide() end
end

local function LinkSpans(text)
    local spans, init = {}, 1
    while true do
        local s, e = text:find("|H.-|h.-|h", init)
        if not s then break end
        local pre = text:sub(1, s - 1)
        local cs = pre:match("()|c%x%x%x%x%x%x%x%x$") or pre:match("()|cn[^:|]+:$")
        if cs then s = cs end
        if text:sub(e + 1, e + 2) == "|r" then e = e + 2 end
        spans[#spans + 1] = { s, e }
        init = e + 1
    end
    return spans
end
ns.LinkSpans = LinkSpans

function KB:Build()
    local rows = self:CurrentRows()
    self.rows = rows
    self.grid = {}

    local maxW = 0
    for _, row in ipairs(rows) do maxW = math.max(maxW, RowWidth(row)) end
    self:RefreshLegend()
    local bar = frame.legendBar
    local copied = ns.Skin.LegendBackground(bar)
    bar.bg:SetShown(not copied)
    bar.line:SetShown(not copied)
    bar.lineBottom:SetShown(not copied)
    frame.legend:SetFrameLevel(bar:GetFrameLevel() + 2)
    maxW = math.max(maxW, frame.legend:GetWidth() + 8)
    self.tabWrap = maxW - (self.page == "quests" and 150 or 0)
    self:RefreshHeader()
    local width = maxW + PAD * 2
    local headerH = HEADER_H
    if (self.tabRows or 0) > 0 then headerH = 4 + frame.tabs:GetHeight() + 10 end
    frame.preview:ClearAllPoints()
    frame.preview:SetPoint("TOPLEFT", PAD, -(PAD + headerH))
    frame.preview:SetPoint("TOPRIGHT", -PAD, -(PAD + headerH))
    local top = PAD + headerH + PREVIEW_H + 10
    local rowsH = 0
    for i, row in ipairs(rows) do
        rowsH = rowsH + (row.h or UNIT) + (i < #rows and (row.gap or GAP) or 0)
    end
    local height = top + rowsH + PAD

    frame:SetSize(width, height)
    frame:SetScale(ns.db and ns.db.scale or 1)
    ns.Skin.Panel(frame)
    ns.Skin.Inset(frame.preview)

    local n = 0
    local yOff = top
    for r, row in ipairs(rows) do
        self.grid[r] = {}
        local x = (width - RowWidth(row)) / 2
        local y = -yOff
        local rowH = row.h or UNIT
        yOff = yOff + rowH + (row.gap or GAP)
        for c, key in ipairs(row) do
            n = n + 1
            local b = AcquireKey(n)
            local w = KeyWidth(key)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
            b:SetSize(w, rowH)
            b.key, b.row, b.col = key, r, c
            b.cx = x + w / 2
            b:Show()
            self.grid[r][c] = b
            x = x + w + GAP
        end
    end
    for i = n + 1, #pool do pool[i]:Hide() end

    if not self.sel or not self.grid[self.sel[1]] or not self.grid[self.sel[1]][self.sel[2]] then
        self.sel = { math.min(2, #rows), 1 }
    end
    self:RefreshKeys()
    self:RefreshHeader()
end

-- Small controller glyph to the left of a key's label (quest picker navigation).
function KB:SetKeyGlyph(b, button)
    if b.padNative then b.padNative:Hide() end
    if b.padIcon then b.padIcon:Hide() end
    b.text:ClearAllPoints()
    if not button then
        b.text:SetPoint("CENTER", 0, b.templated and 0 or 0)
        return
    end
    -- b.glyphSize lets other panels (the auction house) draw larger glyphs than the keyboard's.
    local size = b.glyphSize or 18
    b.text:SetPoint("CENTER", math.floor(size / 2 + 2), 0)
    if b.padNative == nil then
        b.padNative = ns.Glyphs.CreateNativeIcon(b) or false
    end
    if b.padNative then b.padNative:SetSize(size + 2, size + 1) end
    if b.padNative and ns.Glyphs.BindNativeIcon(b.padNative, button) then
        b.padNative:ClearAllPoints()
        b.padNative:SetPoint("RIGHT", b.text, "LEFT", -5, 0)
        b.padNative:Show()
        return
    end
    if not b.padIcon then
        b.padIcon = b:CreateTexture(nil, "OVERLAY")
    end
    b.padIcon:SetSize(size, size)
    b.padIcon:ClearAllPoints()
    b.padIcon:SetPoint("RIGHT", b.text, "LEFT", -5, 0)
    if not ns.Glyphs.Apply(b.padIcon, button) then b.text:SetPoint("CENTER", 0, 0) end
end

function KB:RefreshKeys()
    local upper = self.shift or self.caps
    for r, row in ipairs(self.grid) do
        for c, b in ipairs(row) do
            local key = b.key
            local selected = self.sel[1] == r and self.sel[2] == c
            local label, fn = key, false
            if type(key) == "table" then
                label, fn = key.label, true
                -- While picking a whisper target, Send moves on to writing the message.
                if key.action == "submit" then
                    local target = self.target
                    label = self.whisperPending and "Next" or
                        (target and target.isEBGInput and target.submitLabel) or
                        (target and ns.IsChatBox(target) and "Send") or "Done"
                end
            elseif upper then
                label = ns.Upper(key)
            end
            b.text:SetText(label)
            local icon = fn and key.icon
            if icon then
                if not b.keyIcon then
                    b.keyIcon = b:CreateTexture(nil, "OVERLAY")
                    b.keyIcon:SetPoint("CENTER", 0, 0)
                    b.keyIcon:SetSize(32, 32)
                end
                -- The atlas first, then the same art as a texture file, then the key's text label.
                local shown = false
                if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(icon) then
                    b.keyIcon:SetAtlas(icon, false)
                    shown = true
                elseif key.iconFile then
                    b.keyIcon:SetTexCoord(0, 1, 0, 1)
                    shown = b.keyIcon:SetTexture(key.iconFile) ~= false
                end
                b.keyIcon:SetShown(shown)
                if not shown then b.text:SetText(key.iconText or "?") end
            elseif b.keyIcon then
                b.keyIcon:Hide()
            end
            local state = "normal"
            if selected then
                state = "selected"
            elseif fn and ((key.action == "shift" and upper) or (key.action == "symbols" and self.page == "symbols") or (key.action == "accents" and self.page == "accents")) then
                state = "active"
            elseif fn then
                state = "fn"
            end
            ns.Skin.StyleKey(b, state)
            if b.text.SetFontObject then
                b.text:SetFontObject((fn and key.small) and GameFontHighlightSmall or GameFontHighlightMedium)
                ns.Skin.StyleKey(b, state)
            end
            if fn and key.color then
                local cr, cg, cb = key.color[1], key.color[2], key.color[3]
                if selected then cr, cg, cb = math.min(1, cr + 0.2), math.min(1, cg + 0.2), math.min(1, cb + 0.2) end
                b.text:SetTextColor(cr, cg, cb)
            end
            KB:SetKeyGlyph(b, fn and key.pad or nil)
            b.text:SetWidth(fn and (key.texture or key.small) and math.max(1, b:GetWidth() - (key.texture and 52 or 16)) or 0)
            b.text:SetWordWrap(false)
            if fn and key.texture then
                if not b.itemIcon then b.itemIcon = b:CreateTexture(nil, "OVERLAY") end
                b.itemIcon:SetSize(24, 24)
                b.itemIcon:SetPoint("LEFT", 8, 0)
                b.itemIcon:SetTexture(key.texture)
                b.itemIcon:Show()
                b.text:ClearAllPoints()
                b.text:SetPoint("LEFT", 40, 0)
                b.text:SetJustifyH("LEFT")
            else
                if b.itemIcon then b.itemIcon:Hide() end
                b.text:SetJustifyH("CENTER")
            end
            local glow = ns.Skin.SelectionGlow(b)
            if glow then glow:SetShown(selected) elseif b.glow then b.glow:Hide() end
        end
    end
    self:RefreshQuestPane()
    self:RefreshItemTooltip()
end

function KB:RefreshHeader()
    frame.title:SetText(self.target and ns.DescribeTarget(self.target) or "")
    self:RefreshTabs()
    self:RefreshChannelColor()
    local pageName = ""
    if self.page == "quests" then
        pageName = ("Link a quest  %d/%d"):format(self.questPage or 1, self.questPages or 1)
    elseif self.page == "items" then
        pageName = ("Link an item  %d/%d"):format(self.itemPage or 1, self.itemPages or 1)
    end
    if self.target and ns.Input.IsSearch(self.target) then frame.title:SetText("Searching " .. (ns.Input.Context(self.target) or "items")) end
    frame.layoutName:SetText(pageName)
end

function KB:RefreshLegend()
    local G = ns.Glyphs
    local total, gap = 0, 12
    local LEGEND_ITEMS = LegendItems(self.target and ns.IsChatBox(self.target), self.page)
    for i, item in ipairs(LEGEND_ITEMS) do
        local e = LegendEntry(i)
        local button, label, button2 = item[1], item[2], item[3]
        local w = 0
        if e.native then e.native:Hide() end
        if e.native2 then e.native2:Hide() end
        if e.prompt then e.prompt:Hide() end
        local promptWidth
        local usePrompt = not (ns.db and ns.db.nativePrompts == false)
        if usePrompt and e.prompt and not button2 and G.BindNativePrompt(e.prompt, button, label, "GameFontHighlightSmall") then
            promptWidth = e.prompt:GetWidth()
            if not promptWidth or promptWidth < 10 then
                local okT, t = pcall(e.prompt.GetPromptTextControl, e.prompt)
                local tw = okT and t and t.GetStringWidth and t:GetStringWidth()
                if not tw and okT and t and t.FontString then tw = t.FontString:GetStringWidth() end
                promptWidth = 22 + (tw or 40)
            end
        end
        if promptWidth then
            e.prompt:Show()
            e.icon:Hide(); e.icon2:Hide(); e.key:Hide(); e.label:Hide()
            e:SetWidth(promptWidth)
            e:ClearAllPoints()
            e:SetPoint("LEFT", frame.legend, "LEFT", total, 0)
            e:Show()
            total = total + promptWidth + gap
        else
        e.label:Show()
        if e.native and G.BindNativeIcon(e.native, button) then
            e.native:Show()
            e.icon:Hide(); e.icon2:Hide(); e.key:Hide()
            w = 20
            if button2 and e.native2 and G.BindNativeIcon(e.native2, button2) then
                e.native2:Show()
                w = w + 18
            end
        elseif G.Apply(e.icon, button) then
            e.key:Hide()
            w = 20
            if button2 and G.Apply(e.icon2, button2) then w = w + 18 else e.icon2:Hide() end
        else
            e.icon2:Hide()
            local text = G.Text(button)
            if button2 then text = text .. "/" .. G.Text(button2) end
            e.key:SetText(text)
            e.key:Show()
            w = e.key:GetStringWidth()
        end
        e.label:ClearAllPoints()
        e.label:SetPoint("LEFT", e, "LEFT", w + 4, 0)
        e.label:SetText(label)
        w = w + 4 + e.label:GetStringWidth()
        e:SetWidth(w)
        e:ClearAllPoints()
        e:SetPoint("LEFT", frame.legend, "LEFT", total, 0)
        e:Show()
        total = total + w + gap
        end
    end
    for i = #LEGEND_ITEMS + 1, #frame.legend.entries do frame.legend.entries[i]:Hide() end
    frame.legend:SetWidth(math.max(1, total - gap))
end

local function Escape(s)
    return (s:gsub("|", "||"))
end

function KB:RefreshPreview()
    local real = self.target
    local box = real and not real:IsForbidden() and TextTarget(self) or real
    if not box or box:IsForbidden() then frame.previewText:SetText("") return end
    local text = box:GetText() or ""
    local pos = box:GetCursorPosition() or #text
    if box.IsPassword and box:IsPassword() then
        text = string.rep("*", #text)
    end
    pos = math.max(0, math.min(pos, #text))
    if self.channelKey then
        local key = tostring(box:GetAttribute("chatType")) .. "|" .. tostring(box:GetAttribute("tellTarget") or "") .. "|" .. tostring(box:GetAttribute("channelTarget") or "")
        if key ~= self.channelKey then self:RefreshHeader() end
    end
    local caret = "|cffffd100|||r"
    if text:find("|H", 1, true) then
        -- Keep links intact so they render as [Quest Name]; escape only the plain text between them.
        local out, last, caretDone = {}, 1, false
        local function plain(a, b)
            if b < a then return end
            if not caretDone and pos >= a - 1 and pos <= b then
                out[#out + 1] = Escape(text:sub(a, pos)) .. caret .. Escape(text:sub(pos + 1, b))
                caretDone = true
            else
                out[#out + 1] = Escape(text:sub(a, b))
            end
        end
        for _, sp in ipairs(LinkSpans(text)) do
            plain(last, sp[1] - 1)
            if not caretDone and pos == sp[1] - 1 then
                out[#out + 1] = caret
                caretDone = true
            end
            out[#out + 1] = text:sub(sp[1], sp[2])
            if not caretDone and pos >= sp[1] and pos <= sp[2] then
                out[#out + 1] = caret
                caretDone = true
            end
            last = sp[2] + 1
        end
        plain(last, #text)
        if not caretDone then out[#out + 1] = caret end
        frame.previewText:SetText(table.concat(out))
    else
        frame.previewText:SetText(Escape(text:sub(1, pos)) .. caret .. Escape(text:sub(pos + 1)))
    end
end

-- Text operations ----------------------------------------------------------------

local function Target(self)
    local box = self.target
    if box and not box:IsForbidden() then return box end
end

-- Bag and bank search ------------------------------------------------------------------
-- Writing into the bag search box runs Blizzard's bag filter code as addon code, which taints
-- gamepad state and later blocks SetPreferredGamepadInteractTarget. For these boxes the text is
-- kept in-addon and the item filter is set through the container API; the real text box is not touched - Important
ns.IsItemSearchBox = ns.Input.IsSearch
TextTarget = function(self)
    local box = Target(self)
    if not ns.Input.Allows(box) then return nil end
    return ns.Input.IsSearch(box) and ns.Input.SearchTarget(box) or box
end

function KB:Insert(s)
    local box = TextTarget(self)
    if not box then return end
    if box == self.target and not box.isComposer and not box.isEBGInput then ns.NoteWrite(box, "Insert") end
    box:Insert(s)
    self:RefreshPreview()
end

function KB:Backspace()
    local box = TextTarget(self)
    if not box then return end
    local text = box:GetText() or ""
    local pos = box:GetCursorPosition()
    if pos <= 0 or text == "" then return end
    local start = ns.UTF8CharStart(text, pos)
    local stop = pos
    for _, sp in ipairs(LinkSpans(text)) do
        if start >= sp[1] and start <= sp[2] then start, stop = sp[1], math.max(pos, sp[2]) break end
    end
    if box == self.target and not box.isComposer and not box.isEBGInput then ns.NoteWrite(box, "SetText (backspace)") end
    box:SetText(text:sub(1, start - 1) .. text:sub(stop + 1))
    box:SetCursorPosition(start - 1)
    self:RefreshPreview()
end

function KB:DeleteWord()
    local box = TextTarget(self)
    if not box then return end
    local text = box:GetText() or ""
    local pos = box:GetCursorPosition()
    if pos <= 0 then return end
    local head = text:sub(1, pos)
    local cut = head:match("^(.-)%s*%S+%s*$") or ""
    if box == self.target and not box.isComposer and not box.isEBGInput then ns.NoteWrite(box, "SetText (delete word)") end
    box:SetText(cut .. text:sub(pos + 1))
    box:SetCursorPosition(#cut)
    self:RefreshPreview()
end

function KB:MoveCaret(dir)
    local box = TextTarget(self)
    if not box then return end
    local text = box:GetText() or ""
    local pos = box:GetCursorPosition()
    local newPos = pos
    if dir < 0 and pos > 0 then
        newPos = ns.UTF8CharStart(text, pos) - 1
    elseif dir > 0 and pos < #text then
        newPos = ns.UTF8CharEnd(text, pos + 1) - 1
    end
    -- Step over links in one move.
    for _, sp in ipairs(LinkSpans(text)) do
        if newPos >= sp[1] and newPos < sp[2] then
            newPos = dir < 0 and (sp[1] - 1) or sp[2]
            break
        end
    end
    box:SetCursorPosition(newPos)
    self:RefreshPreview()
end

-- Closes chat (or, for another field, releases its focus) from addon code: the tested exception
-- to the focus rule below. Each call is noted in the trail so a later block can be traced to it.
local function ReleaseField(box, tag)
    if not box or box.isComposer or box.isEBGInput or box:IsForbidden() then return end
    if ns.IsChatBox(box) then
        local close = ChatEdit_DeactivateChat or (ChatFrameUtil and ChatFrameUtil.DeactivateChat)
        if close then
            ns.NoteAction(tag .. " DeactivateChat")
            local ok, err = pcall(close, box)
            if not ok then ns.Debug(tag, "DeactivateChat error", err) end
        end
    end
    if box:HasFocus() then
        ns.NoteAction(tag .. " ClearFocus")
        local ok, err = pcall(box.ClearFocus, box)
        if not ok then ns.Debug(tag, "ClearFocus error", err) end
    end
end

-- Focus rule: this addon never changes keyboard focus itself (no ClearFocus, no chat
-- deactivate, no Enter handlers), except through ReleaseField above: closing chat after Send,
-- and releasing the field when the reload pop-up opens. On Forever a focus change runs Blizzard's gamepad binding
-- manager, and when addon code starts it that manager's state is tainted for the rest of the
-- session, which blocks SetPreferredGamepadInteractTarget. Focus is only ever released by
-- Blizzard's own handling of a real button press. Important
function KB:Submit()
    local box = Target(self)
    if not box then return end
    if box.isEBGInput then
        local text, submit = box:GetText(), box.submit
        ns.HideKeyboard()
        if submit then submit(text) end
        return
    end
    if ns.IsChatBox(box) and self.whisperPending then
        local name = (box:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then
            box:SetAttribute("chatType", "WHISPER")
            box:SetAttribute("tellTarget", name)
            pcall(box.SetText, box, "")
            if ChatEdit_UpdateHeader and not box.isComposer then pcall(ChatEdit_UpdateHeader, box) end
            self.whisperPending = false
            self:Build()
            self:RefreshPreview()
        end
        return
    end
    if box.isComposer then
        if box:Send() then
            box:SetText("")
            ns.HideKeyboard()
        end
        return
    end
    if ns.IsChatBox(box) and ChatEdit_SendText then
        ChatEdit_SendText(box, 1)
        pcall(box.SetText, box, "")
        self:RefreshPreview()
        -- With focus already gone Blizzard will not close chat, so nothing else would hide the keyboard.
        -- A mouse click on Send takes focus before the loss is noticed, so check the box itself;
        -- submittedAt covers the loss being reported just after this.
        self.submittedAt = GetTime()
        -- Closing chat after Send (/ebg closeonsend, default on) is the one exception to the
        -- focus rule above: tested on Forever 2026-11-17 (whisper and slash command, then
        -- guard, banker, auctioneer and vendor interaction) with no blocked action. Each close
        -- is noted in the trail so a later block can still be traced back to it.
        if ns.db and ns.db.closeOnSend then
            -- A mouse click on Send takes focus first, leaving chat open but unfocused, so close
            -- whenever the box is still up, not only while it has focus.
            if box:HasFocus() or box:IsShown() then ReleaseField(box, "closeonsend") end
            ns.HideKeyboard()
            return
        end
        if self.detached or not box:HasFocus() then ns.HideKeyboard() end
        return
    end
    ns.DismissKeyboard()
end

-- Key actions ---------------------------------------------------------------------

local ACTIONS = {}

function ACTIONS.select(self)
    local b = self.grid[self.sel[1]] and self.grid[self.sel[1]][self.sel[2]]
    if b then self:PressKey(b.key) end
end
function ACTIONS.up(self) self:Move(0, -1) end
function ACTIONS.down(self) self:Move(0, 1) end
function ACTIONS.left(self) self:Move(-1, 0) end
function ACTIONS.right(self) self:Move(1, 0) end
function ACTIONS.backspace(self) self:Backspace() end
function ACTIONS.space(self) self:Insert(" ") end
function ACTIONS.char(self, key) if key and key.char then self:Insert(key.char) end end
function ACTIONS.caretleft(self) self:MoveCaret(-1) end
function ACTIONS.caretright(self) self:MoveCaret(1) end
function ACTIONS.deleteword(self) self:DeleteWord() end
function ACTIONS.submit(self) self:Submit() end
function ACTIONS.clearsearch(self)
    if ns.Input.IsSearch(self.target) then ns.Input.SetSearch("") self:RefreshPreview() end
end
function ACTIONS.items(self)
    if not self.target or not ns.IsChatBox(self.target) then return end
    self.page, self.itemPage, self.sel = "items", 1, { 1, 1 }
    self:Build()
end
function ACTIONS.itemprev(self)
    self.itemPage = ((self.itemPage or 1) - 2) % (self.itemPages or 1) + 1
    self.sel = { 1, 1 }
    self:Build()
end
function ACTIONS.itemnext(self)
    self.itemPage = (self.itemPage or 1) % (self.itemPages or 1) + 1
    self.sel = { 1, 1 }
    self:Build()
end
function ACTIONS.itemlink(self, key)
    if not key or not key.link or not self.target or not ns.IsChatBox(self.target) then return end
    self:Insert(key.link .. " ")
    self:SetPage("letters")
end
-- Cancel: an abandoned chat message is discarded, other fields keep their text.
function ACTIONS.quests(self)
    local box = self.target
    if not box or box:IsForbidden() or not ns.IsChatBox(box) then return end
    self.page, self.questPage, self.sel = "quests", 1, { 1, 1 }
    self:Build()
end
function ACTIONS.questprev(self)
    self.questPage = ((self.questPage or 1) - 2) % (self.questPages or 1) + 1
    self.sel = { 1, 1 }
    self:Build()
end
function ACTIONS.questnext(self)
    self.questPage = (self.questPage or 1) % (self.questPages or 1) + 1
    self.sel = { 1, 1 }
    self:Build()
end
function ACTIONS.questlink(self, key)
    local box = self.target
    if not key or not box or box:IsForbidden() then return end
    local link = QuestLink(key.questID, key.title)
    self:Insert(link .. " ")
    self:SetPage("letters")
    self:RefreshPreview()
end

function ACTIONS.close(self)
    -- Circle backs out of the quest picker before it closes the keyboard.
    if self.page == "quests" or self.page == "items" then self:SetPage("letters") return end
    local box = self.target
    if box and not box:IsForbidden() and ns.IsChatBox(box) then pcall(box.SetText, box, "") end
    ns.DismissKeyboard()
end
function ACTIONS.channel(self)
    if not self:CycleChannel() then ns.HideKeyboard() end
end

-- Switches to a ChannelList entry.
function KB:SetChannel(entry)
    local box = Target(self)
    if not box or not ns.IsChatBox(box) then return false end
    if entry.pending then
        -- Next Send takes the typed text as the whisper target.
        self.whisperPending = true
    else
        self.whisperPending = false
        box:SetAttribute("chatType", entry.type)
        if entry.channel then box:SetAttribute("channelTarget", entry.channel) end
        if entry.tell then box:SetAttribute("tellTarget", entry.tell) end
        if ChatEdit_UpdateHeader and not box.isComposer then pcall(ChatEdit_UpdateHeader, box) end
    end
    ns.PlayClick()
    self:Build()
    return true
end

-- Steps to the next available channel, skipping greyed-out ones.
function KB:CycleChannel()
    local box = Target(self)
    if not box or not ns.IsChatBox(box) then return false end
    local list = ChannelList(box)
    local idx = 0
    for i, ch in ipairs(list) do if ch.active then idx = i break end end
    for step = 1, #list do
        local ch = list[((idx - 1 + step) % #list) + 1]
        if ch.available and not ch.extra and not ch.active then
            return self:SetChannel(ch)
        end
    end
    return true
end

function ACTIONS.shift(self)
    local now = GetTime()
    if self.shift and not self.caps and now - (self.lastShift or 0) < 0.4 then
        self.caps = true
    elseif self.caps then
        self.caps, self.shift = false, false
    else
        self.shift = not self.shift
    end
    self.lastShift = now
    self:RefreshKeys()
end

-- The reload key's confirmation pop-up: EBG's own, drawn like Blizzard's (an addon dialog in
-- Blizzard's shared StaticPopup system taints it). ReloadUI is protected on this client: only
-- Blizzard's secure code may call it, even inside a key press. So Accept is a secure action button
-- running the macro "/reload" - the same as typing it - laid over the Accept key for the mouse and,
-- while Accept is highlighted, bound to A (override binding). B or Cancel closes the pop-up.
local confirm
local function ConfirmReload()
    if not confirm then
        confirm = CreateFrame("Frame", "EBGReloadConfirm", UIParent, "BackdropTemplate")
        confirm:SetFrameStrata("FULLSCREEN_DIALOG")
        confirm:SetToplevel(true)
        confirm:SetClampedToScreen(true)
        confirm:SetSize(340, 112)
        confirm:SetPoint("TOP", UIParent, "TOP", 0, -135)
        confirm:EnableMouse(true)
        ns.Skin.Panel(confirm)
        confirm.text = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        confirm.text:SetPoint("TOP", 0, -24)
        confirm.text:SetWidth(300)
        confirm.text:SetText("Reload the user interface?")
        confirm.keys = {}
        local labels = { { ACCEPT or "Accept", "PAD1" }, { CANCEL or "Cancel", "PAD2" } }
        for i, entry in ipairs(labels) do
            local b = ns.Skin.CreateKey(confirm)
            b:SetSize(132, 32)
            b:SetPoint("BOTTOM", (i == 1 and -1 or 1) * 72, 18)
            b.text:SetText(entry[1])
            b.glyphSize = 22
            KB:SetKeyGlyph(b, entry[2])
            b:SetScript("OnEnter", function() confirm.focus = i confirm:Paint() end)
            if i == 2 then b:SetScript("OnClick", function() confirm:Hide() end) end
            confirm.keys[i] = b
        end
        local accept = CreateFrame("Button", "EBGReloadConfirmAccept", confirm, "SecureActionButtonTemplate")
        accept:SetAttribute("type", "macro")
        accept:SetAttribute("macrotext", "/reload")
        accept:RegisterForClicks("AnyUp", "AnyDown")
        accept:SetAllPoints(confirm.keys[1])
        accept:SetFrameLevel(confirm.keys[1]:GetFrameLevel() + 5)
        accept:HookScript("OnEnter", function() confirm.focus = 1 confirm:Paint() end)
        -- A is bound to Accept only once armed (shortly after opening), so the release of the A that
        -- opened the pop-up can never accept it, and only while Accept is highlighted.
        function confirm:Paint()
            for i, b in ipairs(self.keys) do ns.Skin.StyleKey(b, i == self.focus and "selected" or "fn") end
            if InCombatLockdown() then return end
            ClearOverrideBindings(self)
            if self.armed and self.focus == 1 and self:IsShown() then
                SetOverrideBindingClick(self, true, "PAD1", "EBGReloadConfirmAccept", "LeftButton")
            end
        end
        local function Bound(self, key) return key == "PAD1" and self.armed and self.focus == 1 end
        local pressed
        confirm:SetScript("OnGamePadButtonDown", function(self, key)
            if InCombatLockdown() then return end
            -- A on Accept goes on to its binding (the secure button).
            if Bound(self, key) then self:SetPropagateKeyboardInput(true) return end
            self:SetPropagateKeyboardInput(false)
            pressed = key
            if key == "PADDLEFT" or key == "PADDRIGHT" then self.focus = 3 - self.focus self:Paint() end
        end)
        confirm:SetScript("OnGamePadButtonUp", function(self, key)
            if InCombatLockdown() then return end
            if Bound(self, key) then self:SetPropagateKeyboardInput(true) return end
            if pressed ~= key then return end
            pressed = nil
            if key == "PAD2" or (key == "PAD1" and self.armed and self.focus == 2) then self:Hide() end
        end)
        confirm:SetScript("OnKeyDown", function(self, key)
            if InCombatLockdown() then return end
            local escape = key == "ESCAPE"
            self:SetPropagateKeyboardInput(not escape)
            if escape then self:Hide() end
        end)
        confirm:SetScript("OnHide", function(self)
            self.armed = false
            if not InCombatLockdown() then
                ClearOverrideBindings(self)
                self:EnableGamePadButton(false)
                self:EnableKeyboard(false)
            end
        end)
        -- The pop-up holds a secure button and a binding, neither of which can change in combat,
        -- so it closes as combat starts (this event arrives just before the lockdown).
        confirm:RegisterEvent("PLAYER_REGEN_DISABLED")
        confirm:SetScript("OnEvent", function(self) if self:IsShown() then self:Hide() end end)
    end
    confirm.focus, confirm.armed = 1, false -- like Blizzard's pop-ups, A on Accept; B cancels
    confirm:Show()
    confirm:Paint()
    confirm:EnableKeyboard(true)
    confirm:SetPropagateKeyboardInput(true)
    confirm:EnableGamePadButton(true)
    C_Timer.After(0.35, function()
        if confirm:IsShown() and not InCombatLockdown() then confirm.armed = true confirm:Paint() end
    end)
end
ns.ConfirmReload = ConfirmReload
function ACTIONS.reload(self)
    -- Secure buttons and bindings cannot be set up in combat.
    if InCombatLockdown() then ns.Print("Reload the interface after combat.") return end
    -- While a text field has focus the game gives it the button presses and key bindings do not
    -- fire, so A could never reach the pop-up's Accept binding. The field is released first (any
    -- unsent text would be lost to the reload anyway).
    local box = self.target
    ns.HideKeyboard()
    ReleaseField(box, "reload")
    ConfirmReload()
end
function ACTIONS.symbols(self) self:SetPage(self.page == "symbols" and "letters" or "symbols") end
function ACTIONS.accents(self) self:SetPage(self.page == "accents" and "letters" or "accents") end
function ACTIONS.letters(self) self:SetPage("letters") end

function KB:SetPage(page)
    if self.page == page then return end
    self.page = page
    self.sel = nil
    self:Build()
end

function KB:PressKey(key)
    ns.PlayClick()
    local b = self.grid[self.sel[1]] and self.grid[self.sel[1]][self.sel[2]]
    if b and b.key == key then ns.Skin.FlashKey(b) end
    if type(key) == "table" then
        local fn = ACTIONS[key.action]
        if fn then fn(self, key) end
        return
    end
    local c = (self.shift or self.caps) and ns.Upper(key) or key
    self:Insert(c)
    if self.shift and not self.caps then
        self.shift = false
        self:RefreshKeys()
    end
end

function KB:RunAction(action)
    local fn = ACTIONS[action]
    if fn then fn(self) end
end

function KB:SelectKey(r, c)
    if self.sel[1] == r and self.sel[2] == c then return end
    self.sel = { r, c }
    self:RefreshKeys()
end

-- Horizontal moves wrap within the row; vertical moves pick the key whose center is nearest.
function KB:Move(dx, dy)
    local r, c = self.sel[1], self.sel[2]
    if dx ~= 0 then
        local row = self.grid[r]
        c = ((c - 1 + dx) % #row) + 1
    elseif dy ~= 0 then
        local cx = self.grid[r][c].cx
        r = ((r - 1 + dy) % #self.grid) + 1
        local best, bestD = 1, math.huge
        for i, b in ipairs(self.grid[r]) do
            local d = math.abs(b.cx - cx)
            if d < bestD then best, bestD = i, d end
        end
        c = best
    end
    self:SelectKey(r, c)
end

-- Gamepad input ---------------------------------------------------------------------

local held, heldNext
local stickDir, stickNext
local rstickDir, rstickNext

local function SetPropagate(self, on)
    if InCombatLockdown() then return end
    pcall(self.SetPropagateKeyboardInput, self, on)
end

-- Physical keyboard keys reaching this frame are passed straight through to the game.
frame:SetScript("OnKeyDown", function(self, key)
    ns.Debug("key passthrough", key)
    SetPropagate(self, true)
end)
frame:SetScript("OnKeyUp", function(self, key)
    SetPropagate(self, true)
end)

local consumed = {}
local r2Held, r2Used

frame:SetScript("OnGamePadButtonDown", function(self, button)
    if InCombatLockdown() then return end
    SetPropagate(self, false)
    consumed[button] = true
    if KB.closing then return end
    -- R2 is Send on release; held, it is the modifier for D-pad left/right chat window tabs.
    if button == "PADRTRIGGER" then
        r2Held, r2Used = true, false
        return
    end
    if r2Held and (button == "PADDLEFT" or button == "PADDRIGHT") and ns.ChatMirrorShown and ns.ChatMirrorShown() then
        r2Used = true
        ns.CycleChatMirror(button == "PADDLEFT" and -1 or 1)
        return
    end
    local action = BUTTON_ACTIONS[button]
    ns.Debug("pad", button, "->", action or "passthrough")
    if button == "PAD2" and KB.page ~= "quests" and KB.page ~= "items" then
        local box = KB.target
        if box and not box:IsForbidden() and ns.IsChatBox(box) and not box.isComposer then
            -- Empty the message, then let Blizzard see this Circle press and close chat itself.
            pcall(box.SetText, box, "")
            consumed[button] = nil
            SetPropagate(self, true)
            C_Timer.After(0.05, function() if frame:IsShown() then ns.DismissKeyboard() end end)
            return
        end
    end
    if not action then
        -- Unmapped pad buttons (PADSYSTEM etc.) go through to the game
        consumed[button] = nil
        SetPropagate(self, true)
        return
    end
    if KB.page == "quests" then
        -- In the quest picker the bumpers turn pages instead of moving the text caret.
        if action == "caretleft" then action = "questprev" elseif action == "caretright" then action = "questnext" end
    elseif KB.page == "items" then
        if action == "caretleft" then action = "itemprev" elseif action == "caretright" then action = "itemnext" end
    end
    KB:RunAction(action)
    if REPEATABLE[action] then
        held, heldNext = action, GetTime() + REPEAT_DELAY
    end
end)

frame:SetScript("OnGamePadButtonUp", function(self, button)
    if InCombatLockdown() then return end
    local mine = consumed[button]
    consumed[button] = nil
    SetPropagate(self, not mine)
    if BUTTON_ACTIONS[button] == held then held = nil end
    if button == "PADRTRIGGER" and r2Held then
        r2Held = false
        if not r2Used and not KB.closing then KB:RunAction("submit") end
    end
    if KB.closing and not next(consumed) then KB:FinishClose() end
end)

local function StickDirection(x, y, len)
    if len < STICK_DEADZONE then return nil end
    if math.abs(x) > math.abs(y) then return x > 0 and "right" or "left" end
    return y > 0 and "up" or "down"
end

local mirrorDir, mirrorNext
frame:SetScript("OnGamePadStick", function(self, stick, x, y, len)
    if InCombatLockdown() then return end
    -- Right stick scrolls the chat copy while it is up; the left stick always stays with movement.
    if stick == "Right" and ns.ChatMirrorScrollable() then
        SetPropagate(self, false)
        local dir = (math.abs(y) >= STICK_DEADZONE and math.abs(y) >= math.abs(x)) and (y > 0 and 1 or -1) or nil
        if dir ~= mirrorDir then
            mirrorDir = dir
            if dir then
                ns.ScrollChatMirror(dir)
                mirrorNext = GetTime() + 0.25
            end
        end
        return
    end
    if not (ns.db and ns.db.stickNav) then SetPropagate(self, true) return end
    SetPropagate(self, false)
    if stick == "Left" then
        local dir = StickDirection(x, y, len)
        if dir ~= stickDir then
            stickDir = dir
            if dir then
                KB:RunAction(dir)
                stickNext = GetTime() + REPEAT_DELAY
            end
        end
    elseif stick == "Right" then
        local dir = StickDirection(x, 0, math.abs(x))
        local action = dir == "left" and "caretleft" or dir == "right" and "caretright" or nil
        if action ~= rstickDir then
            rstickDir = action
            if action then
                KB:RunAction(action)
                rstickNext = GetTime() + REPEAT_DELAY
            end
        end
    end
end)

local previewElapsed = 0
frame:SetScript("OnUpdate", function(self, dt)
    local now = GetTime()
    -- Remember when the mouse was last pressed on the keyboard, so a focus loss can be told
    -- apart from one caused by Enter or Escape while the pointer just rests over the keyboard.
    if IsMouseButtonDown and IsMouseButtonDown() and self:IsMouseOver() then KB.clickedAt = now end
    -- Once a click on the keyboard has cost the text field its focus, no focus event will close
    -- the keyboard any more, so a click anywhere outside it does.
    if KB.detached and not KB.closing and IsMouseButtonDown and IsMouseButtonDown() and not self:IsMouseOver() then
        ns.HideKeyboard()
        return
    end
    if mirrorDir and now >= mirrorNext then
        if not ns.ScrollChatMirror(mirrorDir) then mirrorDir = nil end
        mirrorNext = now + 0.07
    end
    if held and now >= heldNext then
        KB:RunAction(held)
        heldNext = now + REPEAT_RATE
    end
    if stickDir and now >= stickNext then
        KB:RunAction(stickDir)
        stickNext = now + REPEAT_RATE
    end
    if rstickDir and now >= rstickNext then
        KB:RunAction(rstickDir)
        rstickNext = now + REPEAT_RATE
    end
    previewElapsed = previewElapsed + dt
    if previewElapsed > 0.1 then
        previewElapsed = 0
        KB:RefreshPreview()
        if frame:IsShown() and not KB.closing then
            ns.SetNavPointerHidden(true)
            ReapplyFaded()
        end
    end
end)

frame:SetScript("OnHide", function()
    held, stickDir, rstickDir, mirrorDir = nil, nil, nil, nil
    r2Held = false
    -- However the keyboard goes away, everything it faded comes back.
    ns.SetNavPointerHidden(false)
    ns.SetNativeLegendHidden(false)
    if ns.HideChatMirror then ns.HideChatMirror() end
end)

-- Input capture is protected in combat; fall back to mouse only until combat ends.
local captureWanted = false
local function Capture(on)
    captureWanted = on
    if InCombatLockdown() then
        KB.combatLocked = on
        if on then frame.combat:Show() end
        return
    end
    KB.combatLocked = false
    frame.combat:Hide()
    local ok, err = pcall(function()
        frame:EnableGamePadButton(on)
        -- Sticks stay with the game: left stick moves the character, right stick the camera.
        local db = ns.db or {}
        local wantSticks = db.stickNav == true or (db.chatMirror ~= false and db.mirrorScroll ~= false)
        frame:EnableGamePadStick(on and wantSticks or false)
        frame:SetPropagateKeyboardInput(true)
    end)
    if not ok and not KB.warnedCapture then
        KB.warnedCapture = true
        ns.Print("Gamepad capture unavailable on this client: " .. tostring(err))
    end
end

function ns.OnCombatEnd()
    Capture(frame:IsShown() and not KB.closing)
end

function ns.OnCombatStart()
    held, stickDir, rstickDir, mirrorDir = nil, nil, nil, nil
    r2Held = false
    wipe(consumed)
    KB.combatLocked = frame:IsShown()
    frame.combat:SetShown(frame:IsShown())
end

-- Show / hide ------------------------------------------------------------------------

function KB:SetTarget(box)
    self.target = box
    self.detached = false
    ns.ApplyChatBoxVisibility()
    if box and not box:IsForbidden() and ns.IsChatBox(box) then ns.ShowChatMirror() else ns.HideChatMirror() end
    local numeric = box and box.IsNumeric and box:IsNumeric()
    local page = numeric and "numpad" or "letters"
    if page ~= self.page then
        self.page = page
        self.sel = nil
    end
    self.shift, self.caps = false, false
    self.whisperPending = false
    self:Build()
    self:RefreshPreview()
end

-- Composer ---------------------------------------------------------------------------
local Composer = { isComposer = true }
Composer.__index = Composer
function Composer:IsForbidden() return false end
function Composer:GetObjectType() return "EditBox" end
function Composer:GetName() return "EBGComposer" end
function Composer:GetParent() return nil end
function Composer:HasFocus() return false end
function Composer:GetScript() return nil end
function Composer:GetText() return self.text end
function Composer:GetCursorPosition() return self.pos end
function Composer:SetCursorPosition(p) self.pos = math.max(0, math.min(p, #self.text)) end
function Composer:SetText(t) self.text, self.pos = t, #t end
function Composer:Insert(str)
    self.text = self.text:sub(1, self.pos) .. str .. self.text:sub(self.pos + 1)
    self.pos = self.pos + #str
end
function Composer:GetAttribute(k) return self.attr[k] end
function Composer:SetAttribute(k, v) self.attr[k] = v end

-- Sends the composer's text straight through the chat API.
function Composer:Send()
    local text = self.text
    if text:match("^%s*$") then return false end
    if text:sub(1, 1) == "/" then
        ns.Print("Slash commands are not available in a quick whisper. Open chat normally for those.")
        return false
    end
    local chatType = self.attr.chatType or "SAY"
    local target
    if chatType == "WHISPER" then target = self.attr.tellTarget
    elseif chatType == "CHANNEL" then target = self.attr.channelTarget
    elseif chatType == "BN_WHISPER" then
        ns.Print("Battle.net whispers are not supported here. Open chat normally for those.")
        return false
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local ok, err = pcall(send, text, chatType, nil, target)
    if not ok then
        ns.Print("Could not send: " .. tostring(err))
        return false
    end
    return true
end

-- Opens the keyboard on a new whisper to `name` without opening Blizzard's chat box.
function ns.OpenWhisperComposer(name)
    if not name or name == "" then return end
    local c = setmetatable({ text = "", pos = 0, attr = { chatType = "WHISPER", tellTarget = name } }, Composer)
    ns.ShowKeyboard(true, c)
end

function ns.ShowKeyboard(manual, forced)
    if not ns.db or not ns.db.enabled then return end
    if KB.closing then KB:FinishClose() end
    local box = forced or ns.GetTarget()
    if not box then
        if manual then ns.Print("No text field is focused. Open chat or select a text field first.") end
        return
    end
    if not ns.Input.Allows(box) then
        ns.Print("This native field is not enabled for EBG typing. For auction search use /ebg ah.")
        return
    end
    ns.dismissedBox = nil
    KB:SetTarget(box)
    if not frame:IsShown() then
        frame:SetAlpha(1)
        frame:EnableMouse(true)
        frame:Show()
        Capture(true)
        ns.SetNativeLegendHidden(true)
        ns.SetNavPointerHidden(true)
    end
end

-- Preserve the established pointer parking behavior; it has been exercised on
-- Forever. Text/focus isolation is handled independently by TextSafety.lua.
local pointerActive, pointerPoints, pointerAlpha
local function PointerRegions()
    local nav = _G.SmartNavigation
    local pointer = type(nav) == "table" and nav.Pointer
    if type(pointer) ~= "table" or (pointer.IsForbidden and pointer:IsForbidden()) then return nil end
    return pointer, type(pointer.Icon) == "table" and pointer.Icon or nil
end

local function PointerMode()
    local db = ns.db
    if not db or db.hideNavPointer == false then return "off" end
    return db.navPointer or "move"
end

local function PointerIsParked(pointer)
    if pointer:GetNumPoints() ~= 1 then return false end
    local _, rel = pointer:GetPoint(1)
    return rel == frame.preview
end

local function ReadPoints(pointer)
    local t = {}
    for i = 1, pointer:GetNumPoints() do t[i] = { pointer:GetPoint(i) } end
    return t
end

-- Called on open and on every tick while open (hidden = true), and on close (hidden = false).
function ns.SetNavPointerHidden(hidden)
    local pointer, icon = PointerRegions()
    if not pointer then return end
    pcall(function()
        if hidden then
            local mode = PointerMode()
            if mode == "off" then return end
            pointerActive = true
            if mode == "hide" then
                if icon then
                    local a = icon:GetAlpha() or 1
                    if a > 0.01 then pointerAlpha = a end
                    icon:SetAlpha(0)
                end
                return
            end
            -- If Blizzard re-anchored the pointer since the last tick, remember where it put it.
            if not PointerIsParked(pointer) then
                pointerPoints = ReadPoints(pointer)
                pointer:ClearAllPoints()
                -- Level with the input strip, just outside the panel edge so the panel cannot cover it.
                pointer:SetPoint("RIGHT", frame.preview, "LEFT", -(PAD + 8), 0)
            end
            if icon and icon:GetAlpha() < 0.01 then icon:SetAlpha(pointerAlpha or 1) end
        elseif pointerActive then
            pointerActive = false
            if icon and icon:GetAlpha() < 0.01 then icon:SetAlpha(pointerAlpha or 1) end
            if PointerIsParked(pointer) then
                pointer:ClearAllPoints()
                for _, pt in ipairs(pointerPoints or {}) do pointer:SetPoint(unpack(pt)) end
            end
            pointerPoints = nil
        end
    end)
end

function ns.PointerDiagnostics()
    local pointer, icon = PointerRegions()
    if not pointer then return "SmartNavigation.Pointer not found" end
    local ok, text = pcall(function()
        local pt, rel = pointer:GetPoint(1)
        local relName = rel and (rel.GetDebugName and rel:GetDebugName() or tostring(rel)) or "none"
        return ("mode=%s active=%s, pointer alpha %.2f shown=%s points=%d (%s -> %s), icon alpha %s shown=%s"):format(
            PointerMode(), tostring(pointerActive), pointer:GetAlpha(), tostring(pointer:IsShown()), pointer:GetNumPoints(),
            tostring(pt), relName, icon and ("%.2f"):format(icon:GetAlpha()) or "n/a", tostring(icon and icon:IsShown()))
    end)
    return ok and text or ("unreadable: " .. tostring(text))
end


function ns.SetNativeLegendHidden(hidden)
    if ns.db and ns.db.hideNativeLegend == false then return end
    local legend = _G.GamepadPersistentInputLegend
    if not legend or legend:IsForbidden() then return end
    pcall(legend.SetAlpha, legend, hidden and 0 or 1)
end

function KB:FinishClose()
    self.closing = false
    if self.closeTimer then self.closeTimer:Cancel() self.closeTimer = nil end
    wipe(consumed)
    r2Held = false
    Capture(false)
    frame:SetAlpha(1)
    frame:Hide()
    self.target = nil
    self.detached = false
    if ns.Auction and ns.Auction.ResumeInput then ns.Auction.ResumeInput() end
    ns.SetNativeLegendHidden(false)
    ns.SetNavPointerHidden(false)
    ns.ApplyChatBoxVisibility()
end

-- If a pad button is still held, the keyboard vanishes now but keeps listening until that
-- button is released
function ns.HideKeyboard()
    if not frame:IsShown() or KB.closing then return end
    ns.HideChatMirror()
    if next(consumed) then
        KB.closing = true
        frame:SetAlpha(0)
        frame:EnableMouse(false)
        if KB.closeTimer then KB.closeTimer:Cancel() end
        KB.closeTimer = C_Timer.NewTimer(1, function() if KB.closing then KB:FinishClose() end end)
        return
    end
    KB:FinishClose()
end

function ns.DismissKeyboard()
    local box = KB.target
    ns.HideKeyboard()
    if box and not box:IsForbidden() and box:HasFocus() then
        ns.dismissedBox = box
        ns.ApplyChatBoxVisibility()
    end
end

function ns.ToggleKeyboard()
    if frame:IsShown() then ns.HideKeyboard() else ns.ShowKeyboard(true) end
end

-- resetKeys: destroy the button pool so a new key template takes effect.
function ns.RebuildKeyboard(resetKeys)
    if resetKeys then
        for _, b in ipairs(pool) do b:Hide(); b:SetParent(nil) end
        wipe(pool)
    end
    KB.sel = nil
    KB:Build()
end

-- If opening fails, the field is marked dismissed so a faded chat box shows again instead of
-- leaving an invisible, focused box and no keyboard.
local function SafeOpen(fn, box, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        KB.closing = false
        ns.HideChatMirror()
        ns.SetNativeLegendHidden(false)
        ns.SetNavPointerHidden(false)
        frame:Hide()
        if box and not box:IsForbidden() and box:HasFocus() then ns.dismissedBox = box end
        ns.ApplyChatBoxVisibility()
        ns.Print("Could not open the keyboard: " .. tostring(err))
    end
end

function ns.OnTargetFocused(box)
    if KB.target and KB.target.isEBGInput and frame:IsShown() and not KB.closing then return end
    if not ns.Input.Allows(box) then
        ns.HideKeyboard()
        return
    end
    -- A keyboard still finishing its close (waiting for a held button's release) counts as closed:
    -- retargeting it would let it finish closing on the newly focused field.
    if frame:IsShown() and not KB.closing then
        if KB.target ~= box then SafeOpen(KB.SetTarget, box, KB, box) end
        return
    end
    -- A field focused while the game is loading (login, reload, loading screens) was not chosen by
    -- the player, so the keyboard never opens by itself then.
    if not ns.AutoOpenAllowed() then
        ns.ApplyChatBoxVisibility()
        return
    end
    SafeOpen(ns.ShowKeyboard, box, false)
    ns.ApplyChatBoxVisibility()
end

-- A mouse click on the keyboard can make Blizzard take focus away from the text field. That is
-- not the player leaving the field, so the keyboard stays up and keeps writing into it; it then
-- closes on Send, Close or when another field takes focus.
function ns.OnTargetLost()
    local box = KB.target
    if box and box.isEBGInput then return end
    local now = GetTime()
    local justSent = KB.submittedAt and now - KB.submittedAt < 0.5
    -- Focus loss is reported up to LOSS_GRACE (0.2s) plus one poll after the click.
    local clicked = KB.clickedAt and now - KB.clickedAt < 0.6
    if not justSent and clicked and frame:IsShown() and not KB.closing and box and not box:IsForbidden() and frame:IsMouseOver() then
        KB.detached = true
        return
    end
    ns.HideKeyboard()
end

function ns.OnPadStateChanged()
    ns.Glyphs.Reset()
    if frame:IsShown() then KB:RefreshLegend() end
end

function ns.OnCoreReady()
    KB.page = "letters"
    KB:Build()
end
