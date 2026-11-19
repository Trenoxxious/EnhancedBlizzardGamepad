local ADDON, ns = ...

-- Settings page in Esc > Options > AddOns, built on the game's Settings API.
--
-- The page is a canvas: one frame of ours whose rows are made from the game's own row templates,
-- so it looks like the game's pages. It is not a vertical layout list. On Forever the game reuses
-- that list's row frames for every category, and rows set up by addon code carry taint into other
-- pages (the Social page then had its protected IsUserOAuthed blocked in the addon's name). So
-- nothing is added to the game's lists, and every row is built once at login while the page is
-- hidden, never while the settings panel is open. Same approach as SmoothExperienceBar.
--
-- Each control reads and writes through a proxy table, not ns.db directly: several settings are
-- stored as "nil means on", and many need something applied when they change (a keyboard
-- rebuild, the chat box fade). The proxy turns every read into the effective value and every
-- write into db + apply, so slash commands and this page always agree.

local Options = {}
ns.Options = Options

-- The settings list's own measurements (Blizzard_SettingsList.xml), so the page lines up with
-- the game's: header strip, list position under it, row padding and row heights.
local HEADER_H, TITLE_X, TITLE_Y = 50, 7, -22
local LIST_X, LIST_Y, LIST_RIGHT, LIST_BOTTOM = -15, -2, -20, -2
local PAD, PAD_LEFT, SPACING = 10, 25, 9
local ROW_H, SECTION_H = 26, 45

local TITLE = "Enhanced Blizzard Gamepad"

local category, canvas, content
local rows = {}
local specs = {}

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

-- Proxy: settings[key] reads spec.get(), settings[key] = v runs spec.set(v).
local proxy = setmetatable({}, {
    __index = function(_, key)
        local spec = specs[key]
        if spec and ns.db then return spec.get() end
    end,
    __newindex = function(_, key, value)
        local spec = specs[key]
        if not spec or not ns.db then return end
        if spec.get() == value then return end
        spec.set(value)
    end,
})

local function Register(key, name, default, get, set)
    specs[key] = {
        get = get or Flag(key, default),
        set = set or function(v) ns.db[key] = v end,
    }
    return Settings.RegisterAddOnSetting(category, ADDON .. "_" .. key, key, proxy, type(default), name, default)
end

-- A row: a frame of ours made from the initializer's template. The template's code finds its
-- initializer through GetElementData, as it does in the game's list.
local function Row(initializer, height)
    local frame = CreateFrame("Frame", nil, content, initializer:GetTemplate())
    frame.GetElementData = function() return initializer end
    initializer:InitFrame(frame)
    rows[#rows + 1] = { frame = frame, initializer = initializer, height = height or ROW_H }
end

local function Header(text)
    Row(CreateSettingsListSectionHeaderInitializer(text), SECTION_H)
end

local function Checkbox(setting, tooltip)
    Row(Settings.CreateCheckboxInitializer(setting, nil, tooltip))
end

local function Slider(setting, tooltip, minValue, maxValue, step, format)
    local options = Settings.CreateSliderOptions(minValue, maxValue, step)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
    Row(Settings.CreateSliderInitializer(setting, options, tooltip))
end

local function Dropdown(setting, tooltip, list)
    Row(Settings.CreateDropdownInitializer(setting, function()
        local container = Settings.CreateControlTextContainer()
        for _, entry in ipairs(list()) do container:Add(entry[1], entry[2]) end
        return container:GetData()
    end, tooltip))
end

-- Option lists -----------------------------------------------------------------

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
    for id in pairs(ns.Skin.presets) do
        if not seen[id] then list[#list + 1] = { id, SKIN_NAMES[id] or id } end
    end
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
    return { { "move", "Beside the Keyboard" }, { "hide", "Hidden" }, { "off", "Left Alone" } }
end

-- Page -----------------------------------------------------------------------

local function LayoutRows()
    local y = PAD
    for _, row in ipairs(rows) do
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_LEFT, -y)
        row.frame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        row.frame:SetHeight(row.height)
        y = y + row.height + SPACING
    end
    content:SetHeight(y - SPACING + PAD)
end

local function BuildPage()
    canvas = CreateFrame("Frame")
    canvas:Hide()

    local text = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    text:SetPoint("TOPLEFT", TITLE_X, TITLE_Y)
    text:SetText(TITLE)

    local divider = canvas:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.15)
    divider:SetPoint("TOPLEFT", 0, -HEADER_H)
    divider:SetPoint("TOPRIGHT", LIST_RIGHT, -HEADER_H)
    divider:SetHeight(1)

    local scroll = CreateFrame("ScrollFrame", nil, canvas)
    scroll:SetPoint("TOPLEFT", LIST_X, -HEADER_H + LIST_Y)
    scroll:SetPoint("BOTTOMRIGHT", LIST_RIGHT, LIST_BOTTOM)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width)
        if width and width > 0 then content:SetWidth(width) end
    end)

    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        local bar = CreateFrame("EventFrame", nil, canvas, "MinimalScrollBar")
        ScrollUtil.InitScrollFrameWithScrollBar(scroll, bar)
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 0, -4)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", -1, 7)
    else
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local offset = self:GetVerticalScroll() - delta * 30
            self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), offset)))
        end)
    end

    -- Each time the page opens every row reads its setting again, as the game's list does, so
    -- changes made with slash commands show.
    canvas:SetScript("OnShow", function()
        for _, row in ipairs(rows) do
            row.initializer:Resetter(row.frame)
            row.initializer:InitFrame(row.frame)
        end
    end)
