local ADDON, ns = ...

local Skin = {}
ns.Skin = Skin

local FLAT = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

Skin.presets = {
    dialog  = { keyArt = "common-button-square-gray-up", keyArtDown = "common-button-square-gray-down", entryBox = "common-gray-button-entrybox", metal = true, panel = "Dialog", inset = "InsetFrameTemplate", bgAtlas = "auctionhouse-background-index", bgFile = 131071, preview = "chat" },
    dark    = { keyArt = "common-button-square-gray-up", keyArtDown = "common-button-square-gray-down", entryBox = "common-gray-button-entrybox", metal = true, panel = "Dialog", inset = "InsetFrameTemplate", preview = "chat" },
    classic = { panel = "Dialog", inset = "InsetFrameTemplate", bgFile = 131071, keyTemplate = "UIPanelButtonTemplate" },
    tooltip = { panel = "TooltipDefaultLayout", inset = "InsetFrameTemplate" },
    metal   = { panel = "GenericMetal",         inset = "InsetFrameTemplate" },
    flat    = { },
}

function Skin.Current()
    local id = ns.db and ns.db.skin or "dialog"
    return Skin.presets[id] or Skin.presets.dialog, id
end

local function ApplyNineSlice(frame, layoutName)
    if not layoutName or not NineSliceUtil or not NineSliceUtil.ApplyLayoutByName then return false end
    if not frame.NineSlice then
        local ok, child = pcall(CreateFrame, "Frame", nil, frame, "NineSlicePanelTemplate")
        if not ok or not child then return false end
        child:SetAllPoints()
        child:SetFrameLevel(frame:GetFrameLevel())
        frame.NineSlice = child
    end
    frame.NineSlice:Show()
    local ok = pcall(NineSliceUtil.ApplyLayoutByName, frame.NineSlice, layoutName)
    if not ok then frame.NineSlice:Hide() return false end
    if frame.NineSlice.Center then frame.NineSlice.Center:Hide() end
    return true
end

local function ApplyFlat(frame, bg, border)
    if not frame.SetBackdrop then
        if Mixin and BackdropTemplateMixin then Mixin(frame, BackdropTemplateMixin) else return end
    end
    frame:SetBackdrop(FLAT)
    frame:SetBackdropColor(unpack(bg))
    frame:SetBackdropBorderColor(unpack(border))
end

local function ClearFlat(frame)
    if frame.SetBackdrop and frame.GetBackdrop and frame:GetBackdrop() then frame:SetBackdrop(nil) end
end

local function AtlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local METAL = {
    tl = "UI-Frame-DiamondMetal-CornerTopLeft", tr = "UI-Frame-DiamondMetal-CornerTopRight",
    bl = "UI-Frame-DiamondMetal-CornerBottomLeft", br = "UI-Frame-DiamondMetal-CornerBottomRight",
    top = "_UI-Frame-DiamondMetal-EdgeTop", bottom = "_UI-Frame-DiamondMetal-EdgeBottom",
    left = "!UI-Frame-DiamondMetal-EdgeLeft", right = "!UI-Frame-DiamondMetal-EdgeRight",
}

local function ApplyMetal(frame, preset)
    if not AtlasExists(METAL.tl) or not AtlasExists(METAL.top) then return false end
    if not frame.metal then
        local m = {}
        local function tex(layer, sub)
            return frame:CreateTexture(nil, layer, nil, sub)
        end
        for _, k in ipairs({ "tl", "tr", "bl", "br" }) do
            m[k] = tex("BORDER")
            m[k]:SetAtlas(METAL[k], true)
        end
        m.tl:SetPoint("TOPLEFT", 0, 0)
        m.tr:SetPoint("TOPRIGHT", 0, 0)
        m.bl:SetPoint("BOTTOMLEFT", 0, 0)
        m.br:SetPoint("BOTTOMRIGHT", 0, 0)
        m.top = tex("BORDER")
        m.top:SetAtlas(METAL.top, true)
        m.top:SetHorizTile(true)
        m.top:SetPoint("TOPLEFT", m.tl, "TOPRIGHT", 0, 0)
        m.top:SetPoint("BOTTOMRIGHT", m.tr, "BOTTOMLEFT", 0, 0)
        m.bottom = tex("BORDER")
        m.bottom:SetAtlas(METAL.bottom, true)
        m.bottom:SetHorizTile(true)
        m.bottom:SetPoint("TOPLEFT", m.bl, "TOPRIGHT", 0, 0)
        m.bottom:SetPoint("BOTTOMRIGHT", m.br, "BOTTOMLEFT", 0, 0)
        m.left = tex("BORDER")
        m.left:SetAtlas(METAL.left, true)
        m.left:SetVertTile(true)
        m.left:SetPoint("TOPLEFT", m.tl, "BOTTOMLEFT", 0, 0)
        m.left:SetPoint("BOTTOMRIGHT", m.bl, "TOPRIGHT", 0, 0)
        m.right = tex("BORDER")
        m.right:SetAtlas(METAL.right, true)
        m.right:SetVertTile(true)
        m.right:SetPoint("TOPLEFT", m.tr, "BOTTOMLEFT", 0, 0)
        m.right:SetPoint("BOTTOMRIGHT", m.br, "TOPRIGHT", 0, 0)
        frame.metal = m
    end
    local m = frame.metal
    for _, t in pairs(m) do t:Show() end
    Skin.ApplyBackground(frame, preset)
    return true
