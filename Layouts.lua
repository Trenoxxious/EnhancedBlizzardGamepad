local ADDON, ns = ...

local BS = { label = "Delete", w = 2.5, action = "backspace", pad = "PAD3" }
local SH = { label = "Shift", w = 2.5, action = "shift", pad = "PADLTRIGGER" }
local SY = { label = "?123",  w = 1.5, action = "symbols" }
local AB = { label = "ABC",   w = 1.5, action = "letters" }
local AC = { label = "Àé",    w = 1.5, action = "accents" }
local EN = { label = "Enter", w = 2.5, action = "submit", pad = "PADRTRIGGER" }
local SP = { label = "Space", w = 7, action = "space", pad = "PAD4" }
local CL = { label = "Close", w = 2, action = "close", pad = "PAD2" }
local SP4 = { label = "Space", w = 6, action = "space", pad = "PAD4" }
local QK = { label = "", icon = "QuestLog-tab-icon-quest", w = 1, action = "quests", chatOnly = true }
local LT = { label = "<",     w = 1,   action = "caretleft" }
local RT = { label = ">",     w = 1,   action = "caretright" }

ns.Layouts = {}
ns.LocaleLayout = {}

local function chars(s)
    local out = {}
    local i = 1
    while i <= #s do
        local j = ns.UTF8CharEnd(s, i)
        out[#out + 1] = s:sub(i, j - 1)
        i = j
    end
    return out
end
ns.SplitChars = chars

local function row(...)
    local r = {}
    for _, part in ipairs({ ... }) do
        if type(part) == "string" then
            for _, c in ipairs(chars(part)) do r[#r + 1] = c end
        elseif part.action then
            r[#r + 1] = part
        else
            for _, k in ipairs(part) do r[#r + 1] = k end
        end
    end
    return r
end

local UPPER = {}
local function MapRange(loFrom, hiFrom, count)
    for i = 0, count - 1 do UPPER[ns.UTF8Char(loFrom + i)] = ns.UTF8Char(hiFrom + i) end
end
MapRange(0x0430, 0x0410, 32)            -- Cyrillic а..я
UPPER[ns.UTF8Char(0x0451)] = ns.UTF8Char(0x0401) -- ё
MapRange(0x00E0, 0x00C0, 23)            -- à..ö
MapRange(0x00F8, 0x00D8, 7)             -- ø..þ
UPPER[ns.UTF8Char(0x00FF)] = ns.UTF8Char(0x0178) -- ÿ
UPPER[ns.UTF8Char(0x0153)] = ns.UTF8Char(0x0152) -- œ
UPPER[ns.UTF8Char(0x00DF)] = "SS"                -- ß
MapRange(0x03B1, 0x0391, 17)            -- Greek α..ρ
MapRange(0x03C3, 0x03A3, 7)             -- σ..ω
UPPER[ns.UTF8Char(0x03C2)] = ns.UTF8Char(0x03A3) -- final sigma

function ns.Upper(c)
    if #c == 1 then return c:upper() end
    return UPPER[c] or c
end

local function define(id, name, letterRows, opts)
    opts = opts or {}
    local rows = {}
    rows[1] = row("1234567890", BS)
    for i, r in ipairs(letterRows) do
        rows[#rows + 1] = r
    end
    rows[#rows] = row(SH, rows[#rows], EN) -- wrap last letter row with Shift and Enter
    rows[#rows + 1] = row(SY, AC, QK, ",", SP4, ".")
    ns.Layouts[id] = { id = id, name = name, rows = rows, accents = opts.accents }
    for _, loc in ipairs(opts.locales or {}) do ns.LocaleLayout[loc] = id end
end

local LATIN_ACCENTS = {
    row("àáâäãåæç"),
    row("èéêëìíîï"),
    row("ñòóôöõøœ"),
    row("ùúûüýÿß"),
}

define("qwerty", "English QWERTY", {
    row("qwertyuiop"),
    row("asdfghjkl'"),
    row("zxcvbnm"),
}, { locales = { "enUS", "enGB" }, accents = LATIN_ACCENTS })

define("azerty", "Français AZERTY", {
    row("azertyuiop"),
    row("qsdfghjklm"),
    row("wxcvbn'"),
}, { locales = { "frFR" }, accents = LATIN_ACCENTS })

define("qwertz", "Deutsch QWERTZ", {
    row("qwertzuiopü"),
    row("asdfghjklöä"),
    row("yxcvbnmß"),
}, { locales = { "deDE" }, accents = LATIN_ACCENTS })

define("spanish", "Español", {
    row("qwertyuiop"),
    row("asdfghjklñ"),
    row("zxcvbnm'"),
}, { locales = { "esES", "esMX" }, accents = LATIN_ACCENTS })

define("italian", "Italiano", {
    row("qwertyuiopè"),
    row("asdfghjklòà"),
    row("zxcvbnmù"),
}, { locales = { "itIT" }, accents = LATIN_ACCENTS })

define("portuguese", "Português", {
    row("qwertyuiop"),
    row("asdfghjklç"),
    row("zxcvbnm'"),
}, { locales = { "ptBR", "ptPT" }, accents = LATIN_ACCENTS })

define("russian", "Русский ЙЦУКЕН", {
    row("йцукенгшщзхъ"),
    row("фывапролджэ"),
    row("ячсмитьбю"),
}, { locales = { "ruRU" }, accents = { row("ёЁ") } })

ns.LocaleLayout.koKR = "qwerty"
ns.LocaleLayout.zhCN = "qwerty"
ns.LocaleLayout.zhTW = "qwerty"

ns.SymbolRows = {
    row("!@#$%^&*()", BS),
    row("-_=+[]{}\\|"),
    row(";:\"'<>/?~`"),
    row(AB, "€£¥", EN),
    row(AB, AC, ",", SP, "."),
}

function ns.CurrentLayoutID()
    local id = ns.db and ns.db.layout
    if id and ns.Layouts[id] then return id end
    local loc = GetLocale and GetLocale() or "enUS"
    return ns.LocaleLayout[loc] or "qwerty"
end

function ns.CurrentLayout()
    return ns.Layouts[ns.CurrentLayoutID()]
end

function ns.AccentRows(layout)
    local rows = {}
    for i, r in ipairs(layout.accents or LATIN_ACCENTS) do rows[i] = r end
    rows[1] = row(rows[1], BS)
    rows[#rows] = row(SH, rows[#rows], EN)
    rows[#rows + 1] = row(AB, SY, ",", SP, ".")
    return rows
end

ns.NumpadRows = {
    row("789", BS),
    row("456", { label = ".", w = 2.5, action = "char", char = "." }),
    row("123", { label = "-", w = 2.5, action = "char", char = "-" }),
    { { label = "0", w = 3, action = "char", char = "0" }, EN },
}
