local ADDON, ns = ...

local Glyphs = {}
ns.Glyphs = Glyphs

-- Logical button -> candidate atlas stems per family.
local STEMS = {
    PS = {
        PAD1 = { "ButtonCrox", "ButtonCross" },
        PAD2 = { "ButtonCircle" },
        PAD3 = { "ButtonSquare" },
        PAD4 = { "ButtonTriangle" },
        PADDUP = { "DpadUp" }, PADDDOWN = { "DpadDown" }, PADDLEFT = { "DpadLeft" }, PADDRIGHT = { "DpadRight" },
        PADLSHOULDER = { "TriggerL1" }, PADRSHOULDER = { "TriggerR1" },
        PADLTRIGGER = { "TriggerL2" }, PADRTRIGGER = { "TriggerR2" },
        PADLSTICK = { "StickL3" }, PADRSTICK = { "StickR3" },
        PADFORWARD = { "ButtonOptions", "Options", "ButtonStart", "Start", "ButtonMenu", "Menu" },
        PADBACK = { "ButtonShare", "Share", "ButtonCreate", "Create", "ButtonSelect", "Select", "Touchpad" },
        PADSOCIAL = { "Touchpad" },
        PADSYSTEM = { "ButtonPS", "PS", "Home" },
        RSTICKMOVE = { "StickR" },
    },
    XB = {
        PAD1 = { "ButtonA", "Button1" },
        PAD2 = { "ButtonB", "Button2" },
        PAD3 = { "ButtonX", "Button3" },
        PAD4 = { "ButtonY", "Button4" },
        PADDUP = { "DpadUp" }, PADDDOWN = { "DpadDown" }, PADDLEFT = { "DpadLeft" }, PADDRIGHT = { "DpadRight" },
        PADLSHOULDER = { "TriggerLB", "TriggerL1", "BumperL", "LB" }, PADRSHOULDER = { "TriggerRB", "TriggerR1", "BumperR", "RB" },
        PADLTRIGGER = { "TriggerLT", "TriggerL2", "LT" }, PADRTRIGGER = { "TriggerRT", "TriggerR2", "RT" },
        PADLSTICK = { "StickL3", "StickLS", "StickL" }, PADRSTICK = { "StickR3", "StickRS", "StickR" },
        PADFORWARD = { "ButtonMenu", "Menu", "ButtonStart", "Start" },
        PADBACK = { "ButtonView", "View", "ButtonBack", "Back", "ButtonSelect", "Select" },
        PADSOCIAL = { "ButtonShare", "Share", "ButtonView", "View" },
        PADSYSTEM = { "ButtonXbox", "Xbox", "Guide", "Home" },
        RSTICKMOVE = { "StickR", "StickRS" },
    },
}

local FAMILY_PREFIXES = {
    PS = { "Gamepad-PS-" },
    XB = { "Gamepad-XB-", "Gamepad-Xbox-", "Gamepad-XBX-", "Gamepad-XBOX-", "Gamepad-Gen-", "Gamepad-Generic-" },
}

local TEXT = {
    PS = { PAD1 = "Cross", PAD2 = "Circle", PAD3 = "Square", PAD4 = "Tri", PADLSHOULDER = "L1", PADRSHOULDER = "R1", PADLTRIGGER = "L2", PADRTRIGGER = "R2", PADFORWARD = "Options", PADBACK = "Share", PADLSTICK = "L3", PADRSTICK = "R3", PADSOCIAL = "Touchpad" },
    XB = { PAD1 = "A", PAD2 = "B", PAD3 = "X", PAD4 = "Y", PADLSHOULDER = "LB", PADRSHOULDER = "RB", PADLTRIGGER = "LT", PADRTRIGGER = "RT", PADFORWARD = "Menu", PADBACK = "View", PADLSTICK = "LS", PADRSTICK = "RS", PADSOCIAL = "Share" },
}
local TEXT_COMMON = { PADDUP = "Up", PADDDOWN = "Down", PADDLEFT = "Left", PADDRIGHT = "Right" }