end

function Skin.ApplyBackground(frame, preset)
    local inset = frame.metal and 10 or 6
    if not frame.bgBase then
        frame.bgBase = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame.bgArt = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
    end
    if frame.bgHolder then frame.bgHolder:Hide() end
    for _, t in ipairs({ frame.bgBase, frame.bgArt }) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", inset, -inset)
        t:SetPoint("BOTTOMRIGHT", -inset, inset)
    end
    frame.bgBase:SetColorTexture(0.04, 0.04, 0.05, 1)
    frame.bgBase:Show()

    local shade = ns.db and ns.db.bgShade or 0.7
    local artAlpha = 1 - shade
    local bgAtlas = ns.db and ns.db.bgAtlas or preset.bgAtlas
    local art = frame.bgArt
    art:Hide()
    Skin.lastBackground = ("base dark, shade %.2f, atlas %s"):format(shade, tostring(bgAtlas))
    if artAlpha <= 0 then return end
    if bgAtlas and AtlasExists(bgAtlas) then
        local info = C_Texture.GetAtlasInfo(bgAtlas)
        art:SetAtlas(bgAtlas, false)
        local w, h = frame:GetWidth() - inset * 2, frame:GetHeight() - inset * 2
        local aw, ah = info.width or w, info.height or h
        local l, r, t, b = info.leftTexCoord or 0, info.rightTexCoord or 1, info.topTexCoord or 0, info.bottomTexCoord or 1
        if w > 0 and h > 0 and aw > 0 and ah > 0 then
            local panelAspect, artAspect = w / h, aw / ah
            if panelAspect > artAspect then
                local keep = artAspect / panelAspect
                local mid = (t + b) / 2
                local half = (b - t) * keep / 2
                t, b = mid - half, mid + half
            else
                local keep = panelAspect / artAspect
                local mid = (l + r) / 2
                local half = (r - l) * keep / 2
                l, r = mid - half, mid + half
            end
        end
        art:SetTexCoord(l, r, t, b)
        art:SetVertexColor(1, 1, 1, artAlpha)
        art:Show()
        Skin.lastBackground = Skin.lastBackground .. (" (art alpha %.2f)"):format(artAlpha)
    elseif preset.bgFile then
        art:SetTexture(preset.bgFile, "REPEAT", "REPEAT")
        art:SetTexCoord(0, 1, 0, 1)
        art:SetHorizTile(true)
        art:SetVertTile(true)
        art:SetVertexColor(1, 1, 1, artAlpha)
        art:Show()
        Skin.lastBackground = Skin.lastBackground .. " (file art)"
    end
end

local function HideMetal(frame)
    if frame.metal then for _, t in pairs(frame.metal) do t:Hide() end end
end

