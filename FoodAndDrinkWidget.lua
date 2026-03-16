-- FoodAndDrinkWidget module
-- Shows a horizontal row of icons for tracked food and drink items.
-- Click an icon to use the item.  Icons are greyed and show "0" when
-- the item is not in the player's bags.  No cooldown tracking.
-- Settings stored under ExsarAddonDB.foodDrink.

local ADDON_NAME = "ExsarAddon"

local fdDB = ExsarUI.MakeDB("foodDrink")

-- =========================================================
-- Item definitions
-- =========================================================

local TRACKED_ITEMS = {
    { name = "Conjured Manna Biscuit", id = 34062 },
    { name = "Purified Draenic Water", id = 27860 },
    { name = "Clefthoof Ribs",         id = 29451 },
}

-- =========================================================
-- Layout constants
-- =========================================================

local ICON_SIZE = 29
local ICON_GAP  = 4
local PADDING   = 6

local NUM_ITEMS = #TRACKED_ITEMS
local GRID_W = NUM_ITEMS * ICON_SIZE + (NUM_ITEMS - 1) * ICON_GAP + PADDING * 2
local GRID_H = ICON_SIZE + PADDING * 2

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "FoodDrinkFrame", UIParent)
ExsarUI.SetupMovableFrame(frame, fdDB)

frame:Hide()

local C_locked = false
local C_inCombat = false

-- =========================================================
-- Slot construction
-- =========================================================

local slots = {}

for i, item in ipairs(TRACKED_ITEMS) do
    local s = {
        itemId   = item.id,
        itemName = item.name,
        count    = -1,
        known    = false,
    }

    s.iconFrame = CreateFrame("Button", ADDON_NAME .. "FoodBtn" .. i, frame,
                              "SecureActionButtonTemplate")
    s.iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
    -- Both AnyUp and AnyDown required for TBC Classic Anniversary.
    s.iconFrame:RegisterForClicks("AnyUp", "AnyDown")
    s.iconFrame:SetAttribute("type", "item")
    s.iconFrame:SetAttribute("item", item.name)
    s.iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(s.itemId)
        GameTooltip:Show()
    end)
    s.iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    s.iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT",
        PADDING + (i - 1) * (ICON_SIZE + ICON_GAP), -PADDING)

    -- Fully opaque slot background so the icon is visible against dark bg.
    local slotBg = s.iconFrame:CreateTexture(nil, "BACKGROUND")
    slotBg:SetAllPoints()
    slotBg:SetColorTexture(0, 0, 0, 1.0)

    s.icon = s.iconFrame:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints()
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Pre-load icon if item data is already cached.
    local iconTex = select(10, GetItemInfo(item.id))
    if iconTex then s.icon:SetTexture(iconTex) end

    -- Stack count (bottom-right corner)
    s.countText = s.iconFrame:CreateFontString(nil, "OVERLAY")
    s.countText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    s.countText:SetPoint("BOTTOMRIGHT", s.iconFrame, "BOTTOMRIGHT", 1, 1)
    s.countText:SetTextColor(1, 1, 0.8, 1)
    s.countText:SetText("")

    s.iconFrame:Show()
    slots[#slots + 1] = s
end

-- =========================================================
-- Layout
-- =========================================================

local function ApplyLayout()
    frame:SetSize(GRID_W, GRID_H)
    frame:Show()
end

-- =========================================================
-- Bag scanning
-- =========================================================

local function ScanBags()
    for _, s in ipairs(slots) do
        local count = GetItemCount(s.itemId)
        s.known = count > 0

        if count ~= s.count then
            s.count = count
            s.countText:SetText(count == 0 and "0" or tostring(count))
        end

        -- Retry icon load if GetItemInfo wasn't cached at slot-creation time.
        if not s.icon:GetTexture() then
            local tex = select(10, GetItemInfo(s.itemId))
            if tex then s.icon:SetTexture(tex) end
        end

        if not s.known then
            s.icon:SetDesaturated(true)
            s.icon:SetAlpha(0.35)
        elseif C_inCombat then
            s.icon:SetDesaturated(false)
            s.icon:SetAlpha(0.5)
        else
            s.icon:SetDesaturated(false)
            s.icon:SetAlpha(1.0)
        end
    end
end

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, fdDB, 150, -200)
        C_locked = fdDB().locked and true or false
        ApplyLayout()

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_inCombat = InCombatLockdown()
        ScanBags()

    elseif event == "PLAYER_ALIVE" then
        ScanBags()

    elseif event == "BAG_UPDATE" then
        ScanBags()

    elseif event == "PLAYER_REGEN_DISABLED" then
        C_inCombat = true
        ScanBags()

    elseif event == "PLAYER_REGEN_ENABLED" then
        C_inCombat = false
        ScanBags()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("foodreset", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 150, -200)
    fdDB().x = nil
    fdDB().y = nil
    print(ADDON_NAME .. ": Food and drink widget position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Food & Drink",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, fdDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, fdDB, frame)

        y = ExsarUI.AddResetButton(parent, y, fdDB, frame, "Food and drink", 150, -200)

        return y
    end,
})
