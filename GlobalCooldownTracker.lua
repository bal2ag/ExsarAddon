-- GlobalCooldownTracker module
-- Shows a sweep effect during the Global Cooldown.
-- Useful for timing abilities like Steady Shot during rotations.
-- Settings are stored under ExsarAddonDB.globalCooldown.

local ADDON_NAME = "ExsarAddon"

local gDB = ExsarUI.MakeDB("globalCooldown")

-- =========================================================
-- Constants
-- =========================================================

-- Wing Clip has no cooldown of its own, so GetSpellCooldown only
-- ever returns the GCD when it's active.
local GCD_PROBE_SPELL = "Wing Clip"

local ICON_SIZE = 29
local PADDING   = 6

local CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- =========================================================
-- Frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "GCDFrame", UIParent)
frame:SetSize(ICON_SIZE + PADDING * 2, ICON_SIZE + PADDING * 2)
local movableBg = ExsarUI.SetupMovableFrame(frame, gDB)
movableBg:Hide()
frame:Hide()

local placeholderText = ExsarUI.CreatePlaceholder(frame, "GCD")

-- =========================================================
-- Sweep area (just the cooldown sweep, no background)
-- =========================================================

local sweepFrame = CreateFrame("Frame", nil, frame)
sweepFrame:SetSize(ICON_SIZE, ICON_SIZE)
sweepFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)

-- The swept material is a solid, fully-opaque circle — white while the GCD is
-- running, light blue during the spell-queue window. The shrinking pie is the
-- whole indicator (no glow, no timer text): it shrinks and vanishes with the GCD.
local cooldown = ExsarUI.CreateSweep(sweepFrame)
if cooldown.SetSwipeColor then
    cooldown:SetSwipeColor(1, 1, 1, 1)
end
if cooldown.SetSwipeTexture then
    cooldown:SetSwipeTexture(CIRCLE_MASK)
end
-- Suppress the "bling" flash the cooldown plays when it finishes (the "woosh").
if cooldown.SetDrawBling then
    cooldown:SetDrawBling(false)
end

sweepFrame:Hide()

-- =========================================================
-- Runtime state
-- =========================================================

local lastGCDStart    = 0
local lastGCDDuration = 0
local C_locked        = false
local gcdColorState   = 0  -- 0=white, 1=light blue (spell queue)

local WHITE_SWIPE = { 1, 1, 1, 1 }
local BLUE_SWIPE  = { 0.45, 0.72, 1.0, 1 }

sweepFrame:SetScript("OnUpdate", function()
    if lastGCDStart > 0 and lastGCDDuration > 0 then
        local remaining = (lastGCDStart + lastGCDDuration) - GetTime()
        if remaining > 0 then
            -- Change color during the spell queue window
            local sqw = (tonumber(GetCVar("SpellQueueWindow")) or 400) / 1000
            local newColor = remaining <= sqw and 1 or 0
            if newColor ~= gcdColorState and cooldown.SetSwipeColor then
                gcdColorState = newColor
                local c = newColor == 1 and BLUE_SWIPE or WHITE_SWIPE
                cooldown:SetSwipeColor(c[1], c[2], c[3], c[4])
                -- Re-apply cooldown so the new color takes effect
                cooldown:SetCooldown(lastGCDStart, lastGCDDuration)
            end
        end
    end
end)

local function UpdateGCD()
    local start, duration = GetSpellCooldown(GCD_PROBE_SPELL)
    local onGCD = start and start > 0 and duration and duration > 0

    if onGCD then
        -- New GCD detected when start time changes
        if start ~= lastGCDStart then
            cooldown:SetCooldown(start, duration)
            lastGCDStart = start
            lastGCDDuration = duration
        end
        movableBg:Hide()
        placeholderText:Hide()
        sweepFrame:Show()
        frame:Show()
    else
        lastGCDStart = 0
        lastGCDDuration = 0
        gcdColorState = 0
        if cooldown.SetSwipeColor then
            cooldown:SetSwipeColor(WHITE_SWIPE[1], WHITE_SWIPE[2], WHITE_SWIPE[3], WHITE_SWIPE[4])
        end
        cooldown:SetCooldown(0, 0)
        sweepFrame:Hide()

        if not C_locked then
            movableBg:Show()
            placeholderText:Show()
            frame:Show()
        else
            movableBg:Hide()
            placeholderText:Hide()
            frame:Hide()
        end
    end
end

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, gDB, 0, -200)
        C_locked = gDB().locked and true or false
        UpdateGCD()

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateGCD()

    elseif event == "SPELL_UPDATE_COOLDOWN" then
        UpdateGCD()
    end
end)

-- =========================================================
-- Slash sub-command
-- =========================================================

ExsarUI.AddSlashReset("gcdreset", frame, gDB, "GCD tracker", 0, -200)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Global Cooldown Tracker",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, gDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, gDB, frame, function(v)
            C_locked = v
            UpdateGCD()
        end)

        y = ExsarUI.AddResetButton(parent, y, gDB, frame, "GCD tracker", 0, -200)

        return y
    end,
})