local function PanelInner(frame)
    local preset = Skin.Current()
    if frame.NineSlice then frame.NineSlice:Hide() end
    if preset.metal then
        if ApplyMetal(frame, preset) then
            ClearFlat(frame)
            if preset.headerTrim and AtlasExists(preset.headerTrim) then
                if not frame.trim then
                    frame.trim = frame:CreateTexture(nil, "OVERLAY")
                    frame.trim:SetPoint("TOP", 0, -9)
                    frame.trim:SetSize(174, 4)
                end
                frame.trim:SetAtlas(preset.headerTrim)
                frame.trim:Show()
            elseif frame.trim then
                frame.trim:Hide()
            end
            return "metal"
        end
    end
    HideMetal(frame)
    if ApplyNineSlice(frame, preset.panel) then
        ClearFlat(frame)
        Skin.ApplyBackground(frame, preset)
        if preset.headerTrim and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(preset.headerTrim) then
            if not frame.trim then
                frame.trim = frame:CreateTexture(nil, "OVERLAY")
                frame.trim:SetPoint("TOP", 0, -7)
                frame.trim:SetSize(174, 4)
            end
            frame.trim:SetAtlas(preset.headerTrim)
            frame.trim:Show()
        elseif frame.trim then
            frame.trim:Hide()
        end
        return "nineslice"
    end
    if frame.trim then frame.trim:Hide() end
    ApplyFlat(frame, { 0.05, 0.05, 0.07, 0.94 }, { 0.30, 0.31, 0.36, 1 })
    Skin.ApplyBackground(frame, preset)
    return "flat"
end

local CHAT_LEFT, CHAT_MID, CHAT_RIGHT = 374197, 374198, 374199

local function ApplyChatArt(frame)
    if not frame.chatArt then
        local left = frame:CreateTexture(nil, "BACKGROUND")
        left:SetTexture(CHAT_LEFT)
        left:SetSize(32, 32)
        left:SetPoint("LEFT", 0, 0)
        local right = frame:CreateTexture(nil, "BACKGROUND")
        right:SetTexture(CHAT_RIGHT)
        right:SetSize(32, 32)
        right:SetPoint("RIGHT", 0, 0)
        local mid = frame:CreateTexture(nil, "BACKGROUND")
        mid:SetTexture(CHAT_MID, "REPEAT", "REPEAT")
        mid:SetHorizTile(true)
        mid:SetHeight(32)
        mid:SetPoint("LEFT", left, "RIGHT", 0, 0)
        mid:SetPoint("RIGHT", right, "LEFT", 0, 0)
        frame.chatArt = { left, mid, right }
    end
    for _, t in ipairs(frame.chatArt) do t:Show() end
end

local function HideChatArt(frame)
    if frame.chatArt then for _, t in ipairs(frame.chatArt) do t:Hide() end end
end

local function SetAtlasPart(tex, info, u0, u1, v0, v1)
    local l, r = info.leftTexCoord or 0, info.rightTexCoord or 1
    local t, b = info.topTexCoord or 0, info.bottomTexCoord or 1
    tex:SetTexture(info.file or info.filename)
    tex:SetTexCoord(l + (r - l) * u0, l + (r - l) * u1, t + (b - t) * v0, t + (b - t) * v1)
end

local function ApplyEntryBox(frame, base)
    local li = C_Texture.GetAtlasInfo(base .. "-left")
    local ci = C_Texture.GetAtlasInfo(base .. "-center")
    local ri = C_Texture.GetAtlasInfo(base .. "-right")
    if not (li and ci and ri) then return false end
    if not frame.entryArt then
        local a = {}
        for i = 1, 3 do a[i] = frame:CreateTexture(nil, "BACKGROUND") end
        frame.entryArt = a
    end
    local left, mid, right = frame.entryArt[1], frame.entryArt[2], frame.entryArt[3]
    local h = frame:GetHeight() + 6
    local fw = frame:GetWidth()
    if not fw or fw < 1 then fw = (frame:GetParent():GetWidth() or 600) - 28 end
    local maxCap = math.max(8, fw * 0.45)
    local function capWidth(info)
        local w = h * ((info.width or h) / math.max(1, info.height or h))
        return math.min(w, maxCap)
    end
    left:SetAtlas(base .. "-left", false)
    left:ClearAllPoints()
    left:SetPoint("LEFT", 0, 0)
    left:SetSize(capWidth(li), h)
    right:SetAtlas(base .. "-right", false)
    right:ClearAllPoints()
    right:SetPoint("RIGHT", 0, 0)
    right:SetSize(capWidth(ri), h)
    mid:SetAtlas(base .. "-center", false)
    mid:ClearAllPoints()
    mid:SetPoint("LEFT", left, "RIGHT", 0, 0)
    mid:SetPoint("RIGHT", right, "LEFT", 0, 0)
    mid:SetHeight(h)
    for _, t in ipairs(frame.entryArt) do t:Show() end
    return true
end