end

-- Rows -----------------------------------------------------------------------

local function BuildRows()
    Header("General")
    Checkbox(Register("enabled", "Enable Keyboard", true, nil, function(v)
        ns.db.enabled = v
        if not v and ns.HideKeyboard then ns.HideKeyboard() end
    end), "Turn the on-screen keyboard and the gamepad auction house on or off.")
    Checkbox(Register("autoShow", "Open Automatically", true),
        "Show the keyboard whenever a text field gains focus. When off, open it with /ebg show or the EBG toggle key binding.")
    Checkbox(Register("requirePad", "Only With a Gamepad", true),
        "Open automatically only while the gamepad is the active input, so typing on a physical keyboard is left alone.")
    Checkbox(Register("sounds", "Key Sounds", true), "Play a click when a key is pressed.")

    Header("Keyboard")
    Dropdown(Register("layout", "Layout", "auto",
        function() local id = ns.db.layout return id and ns.Layouts[id] and id or "auto" end,
        function(v) ns.db.layout = v ~= "auto" and v or nil Rebuild() end),
        "Key arrangement. Automatic follows the game's language.", LayoutList)
    Dropdown(Register("skin", "Style", "dialog",
        function() return ns.Skin.presets[ns.db.skin] and ns.db.skin or "dialog" end,
        function(v) ns.db.skin = v Rebuild(true) end),
        "Frame and key art for the keyboard and the gamepad auction house.", SkinList)
    Slider(Register("scale", "Scale", 1,
        function() return ns.db.scale or 1 end,
        function(v) ns.db.scale = v Rebuild() end),
        "Size of the keyboard and the gamepad auction house.", 0.5, 2, 0.05,
        function(v) return ("%d%%"):format(v * 100 + 0.5) end)
    Slider(Register("bgShade", "Background Shade", 0.7,
        function() return ns.db.bgShade or 0.7 end,
        function(v) ns.db.bgShade = v Rebuild() end),
        "How dark the panel background is: 0% shows the art at full strength, 100% is solid black.", 0, 1, 0.05,
        function(v) return ("%d%%"):format(v * 100 + 0.5) end)
    Checkbox(Register("stickNav", "Left Stick Moves Selection", false, nil, function(v)
        ns.db.stickNav = v Rebuild()
    end), "While typing, the left stick moves the key selection. When off, the left stick keeps moving your character.")
    Dropdown(Register("navPointer", "Navigation Pointer", "move",
        function() return ns.db.hideNavPointer == false and "off" or (ns.db.navPointer or "move") end,
        function(v)
            if ns.SetNavPointerHidden then ns.SetNavPointerHidden(false) end
            ns.db.hideNavPointer = v ~= "off"
            if v ~= "off" then ns.db.navPointer = v end
        end),
        "Where Blizzard's gamepad pointer goes while the keyboard is open.", PointerList)

    Header("Chat")
    Checkbox(Register("closeOnSend", "Close Chat After Sending", true),
        "Send also closes chat and the keyboard. When off, Send leaves chat open for another message and Back closes it.")
    Checkbox(Register("hideChatBox", "Hide Chat Input Box", true, nil, function(v)
        ns.db.hideChatBox = v
        if ns.ApplyChatBoxVisibility then ns.ApplyChatBoxVisibility() end
    end), "Fade Blizzard's chat input while the keyboard types into it. The keyboard's own preview shows the text.")
    Checkbox(Register("chatMirror", "Show Chat Above Keyboard", true, nil, function(v)
        ns.db.chatMirror = v
        if not v and ns.HideChatMirror then ns.HideChatMirror() end
    end), "Show a copy of the chat window above the keyboard while you type in chat.")
    Checkbox(Register("mirrorScroll", "Right Stick Scrolls Chat", true),
        "The right stick scrolls the chat copy above the keyboard. When off, it keeps turning the camera. Applies the next time the keyboard opens.")
    Checkbox(Register("fadeChatFrame", "Fade Chat Window Behind Copy", true),
        "Fade the real chat window while its copy is shown above the keyboard, so the text is not shown twice.")
    Checkbox(Register("lfgWhisper", "Quick Whisper in Group Finder", true),
        "Whisper a group's leader straight from the group browser with the gamepad.")

    Header("Gamepad Legend")
    Checkbox(Register("hideNativeLegend", "Hide Blizzard's Legend While Typing", true, nil, function(v)
        if not v and ns.SetNativeLegendHidden then ns.SetNativeLegendHidden(false) end
        ns.db.hideNativeLegend = v
    end), "Fade Blizzard's button legend while the keyboard is open. Its hints are for the game, not the keyboard.")
    Checkbox(Register("nativePrompts", "Blizzard Button Prompts", true, nil, function(v)
        ns.db.nativePrompts = v Rebuild()
    end), "Draw the keyboard's legend with Blizzard's own button prompts.")

    Header("Auction House")
    Checkbox(Register("auctionAuto", "Gamepad Auction House", true),
        "Open the gamepad auction browser when you talk to an auctioneer with a gamepad. /ebg ah opens it at any time.")
    Checkbox(Register("auctionHideNative", "Hide Blizzard's Auction Window", true),
        "Fade Blizzard's auction window while the gamepad browser is open.")
end

function Options.Register()
    if category then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory
        and Settings.RegisterAddOnSetting and Settings.CreateCheckboxInitializer and Settings.CreateSliderInitializer
        and Settings.CreateDropdownInitializer and CreateSettingsListSectionHeaderInitializer) then
        return
    end
    BuildPage()
    category = Settings.RegisterCanvasLayoutCategory(canvas, TITLE)
    local ok, err = pcall(BuildRows)
    if not ok then ns.Print("Options page incomplete: " .. tostring(err)) end
    LayoutRows()
    Settings.RegisterAddOnCategory(category)
end

function Options.Open()
    if not category or not Settings.OpenToCategory then
        ns.Print("The options page is not available on this client. /ebg help lists the commands.")
        return
    end
    if InCombatLockdown() then ns.Print("Open the options after combat.") return end
    Settings.OpenToCategory(category:GetID())
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    local ok, err = pcall(Options.Register)
    if not ok then ns.Print("Could not add the options page: " .. tostring(err)) end
end)
