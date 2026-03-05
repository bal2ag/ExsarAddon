-- MountWidget module
-- Shows two mount icons side by side.  Icons are greyed when the mount item
-- is not in the player's bags.  A yellow glow highlights whichever mount is
-- currently active (buff is present on the player).
-- Settings stored under ExsarAddonDB.mountWidget.

local ADDON_NAME = "ExsarAddon"

local function mwDB()
    ExsarAddonDB.mountWidget = ExsarAddonDB.mountWidget or {}
    return ExsarAddonDB.mountWidget
end

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
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    mwDB().x = x
    mwDB().y = y
end)

local frameBg = frame:CreateTexture(nil, "BACKGROUND")
frameBg:SetAllPoints()
frameBg:SetColorTexture(0, 0, 0, 0.6)

frame:Hide()

local C_locked = false

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

    -- Glow: extends 4 px beyond icon; slotBg (opaque, created after) covers
    -- the center so only the outer ring shows as yellow.
    s.glow = s.iconFrame:CreateTexture(nil, "BACKGROUND")
    s.glow:SetPoint("TOPLEFT",     s.iconFrame, "TOPLEFT",     -4,  4)
    s.glow:SetPoint("BOTTOMRIGHT", s.iconFrame, "BOTTOMRIGHT",  4, -4)
    s.glow:SetColorTexture(1, 0.85, 0, 0.70)
    s.glow:Hide()

    local slotBg = s.iconFrame:CreateTexture(nil, "BACKGROUND")
    slotBg:SetAllPoints()
    slotBg:SetColorTexture(0, 0, 0, 1.0)

    s.icon = s.iconFrame:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints()
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

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
        local db = mwDB()
        if db.x and db.y then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        else
            self:SetPoint("CENTER", UIParent, "CENTER", 150, -240)
        end
        self:SetScale(db.scale or 1.0)
        self:EnableMouse(not db.locked)
        C_locked = db.locked and true or false
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
        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return mwDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                mwDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return mwDB().locked and true or false end,
            function(v)
                mwDB().locked = v
                C_locked = v
                frame:EnableMouse(not v)
            end
        )
        y = y - 30

        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 150, -240)
            mwDB().x = nil
            mwDB().y = nil
            print(ADDON_NAME .. ": Mount widget position reset.")
        end)
        y = y - 30

        return y
    end,
})
