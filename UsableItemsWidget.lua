-- UsableItemsWidget module
-- Shows a dynamic mini action bar of specific consumable items from the
-- player's bags.  Click an icon to use the item.  Cooldowns are displayed
-- with a sweep animation; Drums of Battle uses the Tinnitus debuff duration
-- rather than the item's own cooldown.
-- Settings stored under ExsarAddonDB.usableItems.

local ADDON_NAME = "ExsarAddon"

local function uiDB()
    ExsarAddonDB.usableItems = ExsarAddonDB.usableItems or {}
    return ExsarAddonDB.usableItems
end

-- =========================================================
-- Item definitions
-- =========================================================
-- cdDebuff = "Debuff Name"  →  cooldown driven by a player debuff rather than
--                              the item's own cooldown (e.g. Tinnitus, Recently Bandaged).

-- col/row define fixed grid positions (0-based):
--   col 0 = left,  col 1 = right
--   row 0 = top,   row 1 = bottom,  row 2 = extra row (left only)
-- alternate: a zone-restricted substitute shown instead of the primary item
--   when (a) the player is in one of the valid zones AND (b) count > 0.
local TRACKED_ITEMS = {
    { name = "Dark Rune",                  id = 20520, col = 0, row = 0 },
    { name = "Demonic Rune",               id = 12662, col = 1, row = 0 },
    { name = "Super Mana Potion",          id = 22832, col = 0, row = 1,
      alternate = { name = "Bottled Nethergon Energy", id = 32902 } },
    { name = "Super Healing Potion",       id = 22829, col = 1, row = 1,
      alternate = { name = "Bottled Nethergon Vapor",  id = 32905 } },
    { name = "Drums of Battle",            id = 29529, col = 0, row = 2, cdDebuff = "Tinnitus", useCharges = true },
    { name = "Haste Potion",               id = 22838, col = 1, row = 2 },
    { name = "Heavy Netherweave Bandage",  id = 21991, col = 0, row = 3, cdDebuff = "Recently Bandaged" },
    { name = "Master Healthstone",        id = 22105, col = 1, row = 3, hideWhenEmpty = true, groupFallback = true },
    { name = "Master Healthstone",        id = 22104, col = 1, row = 3, hideWhenEmpty = true },
    { name = "Master Healthstone",        id = 22103, col = 1, row = 3, hideWhenEmpty = true },
}

-- Zones where Bottled Nethergon items are usable (Tempest Keep subzones).
local TK_ZONES = {
    ["The Eye"]      = true,
    ["The Botanica"] = true,
    ["The Arcatraz"] = true,
    ["The Mechanar"] = true,
}
local function InTempestKeep()
    return TK_ZONES[GetRealZoneText()] and true or false
end

-- Durations at or below this threshold are just the GCD, not a real cooldown.
local MIN_COOLDOWN = 1.6

-- =========================================================
-- Layout constants
-- =========================================================

local ICON_SIZE = 29
local ICON_GAP  = 4
local PADDING   = 6

-- Fixed grid dimensions (2 cols × 4 rows, though row 3 only has col 0)
local GRID_W = 2 * ICON_SIZE + ICON_GAP + PADDING * 2
local GRID_H = 4 * ICON_SIZE + 3 * ICON_GAP + PADDING * 2

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "UsableItemsFrame", UIParent)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    uiDB().x = x
    uiDB().y = y
end)


local placeholderText = frame:CreateFontString(nil, "OVERLAY")
placeholderText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
placeholderText:SetPoint("CENTER", frame, "CENTER", 0, 0)
placeholderText:SetTextColor(0.55, 0.55, 0.55, 0.9)
placeholderText:SetText("Items")
placeholderText:Hide()

frame:Hide()

local C_locked = false

-- =========================================================
-- Slot construction
-- =========================================================
--
-- Each icon is a SecureActionButtonTemplate button so the WoW secure system
-- can use the item when clicked.  RegisterForClicks("AnyUp", "AnyDown") is
-- required on TBC Classic Anniversary: the modern client's
-- SecureActionButton_OnClick handler checks ActionButtonUseKeyDown (default 1)
-- and only fires on down-events, so registering only "AnyUp" silently no-ops.

