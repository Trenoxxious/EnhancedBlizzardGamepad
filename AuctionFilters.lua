local ADDON, ns = ...
local Filters = { selected = {}, minLevel = 0, maxLevel = 0, sort = "Price", reverse = false }
ns.AuctionFilters = Filters

local function CopyClassFilters(source)
    local out = {}
    for _, f in ipairs(source or {}) do
        out[#out + 1] = { classID = f.classID, subClassID = f.subClassID, inventoryType = f.inventoryType }
    end
    return out
end
-- Snapshot data only. Do not invoke category mixins or write selection/expansion
-- into AuctionCategories; Blizzard's global table must remain untouched.
function Filters.Categories()
    local function Copy(nodes, parent, prefix, inherited)
        local out = {}
        for i, native in ipairs(nodes or {}) do
            if not (native.flags and native.flags.WOW_TOKEN_FLAG) then
                local node = { name = native.name, filters = CopyClassFilters(native.filters), parent = parent,
                    id = prefix .. i, implicit = native.implicitFilter or inherited }
                node.children = Copy(native.subCategories, node, node.id .. ".", node.implicit)
                out[#out + 1] = node
            end
        end
        return out
    end
    if AuctionCategories and #AuctionCategories > 0 then return Copy(AuctionCategories, nil, "") end
    local list = {}
    for _, entry in ipairs({ {2,"Weapons"}, {4,"Armor"}, {1,"Containers"}, {0,"Consumables"}, {7,"Trade Goods"},
        {6,"Ammo"}, {9,"Recipes"}, {12,"Quest Items"}, {15,"Miscellaneous"} }) do
        local name = C_Item and C_Item.GetItemClassInfo and C_Item.GetItemClassInfo(entry[1]) or entry[2]
        list[#list + 1] = { name = name, id = tostring(entry[1]), filters = {{classID=entry[1]}}, children = {} }
    end
    return list
end
function Filters.Reset()
    Filters.selected = {}
    for key, value in pairs(AUCTION_HOUSE_DEFAULT_FILTERS or {}) do Filters.selected[key] = value end
    Filters.minLevel, Filters.maxLevel = 0, 0
end
function Filters.Options()
    local list = {}
    if C_AuctionHouse and C_AuctionHouse.GetFilterGroups then
        for _, group in ipairs(C_AuctionHouse.GetFilterGroups() or {}) do
            for _, id in ipairs(group.filters or {}) do
                local name = AUCTION_HOUSE_FILTER_STRINGS and AUCTION_HOUSE_FILTER_STRINGS[id]
                list[#list + 1] = { id = id, name = name or ("Filter " .. id) }
            end
        end
    end
    return list
end
-- Blizzard's filter names carry colour markup (e.g. "|cnIQ0:Poor|r"). The quality is kept for
-- colouring and the markup removed, so the label never shows raw codes.
local function Clean(text)
    text = tostring(text or "")
    local quality = tonumber(text:match("|cnIQ(%d+):"))
    text = text:gsub("|cn[^:|]*:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return text, quality
end
Filters.Clean = Clean
-- The options grouped the way Blizzard's filter menu groups them: general options and rarity.
function Filters.Groups(legacy)
    if legacy then
        return { { name = "Options", options = { {id=2,name="Usable only"}, {id=5,name="Exact match"} } } }
    end
    local general, rarity = { name = "Options", options = {} }, { name = "Rarity", options = {}, rarity = true }
    local cat = Enum and Enum.AuctionHouseFilterCategory or {}
    local poor = Enum and Enum.AuctionHouseFilter and Enum.AuctionHouseFilter.PoorQuality
    if C_AuctionHouse and C_AuctionHouse.GetFilterGroups then
        for _, group in ipairs(C_AuctionHouse.GetFilterGroups() or {}) do
            local isRarity = group.category ~= nil and group.category == cat.Rarity
            for _, id in ipairs(group.filters or {}) do
                local name, quality = Clean(AUCTION_HOUSE_FILTER_STRINGS and AUCTION_HOUSE_FILTER_STRINGS[id] or ("Filter " .. id))
                if isRarity and not quality and poor then quality = id - poor end
                local list = isRarity and rarity.options or general.options
                list[#list + 1] = { id = id, name = name, quality = quality }
            end
        end
    end
    local groups = {}
    if #general.options > 0 then groups[#groups + 1] = general end
    if #rarity.options > 0 then groups[#groups + 1] = rarity end
    return groups
end
-- How many settings differ from Blizzard's defaults, shown on the Filter button.
function Filters.ActiveCount()
    local defaults, count, seen = AUCTION_HOUSE_DEFAULT_FILTERS or {}, 0, {}
    for id, on in pairs(Filters.selected) do
        seen[id] = true
        if (on and true or false) ~= (defaults[id] and true or false) then count = count + 1 end
    end
    for id, on in pairs(defaults) do if on and not seen[id] then count = count + 1 end end
    if Filters.minLevel > 0 then count = count + 1 end
    if Filters.maxLevel > 0 then count = count + 1 end
    return count
end
-- Whether the chosen category holds gear, where the required-level column and sort are offered.
function Filters.IsEquipment()
    local node = Filters.category
    while node do
        for _, f in ipairs(node.filters or {}) do
            if f.classID == 2 or f.classID == 4 then return true end
        end
        node = node.parent
    end
    return false
end
-- The level range means the level required to use the item ("Requires Level N"), not item level.
-- The modern browse query's own minLevel/maxLevel are matched against item level on Forever, so
-- they are sent as 0 (any) and AuctionData filters the browse results here instead. The legacy
-- QueryAuctionItems takes the required level itself, so it still gets the range directly.
function Filters.LevelActive()
    return Filters.minLevel > 0 or Filters.maxLevel > 0
end
function Filters.LevelMatches(level)
    if Filters.minLevel > 0 and level < Filters.minLevel then return false end
    if Filters.maxLevel > 0 and level > Filters.maxLevel then return false end
    return true
end
-- An item's required level (0 when it has none), or nil while its data is not loaded yet; the
-- load is then requested, and GET_ITEM_INFO_RECEIVED brings the answer (see AuctionData).
function Filters.RequiredLevel(itemID)
    local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not get or not itemID then return nil end
    local ok, name, _, _, _, minLevel = pcall(get, itemID)
    if ok and name then return minLevel or 0 end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    return nil
end
-- Whether the current sort runs highest first. Price starts cheapest first; Level starts at the
-- highest required level, the useful end when shopping for gear. Pressing the header flips it.
function Filters.Descending()
    return (Filters.sort == "Level") ~= (Filters.reverse == true)
end
-- The Level column is the required level, which the server cannot sort by (its Level sort is item
-- level, and on Forever it does not reorder the results at all). Browse rows are therefore sorted
-- here: by required level, unknown levels last, then cheapest first. Only loaded rows can be
-- sorted; rows that Next loads are sorted in with them.
function Filters.SortByLevel(rows)
    local down = Filters.Descending()
    table.sort(rows, function(a, b)
        local la, lb = a.required, b.required
        if la ~= lb then
            if la == nil then return false end
            if lb == nil then return true end
            if down then return la > lb end
            return la < lb
        end
        local pa, pb = a.price or 0, b.price or 0
        if pa ~= pb then return pa < pb end
        return tostring(a.identity or "") < tostring(b.identity or "")
    end)
end
function Filters.Query(text)
    local enabled = {}
    for id, on in pairs(Filters.selected) do if on then enabled[#enabled + 1] = id end end
    if Filters.category and Filters.category.implicit and not Filters.selected[Filters.category.implicit] then
        enabled[#enabled + 1] = Filters.category.implicit
    end
    -- The server's own sort is still requested (reverseSort meaning highest first), so with more
    -- results than one load the first loads lean the right way; SortByLevel then orders them.
    local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder[Filters.sort]
    return { searchString = text, minLevel = 0, maxLevel = 0,
        filters = enabled, itemClassFilters = Filters.category and CopyClassFilters(Filters.category.filters) or nil,
        sorts = order and {{ sortOrder = order, reverseSort = Filters.Descending() }} or {} }
end
function Filters.Legacy()
    local enum = Enum and Enum.AuctionHouseFilter or {}
    return Filters.selected[enum.UsableOnly or 2] == true, Filters.selected[enum.ExactMatch or 5] == true,
        Filters.category and CopyClassFilters(Filters.category.filters) or nil
end
