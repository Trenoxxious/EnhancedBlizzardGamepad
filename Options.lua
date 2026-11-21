local ADDON, ns = ...

-- EBG's settings window: an addon-owned panel, drawn like the auction browser and driven fully
-- by the pad. It is opened from the small gear on the keyboard and in the auction browser, or
-- with /ebg options.
--
-- It is not a page in Esc > Options > AddOns. Pages there are not reachable with the D-pad, and
-- on Forever the game's settings list carries taint from addon rows into other pages (the Social
-- page had its protected IsUserOAuthed blocked in the addon's name).
--
-- While the window is open it holds the pad (EnableGamePadButton). The keyboard and the auction
-- browser let go of it when the window opens and take it back when it closes
-- (ns.OnSettingsOpened / ns.OnSettingsClosed, Auction.ResumeInput).
--
-- Every control reads and writes through its spec's get/set, not ns.db directly: several settings
-- are stored as "nil means on", and many need something applied when they change (a keyboard
-- rebuild, the chat box fade), so slash commands and this window always agree.

local Options = {}
ns.Options = Options

local Style = ns.AuctionStyle

local W, H = 540, 560
local TITLE_H, DESC_H = 32, 46
local ROW_H, HEADER_H, ROW_GAP, SECTION_GAP = 30, 26, 4, 10
local REPEAT_DELAY, REPEAT_RATE = 0.35, 0.07
local TITLE = "Enhanced Blizzard Gamepad"

local window, scroll, content, desc, legend, thumb, track
local specs = {}      -- every entry, headers included, in display order
local controls = {}   -- the focusable entries, in order
local focus = 1
local listH, contentH = 1, 1
local pressed = {}
local held, heldNext

-- Settings ---------------------------------------------------------------------

local function Rebuild(resetKeys)
    if ns.RebuildKeyboard then ns.RebuildKeyboard(resetKeys) end
end

-- A stored flag where nil means the default.
local function Flag(key, default)
    return function()
        local v = ns.db[key]
        if v == nil then return default end
        return v and true or false
    end
end