local slots = {}

for i, item in ipairs(TRACKED_ITEMS) do
    local s = {
        itemId        = item.id,
        itemName      = item.name,
        primaryId     = item.id,
        primaryName   = item.name,
        altId         = item.alternate and item.alternate.id   or nil,
        altName       = item.alternate and item.alternate.name or nil,
        useAlternate  = false,
        cdDebuff      = item.cdDebuff,
        useCharges    = item.useCharges,
        hideWhenEmpty = item.hideWhenEmpty,
        groupFallback = item.groupFallback,
        col           = item.col,
        row           = item.row,
        count         = -1,   -- -1 forces countText update on first ScanBags
        known         = false,
    }

    -- Pre-load alternate item data so the icon is ready before entering the zone.
    if item.alternate and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(item.alternate.id)
    end

    s.iconFrame = CreateFrame("Button", ADDON_NAME .. "ItemBtn" .. i, frame,
                              "SecureActionButtonTemplate")
    s.iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
    -- Both AnyUp and AnyDown required for TBC Classic Anniversary.
    s.iconFrame:RegisterForClicks("AnyUp", "AnyDown")
    s.iconFrame:SetAttribute("type", "item")
    s.iconFrame:SetAttribute("item", item.hideWhenEmpty and ("item:" .. item.id) or item.name)
    s.iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(s.itemId)
        GameTooltip:Show()
    end)
    s.iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Ready border: golden ring around the icon.
    -- Created first so slotBg (same layer, created after) covers the center,
    -- leaving only the outer 1px ring visible.
    s.border = s.iconFrame:CreateTexture(nil, "BACKGROUND")
    s.border:SetPoint("TOPLEFT",     s.iconFrame, "TOPLEFT",     -1,  1)
    s.border:SetPoint("BOTTOMRIGHT", s.iconFrame, "BOTTOMRIGHT",  1, -1)
    s.border:SetColorTexture(1, 0.82, 0.25, 0.85)
    s.border:Hide()

    -- Slot background: fully opaque so it covers the border's center area,
    -- leaving only the outer 1px ring of the border visible.
    local slotBg = s.iconFrame:CreateTexture(nil, "BACKGROUND")
    slotBg:SetAllPoints()
    slotBg:SetColorTexture(0, 0, 0, 1.0)

    -- Item icon
    s.icon = s.iconFrame:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints()
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Attempt to pre-load icon; may return nil if item data not yet cached —
    -- retried in ScanBags once the item is confirmed to be in the player's bags.
    local iconTex = select(10, GetItemInfo(item.id))
    if iconTex then s.icon:SetTexture(iconTex) end

    -- Cooldown sweep
    s.cooldown = CreateFrame("Cooldown", nil, s.iconFrame, "CooldownFrameTemplate")
    s.cooldown:SetAllPoints()
    s.cooldown:SetDrawEdge(false)
    s.cooldown:EnableMouse(false)
    if s.cooldown.SetHideCountdownNumbers then
        s.cooldown:SetHideCountdownNumbers(true)
    end

    -- Stack count (bottom-right corner; hidden when count is 1)
    s.countText = s.iconFrame:CreateFontString(nil, "OVERLAY")
    s.countText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    s.countText:SetPoint("BOTTOMRIGHT", s.iconFrame, "BOTTOMRIGHT", 1, 1)
    s.countText:SetTextColor(1, 1, 0.8, 1)
    s.countText:SetText("")

    -- Cooldown timer (center of icon)
    s.timeText = s.iconFrame:CreateFontString(nil, "OVERLAY")
    s.timeText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    s.timeText:SetPoint("CENTER", s.iconFrame, "CENTER", 0, 0)
    s.timeText:SetTextColor(1, 1, 1, 1)
    s.timeText:SetText("")

    s.iconFrame:Hide()
    slots[#slots + 1] = s
end

-- =========================================================
-- Layout
-- =========================================================

local function ApplyLayout()
    -- SecureActionButtonTemplate frames must not be moved/hidden from
    -- non-secure code during combat.
    if InCombatLockdown() then return end

    -- Check whether any hideWhenEmpty slot in each group has items.
    -- Key = "col,row", value = true if at least one member is known.
    local groupHasAny = {}
    for _, s in ipairs(slots) do
        if s.hideWhenEmpty and s.known then
            groupHasAny[s.col .. "," .. s.row] = true
        end
    end

    -- Track dynamic row counters per column for hideWhenEmpty slots that
    -- share a base row.  Key = "col,row", value = next dynamic row offset.
    local dynRow = {}
    local maxRow = 3  -- fixed rows 0-3

    for _, s in ipairs(slots) do
        if s.hideWhenEmpty and not s.known then
            -- Show the groupFallback slot when nobody in the group has items.
            local key = s.col .. "," .. s.row
            if s.groupFallback and not groupHasAny[key] then
                -- Show as empty placeholder at the base row.
                s.iconFrame:ClearAllPoints()
                s.iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT",
                    PADDING + s.col * (ICON_SIZE + ICON_GAP),
                    -(PADDING + s.row * (ICON_SIZE + ICON_GAP)))
                s.iconFrame:Show()
            else
                s.iconFrame:Hide()
            end
        else
            local row = s.row
            if s.hideWhenEmpty then
                local key = s.col .. "," .. s.row
                local nextRow = dynRow[key] or s.row
                row = nextRow
                dynRow[key] = nextRow + 1
            end
            if row > maxRow then maxRow = row end
            s.iconFrame:ClearAllPoints()
            s.iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT",
                PADDING + s.col * (ICON_SIZE + ICON_GAP),
                -(PADDING + row * (ICON_SIZE + ICON_GAP)))
            s.iconFrame:Show()
        end
    end

    placeholderText:Hide()
    local rows = maxRow + 1
    frame:SetSize(GRID_W, rows * ICON_SIZE + (rows - 1) * ICON_GAP + PADDING * 2)
    frame:Show()
