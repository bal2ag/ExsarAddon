-- PetAggressiveAlert module
-- Shows a pulsing red skull icon with "PET ON AGGRESSIVE!" text when the
-- player's pet is set to aggressive mode. Always visible when unlocked for
-- positioning. Settings stored under ExsarAddonDB.petAggressiveAlert.

local ADDON_NAME = "ExsarAddon"

local aDB = ExsarUI.MakeDB("petAggressiveAlert")

-- =========================================================
-- Constants
-- =========================================================

local SKULL_SIZE   = 40
local TEXT_GAP     = 2
local FRAME_W      = 120
local FRAME_H      = 80
local PULSE_HZ     = 1.0
local PULSE_LO     = 0.55
local PULSE_HI     = 1.0

-- Raid skull icon (built-in texture)
local SKULL_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

-- =========================================================
-- State
-- =========================================================

local S = {
    active    = false,
    pulseTime = 0,
}

-- =========================================================
-- Pet-aggressive detection
-- =========================================================

local function IsPetAggressive()
    if not UnitExists("pet") then return false end
    -- Scan the pet action bar for the aggressive stance
    for i = 1, 10 do
        local name, _, _, isActive = GetPetActionInfo(i)
        if name == "PET_MODE_AGGRESSIVE" then
            return isActive and true or false
        end
    end
    return false
end

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "PetAggressiveAlertFrame", UIParent)
frame:SetSize(FRAME_W, FRAME_H)
ExsarUI.SetupMovableFrame(frame, aDB, { bgAlpha = 0 })
frame:Hide()

-- =========================================================
-- Visuals
-- =========================================================

-- Red-tinted background for emphasis
local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0.3, 0, 0, 0.5)

-- Skull icon
local skull = frame:CreateTexture(nil, "ARTWORK")
skull:SetSize(SKULL_SIZE, SKULL_SIZE)
skull:SetPoint("TOP", frame, "TOP", 0, -4)
skull:SetTexture(SKULL_TEXTURE)
skull:SetVertexColor(1, 0.15, 0.15)

-- "AGGRESSIVE!" text
local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
text:SetPoint("TOP", skull, "BOTTOM", 0, -TEXT_GAP)
text:SetPoint("LEFT", frame, "LEFT", 4, 0)
text:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
text:SetWordWrap(true)
text:SetJustifyH("CENTER")
text:SetText("PET ON AGGRESSIVE!")
text:SetTextColor(1, 0.2, 0.2, 1)

-- =========================================================
-- Visibility logic
-- =========================================================

local function UpdateVisibility()
    if aDB().disabled then
        frame:Hide()
        return
    end
    S.active = IsPetAggressive()
    local shouldShow = S.active or not aDB().locked
    if shouldShow then
        if not frame:IsShown() then
            S.pulseTime = 0.25
        end
        frame:Show()
    else
        frame:Hide()
    end
end

-- =========================================================
-- Pulse animation
-- =========================================================

frame:SetScript("OnUpdate", function(self, elapsed)
    S.pulseTime = S.pulseTime + elapsed
    frame:SetAlpha(ExsarLogic.PulseAlpha(S.pulseTime, PULSE_HZ, PULSE_LO, PULSE_HI))
end)

-- =========================================================
-- Safety-net poll (catches missed events)
-- =========================================================

local pollFrame = ExsarUI.CreatePoller(nil, 0.5, UpdateVisibility)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PET_BAR_UPDATE")
frame:RegisterEvent("UNIT_PET")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, aDB, 0, 50)
        if not aDB().locked then
            S.pulseTime = 0.25
            frame:Show()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateVisibility()

    elseif event == "PET_BAR_UPDATE" then
        UpdateVisibility()

    elseif event == "UNIT_PET" then
        if arg1 == "player" then UpdateVisibility() end
    end
end)

-- =========================================================
-- Slash sub-command
-- =========================================================

ExsarUI.AddSlashReset("aggressivereset", frame, aDB, "Pet Aggressive alert", 0, 50)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Pet Aggressive Alert",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateCheckbox(parent, "Enable alert", 16, y,
            function() return not aDB().disabled end,
            function(v)
                aDB().disabled = not v
                UpdateVisibility()
            end
        )
        y = y - 30

        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return aDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                aDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return aDB().locked and true or false end,
            function(v)
                aDB().locked = v
                frame:EnableMouse(not v)
                UpdateVisibility()
            end
        )
        y = y - 30

        y = ExsarUI.AddResetButton(parent, y, aDB, frame, "Pet Aggressive alert", 0, 50)

        return y
    end,
})