local function HideEntryBox(frame)
    if frame.entryArt then for _, t in ipairs(frame.entryArt) do t:Hide() end end
end

function Skin.Inset(frame)
    local preset = Skin.Current()
    if frame.NineSlice then frame.NineSlice:Hide() end
    local entry = ns.db and ns.db.entryBox or preset.entryBox
    if entry and entry ~= "off" and ApplyEntryBox(frame, entry) then
        ClearFlat(frame)
        HideChatArt(frame)
        frame.tintArt = frame.entryArt
        return "entrybox"
    end
    HideEntryBox(frame)
    frame.tintArt = nil
    if preset.preview == "chat" then
        frame.tintArt = nil
        ClearFlat(frame)
        ApplyChatArt(frame)
        frame.tintArt = frame.chatArt
        return "chat"
    end
    HideChatArt(frame)
    if ApplyNineSlice(frame, preset.inset) then
        ClearFlat(frame)
        return "nineslice"
    end
    ApplyFlat(frame, { 0.09, 0.09, 0.12, 1 }, { 0.33, 0.35, 0.40, 1 })
    return "flat"
end

local KEY = {
    normal   = { fill = { 0.07, 0.07, 0.09, 0.97 }, border = { 0.36, 0.31, 0.20, 1 }, text = { 0.93, 0.93, 0.93 } },
    fn       = { fill = { 0.12, 0.11, 0.10, 0.97 }, border = { 0.42, 0.35, 0.22, 1 }, text = { 0.88, 0.82, 0.62 } },
    active   = { fill = { 0.32, 0.25, 0.08, 0.98 }, border = { 0.90, 0.72, 0.20, 1 }, text = { 1.00, 0.90, 0.55 } },
    selected = { fill = { 0.95, 0.76, 0.22, 1.00 }, border = { 1.00, 0.93, 0.60, 1 }, text = { 0.08, 0.06, 0.02 } },
}

local function SetSheen(tex, topAlpha, bottomAlpha)
    if tex.SetGradient and CreateColor then
        pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(1, 1, 1, bottomAlpha), CreateColor(1, 1, 1, topAlpha))
    else
        tex:SetAlpha(topAlpha)
    end
end

function Skin.CreateKey(parent)
    local preset = Skin.Current()
    if preset.keyTemplate then
        local ok, btn = pcall(CreateFrame, "Button", nil, parent, preset.keyTemplate)
        if ok and btn and btn.GetFontString then
            btn.text = btn:GetFontString() or btn.Text
            if btn.text then
                btn.text:ClearAllPoints()
                btn.text:SetPoint("CENTER", 0, 0)
                btn.text:SetFontObject(GameFontHighlightMedium)
            end
            btn.templated = true
            return btn
        end
    end
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetBackdrop(FLAT)
    b.sheen = b:CreateTexture(nil, "BORDER")
    b.sheen:SetTexture("Interface\\Buttons\\WHITE8x8")
    b.sheen:SetPoint("TOPLEFT", 1, -1)
    b.sheen:SetPoint("BOTTOMRIGHT", -1, 1)
    SetSheen(b.sheen, 0.10, 0.0)
    b.lip = b:CreateTexture(nil, "ARTWORK")
    b.lip:SetPoint("TOPLEFT", 1, -1)
    b.lip:SetPoint("TOPRIGHT", -1, -1)
    b.lip:SetHeight(1)
    b.lip:SetColorTexture(1, 0.92, 0.70, 0.22)
    b.shadow = b:CreateTexture(nil, "ARTWORK")
    b.shadow:SetPoint("BOTTOMLEFT", 1, 1)
    b.shadow:SetPoint("BOTTOMRIGHT", -1, 1)
    b.shadow:SetHeight(2)
    b.shadow:SetColorTexture(0, 0, 0, 0.45)
    b.artParts = {}
    for i = 1, 3 do
        b.artParts[i] = b:CreateTexture(nil, "BORDER", nil, -1)
        b.artParts[i]:Hide()
    end
    b.glowParts = {}
    for i = 1, 6 do
        local t = b:CreateTexture(nil, "ARTWORK", nil, 1)
        t:SetBlendMode("ADD")
        t:Hide()
        b.glowParts[i] = t
    end
    b.flash = b:CreateTexture(nil, "OVERLAY")
    b.flash:SetTexture("Interface\\Buttons\\WHITE8x8")
    b.flash:SetAllPoints()
    b.flash:SetVertexColor(1, 1, 1, 0.35)
    b.flash:Hide()
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightMedium")
    b.text:SetPoint("CENTER", 0, 0)
    b.templated = false
    return b