end

-- =========================================================
-- Alternate item switching
-- =========================================================
-- Swaps a slot between its primary and alternate item when zone/count changes.
-- Cannot run during combat lockdown; PLAYER_REGEN_ENABLED triggers a retry.

local function UpdateActiveItems()
    if InCombatLockdown() then return end
    local inTK = InTempestKeep()
    for _, s in ipairs(slots) do
        if s.altId then
            local shouldUseAlt = inTK and GetItemCount(s.altId) > 0
            if shouldUseAlt ~= s.useAlternate then
                s.useAlternate = shouldUseAlt
                local newId   = shouldUseAlt and s.altId   or s.primaryId
                local newName = shouldUseAlt and s.altName or s.primaryName
                s.itemId   = newId
                s.itemName = newName
                s.iconFrame:SetAttribute("item", newName)
                local tex = select(10, GetItemInfo(newId))
                s.icon:SetTexture(tex or nil)
                s.count = -1  -- force countText refresh in ScanBags
            end
        end
    end
end

-- =========================================================
-- Bag scanning
-- =========================================================

local function ScanBags()
    local needLayout = false
    for _, s in ipairs(slots) do
        local count = GetItemCount(s.itemId, false, s.useCharges and true or false)
        local wasKnown = s.known
        s.known = count > 0

        if s.hideWhenEmpty and (wasKnown ~= s.known) then
            needLayout = true
        end

        if count ~= s.count then
            s.count = count
            if count == 0 then
                s.countText:SetText("0")
            else
                s.countText:SetText(tostring(count))
            end
        end

        -- Retry icon load if GetItemInfo wasn't cached at slot-creation time.
        if not s.icon:GetTexture() then
            local tex = select(10, GetItemInfo(s.itemId))
            if tex then s.icon:SetTexture(tex) end
        end
    end
    if needLayout then ApplyLayout() end
end

-- =========================================================
-- Cooldown updates
-- =========================================================

local function FormatCooldown(remaining)
    if remaining >= 60 then
        return string.format("%dm", math.ceil(remaining / 60))
    elseif remaining >= 10 then
        return string.format("%d", math.ceil(remaining))
    else
        return string.format("%.1f", remaining)
    end