local function AtlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- Reads the atlas family the native gamepad legend is currently drawing, e.g. "Gamepad-PS-".
local function PrefixFromNativeLegend()
    local legend = _G.GamepadPersistentInputLegend
    if not legend or legend:IsForbidden() then return nil end
    local function scan(f, depth)
        if depth > 5 or f:IsForbidden() then return nil end
        if f.GetRegions then
            for _, r in ipairs({ f:GetRegions() }) do
                if r.GetAtlas then
                    local a = r:GetAtlas()
                    local prefix = a and a:match("^(Gamepad%-%w+%-)")
                    if prefix then return prefix end
                end
            end
        end
        if f.GetChildren then
            for _, c in ipairs({ f:GetChildren() }) do
                local p = scan(c, depth + 1)
                if p then return p end
            end
        end
    end
    return scan(legend, 0)
end

local cache = { prefix = nil, family = nil, atlases = {} }

function Glyphs.Reset()
    cache.prefix, cache.family = nil, nil
    wipe(cache.atlases)
end

-- Returns family ("PS" | "XB") and the atlas prefix in use.
function Glyphs.Family()
    if cache.family then return cache.family, cache.prefix end
    local prefix = PrefixFromNativeLegend()
    local family
    if prefix then
        family = prefix:find("PS") and "PS" or "XB"
    else
        family = ns.GlyphStyle() == "shapes" and "PS" or "XB"
        for _, p in ipairs(FAMILY_PREFIXES[family]) do
            if AtlasExists(p .. "DpadUp-Normal") then prefix = p break end
        end
    end
    cache.family, cache.prefix = family, prefix
    return family, prefix
end

-- Atlas name for a logical pad button, or nil if none exists on this client.
function Glyphs.Atlas(button, state)
    state = state or "Normal"
    local key = button .. ":" .. state
    if cache.atlases[key] ~= nil then return cache.atlases[key] or nil end
    local family, prefix = Glyphs.Family()
    local found = false
    if prefix then
        for _, stem in ipairs(STEMS[family][button] or {}) do
            local name = prefix .. stem .. "-" .. state
            if AtlasExists(name) then found = name break end
        end
        if not found then
            for _, otherPrefix in ipairs(FAMILY_PREFIXES.PS) do
                for _, stem in ipairs(STEMS.PS[button] or {}) do
                    local name = otherPrefix .. stem .. "-" .. state
                    if AtlasExists(name) then found = name break end
                end
                if found then break end
            end
        end
    end
    cache.atlases[key] = found
    return found or nil
end

function Glyphs.Text(button)
    local family = Glyphs.Family()
    return TEXT[family][button] or TEXT_COMMON[button] or button
end

-- Applies a glyph to a texture; returns true if an atlas was used, false if the caller should show text.
function Glyphs.Apply(texture, button, state)
    local atlas = Glyphs.Atlas(button, state)
    if atlas then
        texture:SetAtlas(atlas, false)
        texture:Show()
        return true
    end
    texture:Hide()
    return false
end