end

function Skin.KeyArt(pressed)
    local db, preset = ns.db, Skin.Current()
    local up = db and db.keyArt or preset.keyArt
    if not up or up == "off" then return nil end
    if pressed then
        local down = db and db.keyArtSelected or (not (db and db.keyArt) and preset.keyArtDown)
        if down and AtlasExists(down) then return down end
    end
    return up
end

function Skin.StyleKey(b, state)
    if b.templated then
        if state == "selected" then
            b:LockHighlight()
            b.text:SetTextColor(1, 0.82, 0)
        else
            b:UnlockHighlight()
            if state == "active" then b.text:SetTextColor(0.4, 0.8, 1)
            elseif state == "fn" then b.text:SetTextColor(0.85, 0.85, 0.85)
            else b.text:SetTextColor(1, 1, 1) end
        end
        return
    end
    local c = KEY[state] or KEY.normal
    b.state = state
    local artName = Skin.KeyArt(b.pressed)
    local info = artName and b.artParts and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(artName)
    if info then
        local pad = ns.db and ns.db.keyArtPad or 0.15
        local bleed = ns.db and ns.db.keyArtBleed or 5
        local w, h = b:GetWidth(), b:GetHeight()
        local span = 1 - pad * 2
        local du = math.min(pad, bleed * span / h)
        bleed = du * h / span
        local cap = math.min(h * 0.45, w * 0.5)
        local capU = span * cap / h
        local function layout(L, M, R)
            L:ClearAllPoints(); L:SetPoint("TOPLEFT", -bleed, bleed); L:SetPoint("BOTTOMLEFT", -bleed, -bleed); L:SetWidth(cap + bleed)
            R:ClearAllPoints(); R:SetPoint("TOPRIGHT", bleed, bleed); R:SetPoint("BOTTOMRIGHT", bleed, -bleed); R:SetWidth(cap + bleed)
            M:ClearAllPoints(); M:SetPoint("TOPLEFT", L, "TOPRIGHT"); M:SetPoint("BOTTOMRIGHT", R, "BOTTOMLEFT")
            SetAtlasPart(L, info, pad - du, pad + capU, pad - du, 1 - pad + du)
            SetAtlasPart(M, info, pad + capU, 1 - pad - capU, pad - du, 1 - pad + du)
            SetAtlasPart(R, info, 1 - pad - capU, 1 - pad + du, pad - du, 1 - pad + du)
            L:Show(); R:Show(); M:SetShown(w - cap * 2 > 0.5)
        end
        layout(b.artParts[1], b.artParts[2], b.artParts[3])
        local tr, tg, tb = 1, 1, 1
        if state == "active" then tr, tg, tb = 1, 0.78, 0.35 elseif state == "fn" then tr, tg, tb = 1, 0.95, 0.85 end
        for _, t in ipairs(b.artParts) do t:SetVertexColor(tr, tg, tb) end
        b:SetBackdropColor(0, 0, 0, 0)
        b:SetBackdropBorderColor(0, 0, 0, 0)
        if state == "selected" then
            local strength = ns.db and ns.db.keyGlow or 1
            layout(b.glowParts[1], b.glowParts[2], b.glowParts[3])
            layout(b.glowParts[4], b.glowParts[5], b.glowParts[6])
            for i, t in ipairs(b.glowParts) do
                local a = math.max(0, math.min(1, i <= 3 and strength or strength - 1))
                t:SetVertexColor(1, 0.86, 0.50, a)
                if a <= 0 then t:Hide() end
            end
            b.text:SetTextColor(1, 0.90, 0.45)
        else
            for _, t in ipairs(b.glowParts) do t:Hide() end
            b.text:SetTextColor(unpack(c.text))
        end
        if b.sheen then b.sheen:Hide() end
        if b.lip then b.lip:Hide() b.shadow:Hide() end
        return
    end
    if b.artParts then
        for _, t in ipairs(b.artParts) do t:Hide() end
        for _, t in ipairs(b.glowParts) do t:Hide() end
    end
    if b.sheen then b.sheen:Show() end
    if b.lip then b.lip:Show() b.shadow:Show() end
    b:SetBackdropColor(unpack(c.fill))
    b:SetBackdropBorderColor(unpack(c.border))
    b.text:SetTextColor(unpack(c.text))
    if b.sheen then
        if state == "selected" then SetSheen(b.sheen, 0.30, 0.0) else SetSheen(b.sheen, 0.10, 0.0) end
    end
