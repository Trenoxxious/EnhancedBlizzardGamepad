local ADDON, ns = ...
local Inventory = {}
ns.Inventory = Inventory

-- Read only; identical links group stacks while preserving item variants.
function Inventory.Read()
    local items, byLink = {}, {}
    local api = C_Container
    if not (api and api.GetContainerNumSlots and api.GetContainerItemInfo and api.GetContainerItemLink) then return items end
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, api.GetContainerNumSlots(bag) do
            local info = api.GetContainerItemInfo(bag, slot)
            local link = info and (info.hyperlink or api.GetContainerItemLink(bag, slot))
            if link then
                local entry = byLink[link]
                if not entry then
                    entry = { link = link, name = link:match("%[(.-)%]") or ("Item " .. tostring(info.itemID or "")),
                        icon = info.iconFileID, quality = info.quality, count = 0, itemID = info.itemID, bag = bag, slot = slot }
                    byLink[link], items[#items + 1] = entry, entry
                end
                entry.count = entry.count + (info.stackCount or 1)
            end
        end
    end
    table.sort(items, function(a, b)
        if a.name == b.name then return a.link < b.link end
        return a.name < b.name
    end)
    return items
end
function Inventory.Sellable()
    local items,seen = {},{}
    if not ItemLocation or not C_AuctionHouse or not C_AuctionHouse.IsSellItemValid then return items end
    for bag=0,NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot=1,C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag,slot)
            local link = info and (info.hyperlink or C_Container.GetContainerItemLink(bag,slot))
            if link and not seen[link] and not info.isLocked then
                local location = ItemLocation:CreateFromBagAndSlot(bag,slot)
                if C_AuctionHouse.IsSellItemValid(location,false) then
                    items[#items+1] = {link=link,name=link:match("%[(.-)%]") or "Item",icon=info.iconFileID,
                        quality=info.quality,itemID=info.itemID,bag=bag,slot=slot,count=C_AuctionHouse.GetAvailablePostCount(location)}
                    seen[link] = true
                end
            end
        end
    end
    table.sort(items,function(a,b) return a.name==b.name and a.link<b.link or a.name<b.name end)
    return items
end
function Inventory.Color(quality)
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
    return c and { c.r, c.g, c.b } or { 1, 1, 1 }
end