function Glyphs.Report()
    local family, prefix = Glyphs.Family()
    local style, devName = ns.LabelStyle()
    local lines = {
        ("Device: %s   labelStyle: %s"):format(tostring(devName), tostring(style)),
        ("Glyph family: %s   atlas prefix: %s"):format(family, tostring(prefix)),
        "Native icon template: " .. tostring(Glyphs.NativeIconTemplate() or "not found, using atlases"),
        "Native prompt template: " .. tostring(Glyphs.NativePromptTemplate() or "not found, using own entries"),
        "",
        "Button -> atlas (or text fallback)",
    }
    local order = { "PAD1", "PAD2", "PAD3", "PAD4", "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT", "PADLSHOULDER", "PADRSHOULDER", "PADLTRIGGER", "PADRTRIGGER", "PADLSTICK", "PADRSTICK", "PADFORWARD", "PADBACK", "PADSOCIAL", "PADSYSTEM" }
    for _, b in ipairs(order) do
        lines[#lines + 1] = ("  %-14s %s"):format(b, Glyphs.Atlas(b) or ("text '" .. Glyphs.Text(b) .. "'"))
    end
    ns.ShowReport("glyphs", lines)
end


-- Native icon frames -------------------------------------------------------------------
local ICON_TEMPLATE_GUESSES = {
    "InputIconTextureFrameTemplate", -- confirmed on 16001 (InputIconTextureMixin)
    "GamepadInputIconTemplate", "GamepadInputIconFrameTemplate", "GamePadInputIconTemplate",
    "GamepadLegendInputIconTemplate", "GamepadInputLegendIconTemplate", "InputIconTemplate",
    "GamepadPersistentInputLegendIconTemplate", "GamepadButtonIconTemplate",
}
local PROMPT_TEMPLATE_GUESSES = {
    "GamepadPersistentInputLegendEntryTemplate", -- confirmed on 16001 (InputPromptMixin)
    "GamepadInputPromptTemplate", "GamepadPersistentInputLegendEntryTemplate", "GamepadInputLegendEntryTemplate",
    "GamepadInputLegendPromptTemplate", "GamepadPromptTemplate", "GamepadLegendPromptTemplate",
}

local scanned, iconMixins, promptMixins = false, {}, {}
local function ScanMixins()
    if scanned then return end
    scanned = true
    pcall(function()
        for k, v in pairs(_G) do
            if type(k) == "string" and type(v) == "table" and rawget(v, "GetObjectType") == nil then
                if type(rawget(v, "SetInputKey")) == "function" and type(rawget(v, "RefreshIconTextures")) == "function" then
                    iconMixins[#iconMixins + 1] = k
                end
                if type(rawget(v, "SetPromptInputIconKey")) == "function" then
                    promptMixins[#promptMixins + 1] = k
                end
            end
        end
    end)
    table.sort(iconMixins); table.sort(promptMixins)
end

local function TemplateCandidates(mixins, guesses)
    local out, seen = {}, {}
    local function add(n) if n and not seen[n] then seen[n] = true out[#out + 1] = n end end
    for _, m in ipairs(mixins) do
        local base = m:gsub("Mixin$", "")
        add(base .. "Template"); add(base .. "FrameTemplate"); add(base .. "ButtonTemplate")
    end
    for _, g in ipairs(guesses) do add(g) end
    return out
end

local iconTemplate -- nil = untested, false = none found
function Glyphs.NativeIconTemplate()
    if iconTemplate ~= nil then return iconTemplate or nil end
    ScanMixins()
    iconTemplate = false
    for _, name in ipairs(TemplateCandidates(iconMixins, ICON_TEMPLATE_GUESSES)) do
        local ok, f = pcall(CreateFrame, "Frame", nil, UIParent, name)
        if ok and f then
            if type(f.SetInputKey) == "function" then
                local works = pcall(f.SetInputKey, f, "PAD1")
                f:Hide()
                if works then iconTemplate = name break end
            else
                f:Hide()
            end
        end
    end
    return iconTemplate or nil
end

-- Creates a Blizzard icon frame bound to `button`, or nil when the template is unavailable.
function Glyphs.CreateNativeIcon(parent)
    local tpl = Glyphs.NativeIconTemplate()
    if not tpl then return nil end
    local ok, f = pcall(CreateFrame, "Frame", nil, parent, tpl)
    if not ok or not f then return nil end
    return f
end

-- Binds a native icon frame to a button; returns true on success.
function Glyphs.BindNativeIcon(f, button)
    if not f or type(f.SetInputKey) ~= "function" then return false end
    local ok = pcall(f.SetInputKey, f, button)
    if ok and type(f.RefreshIconTextures) == "function" then pcall(f.RefreshIconTextures, f) end
    if ok and type(f.SetEnabled) == "function" then pcall(f.SetEnabled, f, true) end
    return ok
end

function Glyphs.MixinReport()
    ScanMixins()
    local lines = {}
    lines[#lines + 1] = "== Icon mixins (own SetInputKey + RefreshIconTextures) =="
    if #iconMixins == 0 then lines[#lines + 1] = "  none found" end
    for _, m in ipairs(iconMixins) do lines[#lines + 1] = "  " .. m end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "== Prompt mixins (own SetPromptInputIconKey) =="
    if #promptMixins == 0 then lines[#lines + 1] = "  none found" end
    for _, m in ipairs(promptMixins) do lines[#lines + 1] = "  " .. m end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "== Icon template candidates =="
    for _, name in ipairs(TemplateCandidates(iconMixins, ICON_TEMPLATE_GUESSES)) do
        local ok, f = pcall(CreateFrame, "Frame", nil, UIParent, name)
        local result
        if ok and f then
            result = type(f.SetInputKey) == "function" and "exists, has SetInputKey" or "exists, no SetInputKey"
            f:Hide()
        else
            result = "no such template"
        end
        lines[#lines + 1] = ("  %-50s %s"):format(name, result)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Resolved icon template: " .. tostring(Glyphs.NativeIconTemplate() or "none")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "== Prompt template candidates =="
    for _, name in ipairs(TemplateCandidates(promptMixins, PROMPT_TEMPLATE_GUESSES)) do
        local ok, f = pcall(CreateFrame, "Frame", nil, UIParent, name)
        local result
        if ok and f then
            result = type(f.SetPromptInputIconKey) == "function" and "exists, has SetPromptInputIconKey" or "exists"
            f:Hide()
        else
            result = "no such template"
        end
        lines[#lines + 1] = ("  %-50s %s"):format(name, result)
    end
    ns.ShowReport("mixins", lines)
end


-- Native prompt entries (icon + text) --
local promptTemplate
function Glyphs.NativePromptTemplate()
    if promptTemplate ~= nil then return promptTemplate or nil end
    ScanMixins()
    promptTemplate = false
    for _, name in ipairs(TemplateCandidates(promptMixins, PROMPT_TEMPLATE_GUESSES)) do
        local ok, f = pcall(CreateFrame, "Frame", nil, UIParent, name)
        if ok and f then
            local good = type(f.SetPromptInputIconKey) == "function" and type(f.SetPromptText) == "function"
            f:Hide()
            if good then promptTemplate = name break end
        end
    end
    return promptTemplate or nil
end

function Glyphs.CreateNativePrompt(parent)
    local tpl = Glyphs.NativePromptTemplate()
    if not tpl then return nil end
    local ok, f = pcall(CreateFrame, "Frame", nil, parent, tpl)
    if ok and f then return f end
    return nil
end

-- true/false when the icon control's state can be read, nil when it cannot.
local function IconBoundTo(f, button)
    if type(f.GetInputIconControl) ~= "function" then return nil end
    local ok, c = pcall(f.GetInputIconControl, f, 1)
    if not ok or type(c) ~= "table" then return nil end
    if c.mappedButtonKey ~= nil then return c.mappedButtonKey == button end
    local tex = c.NormalTexture
    local drawn = tex and tex.GetAtlas and tex:GetAtlas()
    local expected = Glyphs.Atlas(button, "Normal")
    if drawn and expected then return drawn == expected end
    return nil
end

-- After binding, confirm the drawn atlas matches what this button should show.
local function DrewExpected(f, button)
    local ok, c = pcall(f.GetInputIconControl, f, 1)
    if not ok or type(c) ~= "table" then return true end
    local tex = c.NormalTexture
    local drawn = tex and tex.GetAtlas and tex:GetAtlas()
    local expected = Glyphs.Atlas(button, "Normal")
    if drawn and expected then return drawn == expected end
    return true
end

function Glyphs.BindNativePrompt(f, button, label, fontName)
    if not f then return false end
    local ok = pcall(f.SetPromptInputIconKey, f, button)
    local bound = IconBoundTo(f, button)
    if bound == false then
        ok = pcall(f.SetPromptInputIconKey, f, 1, button)
        bound = IconBoundTo(f, button)
        if bound == false then
            ok = pcall(f.SetPromptInputIconKey, f, button, 1)
            bound = IconBoundTo(f, button)
        end
    end
    if not ok or bound == false then return false end
    if type(f.RefreshInputPromptSize) == "function" then pcall(f.RefreshInputPromptSize, f) end
    if not DrewExpected(f, button) then return false end
    pcall(f.SetPromptText, f, label)
    if fontName and type(f.SetPromptFont) == "function" then
        if not pcall(f.SetPromptFont, f, fontName) then pcall(f.SetPromptFont, f, _G[fontName]) end
    end
    if type(f.SetInputIconSize) == "function" then
        if not pcall(f.SetInputIconSize, f, 18, 17) then pcall(f.SetInputIconSize, f, 18) end
    end
    if type(f.EnablePrompt) == "function" then pcall(f.EnablePrompt, f) end
    if type(f.RefreshInputPromptSize) == "function" then pcall(f.RefreshInputPromptSize, f) end
    return true
end
