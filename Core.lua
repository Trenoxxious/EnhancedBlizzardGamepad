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
    chatMirror = true,       -- show a copy of the chat window above the keyboard while typing in chat
    hideNavPointer = true,   -- fade SmartNavigation.Pointer.Icon while typing
    hideNativeLegend = true, -- fade Blizzard's gamepad legend while the keyboard is open
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

ns.padActive = false

local function HasDevice()
    if not C_GamePad or not C_GamePad.IsEnabled then return false end
    if not C_GamePad.IsEnabled() then return false end
    if C_GamePad.GetActiveDeviceID then
        local id = C_GamePad.GetActiveDeviceID()
        if id == nil or id == -1 then return false end
    end
    return true
end

function ns.IsGamepadActive()
    if not HasDevice() then return false end

    if ns.sawActiveEvent then return ns.padActive end
    return true
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

-- Returns "letters" (Xbox) or "shapes" (PlayStation) so glyphs match the native UI.
function ns.GlyphStyle()
    local style = ns.LabelStyle()
    if style and style:lower():find("shape") then return "shapes" end
    return "letters"
end

-- Events ---------------------------------------------------------------------

local f = CreateFrame("Frame")
ns.coreFrame = f

local function SafeRegister(frame, event)
    pcall(frame.RegisterEvent, frame, event)
end

f:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON then
            EnhancedBlizzardGamepadDB = EnhancedBlizzardGamepadDB or {}
            ApplyDefaults(EnhancedBlizzardGamepadDB)
            ns.db = EnhancedBlizzardGamepadDB
            ns.padActive = HasDevice()
            if ns.OnCoreReady then ns.OnCoreReady() end
        end
        if ns.OnAddonLoaded then ns.OnAddonLoaded(name) end
    elseif event == "PLAYER_LOGIN" then
        if ns.OnLogin then ns.OnLogin() end
    elseif event == "GAME_PAD_ACTIVE_CHANGED" then
        ns.sawActiveEvent = true
        ns.padActive = (...) and true or false
        if ns.OnPadStateChanged then ns.OnPadStateChanged() end
    elseif event == "GAME_PAD_CONNECTED" or event == "GAME_PAD_DISCONNECTED" then
        ns.padActive = HasDevice()
        if ns.OnPadStateChanged then ns.OnPadStateChanged() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if ns.OnCombatStart then ns.OnCombatStart() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.OnCombatEnd then ns.OnCombatEnd() end
    end
end)

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
SafeRegister(f, "GAME_PAD_ACTIVE_CHANGED")
SafeRegister(f, "GAME_PAD_CONNECTED")
SafeRegister(f, "GAME_PAD_DISCONNECTED")

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
    if cmd == "show" then
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
        -- /ebg pointer move | hide | off
        if rest == "move" or rest == "hide" or rest == "off" then
            ns.SetNavPointerHidden(false)
            db.hideNavPointer = rest ~= "off"
            if rest ~= "off" then db.navPointer = rest end
            ns.Print("Navigation pointer while typing: " .. rest)
        else
            ns.Print("Usage: /ebg pointer move (park left of the keyboard), hide, or off")
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
    elseif cmd == "bagsearch" then
        db.directBagSearch = db.directBagSearch == false
        ns.Print("Bag search through the item filter instead of the search box: " .. (db.directBagSearch and "on" or "off"))
    elseif cmd == "enter" then
        db.submitEnter = not db.submitEnter
        ns.Print("Send runs the field's Enter action outside chat: " .. (db.submitEnter and "on" or "off (Send just closes the keyboard)"))
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
    elseif cmd == "status" then
        local box = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        local style, devName = ns.LabelStyle()
        local id = C_GamePad and C_GamePad.GetActiveDeviceID and C_GamePad.GetActiveDeviceID()
        local lines = {
            "Addon version: " .. ns.VERSION,
            "Build: " .. table.concat({ GetBuildInfo() }, " / "),
            "",
            "C_GamePad.IsEnabled: " .. tostring(C_GamePad and C_GamePad.IsEnabled and C_GamePad.IsEnabled()),
            "Active device ID: " .. tostring(id),
            "Device name: " .. tostring(devName),
            "labelStyle: " .. tostring(style),
            "GlyphStyle: " .. ns.GlyphStyle(),
            "Saw GAME_PAD_ACTIVE_CHANGED: " .. tostring(ns.sawActiveEvent) .. "  padActive=" .. tostring(ns.padActive),
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
        ns.Print("Commands: show, hide, toggle, auto [on|off], pad [on|off], layout <id>, scale <0.5-2>, skin <id>, glow <atlas|off>, atlas [FrameName|ui], bg <atlas|default>, shade <0-1>, keyart <up> [down]|off|default, keypad <0-0.4>, keybleed <0-12>, keyglow <0-2>, entrybox <base>|off|default, glyphs, mixins, probe <FrameName>, check <atlas names>, legendart, lfg, bagsearch, enter, legend, chatbox, pointer, mirror, mirrorscroll, fadechat, prompts, sounds, status")
    end
end

SlashCmdList.EBG = function(msg)
    local ok, err = pcall(HandleSlash, msg)
    if not ok then ns.Print("Error: " .. tostring(err)) end
end

-- Exposed for Bindings.xml
function EnhancedBlizzardGamepad_Toggle()
    ns.ToggleKeyboard()
end