local function Header(label)
    specs[#specs + 1] = { kind = "header", label = label }
end

local function Check(key, label, default, tip, set)
    specs[#specs + 1] = { kind = "check", key = key, label = label, tip = tip,
        get = Flag(key, default), set = set or function(v) ns.db[key] = v end }
end

local function Choice(key, label, tip, list, get, set)
    specs[#specs + 1] = { kind = "choice", key = key, label = label, tip = tip, list = list, get = get, set = set }
end

local function Range(key, label, tip, minValue, maxValue, step, format, get, set)
    specs[#specs + 1] = { kind = "range", key = key, label = label, tip = tip, min = minValue, max = maxValue,
        step = step, format = format, get = get, set = set }
end

local function Percent(v) return ("%d%%"):format(v * 100 + 0.5) end

local SKIN_NAMES = {
    dialog = "Dialog", dark = "Dark", classic = "Classic",
    tooltip = "Tooltip", metal = "Metal", flat = "Flat",
}
local SKIN_ORDER = { "dialog", "dark", "classic", "metal", "tooltip", "flat" }

local function SkinList()
    local list, seen = {}, {}
    for _, id in ipairs(SKIN_ORDER) do
        if ns.Skin.presets[id] then list[#list + 1] = { id, SKIN_NAMES[id] } seen[id] = true end
    end
    local extra = {}
    for id in pairs(ns.Skin.presets) do
        if not seen[id] then extra[#extra + 1] = id end
    end
    table.sort(extra)
    for _, id in ipairs(extra) do list[#list + 1] = { id, SKIN_NAMES[id] or id } end
    return list
end

local function LayoutList()
    local auto = ns.Layouts[ns.LocaleLayout[GetLocale and GetLocale() or "enUS"] or "qwerty"]
    local list = { { "auto", "Automatic" .. (auto and (" (" .. auto.name .. ")") or "") } }
    local ids = {}
    for id in pairs(ns.Layouts) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b) return ns.Layouts[a].name < ns.Layouts[b].name end)
    for _, id in ipairs(ids) do list[#list + 1] = { id, ns.Layouts[id].name } end
    return list
end

local function PointerList()
    return { { "move", "Beside the keyboard" }, { "hide", "Hidden" }, { "off", "Left alone" } }
end

local function GlyphList()
    return { { "auto", "Automatic" }, { "shapes", "PlayStation" }, { "letters", "Xbox" } }
end

local function Restyle() end -- set below, once the window exists

local function DefineSettings()
    Header("General")
    Check("enabled", "Enable keyboard", true, "Turn the on-screen keyboard and the gamepad auction house on or off.",
        function(v)
            ns.db.enabled = v
            if not v and ns.HideKeyboard then ns.HideKeyboard() end
        end)
    Check("autoShow", "Open automatically", true,
        "Show the keyboard whenever a text field gains focus. When off, open it with /ebg show or the EBG toggle key binding.")
    Check("requirePad", "Only with a gamepad", true,
        "Open automatically only while the gamepad is the active input, so typing on a physical keyboard is left alone.")
    Check("sounds", "Key sounds", true, "Play a click when a key is pressed.")

    Header("Keyboard")
    Choice("layout", "Layout", "Key arrangement. Automatic follows the game's language.", LayoutList,
        function() local id = ns.db.layout return id and ns.Layouts[id] and id or "auto" end,
        function(v) ns.db.layout = v ~= "auto" and v or nil Rebuild() end)
    Choice("skin", "Style", "Frame and key art for the keyboard, the gamepad auction house and this window.", SkinList,
        function() return ns.Skin.presets[ns.db.skin] and ns.db.skin or "dialog" end,
        function(v) ns.db.skin = v Rebuild(true) Restyle() end)
    Range("scale", "Scale", "Size of the keyboard and the gamepad auction house.", 0.5, 2, 0.05, Percent,
        function() return ns.db.scale or 1 end,
        function(v) ns.db.scale = v Rebuild() end)
    Range("bgShade", "Background shade",
        "How dark the panel background is: 0% shows the art at full strength, 100% is solid black.", 0, 1, 0.05, Percent,
        function() return ns.db.bgShade or 0.7 end,
        function(v) ns.db.bgShade = v Rebuild() Restyle() end)
    Check("stickNav", "Left stick moves selection", false,
        "While typing, the left stick moves the key selection. When off, the left stick keeps moving your character.",
        function(v) ns.db.stickNav = v Rebuild() end)
    Choice("navPointer", "Navigation pointer", "Where Blizzard's gamepad pointer goes while the keyboard is open.", PointerList,
        function() return ns.db.hideNavPointer == false and "off" or (ns.db.navPointer or "move") end,
        function(v)
            if ns.SetNavPointerHidden then ns.SetNavPointerHidden(false) end
            ns.db.hideNavPointer = v ~= "off"
            if v ~= "off" then ns.db.navPointer = v end
        end)

    Header("Chat")
    Check("closeOnSend", "Close chat after sending", true,
        "Send also closes chat and the keyboard. When off, Send leaves chat open for another message and Back closes it.")
    Check("hideChatBox", "Hide chat input box", true,
        "Fade Blizzard's chat input while the keyboard types into it. The keyboard's own preview shows the text.",
        function(v)
            ns.db.hideChatBox = v
            if ns.ApplyChatBoxVisibility then ns.ApplyChatBoxVisibility() end
        end)
    Check("chatMirror", "Show chat above keyboard", true, "Show a copy of the chat window above the keyboard while you type in chat.",
        function(v)
            ns.db.chatMirror = v
            if not v and ns.HideChatMirror then ns.HideChatMirror() end
        end)
    Check("mirrorScroll", "Right stick scrolls chat", true,
        "The right stick scrolls the chat copy above the keyboard. When off, it keeps turning the camera. Applies the next time the keyboard opens.")
    Check("fadeChatFrame", "Fade chat window behind copy", true,
        "Fade the real chat window while its copy is shown above the keyboard, so the text is not shown twice.")
    Check("lfgWhisper", "Quick whisper in Group Finder", true, "Whisper a group's leader straight from the group browser with the gamepad.")

    Header("Gamepad legend")
    Check("hideNativeLegend", "Hide Blizzard's legend while typing", true,
        "Fade Blizzard's button legend while the keyboard is open. Its hints are for the game, not the keyboard.",
        function(v)
            if not v and ns.SetNativeLegendHidden then ns.SetNativeLegendHidden(false) end
            ns.db.hideNativeLegend = v
        end)
    Check("nativePrompts", "Blizzard button prompts", true, "Draw the keyboard's legend with Blizzard's own button prompts.",
        function(v) ns.db.nativePrompts = v Rebuild() end)
    Choice("glyphStyle", "Button glyphs",
        "Which controller's button art to show. Automatic follows the controller the game reports, and PlayStation on a PC when none is identified. A PlayStation pad used through Steam Input or DS4Windows is often reported as Xbox; pick PlayStation then.",
        GlyphList,
        function() local v = ns.db.glyphStyle return (v == "shapes" or v == "letters") and v or "auto" end,
        function(v)
            ns.db.glyphStyle = v ~= "auto" and v or nil
            if ns.OnGlyphStyleChanged then ns.OnGlyphStyleChanged() end
            Options.RefreshLegend()
        end)

    Header("Auction House")
    Check("auctionAuto", "Gamepad auction house", true,
        "Open the gamepad auction browser when you talk to an auctioneer with a gamepad. /ebg ah opens it at any time.")
    Check("auctionHideNative", "Hide Blizzard's auction window", true, "Fade Blizzard's auction window while the gamepad browser is open.")
end

-- Values -----------------------------------------------------------------------

local function ChoiceIndex(spec)
    local list, cur = spec.list(), spec.get()
    for i, entry in ipairs(list) do
        if entry[1] == cur then return i, list end
    end
    return 1, list
end

local function ValueText(spec)
    if spec.kind == "choice" then
        local i, list = ChoiceIndex(spec)
        return list[i] and list[i][2] or tostring(spec.get())
    elseif spec.kind == "range" then
        return spec.format(spec.get())
    end
    return ""
end

local function Paint() end -- set below

local function Change(spec, value)
    if spec.get() == value then return end
    spec.set(value)
    if ns.PlayClick then ns.PlayClick() end
    Paint()
end

-- dir: +1 or -1. Toggles: right turns on, left turns off; A flips (dir nil).
local function Step(spec, dir)
    if spec.kind == "check" then
        local v = spec.get()
        if dir == nil then Change(spec, not v) else Change(spec, dir > 0) end
    elseif spec.kind == "choice" then
        local i, list = ChoiceIndex(spec)
        local n = #list
        if n == 0 then return end
        Change(spec, list[(i - 1 + (dir or 1)) % n + 1][1])
    elseif spec.kind == "range" then
        if not dir then return end
        local v = spec.get() + dir * spec.step
        v = math.floor(v / spec.step + 0.5) * spec.step
        v = math.max(spec.min, math.min(spec.max, v))
        Change(spec, v)
    end
end

-- Focus and scrolling ----------------------------------------------------------------

local function SetScroll(offset)
    offset = math.max(0, math.min(offset, math.max(0, contentH - listH)))
    scroll:SetVerticalScroll(offset)
    local range = contentH - listH
    if range <= 0 then
        track:Hide()
        return
    end
    track:Show()
    local trackH = listH
    local thumbH = math.max(24, trackH * listH / contentH)
    thumb:SetHeight(thumbH)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -(trackH - thumbH) * offset / range)
end

-- Keeps the focused row in view, with its section heading when that is the first row under it.
local function EnsureVisible(spec)
    local top, bottom = spec.y, spec.y + spec.h
    if spec.headerY then top = spec.headerY end
    local offset = scroll:GetVerticalScroll() or 0
    if top < offset then
        SetScroll(top - 4)
    elseif bottom > offset + listH then
        SetScroll(bottom - listH + 4)
    end
end

local function SetFocus(index, keepScroll)
    if #controls == 0 then return end
    focus = (index - 1) % #controls + 1
    Paint()
    if not keepScroll then EnsureVisible(controls[focus]) end
end

local function Move(dir) SetFocus(focus + dir) end

-- Bumpers jump to the first setting of the previous or next section.
local function Section(dir)
    local starts = {}
    for i, spec in ipairs(controls) do
        if spec.first then starts[#starts + 1] = i end
    end
    if #starts == 0 then return end
    local cur = 1
    for k, i in ipairs(starts) do if i <= focus then cur = k end end
    if dir < 0 and focus ~= starts[cur] then
        SetFocus(starts[cur])
    else
        SetFocus(starts[(cur - 1 + dir) % #starts + 1])
    end
end

Paint = function()
    if not window then return end
    for i, spec in ipairs(controls) do
        local b, focused = spec.button, i == focus
        if spec.kind == "check" then b.checked = spec.get() end
        Style.Paint(b, focused)
        if b.value then
            b.value:SetText(ValueText(spec))
            if focused then b.value:SetTextColor(1, 0.86, 0.45) else b.value:SetTextColor(1, 0.82, 0) end
            b.prev:SetAlpha(focused and 1 or 0.55)
            b.next:SetAlpha(focused and 1 or 0.55)
        end
    end
    local spec = controls[focus]
    desc:SetText(spec and spec.tip or "")
end

-- Window -------------------------------------------------------------------------

local function Arrow(parent, dir, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    local name = dir < 0 and "PrevPage" or "NextPage"
    b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", onClick)
    return b
end

local function CreateRow(spec, index)
    if spec.kind == "header" then
        local text = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetJustifyH("LEFT")
        text:SetText(spec.label)
        local rule = content:CreateTexture(nil, "ARTWORK")
        rule:SetHeight(1)
        rule:SetColorTexture(0.62, 0.50, 0.25, 0.55)
        spec.text, spec.rule = text, rule
        return
    end
    local b = Style.Control(content, spec.kind == "check" and "check" or "option")
    b:SetHeight(ROW_H)
    b.text:ClearAllPoints()
    b.text:SetJustifyH("LEFT")
    b.text:SetFontObject(GameFontHighlight)
    b.text:SetText(spec.label)
    if spec.kind == "check" then
        b.text:SetPoint("LEFT", b.box, "RIGHT", 10, 0)
        b:SetScript("OnClick", function() SetFocus(index, true) Step(spec) end)
    else
        b.text:SetPoint("LEFT", 12, 0)
        b.next = Arrow(b, 1, function() SetFocus(index, true) Step(spec, 1) end)
        b.next:SetPoint("RIGHT", -6, 0)
        b.value = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.value:SetPoint("RIGHT", b.next, "LEFT", -4, 0)
        b.value:SetWidth(200)
        b.value:SetJustifyH("CENTER")
        b.value:SetWordWrap(false)
        b.prev = Arrow(b, -1, function() SetFocus(index, true) Step(spec, -1) end)
        b.prev:SetPoint("RIGHT", b.value, "LEFT", -4, 0)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, mouse)
            SetFocus(index, true)
            Step(spec, mouse == "RightButton" and -1 or 1)
        end)
    end
    b:SetScript("OnEnter", function() SetFocus(index, true) end)
    spec.button = b
end

-- Places the rows and every docked part; run again when the style changes the border width.
local function Layout()
    local inset = ns.Skin.ContentInset(window)
    ns.Skin.DockBar(window.titleBand, window, "TOP", TITLE_H)
    ns.Skin.DockBar(legend, window, "BOTTOM")
    local legendH = legend:GetHeight() or 38
    local left, right = inset + 14, inset + 26
    local top, bottom = inset + TITLE_H + 10, inset + legendH + DESC_H + 14
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", left, -top)
    scroll:SetPoint("BOTTOMRIGHT", -right, bottom)
    listH = H - top - bottom
    local width = W - left - right
    content:SetWidth(width)
    track:ClearAllPoints()
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 0)
    track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 0)
    window.descRule:ClearAllPoints()
    window.descRule:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -6)
    window.descRule:SetPoint("TOPRIGHT", scroll, "BOTTOMRIGHT", 0, -6)
    desc:ClearAllPoints()
    desc:SetPoint("TOPLEFT", window.descRule, "BOTTOMLEFT", 2, -6)
    desc:SetPoint("TOPRIGHT", window.descRule, "BOTTOMRIGHT", -2, -6)
    desc:SetHeight(DESC_H - 8)

    local y, headerY, first = 0, nil, false
    for i, spec in ipairs(specs) do
        if spec.kind == "header" then
            if i > 1 then y = y + SECTION_GAP end
            headerY, first = y, true
            spec.text:ClearAllPoints()
            spec.text:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -(y + 4))
            spec.rule:ClearAllPoints()
            spec.rule:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(y + HEADER_H - 4))
            spec.rule:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(y + HEADER_H - 4))
            y = y + HEADER_H
        else
            local b = spec.button
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
            b:SetWidth(width)
            spec.y, spec.h = y, ROW_H
            spec.headerY = first and headerY or nil
            spec.first = first
            first = false
            y = y + ROW_H + ROW_GAP
        end
    end
    contentH = math.max(1, y - ROW_GAP)
    content:SetHeight(contentH)
    SetScroll(scroll:GetVerticalScroll() or 0)
