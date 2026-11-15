local ADDON, ns = ...

local listener = CreateFrame("Frame", nil, UIParent)
local capturing, r2Held = false, false
local consumed = {}
local hint

local function Browser()
    local f = _G.LFGBrowseFrame
    if f and not (f.IsForbidden and f:IsForbidden()) and f:IsVisible() then return f end
end

local function SelectedResultID()
    local nav = _G.SmartNavigation
    local f = type(nav) == "table" and nav.currentButton
    for _ = 1, 6 do
        if type(f) ~= "table" or (f.IsForbidden and f:IsForbidden()) then return nil end
        local id = f.resultID
        if not id and f.GetElementData then
            local ok, data = pcall(f.GetElementData, f)
            if ok then
                if type(data) == "table" then id = data.resultID elseif type(data) == "number" then id = data end
            end
        end
        if type(id) == "number" then return id end
        f = f.GetParent and f:GetParent()
    end
end

local function LeaderName(resultID)
    if not (C_LFGList and C_LFGList.GetSearchResultInfo) then return nil end
    local ok, info = pcall(C_LFGList.GetSearchResultInfo, resultID)
    if not ok or type(info) ~= "table" then return nil end
    local name = info.leaderName
    if issecretvalue and issecretvalue(name) then return nil end
    if type(name) == "string" and name ~= "" then return name end
end

local function SetPropagate(on)
    if InCombatLockdown() then return end
    pcall(listener.SetPropagateKeyboardInput, listener, on)
end

listener:SetScript("OnGamePadButtonDown", function(self, button)
    SetPropagate(true)
    if ns.KB and ns.KB.frame:IsShown() then return end
    if InCombatLockdown() or not Browser() then return end
    if button == "PADRTRIGGER" then
        if SelectedResultID() then
            r2Held = true
            consumed[button] = true
            SetPropagate(false)
        end
        return
    end
    if r2Held and button == "PAD1" then
        consumed[button] = true
        SetPropagate(false)
        local id = SelectedResultID()
        local name = id and LeaderName(id)
        if name then
            ns.OpenWhisperComposer(name)
        else
            ns.Print("Could not read who posted that listing.")
        end
    end
end)

listener:SetScript("OnGamePadButtonUp", function(self, button)
    local mine = consumed[button]
    consumed[button] = nil
    SetPropagate(not mine)
    if button == "PADRTRIGGER" then r2Held = false end
end)

local function Hint(browser)
    if not hint then
        hint = CreateFrame("Frame", nil, UIParent)
        hint:SetSize(200, 24)
        hint:SetFrameStrata("HIGH")
        hint.bg = hint:CreateTexture(nil, "BACKGROUND")
        hint.bg:SetAllPoints()
        hint.bg:SetColorTexture(0, 0, 0, 0.62)
        hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint.plus = hint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint.plus:SetText("+")
        hint.icons = {}
        local x = 8
        for i, button in ipairs({ "PADRTRIGGER", "PAD1" }) do
            local icon = ns.Glyphs.CreateNativeIcon(hint)
            local shown
            if icon and ns.Glyphs.BindNativeIcon(icon, button) then
                icon:SetSize(18, 17)
                shown = icon
            else
                if icon then icon:Hide() end
                local tex = hint:CreateTexture(nil, "ARTWORK")
                tex:SetSize(18, 18)
                if ns.Glyphs.Apply(tex, button) then shown = tex end
            end
            if shown then
                shown:ClearAllPoints()
                shown:SetPoint("LEFT", hint, "LEFT", x, 0)
                x = x + 20
            end
            if i == 1 then
                hint.plus:SetPoint("LEFT", hint, "LEFT", x, 0)
                x = x + hint.plus:GetStringWidth() + 3
            end
        end
        hint.text:SetPoint("LEFT", hint, "LEFT", x + 4, 0)
        hint.text:SetText("Send Whisper")
        hint:SetWidth(x + 4 + hint.text:GetStringWidth() + 10)
    end
    if not hint.dressed then
        hint:SetHeight(34)
        if ns.Skin.LegendBackground(hint) then
            hint.bg:Hide()
            hint.dressed = true
        end
    end
    hint:ClearAllPoints()
    hint:SetPoint("TOPLEFT", browser, "BOTTOMLEFT", 8, -2)
    hint:Show()
end

local sendAlpha
local function FadeSendButton(hide)
    local b = _G.LFGBrowseFrameSendMessageButton
    if not b or (b.IsForbidden and b:IsForbidden()) then return end
    if hide then
        local a = b:GetAlpha() or 1
        if a > 0.01 then
            sendAlpha = a
            pcall(b.SetAlpha, b, 0)
        end
    elseif sendAlpha then
        pcall(b.SetAlpha, b, sendAlpha)
        sendAlpha = nil
    end
end

local elapsed = 0
listener:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + dt
    if elapsed < 0.3 then return end
    elapsed = 0
    local db = ns.db
    local browser = db and db.enabled and db.lfgWhisper ~= false and ns.IsGamepadActive() and Browser() or nil
    local want = browser ~= nil
    FadeSendButton(db and db.enabled and db.lfgWhisper ~= false and ns.IsGamepadActive() or false)
    if browser then Hint(browser) elseif hint then hint:Hide() end
    if want == capturing or InCombatLockdown() then return end
    local ok = pcall(function()
        listener:EnableGamePadButton(want)
        listener:SetPropagateKeyboardInput(true)
    end)
    if ok then
        capturing = want
        if not want then r2Held = false wipe(consumed) end
    end
end)
