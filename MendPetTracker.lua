-- MendPetTracker module
-- Shows a single icon with a pulsating green glow and countdown timer when
-- Mend Pet is active on the player's pet.
-- Settings stored under ExsarAddonDB.mendPet.

local ADDON_NAME = "ExsarAddon"

local mpDB = ExsarUI.MakeDB("mendPet")

local MEND_PET_NAME = "Mend Pet"

-- =========================================================
-- Layout constants
-- =========================================================

local ICON_SIZE  = 29
local PADDING    = 6

-- Glow pulse
local PULSE_FREQ = 1.0   -- pulses per second
local PULSE_MIN  = 0.50
local PULSE_MAX  = 0.85

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "MendPetFrame", UIParent)
ExsarUI.SetupMovableFrame(frame, mpDB)

local placeholderText = frame:CreateFontString(nil, "OVERLAY")
placeholderText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
placeholderText:SetPoint("CENTER", frame, "CENTER", 0, 0)
placeholderText:SetTextColor(0.55, 0.55, 0.55, 0.9)
placeholderText:SetText("Mend Pet")
placeholderText:Hide()

frame:Hide()

local C_locked = false

-- =========================================================
-- Icon construction
-- =========================================================

local iconFrame = CreateFrame("Frame", nil, frame)
iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)

local glow = iconFrame:CreateTexture(nil, "BACKGROUND")
glow:SetPoint("TOPLEFT",     iconFrame, "TOPLEFT",     -3,  3)
glow:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT",  3, -3)
glow:SetColorTexture(0.3, 1.0, 0.4, 1.0)
glow:SetAlpha(0)

local icon = iconFrame:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local sweep = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
sweep:SetAllPoints()
sweep:SetDrawEdge(false)
if sweep.SetHideCountdownNumbers then
    sweep:SetHideCountdownNumbers(true)
end
if sweep.SetReverse then
    sweep:SetReverse(true)
end

local timeText = iconFrame:CreateFontString(nil, "OVERLAY")
timeText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
timeText:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
timeText:SetTextColor(1, 1, 1, 1)
timeText:SetText("")

iconFrame:EnableMouse(true)
iconFrame:SetScript("OnEnter", function(self)
    local spellId = select(7, GetSpellInfo(MEND_PET_NAME))
    if spellId then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(spellId)
        GameTooltip:Show()
    end
end)
iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

iconFrame:Hide()

-- =========================================================
-- State
-- =========================================================

local active    = false
local lastStr   = ""

-- =========================================================
-- Update
-- =========================================================

local function UpdateMendPet()
    local now = GetTime()
    local found = false

    if UnitExists("pet") then
        for i = 1, 40 do
            local bName, bIcon, _, _, bDuration, bExpTime = UnitBuff("pet", i)
            if not bName then break end
            if bName == MEND_PET_NAME then
                found  = true
                active = true
                icon:SetTexture(bIcon)
                iconFrame:Show()

                if bExpTime and bExpTime > 0 and bDuration and bDuration > 0 then
                    sweep:SetCooldown(bExpTime - bDuration, bDuration)
                else
                    sweep:SetCooldown(0, 0)
                end

                local remaining = bExpTime and bExpTime > 0 and math.max(0, bExpTime - now) or nil
                local newStr
                if not remaining then
                    newStr = ""
                else
                    newStr = ExsarLogic.FormatShortTimer(remaining)
                end
                if newStr ~= lastStr then
                    lastStr = newStr
                    timeText:SetText(newStr)
                end

                break
            end
        end
    end

    if not found then
        if active then
            active = false
            icon:SetTexture(nil)
            sweep:SetCooldown(0, 0)
            timeText:SetText("")
            lastStr = ""
            iconFrame:Hide()
        end

        if not C_locked then
            frame:SetSize(ICON_SIZE + PADDING * 2, ICON_SIZE + PADDING * 2)
            placeholderText:Show()
            frame:Show()
        else
            placeholderText:Hide()
            frame:Hide()
        end
        return
    end

    placeholderText:Hide()
    frame:SetSize(ICON_SIZE + PADDING * 2, ICON_SIZE + PADDING * 2)
    frame:Show()
end

-- =========================================================
-- Pulsating glow animation
-- =========================================================

local animTicker = CreateFrame("Frame")
animTicker:Show()
animTicker:SetScript("OnUpdate", function()
    if not active then
        glow:SetAlpha(0)
        return
    end
    local pulse = PULSE_MIN + (PULSE_MAX - PULSE_MIN) *
                  (0.5 + 0.5 * math.sin(GetTime() * 2 * math.pi * PULSE_FREQ))
    glow:SetAlpha(pulse)
end)

-- =========================================================
-- OnUpdate: timer text (every 0.1 s)
-- =========================================================

local scanElapsed = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    scanElapsed = scanElapsed + elapsed
    if scanElapsed >= 0.1 then
        scanElapsed = 0
        UpdateMendPet()
    end
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_AURA")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, mpDB, -340, 70)
        C_locked = mpDB().locked and true or false
        UpdateMendPet()

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateMendPet()

    elseif event == "UNIT_AURA" then
        if arg1 == "pet" then UpdateMendPet() end
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("mendpetreset", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", -340, 70)
    mpDB().x = nil
    mpDB().y = nil
    print(ADDON_NAME .. ": Mend Pet tracker position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Mend Pet Tracker",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, mpDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, mpDB, frame, function(v)
            C_locked = v
            UpdateMendPet()
        end)

        y = ExsarUI.AddResetButton(parent, y, mpDB, frame, "Mend Pet", -340, 70)

        return y
    end,
})