end

Restyle = function()
    if not window then return end
    ns.Skin.Panel(window)
    Layout()
end

local function Create()
    window = CreateFrame("Frame", "EBGSettingsFrame", UIParent, "BackdropTemplate")
    window:SetSize(W, H)
    window:SetPoint("TOP", UIParent, "TOP", 0, -80)
    window:SetFrameStrata("FULLSCREEN_DIALOG")
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:Hide()
    ns.Skin.Panel(window)

    window.titleBand = Style.Band(window, 0, 0, 1, TITLE_H)
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", window.titleBand, "LEFT", 14, 0)
    title:SetText(TITLE .. "  |cffbbbbbbSettings|r")
    local ok, close = pcall(CreateFrame, "Button", nil, window, "UIPanelCloseButton")
    if ok and close then
        close:SetPoint("RIGHT", window.titleBand, "RIGHT", 2, 0)
        close:SetScript("OnClick", function() Options.Close() end)
    end

    scroll = CreateFrame("ScrollFrame", nil, window)
    scroll:SetClipsChildren(true)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        SetScroll((self:GetVerticalScroll() or 0) - delta * (ROW_H + ROW_GAP) * 2)
    end)

    track = CreateFrame("Frame", nil, window)
    track:SetWidth(4)
    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(0, 0, 0, 0.45)
    thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(4)
    thumb:SetColorTexture(0.80, 0.64, 0.30, 0.9)

    window.descRule = window:CreateTexture(nil, "ARTWORK")
    window.descRule:SetHeight(1)
    window.descRule:SetColorTexture(0.62, 0.50, 0.25, 0.55)
    desc = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetWordWrap(true)
    desc:SetTextColor(0.80, 0.78, 0.70)

    legend = ns.Glyphs.CreateLegendBar(window)

    DefineSettings()
    for _, spec in ipairs(specs) do
        if spec.kind ~= "header" then controls[#controls + 1] = spec end
    end
    for i, spec in ipairs(specs) do
        local index
        for k, c in ipairs(controls) do if c == spec then index = k break end end
        CreateRow(spec, index)
    end
    Layout()

    -- Pad: D-pad up/down moves, left/right changes, bumpers jump sections; A and B act on release
    -- (so the release of the press that opened the window is never taken as one).
    local function Act(key)
        if key == "PADDUP" then Move(-1)
        elseif key == "PADDDOWN" then Move(1)
        elseif key == "PADDLEFT" then Step(controls[focus], -1)
        elseif key == "PADDRIGHT" then Step(controls[focus], 1)
        end
    end
    local REPEATS = { PADDUP = true, PADDDOWN = true, PADDLEFT = true, PADDRIGHT = true }
    window:SetScript("OnGamePadButtonDown", function(self, key)
        if InCombatLockdown() then return end
        -- The guide button stays with the game; everything else is the window's.
        if key == "PADSYSTEM" then self:SetPropagateKeyboardInput(true) return end
        self:SetPropagateKeyboardInput(false)
        pressed[key] = true
        if REPEATS[key] then
            Act(key)
            held, heldNext = key, GetTime() + REPEAT_DELAY
        elseif key == "PADLSHOULDER" then Section(-1)
        elseif key == "PADRSHOULDER" then Section(1)
        end
    end)
    window:SetScript("OnGamePadButtonUp", function(self, key)
        if InCombatLockdown() then return end
        if held == key then held = nil end
        if key == "PADSYSTEM" then self:SetPropagateKeyboardInput(true) return end
        self:SetPropagateKeyboardInput(false)
        if not pressed[key] then return end
        pressed[key] = nil
        if key == "PAD1" then Step(controls[focus])
        elseif key == "PAD2" or key == "PADFORWARD" then Options.Close()
        end
    end)
    window:SetScript("OnUpdate", function()
        if held and GetTime() >= heldNext then
            Act(held)
            heldNext = GetTime() + REPEAT_RATE
        end
    end)
    window:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        local escape = key == "ESCAPE"
        self:SetPropagateKeyboardInput(not escape)
        if escape then Options.Close() end
    end)
    window:SetScript("OnHide", function(self)
        held = nil
        wipe(pressed)
        if not InCombatLockdown() then
            self:EnableGamePadButton(false)
            self:EnableKeyboard(false)
        end
        if ns.OnSettingsClosed then ns.OnSettingsClosed() end
        if ns.Auction and ns.Auction.ResumeInput then ns.Auction.ResumeInput() end
    end)
    -- Pad capture cannot change in combat, so the window closes as combat starts (this event
    -- arrives just before the lockdown).
    window:RegisterEvent("PLAYER_REGEN_DISABLED")
    window:SetScript("OnEvent", function(self) if self:IsShown() then self:Hide() end end)
