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
-- useTinnitus = true  →  cooldown driven by the player's Tinnitus debuff
--                        rather than the item's own cooldown.

-- col/row define fixed grid positions (0-based):
--   col 0 = left,  col 1 = right
--   row 0 = top,   row 1 = bottom
local TRACKED_ITEMS = {
    { name = "Super Mana Potion",    id = 22832, col = 0, row = 0 },
    { name = "Super Healing Potion", id = 22829, col = 1, row = 0 },
    { name = "Drums of Battle",      id = 29529, col = 0, row = 1, useTinnitus = true },
    { name = "Haste Potion",         id = 22838, col = 1, row = 1 },
}

-- Tinnitus: the debuff applied after using Drums of Battle that gates re-use.
-- Matched by name; spell ID not used as it may vary across patch revisions.
local TINNITUS_NAME = "Tinnitus"

-- Durations at or below this threshold are just the GCD, not a real cooldown.
local MIN_COOLDOWN = 1.6

-- =========================================================
-- Layout constants
-- =========================================================

local ICON_SIZE = 29
local ICON_GAP  = 4
local PADDING   = 6

-- Fixed 2×2 grid dimensions
local GRID_W = 2 * ICON_SIZE + ICON_GAP + PADDING * 2
local GRID_H = 2 * ICON_SIZE + ICON_GAP + PADDING * 2

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
        itemId      = item.id,
        itemName    = item.name,
        useTinnitus = item.useTinnitus,
        col         = item.col,
        row         = item.row,
        count       = 0,
        known       = false,
    }

    s.iconFrame = CreateFrame("Button", ADDON_NAME .. "ItemBtn" .. i, frame,
                              "SecureActionButtonTemplate")
    s.iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
    -- Both AnyUp and AnyDown required for TBC Classic Anniversary.
    s.iconFrame:RegisterForClicks("AnyUp", "AnyDown")
    s.iconFrame:SetAttribute("type", "item")
    s.iconFrame:SetAttribute("item", item.name)

    -- Slot background (only visible when this slot is shown)
    local slotBg = s.iconFrame:CreateTexture(nil, "BACKGROUND")
    slotBg:SetAllPoints()
    slotBg:SetColorTexture(0, 0, 0, 0.6)

    -- Ready border: 1px golden ring around the icon, shown only when off cooldown.
    -- Positioned 1px outside the icon frame so it peeks out around all edges.
    s.border = s.iconFrame:CreateTexture(nil, "BACKGROUND")
    s.border:SetPoint("TOPLEFT",     s.iconFrame, "TOPLEFT",     -1,  1)
    s.border:SetPoint("BOTTOMRIGHT", s.iconFrame, "BOTTOMRIGHT",  1, -1)
    s.border:SetColorTexture(1, 0.82, 0.25, 0.85)
    s.border:Hide()

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

    local anyKnown = false
    for _, s in ipairs(slots) do
        if s.known then
            anyKnown = true
            s.iconFrame:ClearAllPoints()
            s.iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT",
                PADDING + s.col * (ICON_SIZE + ICON_GAP),
                -(PADDING + s.row * (ICON_SIZE + ICON_GAP)))
            s.iconFrame:Show()
        else
            s.iconFrame:Hide()
        end
    end

    if anyKnown then
        placeholderText:Hide()
        frame:SetSize(GRID_W, GRID_H)
        frame:Show()
    elseif not C_locked then
        frame:SetSize(60, ICON_SIZE + PADDING * 2)
        placeholderText:Show()
        frame:Show()
    else
        placeholderText:Hide()
        frame:Hide()
    end
end

-- =========================================================
-- Bag scanning
-- =========================================================

local function ScanBags()
    local changed = false
    for _, s in ipairs(slots) do
        local count    = GetItemCount(s.itemId)
        local wasKnown = s.known
        s.known = count > 0

        if count ~= s.count then
            s.count = count
            s.countText:SetText(count > 1 and tostring(count) or "")
        end

        -- Retry icon load if GetItemInfo wasn't cached at slot-creation time.
        if s.known and not s.icon:GetTexture() then
            local tex = select(10, GetItemInfo(s.itemId))
            if tex then s.icon:SetTexture(tex) end
        end

        if s.known ~= wasKnown then changed = true end
    end

    if changed then ApplyLayout() end
end

-- =========================================================
-- Cooldown updates
-- =========================================================

local function FormatCooldown(remaining)
    if remaining >= 60 then
        return string.format("%dm", math.floor(remaining / 60))
    elseif remaining >= 10 then
        return string.format("%d", math.ceil(remaining))
    else
        return string.format("%.1f", remaining)
    end
end

-- Returns start, duration for the Tinnitus debuff if it is currently active.
local function GetTinnitusCooldown()
    for i = 1, 40 do
        local name, _, _, _, duration, expTime = UnitDebuff("player", i)
        if not name then break end
        if name == TINNITUS_NAME and duration and duration > 0 then
            return expTime - duration, duration
        end
    end
    return nil, nil
end

local function UpdateCooldowns()
    local now = GetTime()
    for _, s in ipairs(slots) do
        if s.known then
            local start, duration
            if s.useTinnitus then
                start, duration = GetTinnitusCooldown()
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
                s.border:Hide()
            else
                s.icon:SetDesaturated(false)
                s.icon:SetAlpha(1.0)
                s.cooldown:SetCooldown(0, 0)
                s.timeText:SetText("")
                s.border:Show()
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
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:RegisterEvent("UNIT_AURA")

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

    elseif event == "PLAYER_ENTERING_WORLD" then
        ScanBags()
        UpdateCooldowns()

    elseif event == "BAG_UPDATE" then
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
