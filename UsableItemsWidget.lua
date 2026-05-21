-- UsableItemsWidget module
-- Shows a dynamic mini action bar of specific consumable items from the
-- player's bags.  Click an icon to use the item.  Cooldowns are displayed
-- with a sweep animation; Drums of Battle uses the Tinnitus debuff duration
-- rather than the item's own cooldown.
-- Settings stored under ExsarAddonDB.usableItems.

local ADDON_NAME = "ExsarAddon"

local uiDB = ExsarUI.MakeDB("usableItems")

-- =========================================================
-- Item definitions
-- =========================================================
-- cdDebuff = "Debuff Name"  →  cooldown driven by a player debuff rather than
--                              the item's own cooldown (e.g. Tinnitus, Recently Bandaged).

-- col/row define fixed grid positions (0-based):
--   col 0 = left,  col 1 = right
--   row 0 = top,   row 1 = bottom,  row 2 = extra row (left only)
-- alternates: ordered list of substitute items. The first whose conditions are
--   met (optional `zones` check, count > 0) replaces the primary. Order matters:
--   zone-restricted alts should come first so they win in-zone.
-- ranks: ordered list (highest-first) of interchangeable item IDs layered into a
--   single slot (e.g. Master Healthstone variants). The highest rank in the bags
--   is shown; falls back to the highest rank (greyed) when none are carried.
--   Unlike alternates, the primary always loses to a higher-ranked item; selection
--   is by ExsarLogic.SelectBestRank, not first-in-stock.
local TK_ZONES = {
    ["The Eye"]      = true,
    ["The Botanica"] = true,
    ["The Arcatraz"] = true,
    ["The Mechanar"] = true,
}

local TRACKED_ITEMS = {
    { name = "Dark Rune",                  id = 20520, col = 0, row = 0,
      alternates = {
          { name = "Demonic Rune", id = 12662 },
      } },
    { name = "Super Mana Potion",          id = 22832, col = 0, row = 1,
      alternates = {
          { name = "Bottled Nethergon Energy", id = 32902, zones = TK_ZONES },
          { name = "Crystal Mana Potion",      id = 33935 },
          { name = "Auchenai Mana Potion",     id = 32948 },
      } },
    { name = "Super Healing Potion",       id = 22829, col = 1, row = 1,
      alternates = {
          { name = "Bottled Nethergon Vapor",  id = 32905, zones = TK_ZONES },
          { name = "Crystal Healing Potion",   id = 33934 },
          { name = "Auchenai Healing Potion",  id = 32947 },
      } },
    { name = "Drums of Battle",            id = 29529, col = 0, row = 2, cdDebuff = "Tinnitus", useCharges = true },
    { name = "Haste Potion",               id = 22838, col = 1, row = 2 },
    { name = "Heavy Netherweave Bandage",  id = 21991, col = 0, row = 3, cdDebuff = "Recently Bandaged" },
    { name = "Master Healthstone",        id = 22105, col = 1, row = 3, hideWhenEmpty = true, groupFallback = true,
      ranks = {
          { name = "Master Healthstone", id = 22105 },
          { name = "Master Healthstone", id = 22104 },
          { name = "Master Healthstone", id = 22103 },
      } },
}

-- Durations at or below this threshold are just the GCD, not a real cooldown.
local MIN_COOLDOWN = ExsarLogic.MIN_COOLDOWN_DURATION

-- =========================================================
-- Layout constants
-- =========================================================

local ICON_SIZE = 29
local ICON_GAP  = 4
local PADDING   = 6

-- Fixed grid width (2 cols)
local GRID_W = 2 * ICON_SIZE + ICON_GAP + PADDING * 2

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "UsableItemsFrame", UIParent)
ExsarUI.SetupMovableFrame(frame, uiDB)


local placeholderText = ExsarUI.CreatePlaceholder(frame, "Items")