end

-- API ----------------------------------------------------------------------------

function Options.IsShown()
    return window and window:IsShown() or false
end

function Options.IsMouseOver()
    return window and window:IsShown() and window:IsMouseOver() or false
end

function Options.RefreshLegend()
    if not legend then return end
    legend:SetItems({
        { "PAD1", "Change" }, { "PADDLEFT", "Adjust", "PADDRIGHT" },
        { "PADLSHOULDER", "Section", "PADRSHOULDER" }, { "PAD2", "Close" },
    })
end

function Options.Open()
    if not ns.db then return end
    if InCombatLockdown() then ns.Print("Open the settings after combat.") return end
    if not window then
        local ok, err = pcall(Create)
        if not ok then
            window = nil
            ns.Print("Could not open the settings: " .. tostring(err))
            return
        end
    end
    if window:IsShown() then window:Raise() return end
    if ns.OnSettingsOpened then ns.OnSettingsOpened() end
    held = nil
    wipe(pressed)
    Options.RefreshLegend()
    window:Show()
    window:Raise()
    window:EnableGamePadButton(true)
    window:EnableKeyboard(true)
    window:SetPropagateKeyboardInput(true)
    SetFocus(focus)
end

function Options.Close()
    if window and window:IsShown() then window:Hide() end
end

function Options.Toggle()
    if Options.IsShown() then Options.Close() else Options.Open() end
end
