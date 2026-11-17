local ADDON, ns = ...
local Style = {}
ns.AuctionStyle = Style

local BORDER = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local function Fill(parent, layer, color)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(unpack(color))
    return t
end

-- Buttons are drawn as keyboard keys; the role decides the action colour.
--   primary  commits (Search, Post, Buyout, Confirm)  green
--   danger   gives something up (Cancel auction)      red
--   gold     money entry and bidding                 gold
--   tab      view switcher; the open view is lit      plain / active
--   segment  one choice of several (duration)        plain / active
--   secondary everything else (Back, paging)          function-key gray
-- Rows, options, categories and the search field stay list-styled: they are content, not actions.
local KEY_ROLES = { primary = "confirm", danger = "danger", gold = "gold", tab = false, segment = false, secondary = false }
Style.KEY_ROLES = KEY_ROLES

function Style.Pane(parent, x, y, w, h, kind)
    local p = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    p:SetPoint("TOPLEFT", x, y)
    p:SetSize(w, h)
    p:SetBackdrop(BORDER)
    local color = kind == "detail" and {0.085,0.07,0.05,0.92} or
        kind == "categories" and {0.055,0.052,0.042,0.92} or {0.02,0.022,0.026,0.92}
    p:SetBackdropColor(unpack(color))
    p:SetBackdropBorderColor(0.36,0.31,0.20,0.85)
    -- Decorative frames never receive input and sit behind controls.
    p:SetFrameLevel(parent:GetFrameLevel())
    return p
end
function Style.Band(parent, x, y, w, h)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetPoint("TOPLEFT", x, y)
    t:SetSize(w,h)
    t:SetColorTexture(0.17,0.145,0.095,0.9)
    return t
end
-- A thin gold divider, like the rule under the keyboard's quest pane title.
function Style.Rule(parent, x, y, w)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", x, y)
    t:SetSize(w, 1)
    t:SetColorTexture(0.62,0.50,0.25,0.55)
    return t
end
function Style.IsKey(role) return KEY_ROLES[role or "secondary"] ~= nil end
function Style.Control(parent, role)
    role = role or "secondary"
    local b
    if Style.IsKey(role) then
        b = ns.Skin.CreateKey(parent)
        b.isKey = true
        b.text:SetFontObject(GameFontHighlight)
    else
        b = CreateFrame("Button", nil, parent, "BackdropTemplate")
        b.text = b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        b.face = Fill(b,"BACKGROUND",{0.05,0.05,0.05,1})
        b.wash = Fill(b,"ARTWORK",{0.38,0.28,0.1,0.3})
        b.wash:Hide()
        b.line = b:CreateTexture(nil,"BORDER")
        b.line:SetPoint("BOTTOMLEFT",1,0)
        b.line:SetPoint("BOTTOMRIGHT",-1,0)
        b.line:SetHeight(1)
        b.line:SetColorTexture(0.36,0.3,0.18,0.4)
        b.marker = b:CreateTexture(nil,"OVERLAY")
        b.marker:SetPoint("TOPLEFT",0,0)
        b.marker:SetPoint("BOTTOMLEFT",0,0)
        b.marker:SetWidth(3)
        b.marker:SetColorTexture(1,0.78,0.24,1)
        b.marker:Hide()
        b.focusRing = CreateFrame("Frame",nil,b,"BackdropTemplate")
        b.focusRing:SetAllPoints()
        b.focusRing:SetFrameLevel(b:GetFrameLevel()+2)
        b.focusRing:SetBackdrop(BORDER)
        b.focusRing:SetBackdropColor(0,0,0,0)
        b.focusRing:SetBackdropBorderColor(1,0.82,0.35,0.95)
        b.focusRing:Hide()
        b.flash = Fill(b,"OVERLAY",{1,0.88,0.5,0.16})
        b.flash:Hide()
        if role == "check" then
            -- A checkbox: a small framed box with Blizzard's tick, label to its right.
            b.box = CreateFrame("Frame",nil,b,"BackdropTemplate")
            b.box:SetSize(16,16)
            b.box:SetPoint("LEFT",8,0)
            b.box:SetBackdrop(BORDER)
            b.box:SetBackdropColor(0,0,0,0.85)
            b.box:SetBackdropBorderColor(0.62,0.50,0.25,0.9)
            b.tick = b.box:CreateTexture(nil,"OVERLAY")
            b.tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            b.tick:SetPoint("CENTER",1,0)
            b.tick:SetSize(22,22)
            b.tick:Hide()
        elseif role == "header" then
            b.text:SetFontObject(GameFontNormalSmall)
        end
    end
    b.role = role
    b.text:ClearAllPoints()
    b.text:SetPoint("CENTER")
    return b
