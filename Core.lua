local ADDON, ns = ...
_G.EnhancedBlizzardGamepad = ns

ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
    or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version")) or "dev"

local DEFAULTS = {
    enabled = true,
    autoShow = true,     -- pop up whenever an edit box gains focus while a gamepad is active
    requirePad = true,   -- only auto show when a gamepad is the active input
    layout = nil,        -- nil = pick from GetLocale()
    scale = 1.0,
    sounds = true,
    skin = "dialog",
    glowAtlas = nil,     -- optional atlas name for the selection glow
    stickNav = false,
    bgAtlas = nil,           -- background atlas override (nil = preset)
    bgShade = 0.7,           -- 0 = art at full strength, 1 = solid black
    hideChatBox = true,      -- fade the real chat edit box while the keyboard targets it
    closeOnSend = true,      -- Send in chat also closes chat (/ebg closeonsend)
    chatMirror = true,      -- show a copy of the chat window above the keyboard while typing in chat
    hideNavPointer = true,   -- park the native pointer beside the keyboard preview (or hide it)
    hideNativeLegend = true, -- fade the native legend while EBG shows contextual prompts
    nativePrompts = true,    -- build the legend from Blizzard's prompt entry template
}

local SCHEMA = 3

local function ApplyDefaults(db)
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    -- Settings saved by early builds carried defaults that no longer apply.
    if (db.schema or 0) < 2 then
        if db.skin == "tooltip" then db.skin = "dialog" end
        db.bgShade = DEFAULTS.bgShade
        db.schema = 2
    end
    if db.schema < 3 then
        db.keyArt, db.keyArtSelected = nil, nil
        db.schema = SCHEMA
    end
end

-- Gamepad state --------------------------------------------------------------

-- The client reports its input style directly: 1 while the gamepad interface is enabled, 0 otherwise.
function ns.IsGamepadActive()
    local api = C_InputInterfaceStyle
    if not api or not api.GetCurrentStyle then return false end
    local ok, style = pcall(api.GetCurrentStyle)
    return ok and style == 1
end