end

function Skin.FlashKey(b)
    if b.artParts and Skin.KeyArt() then
        b.pressed = true
        Skin.StyleKey(b, b.state or "normal")
        C_Timer.After(0.09, function()
            b.pressed = nil
            Skin.StyleKey(b, b.state or "normal")
        end)
        return
    end
    if not b.flash then return end
    b.flash:Show()
    C_Timer.After(0.07, function() b.flash:Hide() end)
end

local EDITMODE_LAYOUT = {
    mirrorLayout = true,
    TopLeftCorner     = { atlas = "editmode-actionbar-highlight-nineslice-corner" },
    TopRightCorner    = { atlas = "editmode-actionbar-highlight-nineslice-corner" },
    BottomLeftCorner  = { atlas = "editmode-actionbar-highlight-nineslice-corner" },
    BottomRightCorner = { atlas = "editmode-actionbar-highlight-nineslice-corner" },
    TopEdge    = { atlas = "_editmode-actionbar-highlight-nineslice-edgetop" },
    BottomEdge = { atlas = "_editmode-actionbar-highlight-nineslice-edgebottom" },
    LeftEdge   = { atlas = "!editmode-actionbar-highlight-nineslice-edgeleft" },
    RightEdge  = { atlas = "!editmode-actionbar-highlight-nineslice-edgeright" },
}

local function EditModeGlow(b)
    if b.glowFrame ~= nil then return b.glowFrame or nil end
    b.glowFrame = false
    if not NineSliceUtil or not NineSliceUtil.ApplyLayout then return nil end
    local ok, f = pcall(CreateFrame, "Frame", nil, b, "NineSlicePanelTemplate")
    if not ok or not f then return nil end
    f:SetPoint("TOPLEFT", -6, 6)
    f:SetPoint("BOTTOMRIGHT", 6, -6)
    f:SetFrameLevel(b:GetFrameLevel() + 1)
    local applied = pcall(NineSliceUtil.ApplyLayout, f, EDITMODE_LAYOUT)
    if not applied then f:Hide() return nil end
    if f.Center then f.Center:Hide() end
    f:Hide()
    b.glowFrame = f
    return f
end

function Skin.SelectionGlow(b)
    local name = ns.db and ns.db.glowAtlas
    if name == "off" then
        if b.glow then b.glow:Hide() end
        if b.glowFrame then b.glowFrame:Hide() end
        return nil
    end
    if name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) then
        if b.glowFrame then b.glowFrame:Hide() end
        if not b.glow then
            b.glow = b:CreateTexture(nil, "OVERLAY", nil, 7)
            b.glow:SetPoint("TOPLEFT", -6, 6)
            b.glow:SetPoint("BOTTOMRIGHT", 6, -6)
        end
        b.glow:SetAtlas(name)
        return b.glow
    end
    if b.glow then b.glow:Hide() end
    if name == "editmode" then return EditModeGlow(b) end
    if b.glowFrame then b.glowFrame:Hide() end
    return nil
end

function Skin.Panel(frame)
    local ok, mode = pcall(PanelInner, frame)
    if not ok then
        Skin.lastPanel = "error: " .. tostring(mode)
        ns.Print("Skin error: " .. tostring(mode))
        return "error"
    end
    Skin.lastPanel = mode
    return mode
end

