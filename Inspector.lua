local ADDON, ns = ...

-- /ebg atlas [FrameName]  dumps every texture, atlas, font and nine-slice layout under a frame
-- into a copyable window, so the live client's art names can be reused for the keyboard skin.

local MAX_DEPTH = 6
local MAX_LINES = 1500

local function Name(obj)
    if not obj or obj:IsForbidden() then return "<forbidden>" end
    local ok, n = pcall(obj.GetName, obj)
    if ok and n then return n end
    local dn = obj.GetDebugName and obj:GetDebugName()
    return dn or ("<" .. obj:GetObjectType() .. ">")
end

local function DescribeTexture(t)
    local parts = {}
    local atlas = t.GetAtlas and t:GetAtlas()
    if atlas then parts[#parts + 1] = "atlas=" .. atlas end
    local file = t.GetTextureFileID and t:GetTextureFileID()
    if file and file ~= 0 then parts[#parts + 1] = "file=" .. tostring(file) end
    local tex = t.GetTexture and t:GetTexture()
    if type(tex) == "string" then parts[#parts + 1] = "path=" .. tex end
    if #parts == 0 then
        local r, g, b, a = t:GetVertexColor()
        parts[#parts + 1] = ("color=%.2f,%.2f,%.2f,%.2f"):format(r or 0, g or 0, b or 0, a or 1)
    end
    local w, h = t:GetSize()
    parts[#parts + 1] = ("size=%dx%d"):format(w or 0, h or 0)
    if t.GetTexCoord then
        local ok, ulx, uly, llx, lly, urx, ury, lrx, lry = pcall(t.GetTexCoord, t)
        if ok and ulx and (ulx ~= 0 or lry ~= 1 or urx ~= 1 or uly ~= 0) then
            parts[#parts + 1] = ("coords=%.3f,%.3f,%.3f,%.3f"):format(ulx, urx, uly, lry)
        end
    end
    if not t:IsShown() then parts[#parts + 1] = "hidden" end
    return table.concat(parts, " ")
end

-- Midnight-era clients hand addons "secret" strings for some unit text; string ops on them error.
local function SafeText(v)
    if v == nil then return "" end
    if issecretvalue and issecretvalue(v) then return "<secret>" end
    if type(v) ~= "string" then return tostring(v) end
    return v:sub(1, 30)
end

local function DescribeFont(fs)
    local font, size, flags = fs:GetFont()
    local obj = fs.GetFontObject and fs:GetFontObject()
    local objName = obj and obj.GetName and obj:GetName()
    local ok, text = pcall(fs.GetText, fs)
    return ("font=%s size=%s %s%s text=%q"):format(
        tostring(font), tostring(size and math.floor(size + 0.5)), flags or "",
        objName and (" object=" .. objName) or "", ok and SafeText(text) or "<error>")
end

local function Walk(frame, depth, lines, seen)
    if #lines >= MAX_LINES then return end
    if not frame or frame:IsForbidden() or seen[frame] or depth > MAX_DEPTH then return end
    seen[frame] = true
    local indent = string.rep("  ", depth)
    local kind = frame:GetObjectType()
    local okSize, w, h = pcall(frame.GetSize, frame)
    if not okSize or (issecretvalue and (issecretvalue(w) or issecretvalue(h))) then w, h = -1, -1 end
    local extra = ""
    if frame.NineSlice or (frame.TopLeftCorner and frame.TopEdge) then
        local target = frame.NineSlice or frame
        local okL, layout = pcall(function() return target.layoutType or (target.GetFrameLayoutType and target:GetFrameLayoutType()) end)
        extra = " nineslice=" .. tostring(okL and layout or "?")
    end
    local okB, bd = pcall(function() return frame.GetBackdrop and frame:GetBackdrop() end)
    if okB and bd then extra = extra .. " backdrop" end
    lines[#lines + 1] = ("%s%s [%s %dx%d]%s%s"):format(indent, Name(frame), kind, w or 0, h or 0, extra, frame:IsShown() and "" or " hidden")

    if frame.GetRegions then
        for _, r in ipairs({ frame:GetRegions() }) do
            if not r:IsForbidden() then
                local t = r:GetObjectType()
                local ok, desc
                if t == "Texture" or t == "MaskTexture" then
                    ok, desc = pcall(DescribeTexture, r)
                    lines[#lines + 1] = ("%s  - %s %s: %s"):format(indent, t, Name(r), ok and desc or ("<error: " .. tostring(desc) .. ">"))
                elseif t == "FontString" then
                    ok, desc = pcall(DescribeFont, r)
                    lines[#lines + 1] = ("%s  - Font %s: %s"):format(indent, Name(r), ok and desc or ("<error: " .. tostring(desc) .. ">"))
                end
            end
        end
    end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            local ok, err = pcall(Walk, child, depth + 1, lines, seen)
            if not ok then lines[#lines + 1] = indent .. "  <error walking child: " .. tostring(err) .. ">" end
        end
    end
end

-- Output window ---------------------------------------------------------------------

local win
local function Window()
    if win then return win end
    win = CreateFrame("Frame", "EnhancedBlizzardGamepadInspector", UIParent, "BackdropTemplate")
    win:SetSize(720, 460)
    win:SetPoint("CENTER")
    win:SetFrameStrata("FULLSCREEN_DIALOG")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    win:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
    win:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)

    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.title:SetPoint("TOPLEFT", 12, -10)

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -34)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetWidth(660)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(edit)
    win.edit = edit
    -- Inspector output must never trigger the keyboard itself.
    edit.ebgIgnore = true
    return win
end

-- Any diagnostic output goes here so it can be copied with Ctrl+A, Ctrl+C.
function ns.ShowReport(title, lines)
    local w = Window()
    w.title:SetText("EBG " .. title .. "  (Ctrl+A, Ctrl+C to copy)")
    w.edit:SetText(table.concat(lines, "\n"))
    w.edit:SetCursorPosition(0)
    w:Show()
end

function ns.Inspect(target, label)
    local lines, seen = {}, {}
    Walk(target, 0, lines, seen)
    if #lines >= MAX_LINES then lines[#lines + 1] = "... truncated at " .. MAX_LINES .. " lines" end
    local w = Window()
    w.title:SetText("EBG inspector: " .. (label or Name(target)) .. "  (Ctrl+A, Ctrl+C to copy)")
    w.edit:SetText(table.concat(lines, "\n"))
    w.edit:SetCursorPosition(0)
    w:Show()
end

local function FrameUnderMouse()
    if GetMouseFoci then
        local foci = GetMouseFoci()
        return foci and foci[1]
    end
    if GetMouseFocus then return GetMouseFocus() end
end

local function InspectCommandInner(arg)
    arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "" or arg == "mouse" then
        local f = FrameUnderMouse()
        if not f or f == WorldFrame then
            ns.Print("Hover a frame, then run /ebg atlas. Or pass a frame name, e.g. /ebg atlas PlayerFrame")
            return
        end
        -- Walk up to the top-level parent so the whole widget is captured.
        local top = f
        while top:GetParent() and top:GetParent() ~= UIParent and not top:GetParent():IsForbidden() do
            top = top:GetParent()
        end
        ns.Inspect(top, Name(top) .. " (hovered " .. Name(f) .. ")")
        return
    end
    if arg:lower() == "ui" then
        local lines = {}
        for _, name in ipairs({ "PlayerFrame", "TargetFrame", "MainMenuBar", "ChatFrame1EditBox", "GamePadLegendFrame", "GamePadDeviceFrame" }) do
            local f = _G[name]
            if f then
                lines[#lines + 1] = "===== " .. name .. " ====="
                local seen = {}
                Walk(f, 0, lines, seen)
                lines[#lines + 1] = ""
            end
        end
        local w = Window()
        w.title:SetText("EBG inspector: core UI frames  (Ctrl+A, Ctrl+C to copy)")
        w.edit:SetText(table.concat(lines, "\n"))
        w.edit:SetCursorPosition(0)
        w:Show()
        return
    end
    local f = _G[arg]
    if type(f) ~= "table" or not f.GetObjectType then
        ns.Print("No frame named " .. arg)
        return
    end
    ns.Inspect(f, arg)
end

function ns.InspectCommand(arg)
    local ok, err = pcall(InspectCommandInner, arg)
    if not ok then ns.Print("Inspector error: " .. tostring(err)) end
end

-- Quick existence checks for atlas names the user wants to try.
function ns.AtlasCheck(names)
    local lines = {}
    for name in names:gmatch("%S+") do
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
        if info then
            lines[#lines + 1] = ("%s: %dx%d file=%s"):format(name, info.width or 0, info.height or 0, tostring(info.file or info.filename))
        else
            lines[#lines + 1] = name .. ": not found"
        end
    end
    if #lines == 0 then lines[1] = "Usage: /ebg check <atlas name> [more names]" end
    ns.ShowReport("atlas check", lines)
end

-- /ebg probe [FrameName]  lists the Lua table keys of a frame (mixin methods and fields), which is
-- how to find the API Blizzard's own gamepad icon frames use. With no name it probes the first
-- InputIcon child of the native gamepad legend.
local function FirstInputIcon(f, depth)
    if depth > 6 or not f or f:IsForbidden() then return nil end
    if f.GetChildren then
        for _, c in ipairs({ f:GetChildren() }) do
            if not c:IsForbidden() then
                local n = c.GetDebugName and c:GetDebugName() or ""
                if n:find("InputIcon") then return c end
                local r = FirstInputIcon(c, depth + 1)
                if r then return r end
            end
        end
    end
end

local function ProbeCommandInner(arg)
    arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local target
    if arg == "" then
        target = FirstInputIcon(_G.GamepadPersistentInputLegend, 0)
        if not target then ns.Print("Native gamepad legend not found; pass a frame name.") return end
    else
        target = _G[arg]
        if type(target) ~= "table" then ns.Print("No frame named " .. arg) return end
    end
    local lines = { "Probe of " .. Name(target) .. " (" .. (target.GetObjectType and target:GetObjectType() or "table") .. ")", "" }
    local funcs, fields = {}, {}
    local function collect(t, label)
        for k, v in pairs(t) do
            if type(k) == "string" then
                if type(v) == "function" then funcs[#funcs + 1] = label .. k .. "()"
                elseif type(v) ~= "table" or not v.GetObjectType then fields[#fields + 1] = label .. k .. " = " .. tostring(v)
                else fields[#fields + 1] = label .. k .. " = <" .. v:GetObjectType() .. ">" end
            end
        end
    end
    collect(target, "")
    local mt = getmetatable(target)
    if mt and type(mt.__index) == "table" then collect(mt.__index, "mt.") end
    table.sort(funcs); table.sort(fields)
    lines[#lines + 1] = "== Functions (" .. #funcs .. ") =="
    for _, f in ipairs(funcs) do lines[#lines + 1] = f end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "== Fields (" .. #fields .. ") =="
    for _, f in ipairs(fields) do lines[#lines + 1] = f end
    if target.GetParent then
        local p = target:GetParent()
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Parent: " .. Name(p)
        if p and not p:IsForbidden() then
            local pf = {}
            for k, v in pairs(p) do if type(v) == "function" then pf[#pf + 1] = k .. "()" end end
            table.sort(pf)
            lines[#lines + 1] = "Parent functions: " .. table.concat(pf, ", ")
        end
    end
    local w = Window()
    w.title:SetText("EBG probe  (Ctrl+A, Ctrl+C to copy)")
    w.edit:SetText(table.concat(lines, "\n"))
    w.edit:SetCursorPosition(0)
    w:Show()
end

function ns.ProbeCommand(arg)
    local ok, err = pcall(ProbeCommandInner, arg)
    if not ok then ns.Print("Probe error: " .. tostring(err)) end
end