-- Blizzard identifies the controller family through labelStyle on the mapped device state
-- ("Letters" for Xbox style, "Shapes" for PlayStation, plus "Generic"/"Reverse")
function ns.LabelStyle()
    if not C_GamePad or not C_GamePad.GetActiveDeviceID then return nil end
    local id = C_GamePad.GetActiveDeviceID()
    if id == nil or id == -1 then return nil end
    local function try(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, t = pcall(fn, ...)
        if ok and type(t) == "table" and t.labelStyle then return tostring(t.labelStyle), t.name end
    end
    local style, name = try(C_GamePad.GetDeviceMappedState, id)
    if not style then style, name = try(C_GamePad.GetDeviceMapping, id) end
    if not style and C_GamePad.GetConfig and C_GamePad.GetAllConfigIDs then
        -- Fall back to the active config's declared style
        local ok, ids = pcall(C_GamePad.GetAllConfigIDs)
        if ok and type(ids) == "table" then
            for _, cid in ipairs(ids) do
                style = try(C_GamePad.GetConfig, cid)
                if style then break end
            end
        end
    end
    return style, name
end

-- The family the controller itself reports: "shapes" (PlayStation), "letters" (Xbox, and the
-- Nintendo-style "Reverse" layout), or nil when no controller is identified (no active device, or
-- a "Generic" label style).
function ns.DetectedGlyphStyle()
    local style = ns.LabelStyle()
    style = style and style:lower() or ""
    if style:find("shape") then return "shapes" end
    if style:find("letter") or style:find("reverse") then return "letters" end
    return nil
end
-- Returns "letters" (Xbox) or "shapes" (PlayStation) so glyphs match the controller. With no
-- controller identified, a PC defaults to PlayStation glyphs (a Mac keeps Xbox, as before).
-- The Button glyphs setting (ns.db.glyphStyle) overrides both.
function ns.GlyphStyle()
    local chosen = ns.db and ns.db.glyphStyle
    if chosen == "shapes" or chosen == "letters" then return chosen end
    local detected = ns.DetectedGlyphStyle()
    if detected then return detected end
    if IsMacClient and IsMacClient() then return "letters" end
    return "shapes"
end

-- The Button glyphs setting changed: drop the cached glyph family and redraw every glyph shown.
function ns.OnGlyphStyleChanged()
    if ns.Glyphs and ns.Glyphs.Reset then ns.Glyphs.Reset() end
    if ns.RebuildKeyboard then pcall(ns.RebuildKeyboard) end
    if ns.OnPadStateChanged then pcall(ns.OnPadStateChanged) end
    if ns.Auction and ns.Auction.RefreshGlyphs then pcall(ns.Auction.RefreshGlyphs) end
end

-- Events ---------------------------------------------------------------------

local f = CreateFrame("Frame")
ns.coreFrame = f

local function SafeRegister(frame, event)
    pcall(frame.RegisterEvent, frame, event)
end

-- Each module hook runs on its own: an error in one is reported once and cannot stop the rest of
-- the event (above all, the saved settings being attached at ADDON_LOADED).
local reported = {}
local function Run(label, fn, ...)
    if not fn then return end
    local ok, err = pcall(fn, ...)
    if not ok and not reported[label] then
        reported[label] = true
        print("|cff66ccffEBG|r: " .. label .. " failed: " .. tostring(err))
    end
end

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON then
            if type(EnhancedBlizzardGamepadDB) ~= "table" then EnhancedBlizzardGamepadDB = {} end
            Run("Settings", ApplyDefaults, EnhancedBlizzardGamepadDB)
            ns.db = EnhancedBlizzardGamepadDB
            Run("Keyboard setup", ns.OnCoreReady)
        end
        Run("Field scan", ns.OnAddonLoaded, name)
    elseif event == "PLAYER_LOGIN" then
        Run("Focus tracking", ns.OnLogin)
    elseif event == "GAME_PAD_ACTIVE_CHANGED" or event == "GAME_PAD_CONNECTED" or event == "GAME_PAD_DISCONNECTED" then
        Run("Gamepad change", ns.OnPadStateChanged)
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        Run("Blocked-action log", ns.RecordBlockedAction, event, ...)
    elseif event == "PLAYER_REGEN_DISABLED" then
        Run("Combat start", ns.OnCombatStart)
    elseif event == "PLAYER_REGEN_ENABLED" then
        Run("Combat end", ns.OnCombatEnd)
    end
end)

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
SafeRegister(f, "GAME_PAD_ACTIVE_CHANGED")
SafeRegister(f, "GAME_PAD_CONNECTED")
SafeRegister(f, "GAME_PAD_DISCONNECTED")
SafeRegister(f, "ADDON_ACTION_BLOCKED")
SafeRegister(f, "ADDON_ACTION_FORBIDDEN")

-- Blocked action log ----------------------------------------------------------
-- When Blizzard blocks an action it names the addon and the protected function. That is saved
-- with the last text field this addon wrote into, so the write that caused the taint can be
-- found afterwards. Kept in saved variables (db.blocked) and shown by /ebg blocked.