frame:Hide()

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
        alternates    = item.alternates,
        ranks         = item.ranks,
        cdDebuff      = item.cdDebuff,
        useCharges    = item.useCharges,
        hideWhenEmpty = item.hideWhenEmpty,
        groupFallback = item.groupFallback,
        col           = item.col,
        row           = item.row,
        count         = -1,   -- -1 forces countText update on first ScanBags
        known         = false,
    }

    -- Pre-load alternate / rank item data so icons are ready before a swap.
    if C_Item and C_Item.RequestLoadItemDataByID then
        for _, alt in ipairs(item.alternates or {}) do
            C_Item.RequestLoadItemDataByID(alt.id)
        end
        for _, rank in ipairs(item.ranks or {}) do
            C_Item.RequestLoadItemDataByID(rank.id)
        end
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

    -- Active Glow (1px border ring): golden ring around the icon.
    -- Created first so slotBg (same layer, created after) covers the center,
    -- leaving only the outer 1px ring visible.
    s.border = ExsarUI.CreateGlow(s.iconFrame, 1, 0.82, 0.25, 0.85, 1)

    -- Slot background: fully opaque so it covers the border's center area,
    -- leaving only the outer 1px ring of the border visible.
    local slotBg = s.iconFrame:CreateTexture(nil, "BACKGROUND")
    slotBg:SetAllPoints()
    slotBg:SetColorTexture(0, 0, 0, 1.0)

    -- Item icon
    s.icon = ExsarUI.CreateIcon(s.iconFrame)

    -- Attempt to pre-load icon; may return nil if item data not yet cached —
    -- retried in ScanBags once the item is confirmed to be in the player's bags.
    local iconTex = select(10, GetItemInfo(item.id))
    if iconTex then s.icon:SetTexture(iconTex) end

    -- Cooldown sweep
    s.cooldown = ExsarUI.CreateSweep(s.iconFrame)
    s.cooldown:EnableMouse(false)

    -- Stack count (bottom-right corner; hidden when count is 1)
    s.countText = s.iconFrame:CreateFontString(nil, "OVERLAY")
    s.countText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    s.countText:SetPoint("BOTTOMRIGHT", s.iconFrame, "BOTTOMRIGHT", 1, 1)
    s.countText:SetTextColor(1, 1, 0.8, 1)
    s.countText:SetText("")

    -- Cooldown timer (center of icon)
    s.timeText = ExsarUI.CreateCountdownText(s.iconFrame)

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
    local zone = GetRealZoneText()
    for _, s in ipairs(slots) do
        if s.ranks then
            -- Layered ranks (e.g. Master Healthstone variants): show the
            -- highest rank in the bags, falling back to the highest rank as a
            -- greyed placeholder when none are carried. Single slot, no extra
            -- rows. Uses item:ID for the secure attribute since all ranks share
            -- a name.
            local best = ExsarLogic.SelectBestRank(s.ranks, GetItemCount)
            if best.id ~= s.itemId then
                s.itemId   = best.id
                s.itemName = best.name
                s.iconFrame:SetAttribute("item",
                    s.hideWhenEmpty and ("item:" .. best.id) or best.name)
                local tex = select(10, GetItemInfo(best.id))
                s.icon:SetTexture(tex or nil)
                s.count = -1  -- force countText refresh in ScanBags
            end
        elseif s.alternates then
            local chosenId, chosenName = s.primaryId, s.primaryName
            for _, alt in ipairs(s.alternates) do
                local zoneOk = not alt.zones or alt.zones[zone]
                if zoneOk and GetItemCount(alt.id) > 0 then
                    chosenId, chosenName = alt.id, alt.name
                    break
                end
            end
            if chosenId ~= s.itemId then
                s.itemId   = chosenId
                s.itemName = chosenName
                s.iconFrame:SetAttribute("item", chosenName)
                local tex = select(10, GetItemInfo(chosenId))
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

local FormatCooldown = ExsarLogic.FormatCooldown

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

ExsarUI.CreatePoller(frame, 0.1, UpdateCooldowns)

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
        ExsarUI.RestorePosition(self, uiDB, 150, -160)
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

ExsarUI.AddSlashReset("itemsreset", frame, uiDB, "Usable items widget", 150, -160)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Usable Items",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, uiDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, uiDB, frame, function()
            ApplyLayout()
        end)

        y = ExsarUI.AddResetButton(parent, y, uiDB, frame, "Usable items", 150, -160)

        return y
    end,
})
