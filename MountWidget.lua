-- MountWidget module
-- Shows two mount icons side by side.  Icons are greyed when the mount item
-- is not in the player's bags.  A yellow glow highlights whichever mount is
-- currently active (buff is present on the player).
-- Settings stored under ExsarAddonDB.mountWidget.

local ADDON_NAME = "ExsarAddon"

local mwDB = ExsarUI.MakeDB("mountWidget")

-- =========================================================
-- Mount definitions
-- =========================================================

local TRACKED_MOUNTS = {
    { name = "Reins of the Swift Stormsaber", id = 18902,  buffId = 23338   },
    { name = "Starshard Netherdrake",         id = 260759, buffId = 1266866 },
}

-- =========================================================
-- Layout constants
-- =========================================================

local ICON_SIZE = 29
local ICON_GAP  = 4
local PADDING   = 6

local NUM_MOUNTS = #TRACKED_MOUNTS
local GRID_W = NUM_MOUNTS * ICON_SIZE + (NUM_MOUNTS - 1) * ICON_GAP + PADDING * 2
local GRID_H = ICON_SIZE + PADDING * 2

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "MountFrame", UIParent)
ExsarUI.SetupMovableFrame(frame, mwDB)

frame:Hide()

-- =========================================================
-- Slot construction
-- =========================================================

-- Request item data for mounts not yet in the client cache.
if C_Item and C_Item.RequestLoadItemDataByID then
    for _, mount in ipairs(TRACKED_MOUNTS) do
        C_Item.RequestLoadItemDataByID(mount.id)
    end
end

local slots = {}

for i, mount in ipairs(TRACKED_MOUNTS) do
    local s = {
        itemId     = mount.id,
        itemName   = mount.name,
        buffId     = mount.buffId,
        count      = -1,
        known      = false,
        buffActive = false,
    }

    s.iconFrame = CreateFrame("Button", ADDON_NAME .. "MountBtn" .. i, frame,
                              "SecureActionButtonTemplate")
    s.iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
    s.iconFrame:RegisterForClicks("AnyUp", "AnyDown")
    s.iconFrame:SetAttribute("type", "item")
    s.iconFrame:SetAttribute("item", mount.name)
    s.iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT",
        PADDING + (i - 1) * (ICON_SIZE + ICON_GAP), -PADDING)
    s.iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(s.itemId)
        GameTooltip:Show()
    end)
    s.iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Active Glow: extends 4 px beyond icon; slotBg (opaque, created after) covers
    -- the center so only the outer ring shows as yellow.
    s.glow = ExsarUI.CreateGlow(s.iconFrame, 1, 0.85, 0, 0.70)

    local slotBg = s.iconFrame:CreateTexture(nil, "BACKGROUND")
    slotBg:SetAllPoints()
    slotBg:SetColorTexture(0, 0, 0, 1.0)

    s.icon = ExsarUI.CreateIcon(s.iconFrame)

    local iconTex = select(10, GetItemInfo(mount.id))
    if iconTex then s.icon:SetTexture(iconTex) end

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
        end

        if not s.icon:GetTexture() then
            local tex = select(10, GetItemInfo(s.itemId))
            if tex then s.icon:SetTexture(tex) end
        end

        s.icon:SetDesaturated(not s.known)
        s.icon:SetAlpha(s.known and 1.0 or 0.35)
    end
end

-- =========================================================
-- Mount buff detection
-- =========================================================

local function UpdateMounts()
    local activeById = {}
    for i = 1, 40 do
        local bName, _, _, _, _, _, _, _, _, bSpellId = UnitBuff("player", i)
        if not bName then break end
        if bSpellId then activeById[bSpellId] = true end
    end

    for _, s in ipairs(slots) do
        local isActive = activeById[s.buffId] and true or false
        if isActive ~= s.buffActive then
            s.buffActive = isActive
            if isActive then
                s.glow:Show()
            else
                s.glow:Hide()
            end
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
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, mwDB, 150, -240)
        ApplyLayout()

    elseif event == "PLAYER_ENTERING_WORLD" then
        ScanBags()
        UpdateMounts()

    elseif event == "PLAYER_ALIVE" then
        ScanBags()
        UpdateMounts()

    elseif event == "BAG_UPDATE" then
        ScanBags()

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then UpdateMounts() end

    elseif event == "ITEM_DATA_LOAD_RESULT" then
        ScanBags()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("mountreset", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 150, -240)
    mwDB().x = nil
    mwDB().y = nil
    print(ADDON_NAME .. ": Mount widget position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Mount Widget",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, mwDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, mwDB, frame)

        y = ExsarUI.AddResetButton(parent, y, mwDB, frame, "Mounts", 150, -240)

        return y
    end,
})
