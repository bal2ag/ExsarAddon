-- AmmoTracker module
-- Shows the equipped ammunition icon with a count overlay. Displays a red X
-- when no ammo is equipped. Pulses a red low-HP-style glow when ammo count
-- is 0 or <= 600 to remind the player to restock.
-- Settings stored under ExsarAddonDB.ammoTracker.

local ADDON_NAME = "ExsarAddon"

local aDB = ExsarUI.MakeDB("ammoTracker")

-- =========================================================
-- Constants
-- =========================================================

local ICON_SIZE       = 36
local PADDING         = 4
local FRAME_W         = ICON_SIZE + PADDING * 2
local FRAME_H         = ICON_SIZE + PADDING * 2
local LOW_AMMO_THRESH = 600
local AMMO_SLOT       = 0   -- inventory slot for ammo (paper doll slot 0)

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "AmmoTrackerFrame", UIParent)
frame:SetSize(FRAME_W, FRAME_H)
ExsarUI.SetupMovableFrame(frame, aDB)
frame:Hide()

-- =========================================================
-- Icon
-- =========================================================

local iconFrame = CreateFrame("Frame", nil, frame)
iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
iconFrame:SetPoint("CENTER", frame, "CENTER", 0, 0)

local icon = ExsarUI.CreateIcon(iconFrame)

-- Red X for no ammo
local redX1, redX2 = ExsarUI.CreateRedX(iconFrame)
redX1:Hide()
redX2:Hide()

-- Count text
local countText = iconFrame:CreateFontString(nil, "OVERLAY")
countText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
countText:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -1, 1)
countText:SetJustifyH("RIGHT")
countText:SetTextColor(1, 1, 1, 1)

-- =========================================================
-- Low-ammo warning (reuses CreateLowHpWarning)
-- =========================================================

local ShowLowAmmoWarning, HideLowAmmoWarning = ExsarUI.CreateLowHpWarning(frame)

-- =========================================================
-- State
-- =========================================================

local S = {
    hasAmmo   = false,
    ammoCount = 0,
    ammoId    = nil,
}

-- =========================================================
-- Update logic
-- =========================================================

local function UpdateAmmo()
    local itemId = GetInventoryItemID("player", AMMO_SLOT)
    local count  = GetInventoryItemCount("player", AMMO_SLOT)

    S.ammoId    = itemId
    S.ammoCount = count or 0
    S.hasAmmo   = itemId ~= nil

    if S.hasAmmo then
        -- Show icon texture
        local texture = GetInventoryItemTexture("player", AMMO_SLOT)
        if texture then
            icon:SetTexture(texture)
        end
        icon:SetDesaturated(false)
        icon:SetAlpha(1.0)

        -- Hide red X
        redX1:Hide()
        redX2:Hide()

        -- Show count
        countText:SetText(tostring(S.ammoCount))
        countText:Show()

        -- Low ammo warning
        if S.ammoCount <= LOW_AMMO_THRESH then
            ShowLowAmmoWarning()
        else
            HideLowAmmoWarning()
        end
    else
        -- No ammo equipped
        icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        icon:SetDesaturated(true)
        icon:SetAlpha(0.35)

        -- Show red X
        redX1:Show()
        redX2:Show()

        -- Hide count
        countText:Hide()

        -- Show warning (empty = bad)
        ShowLowAmmoWarning()
    end
end

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, aDB, 0, -100)
        frame:Show()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        UpdateAmmo()

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- arg1 is the equipment slot that changed
        if arg1 == AMMO_SLOT then
            UpdateAmmo()
        end

    elseif event == "BAG_UPDATE" then
        -- Ammo count can change when bags change
        UpdateAmmo()
    end
end)

-- Safety-net poll (catches edge cases like vendor purchases)
ExsarUI.CreatePoller(nil, 1.0, UpdateAmmo)

-- =========================================================
-- Slash sub-command
-- =========================================================

ExsarUI.AddSlashReset("ammoreset", frame, aDB, "Ammo tracker", 0, -100)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Ammo Tracker",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, aDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, aDB, frame)

        y = ExsarUI.AddResetButton(parent, y, aDB, frame, "Ammo tracker", 0, -100)

        return y
    end,
})