function Skin.Diagnostics()
    local lines = {
        "Panel path: " .. tostring(Skin.lastPanel),
        "Background: " .. tostring(Skin.lastBackground),
        "",
        "Atlas availability:",
    }
    for _, name in ipairs({ METAL.tl, METAL.top, METAL.left, "UI-World-Quest-golden-line", "auctionhouse-background-index" }) do
        lines[#lines + 1] = ("  %-45s %s"):format(name, AtlasExists(name) and "yes" or "NO")
    end
    lines[#lines + 1] = "Legend art: " .. tostring(Skin.lastLegend)
    lines[#lines + 1] = "NineSliceUtil.ApplyLayoutByName: " .. tostring(NineSliceUtil and NineSliceUtil.ApplyLayoutByName ~= nil)
    lines[#lines + 1] = "C_Texture.GetAtlasInfo: " .. tostring(C_Texture and C_Texture.GetAtlasInfo ~= nil)
    return lines
end

local legendSource, legendSearched = nil, 0

local function IsLegendContainer(f)
    return type(f) == "table" and type(f.backgroundSlot) == "table" and type(f.backgroundBorder) == "table"
        and not (f.IsForbidden and f:IsForbidden())
end

local function FindLegendSource()
    if legendSource then return legendSource end
    if legendSearched >= 6 then return nil end
    legendSearched = legendSearched + 1
    local found
    pcall(function()
        local f = EnumerateFrames()
        local n = 0
        while f and n < 20000 do
            n = n + 1
            if not f:IsForbidden() then
                local c = f.promptContainerFrame
                if IsLegendContainer(c) then found = c break end
                if IsLegendContainer(f) then found = f break end
            end
            f = EnumerateFrames(f)
        end
    end)
    legendSource = found
    return found
end

local function CloneTexture(src, parent)
    local layer, sub = src:GetDrawLayer()
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
    local atlas = src.GetAtlas and src:GetAtlas()
    if atlas then
        t:SetAtlas(atlas, false)
    else
        local file = src:GetTexture()
        if file then
            t:SetTexture(file)
            t:SetTexCoord(src:GetTexCoord())
        else
            t:SetColorTexture(src:GetVertexColor())
        end
    end
    if src.GetTextureSliceMargins and t.SetTextureSliceMargins then
        local l, r, top, b = src:GetTextureSliceMargins()
        if l and (l + r + top + b) > 0 then
            t:SetTextureSliceMargins(l, r, top, b)
            if src.GetTextureSliceMode and t.SetTextureSliceMode then t:SetTextureSliceMode(src:GetTextureSliceMode()) end
        end
    end
    if src.GetHorizTile and src:GetHorizTile() then t:SetHorizTile(true) end
    if src.GetVertTile and src:GetVertTile() then t:SetVertTile(true) end
    if atlas or src:GetTexture() then t:SetVertexColor(src:GetVertexColor()) end
    t:SetAlpha(src:GetAlpha())
    if src.GetBlendMode then t:SetBlendMode(src:GetBlendMode()) end
    return t
end

local function ClonePoints(src, dst, map, band)
    local n = src:GetNumPoints()
    dst:ClearAllPoints()
    if n == 0 then dst:SetAllPoints(band) return end
    for i = 1, n do
        local point, rel, relPoint, x, y = src:GetPoint(i)
        dst:SetPoint(point, map[rel] or band, relPoint or point, x or 0, y or 0)
    end
    if n < 2 then
        local w, h = src:GetSize()
        if w and h and w > 0 and h > 0 then dst:SetSize(w, h) end
    end
end

local function ClonePiece(src, band, map, made)
    if src.GetObjectType and src:IsObjectType("Texture") then
        local t = CloneTexture(src, band)
        map[src] = t
        made[#made + 1] = { src, t }
        return
    end
    local f = CreateFrame("Frame", nil, band)
    f:SetFrameLevel(band:GetFrameLevel())
    map[src] = f
    made[#made + 1] = { src, f }
    for _, r in ipairs({ src:GetRegions() }) do
        if r:IsObjectType("Texture") and r:IsShown() then
            local t = CloneTexture(r, f)
            map[r] = t
            made[#made + 1] = { r, t }
        end
    end
end

function Skin.LegendBackground(band)
    if band.legendArt then return true end
    if ns.db and ns.db.legendArt == false then return false end
    local source = FindLegendSource()
    if not source then
        Skin.lastLegend = "fallback (no Blizzard input legend found yet)"
        return false
    end
    local made = {}
    local ok, err = pcall(function()
        local map = { [source] = band }
        ClonePiece(source.backgroundSlot, band, map, made)
        ClonePiece(source.backgroundBorder, band, map, made)
        for _, pair in ipairs(made) do ClonePoints(pair[1], pair[2], map, band) end
    end)
    if not ok then
        for _, pair in ipairs(made) do pair[2]:Hide() end
        Skin.lastLegend = "fallback (copy failed: " .. tostring(err) .. ")"
        legendSearched = 99
        legendSource = nil
        return false
    end
    band.legendArt = made
    local name = source.GetDebugName and source:GetDebugName() or "?"
    Skin.lastLegend = ("copied %d pieces from %s"):format(#made, name)
    return true
end