local function FrameChain(box)
    if type(box) ~= "table" then return "none" end
    if box.isComposer then return "EBGComposer" end
    local parts, f = {}, box
    for _ = 1, 8 do
        if not f or (f.IsForbidden and f:IsForbidden()) then break end
        parts[#parts + 1] = (f.GetName and f:GetName()) or (f.GetDebugName and f:GetDebugName()) or "?"
        f = f.GetParent and f:GetParent()
    end
    return table.concat(parts, " < ")
end

local lastWrite

-- Called for every write into a real text field.
function ns.NoteWrite(box, op)
    local ok, chain = pcall(FrameChain, box)
    lastWrite = { chain = ok and chain or "unreadable", op = op, t = GetTime() }
    if ns.NoteAction then ns.NoteAction(op) end
end

-- The last few EBG calls into Blizzard code or protected-adjacent APIs, newest last. A blocked
-- action names UNKNOWN() when the client cannot attribute it, so the trail is what identifies it.
local trail = {}
function ns.NoteAction(op)
    trail[#trail + 1] = { op = op, t = GetTime() }
    if #trail > 8 then table.remove(trail, 1) end
end
-- Modules add a one-line snapshot of their state to every record.
ns.blockedContext = {}
local function Trail()
    local parts, now = {}, GetTime()
    for i = #trail, 1, -1 do parts[#parts + 1] = ("%s (%.1fs)"):format(trail[i].op, now - trail[i].t) end
    return #parts > 0 and table.concat(parts, " < ") or "none"
end
function ns.RecordBlockedAction(event, addon, func)
    local db = ns.db
    if not db then return end
    db.blocked = db.blocked or {}
    local okT, target = pcall(FrameChain, ns.KB and ns.KB.target)
    local okF, focus = pcall(FrameChain, GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus())
    local entry = {
        when = date("%Y-%m-%d %H:%M:%S"),
        event = event,
        addon = tostring(addon),
        func = tostring(func),
        keyboardShown = ns.KB and ns.KB.frame:IsShown() or false,
        target = okT and target or "unreadable",
        focus = okF and focus or "unreadable",
        lastWrite = lastWrite and ("%s into %s, %.1fs earlier"):format(lastWrite.op, lastWrite.chain, GetTime() - lastWrite.t) or "none this session",
        trail = Trail(),
        combat = InCombatLockdown() and true or false,
    }
    local context = {}
    for name, fn in pairs(ns.blockedContext) do
        local ok, text = pcall(fn)
        context[#context + 1] = name .. ": " .. (ok and tostring(text) or "unreadable")
    end
    entry.context = table.concat(context, "  |  ")
    table.insert(db.blocked, entry)
    while #db.blocked > 30 do table.remove(db.blocked, 1) end
    if tostring(addon) == ADDON then
        ns.Print(("Blocked action recorded: %s (%s). Last write: %s"):format(entry.func, event, entry.lastWrite))
        ns.Print("Recent EBG calls: " .. entry.trail)
        if entry.context ~= "" then ns.Print(entry.context) end
        ns.Print("Full record: /ebg blocked")
    end
end

-- Utilities ------------------------------------------------------------------
function ns.Print(msg)
    print("|cff66ccffEBG|r: " .. tostring(msg))
end

function ns.Debug(...)
    if ns.debug then print("|cff66ccffEBG dbg|r:", ...) end
end

function ns.PlayClick()
    if ns.db and ns.db.sounds and PlaySound and SOUNDKIT then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

local band = bit.band
local strbyte, strchar, strsub = string.byte, string.char, string.sub

function ns.UTF8Char(cp)
    if cp < 0x80 then return strchar(cp)
    elseif cp < 0x800 then return strchar(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    elseif cp < 0x10000 then return strchar(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    else return strchar(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40, 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40) end
end

function ns.UTF8CharStart(s, pos)
    local i = pos
    while i > 1 do
        local b = strbyte(s, i)
        if not b or band(b, 0xC0) ~= 0x80 then break end
        i = i - 1
    end
    return i
end

function ns.UTF8CharEnd(s, pos)
    local b = strbyte(s, pos)
    if not b then return pos end
    local len = 1
    if b >= 0xF0 then len = 4 elseif b >= 0xE0 then len = 3 elseif b >= 0xC0 then len = 2 end
    return pos + len
end

-- Slash commands -------------------------------------------------------------
SLASH_EBG1 = "/ebg"
SLASH_EBG2 = "/ebgamepad"
local function HandleSlash(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local db = ns.db
    if cmd == "" or cmd == "options" or cmd == "config" then
        if ns.Options then ns.Options.Open() end
        if cmd == "" then ns.Print("/ebg help lists the commands.") end
    elseif cmd == "show" then
        ns.ShowKeyboard(true)
    elseif cmd == "hide" then
        ns.HideKeyboard()
    elseif cmd == "toggle" then
        ns.ToggleKeyboard()
    elseif cmd == "auto" then
        if rest == "on" then db.autoShow = true elseif rest == "off" then db.autoShow = false else db.autoShow = not db.autoShow end
        ns.Print("Auto show " .. (db.autoShow and "on" or "off"))
    elseif cmd == "pad" then
        if rest == "on" then db.requirePad = true elseif rest == "off" then db.requirePad = false else db.requirePad = not db.requirePad end
        ns.Print("Require gamepad " .. (db.requirePad and "on" or "off"))
    elseif cmd == "layout" then
        if rest == "" or not ns.Layouts[rest] then
            local names = {}
            for id, l in pairs(ns.Layouts) do names[#names + 1] = id .. " (" .. l.name .. ")" end
            table.sort(names)
            ns.Print("Layouts: " .. table.concat(names, ", ") .. ". Current: " .. ns.CurrentLayoutID())
        else
            db.layout = rest
            ns.Print("Layout set to " .. rest)
            if ns.RebuildKeyboard then ns.RebuildKeyboard() end
        end
    elseif cmd == "scale" then
        local n = tonumber(rest)
        if n and n >= 0.5 and n <= 2 then
            db.scale = n
            if ns.RebuildKeyboard then ns.RebuildKeyboard() end
            ns.Print("Scale " .. n)
        else
            ns.Print("Scale must be between 0.5 and 2")
        end
    elseif cmd == "prompts" then
        db.nativePrompts = not db.nativePrompts
        if ns.RebuildKeyboard then ns.RebuildKeyboard() end
        ns.Print("Native prompt entries " .. (db.nativePrompts and "on" or "off"))
    elseif cmd == "keyart" then
        -- /ebg keyart <upAtlas> [downAtlas] | off | default
        local a, b = rest:match("^(%S*)%s*(%S*)$")
        if a == "" or a == "default" then
            db.keyArt, db.keyArtSelected = nil, nil
        else
            db.keyArt = a
            db.keyArtSelected = (b ~= "" and b) or nil
        end
        if ns.RebuildKeyboard then ns.RebuildKeyboard() end
        ns.Print("Key art: " .. tostring(db.keyArt or "skin default"))
    elseif cmd == "keypad" then
        local n = tonumber(rest)
        if n and n >= 0 and n <= 0.4 then
            db.keyArtPad = n
            if ns.RebuildKeyboard then ns.RebuildKeyboard() end
            ns.Print("Key art margin crop " .. n)
        else
            ns.Print("keypad takes 0 to 0.4 (fraction of the atlas trimmed from each edge, default 0.15)")
        end
    elseif cmd == "keyglow" then
        local n = tonumber(rest)
        if n and n >= 0 and n <= 2 then
            db.keyGlow = n
            if ns.RebuildKeyboard then ns.RebuildKeyboard() end
            ns.Print("Selected key brightness " .. n)
        else
            ns.Print("keyglow takes 0 to 2 (default 1)")
        end
    elseif cmd == "keybleed" then
        local n = tonumber(rest)
        if n and n >= 0 and n <= 12 then
            db.keyArtBleed = n
            if ns.RebuildKeyboard then ns.RebuildKeyboard() end
            ns.Print("Key shadow bleed " .. n .. "px")
        else
            ns.Print("keybleed takes 0 to 12 pixels (default 5)")
        end
    elseif cmd == "entrybox" then
        if rest == "" or rest == "default" then db.entryBox = nil else db.entryBox = rest end
        if ns.RebuildKeyboard then ns.RebuildKeyboard() end
        ns.Print("Entry box art: " .. tostring(db.entryBox or "skin default"))
    elseif cmd == "pointer" then
        if rest == "move" or rest == "hide" or rest == "off" then
            ns.SetNavPointerHidden(false)
            db.hideNavPointer = rest ~= "off"
            if rest ~= "off" then db.navPointer = rest end
            ns.Print("Navigation pointer while typing: " .. rest)
        else
            ns.Print("Usage: /ebg pointer move, hide, or off")
        end
    elseif cmd == "mirrorscroll" then
        db.mirrorScroll = db.mirrorScroll == false
        ns.Print("Right stick scrolls the chat copy: " .. (db.mirrorScroll and "on" or "off (right stick stays on the camera)") .. ". Reopen the keyboard to apply.")
    elseif cmd == "fadechat" then
        db.fadeChatFrame = db.fadeChatFrame == false
        ns.Print("Fade the real chat window while the copy is shown: " .. (db.fadeChatFrame and "on" or "off"))
    elseif cmd == "mirror" then
        db.chatMirror = not db.chatMirror
        if not db.chatMirror then ns.HideChatMirror() end
        ns.Print("Chat window copy above the keyboard: " .. (db.chatMirror and "on" or "off"))
    elseif cmd == "legendart" then
        db.legendArt = db.legendArt == false
        ns.Print("Copy Blizzard's input legend background: " .. (db.legendArt and "on" or "off") .. ". /reload to apply.")
    elseif cmd == "lfg" then
        db.lfgWhisper = db.lfgWhisper == false
        ns.Print("R2 + Cross whisper in the group browser: " .. (db.lfgWhisper and "on" or "off"))
    elseif cmd == "ah" then
        if rest == "auto" then
            db.auctionAuto = db.auctionAuto == false
            ns.Print("Open the gamepad auction browser at auctioneers: " .. (db.auctionAuto and "on" or "off"))
        elseif rest == "native" then
            db.auctionHideNative = db.auctionHideNative == false
            ns.Print("Fade Blizzard's auction window while the gamepad browser is open: " .. (db.auctionHideNative and "on" or "off"))
        elseif ns.Auction then ns.Auction.Open() end
    elseif cmd == "bagsearch" then
        db.directBagSearch = true
        ns.Print("Bag/bank search always uses the item filter API. Native search fields are never written to.")
    elseif cmd == "enter" then
        db.submitEnter = nil
        ns.Print("Native Enter-handler execution was removed to prevent taint. Done closes the keyboard; auction search uses /ebg ah.")
    elseif cmd == "closeonsend" then
        -- Stored as true/false: nil would be reset to the default on the next load.
        if rest == "on" then db.closeOnSend = true
        elseif rest == "off" then db.closeOnSend = false
        else db.closeOnSend = not db.closeOnSend end
        ns.Print("Close chat after Send: " .. (db.closeOnSend and "on" or "off (Send leaves chat open; B closes it)"))
    elseif cmd == "chatbox" then
        db.hideChatBox = db.hideChatBox == false
        if ns.ApplyChatBoxVisibility then ns.ApplyChatBoxVisibility() end
        ns.Print("Hide the chat edit box: " .. (db.hideChatBox and "on" or "off"))
    elseif cmd == "legend" then
        db.hideNativeLegend = not db.hideNativeLegend
        ns.Print("Hide native legend while typing: " .. (db.hideNativeLegend and "on" or "off"))
    elseif cmd == "sounds" then
        db.sounds = not db.sounds
        ns.Print("Sounds " .. (db.sounds and "on" or "off"))
    elseif cmd == "atlas" then
        ns.InspectCommand(rest)
    elseif cmd == "debug" then
        ns.debug = not ns.debug
        ns.Print("Debug " .. (ns.debug and "on" or "off"))
    elseif cmd == "glyphs" then
        ns.Glyphs.Reset()
        ns.Glyphs.Report()
    elseif cmd == "mixins" then
        ns.Glyphs.MixinReport()
    elseif cmd == "probe" then
        ns.ProbeCommand(rest)
    elseif cmd == "check" then
        ns.AtlasCheck(rest)
    elseif cmd == "skin" then
        if ns.Skin.presets[rest] then
            db.skin = rest
            if ns.RebuildKeyboard then ns.RebuildKeyboard(true) end
            ns.Print("Skin " .. rest)
        else
            local names = {}
            for id in pairs(ns.Skin.presets) do names[#names + 1] = id end
            table.sort(names)
            ns.Print("Skins: " .. table.concat(names, ", ") .. ". Current: " .. tostring(db.skin))
        end
    elseif cmd == "bg" then
        if rest == "" or rest == "default" then db.bgAtlas = nil else db.bgAtlas = rest end
        if ns.RebuildKeyboard then ns.RebuildKeyboard() end
        ns.Print("Background atlas: " .. tostring(db.bgAtlas or "preset default"))
    elseif cmd == "shade" then
        local n = tonumber(rest)
        if n and n >= 0 and n <= 1 then
            db.bgShade = n
            if ns.RebuildKeyboard then ns.RebuildKeyboard() end
            ns.Print("Background shade " .. n)
        else
            ns.Print("Shade must be between 0 (art at full strength) and 1 (solid black)")
        end
    elseif cmd == "sticks" then
        db.stickNav = not db.stickNav
        ns.Print("Stick navigation " .. (db.stickNav and "on (sticks captured while typing)" or "off (sticks move you)"))
        if ns.RebuildKeyboard then ns.RebuildKeyboard() end
    elseif cmd == "glow" then
        if rest == "" or rest == "default" or rest == "off" then
            db.glowAtlas = nil
        else
            db.glowAtlas = rest
        end
        if ns.RebuildKeyboard then ns.RebuildKeyboard(true) end
        ns.Print("Selection glow atlas: " .. tostring(db.glowAtlas))
    elseif cmd == "blocked" then
        if rest == "clear" then
            db.blocked = nil
            ns.Print("Blocked action log cleared.")
            return
        end
        local lines = {}
        for i, e in ipairs(db.blocked or {}) do
            lines[#lines + 1] = ("%d. %s  %s"):format(i, e.when, e.event)
            lines[#lines + 1] = "   addon: " .. e.addon .. "   function: " .. e.func
            lines[#lines + 1] = "   keyboard shown: " .. tostring(e.keyboardShown) .. "   target: " .. e.target
            lines[#lines + 1] = "   focus: " .. e.focus
            lines[#lines + 1] = "   last write: " .. e.lastWrite
            if e.trail then lines[#lines + 1] = "   recent EBG calls (newest first): " .. e.trail end
            if e.context and e.context ~= "" then lines[#lines + 1] = "   state: " .. e.context end
            if e.combat ~= nil then lines[#lines + 1] = "   in combat: " .. tostring(e.combat) end
        end
        if #lines == 0 then lines[1] = "No blocked actions recorded." end
        ns.ShowReport("blocked", lines)
    elseif cmd == "status" then
        local box = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        local style, devName = ns.LabelStyle()
        local id = C_GamePad and C_GamePad.GetActiveDeviceID and C_GamePad.GetActiveDeviceID()
        local lines = {
            "Addon version: " .. ns.VERSION,
            "Build: " .. table.concat({ GetBuildInfo() }, " / "),
            "",
            "C_InputInterfaceStyle.GetCurrentStyle: " .. tostring(C_InputInterfaceStyle and C_InputInterfaceStyle.GetCurrentStyle and C_InputInterfaceStyle.GetCurrentStyle()),
            "Active device ID: " .. tostring(id),
            "Device name: " .. tostring(devName),
            "labelStyle: " .. tostring(style),
            "GlyphStyle: " .. ns.GlyphStyle() .. ((ns.db and ns.db.glyphStyle) and " (chosen in settings)" or
                (ns.DetectedGlyphStyle() and " (reported by the controller)" or " (no controller identified: default)")),
            "IsGamepadActive(): " .. tostring(ns.IsGamepadActive()),
            "",
            "Focused edit box: " .. (box and (box:IsForbidden() and "forbidden" or (box:GetName() or "unnamed")) or "none"),
            "Tracked target: " .. tostring(ns.GetTarget() and (ns.GetTarget():GetName() or "unnamed") or "none"),
            "Keyboard shown: " .. tostring(ns.KB and ns.KB.frame:IsShown()),
            "Combat locked: " .. tostring(ns.KB and ns.KB.combatLocked),
            "",
            "Layout: " .. ns.CurrentLayoutID() .. "   Skin: " .. tostring(db.skin) .. "   Scale: " .. tostring(db.scale),
            "autoShow=" .. tostring(db.autoShow) .. "  requirePad=" .. tostring(db.requirePad) .. "  glowAtlas=" .. tostring(db.glowAtlas),
            "Native icon template: " .. tostring(ns.Glyphs.NativeIconTemplate() or "none"),
            "NineSliceUtil: " .. tostring(NineSliceUtil ~= nil) .. "   GetMouseFoci: " .. tostring(GetMouseFoci ~= nil),
            "",
        }
        for _, l in ipairs(ns.Skin.Diagnostics()) do lines[#lines + 1] = l end
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Nav pointer: " .. ns.PointerDiagnostics()
        ns.ShowReport("status", lines)
    else
        ns.Print("Commands: options, show, hide, toggle, ah [auto], auto [on|off], pad [on|off], layout <id>, scale <0.5-2>, skin <id>, glow <atlas|off>, atlas [FrameName|ui], bg <atlas|default>, shade <0-1>, keyart <up> [down]|off|default, keypad <0-0.4>, keybleed <0-12>, keyglow <0-2>, entrybox <base>|off|default, glyphs, mixins, probe <FrameName>, check <atlas names>, legendart, lfg, bagsearch, enter, legend, chatbox, closeonsend [on|off], pointer, mirror, mirrorscroll, fadechat, prompts, sounds, blocked [clear], status")
    end
end

SlashCmdList.EBG = function(msg)
    local ok, err = pcall(HandleSlash, msg)
    if not ok then ns.Print("Error: " .. tostring(err)) end
end

-- Exposed for Bindings.xml, which the game loads by itself (it must not be listed in the TOC:
-- loaded as an interface file it only produces "Unrecognized XML" warnings).
BINDING_HEADER_ENHANCEDBLIZZARDGAMEPAD = "Enhanced Blizzard Gamepad"
BINDING_NAME_EBG_TOGGLE = "Toggle Keyboard"
function EnhancedBlizzardGamepad_Toggle()
    ns.ToggleKeyboard()
end
