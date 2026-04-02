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

-- Glow ring pulse parameters
local GLOW_PULSE_HZ  = 2.0
local GLOW_PULSE_MIN = 0.4
local GLOW_PULSE_MAX = 0.9

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

-- Glow sweep: a larger Cooldown frame behind the main one, driven by the same
-- timing so the pie-chart animation clips the glow effect identically.
local GLOW_SIZE = ICON_SIZE + 16
local glowSweepFrame = CreateFrame("Frame", nil, frame)
glowSweepFrame:SetSize(GLOW_SIZE, GLOW_SIZE)
glowSweepFrame:SetPoint("CENTER", sweepFrame, "CENTER")
glowSweepFrame:SetFrameLevel(sweepFrame:GetFrameLevel() - 1)

local glowCooldown = ExsarUI.CreateSweep(glowSweepFrame)
if glowCooldown.SetSwipeColor then
    glowCooldown:SetSwipeColor(0.5, 0.7, 1.0, 0.8)
end
if glowCooldown.SetSwipeTexture then
    glowCooldown:SetSwipeTexture(CIRCLE_MASK)
end
glowSweepFrame:Hide()

local glowActive = false

local glowPulseFrame = CreateFrame("Frame")
glowPulseFrame:SetScript("OnUpdate", function()
    if not glowActive then return end
    glowSweepFrame:SetAlpha(ExsarLogic.PulseAlpha(GetTime(), GLOW_PULSE_HZ, GLOW_PULSE_MIN, GLOW_PULSE_MAX))
end)

-- Main sweep (on top of glow)
local cooldown = ExsarUI.CreateSweep(sweepFrame)
if cooldown.SetSwipeColor then
    cooldown:SetSwipeColor(0.55, 0.55, 0.55, 0.95)
end
if cooldown.SetSwipeTexture then
    cooldown:SetSwipeTexture(CIRCLE_MASK)
end

-- Timer text frame (above the cooldown overlay)
local timerFrame = CreateFrame("Frame", nil, sweepFrame)
timerFrame:SetAllPoints()
timerFrame:SetFrameLevel(cooldown:GetFrameLevel() + 5)
local gcdTimerText = timerFrame:CreateFontString(nil, "OVERLAY")
gcdTimerText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
gcdTimerText:SetPoint("CENTER", sweepFrame, "CENTER", 0, 0)
gcdTimerText:SetTextColor(1, 1, 1, 1)
gcdTimerText:SetText("")

sweepFrame:Hide()

-- =========================================================
-- Runtime state
-- =========================================================

local lastGCDStart    = 0
local lastGCDDuration = 0
local C_locked        = false
local gcdColorState   = 0  -- 0=grey, 1=blue (spell queue)

local GREY_SWIPE = { 0.55, 0.55, 0.55, 0.95 }
local BLUE_SWIPE = { 0.3, 0.65, 1.0, 0.95 }

sweepFrame:SetScript("OnUpdate", function()
    if lastGCDStart > 0 and lastGCDDuration > 0 then
        local remaining = (lastGCDStart + lastGCDDuration) - GetTime()
        if remaining > 0 then
            gcdTimerText:SetText(string.format("%.1f", remaining))

            -- Change color during the spell queue window
            local sqw = (tonumber(GetCVar("SpellQueueWindow")) or 400) / 1000
            local newColor = remaining <= sqw and 1 or 0
            if newColor ~= gcdColorState and cooldown.SetSwipeColor then
                gcdColorState = newColor
                if newColor == 1 then
                    cooldown:SetSwipeColor(BLUE_SWIPE[1], BLUE_SWIPE[2], BLUE_SWIPE[3], BLUE_SWIPE[4])
                else
                    cooldown:SetSwipeColor(GREY_SWIPE[1], GREY_SWIPE[2], GREY_SWIPE[3], GREY_SWIPE[4])
                end
                -- Re-apply cooldown so the new color takes effect
                cooldown:SetCooldown(lastGCDStart, lastGCDDuration)
                glowCooldown:SetCooldown(lastGCDStart, lastGCDDuration)
            end
        else
            gcdTimerText:SetText("")
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
            glowCooldown:SetCooldown(start, duration)
            lastGCDStart = start
            lastGCDDuration = duration
        end
        movableBg:Hide()
        placeholderText:Hide()
        sweepFrame:Show()
        glowActive = true
        glowSweepFrame:Show()
        frame:Show()
    else
        lastGCDStart = 0
        lastGCDDuration = 0
        gcdColorState = 0
        if cooldown.SetSwipeColor then
            cooldown:SetSwipeColor(GREY_SWIPE[1], GREY_SWIPE[2], GREY_SWIPE[3], GREY_SWIPE[4])
        end
        cooldown:SetCooldown(0, 0)
        glowCooldown:SetCooldown(0, 0)
        gcdTimerText:SetText("")
        sweepFrame:Hide()
        glowActive = false
        glowSweepFrame:Hide()

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