end
-- Shows a controller glyph on a key, the way the keyboard marks its shortcut keys.
function Style.Glyph(b, button)
    b.glyphButton = button
    if ns.KB and ns.KB.SetKeyGlyph then ns.KB.SetKeyGlyph(ns.KB, b, button) end
end
local function PaintKey(b, focused)
    local tint = KEY_ROLES[b.role]
    local state = focused and "selected" or (b.active and "active") or ((b.role == "tab" or b.role == "segment") and "normal" or "fn")
    -- An active segment keeps its own colour so the chosen option reads at a glance.
    ns.Skin.StyleKey(b, state, tint or nil)
    local glow = ns.Skin.SelectionGlow(b)
    if glow then glow:SetShown(focused) elseif b.glow then b.glow:Hide() end
    if b.disabled then b.text:SetTextColor(0.5,0.5,0.5) end
    b:SetAlpha(b.disabled and 0.55 or 1)
end
function Style.Paint(b, focused)
    if b.isKey then PaintKey(b, focused) return end
    b.focusRing:SetShown(focused)
    local role = b.role
    if role == "check" or role == "header" then
        -- Checkboxes sit on the pane; sort headers on the column band. Only focus lights them.
        b.face:SetColorTexture(unpack(role == "header" and {0.17,0.145,0.095,0.9} or {0.03,0.032,0.036,0.6}))
        b.wash:SetShown(focused)
        b.wash:SetColorTexture(0.12,0.32,0.55,0.5)
        b.marker:Hide()
        b.line:SetShown(false)
        if b.tick then b.tick:SetShown(b.checked == true) end
        if role == "header" then
            if b.active then b.text:SetTextColor(1,0.82,0.35) else b.text:SetTextColor(0.80,0.72,0.52) end
        elseif b.textColor then b.text:SetTextColor(unpack(b.textColor))
        else b.text:SetTextColor(0.88,0.86,0.79) end
        return
    end
    local color = {0.12,0.115,0.095,1}
    if role == "row" or role == "option" then
        color = b.stripe and {0.065,0.068,0.073,1} or {0.035,0.038,0.042,1}
    elseif role == "category" then color = {0.08,0.075,0.062,0.8}
    elseif role == "search" then color = {0.015,0.017,0.02,1} end
    b.face:SetColorTexture(unpack(color))
    b.wash:SetShown(b.active or (focused and (role == "row" or role == "option" or role == "category")))
    if focused and (role == "row" or role == "option" or role == "category") then b.wash:SetColorTexture(0.12,0.32,0.55,0.5)
    else b.wash:SetColorTexture(0.5,0.34,0.08,0.22) end
    b.marker:SetShown(b.active and role == "category")
    b.line:SetShown(role ~= "category" or b.depth == 0)
    if b.item and b.item.quality then b.text:SetTextColor(unpack(ns.Inventory.Color(b.item.quality)))
    elseif b.active then b.text:SetTextColor(1,0.82,0.35)
    elseif role == "category" then b.text:SetTextColor(0.85,0.79,0.61)
    elseif role == "search" and b.placeholder then b.text:SetTextColor(0.55,0.53,0.48)
    else b.text:SetTextColor(0.88,0.86,0.79) end
end
function Style.Press(b)
    if b.isKey then ns.Skin.FlashKey(b) return end
    b.flash:Show()
    C_Timer.After(0.09,function() b.flash:Hide() end)
end