end

-- Returns start, duration for a named player debuff if it is currently active.
local function GetDebuffCooldown(debuffName)
    for i = 1, 40 do
        local name, _, _, _, duration, expTime = UnitDebuff("player", i)
        if not name then break end
        if name == debuffName and duration and duration > 0 then
            return expTime - duration, duration
        end
    end
    return nil, nil
end

local function UpdateCooldowns()
    local now = GetTime()
    for _, s in ipairs(slots) do
        -- Items with no debuff CD and none in bags: greyed out, no cooldown.
        if not s.known and not s.cdDebuff then
            s.icon:SetDesaturated(true)
            s.icon:SetAlpha(0.35)
            s.cooldown:SetCooldown(0, 0)
            s.timeText:SetText("")
            s.border:Hide()
        else
            -- Debuff-based CDs are visible even when the item is depleted.
            local start, duration
            if s.cdDebuff then
                start, duration = GetDebuffCooldown(s.cdDebuff)
            else
                -- GetItemCooldown does not exist in TBC Classic.  Scan bags to
                -- find the item's location and use GetContainerItemCooldown,
                -- which also returns shared category cooldowns (e.g. potions).
                for bag = 0, 4 do
                    for slot = 1, C_Container.GetContainerNumSlots(bag) do
                        if C_Container.GetContainerItemID(bag, slot) == s.itemId then
                            start, duration = C_Container.GetContainerItemCooldown(bag, slot)
                            break
                        end
                    end
                    if start then break end
                end
            end

            local onCD = start and start > 0 and duration and duration > MIN_COOLDOWN

            if onCD then
                s.icon:SetDesaturated(true)
                s.icon:SetAlpha(0.4)
                s.cooldown:SetCooldown(start, duration)
                local remaining = (start + duration) - now
                s.timeText:SetText(remaining > 0 and FormatCooldown(remaining) or "")
                s.border:SetShown(s.known and true or false)
            else
                s.icon:SetDesaturated(not s.known)
                s.icon:SetAlpha(s.known and 1.0 or 0.35)
                s.cooldown:SetCooldown(0, 0)
                s.timeText:SetText("")
                s.border:SetShown(s.known and true or false)
            end
        end
    end
end

-- =========================================================
-- OnUpdate: cooldown timers (every 0.1 s)
-- =========================================================

local scanElapsed = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    scanElapsed = scanElapsed + elapsed
    if scanElapsed >= 0.1 then
        scanElapsed = 0
        UpdateCooldowns()
    end
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        local db = uiDB()
        if db.x and db.y then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        else
            self:SetPoint("CENTER", UIParent, "CENTER", 150, -160)
        end
        self:SetScale(db.scale or 1.0)
        self:EnableMouse(not db.locked)
        C_locked = db.locked and true or false
        ApplyLayout()
        UpdateActiveItems()
        ScanBags()

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateActiveItems()
        ScanBags()
        UpdateCooldowns()

    elseif event == "PLAYER_ALIVE" then
        UpdateActiveItems()
        ScanBags()
        UpdateCooldowns()

    elseif event == "BAG_UPDATE" then
        UpdateActiveItems()
        ScanBags()

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        UpdateActiveItems()
        ScanBags()

    elseif event == "PLAYER_REGEN_ENABLED" then
        UpdateActiveItems()
        ScanBags()

    elseif event == "BAG_UPDATE_COOLDOWN" then
        UpdateCooldowns()

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then
            UpdateCooldowns()
        end
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("itemsreset", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 150, -160)
    uiDB().x = nil
    uiDB().y = nil
    print(ADDON_NAME .. ": Usable items widget position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Usable Items",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return uiDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                uiDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return uiDB().locked and true or false end,
            function(v)
                uiDB().locked = v
                C_locked = v
                frame:EnableMouse(not v)
                ApplyLayout()
            end
        )
        y = y - 30

        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 150, -160)
            uiDB().x = nil
            uiDB().y = nil
            print(ADDON_NAME .. ": Usable items widget position reset.")
        end)
        y = y - 30

        return y
    end,
})
