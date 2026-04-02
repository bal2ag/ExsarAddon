-- RotationHelper module
-- Shows the current effective weapon speed and suggested rotation.
-- Two lines of text: speed on top (e.g. "1.23s"), rotation below (e.g. "1:1").
-- Settings stored under ExsarAddonDB.rotationHelper.

local ADDON_NAME = "ExsarAddon"

local rDB = ExsarUI.MakeDB("rotationHelper")

-- =========================================================
-- Constants
-- =========================================================

local FRAME_W = 56
local FRAME_H = 34
local PADDING = 4

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "RotationHelperFrame", UIParent)
frame:SetSize(FRAME_W, FRAME_H)
local movableBg = ExsarUI.SetupMovableFrame(frame, rDB)
frame:Show()

local placeholderText = ExsarUI.CreatePlaceholder(frame, "Rot")

-- =========================================================
-- Text elements
-- =========================================================

-- Speed text (top line)
local speedText = frame:CreateFontString(nil, "OVERLAY")
speedText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
speedText:SetPoint("TOP", frame, "TOP", 0, -PADDING)
speedText:SetTextColor(0.9, 0.9, 0.9, 1)

-- Rotation text (bottom line, larger/bolder)
local rotText = frame:CreateFontString(nil, "OVERLAY")
rotText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
rotText:SetPoint("TOP", speedText, "BOTTOM", 0, -1)
rotText:SetTextColor(1, 0.82, 0, 1) -- gold

-- =========================================================
-- State
-- =========================================================

local S = {
    speed    = 0,
    lastRot  = "",
    locked   = false,
}

-- =========================================================
-- Update
-- =========================================================

local function UpdateDisplay()
    local speed = select(1, UnitRangedDamage("player"))
    S.speed = (type(speed) == "number" and speed > 0) and speed or 0

    if S.speed <= 0 then
        speedText:Hide()
        rotText:Hide()
        if not S.locked then
            placeholderText:Show()
            movableBg:Show()
            frame:Show()
        else
            frame:Hide()
        end
        return
    end

    placeholderText:Hide()
    movableBg:Hide()
    frame:Show()

    speedText:SetText(string.format("%.2fs", S.speed))
    speedText:Show()

    local rot = ExsarLogic.SuggestRotation(S.speed)
    rotText:SetText(rot)
    rotText:Show()
end

-- =========================================================
-- Polling fallback: UnitRangedDamage can lag behind events
-- (e.g. Rapid Fire fading reports stale speed on UNIT_AURA).
-- Poll every 1s as a cheap safety net.
-- =========================================================

local pollElapsed = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    pollElapsed = pollElapsed + elapsed
    if pollElapsed < 1 then return end
    pollElapsed = 0
    UpdateDisplay()
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("UNIT_ATTACK_SPEED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("BAG_UPDATE")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, rDB, 0, -250)
        S.locked = rDB().locked and true or false
        UpdateDisplay()

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateDisplay()

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then
            UpdateDisplay()
        end

    elseif event == "UNIT_ATTACK_SPEED" then
        if arg1 == "player" then
            UpdateDisplay()
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE" then
        UpdateDisplay()
    end
end)

-- =========================================================
-- Slash sub-command
-- =========================================================

ExsarUI.AddSlashReset("rotreset", frame, rDB, "Rotation helper", 0, -250)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Rotation Helper",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, rDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, rDB, frame, function(v)
            S.locked = v
            UpdateDisplay()
        end)

        y = ExsarUI.AddResetButton(parent, y, rDB, frame, "Rotation helper", 0, -250)

        return y
    end,
})
