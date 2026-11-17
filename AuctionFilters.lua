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
-- Whether the chosen category holds gear, where sorting by item level is offered.
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
function Filters.Query(text)
    local enabled = {}
    for id, on in pairs(Filters.selected) do if on then enabled[#enabled + 1] = id end end
    if Filters.category and Filters.category.implicit and not Filters.selected[Filters.category.implicit] then
        enabled[#enabled + 1] = Filters.category.implicit
    end
    local order = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder[Filters.sort]
    return { searchString = text, minLevel = Filters.minLevel, maxLevel = Filters.maxLevel,
        filters = enabled, itemClassFilters = Filters.category and CopyClassFilters(Filters.category.filters) or nil,
        sorts = order and {{ sortOrder = order, reverseSort = Filters.reverse }} or {} }
end
function Filters.Legacy()
    local enum = Enum and Enum.AuctionHouseFilter or {}
    return Filters.selected[enum.UsableOnly or 2] == true, Filters.selected[enum.ExactMatch or 5] == true,
        Filters.category and CopyClassFilters(Filters.category.filters) or nil
end
