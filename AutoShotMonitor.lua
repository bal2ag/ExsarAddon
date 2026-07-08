-- AutoShotMonitor module
-- General auto-shot health readout (NOT melee-weave-specific — clipping bites a
-- plain Steady-Shot rotation from casts alone, and auto-repeat can be toggled
-- off on any fight). Two independent signals, both driven off the shared
-- auto-shot cycle tracker:
--   1. OVERDUE readout — a prominent visualization of how late the next auto is.
--      Reuses ExsarLogic.AutoShotDelay (same value RangedSwingTimer shows inline).
--      Red "CLIP" while a cast will finish past the due time (predicted); orange
--      "OVERDUE +x" once a shot is past due and hasn't fired (live counter — the
--      retry-timer window / a botched weave made visible).
--   2. REACTIVATE AUTO! alarm — fires when autos physically COULD fire (Auto Shot
--      in range) but auto-repeat is OFF: you disabled or forgot your auto shot.
--      Keyed on auto-repeat being off (not on overdue) so it never false-alarms
--      while kiting with auto-repeat still on.
--
-- Context-gated (solo/party/raid). The frame only draws when it has something to
-- say; silent otherwise. Settings stored under ExsarAddonDB.autoShotMonitor.

local ADDON_NAME = "ExsarAddon"

local asDB = ExsarUI.MakeDB("autoShotMonitor")

-- =========================================================
-- Constants
-- =========================================================

local POLL_INTERVAL = 0.05
local PULSE_HZ      = 2.0
local PULSE_LO      = 0.55
local PULSE_HI      = 1.0

local FRAME_W = 118
local FRAME_H = 84

-- Delay display thresholds (mirror RangedSwingTimer): predicted clips are
-- client-side math and trustworthy near zero; overdue readings lag the server
-- by event latency, so every normal cycle reads ~0.1s late right before
-- UNIT_SPELLCAST_SUCCEEDED arrives.
local CLIP_PREDICT_GRACE = 0.02
local CLIP_OVERDUE_GRACE = 0.2

local COLOR_CLIP     = { 1.0, 0.30, 0.30 }   -- predicted cast clip (red)
local COLOR_OVERDUE  = { 1.0, 0.65, 0.10 }   -- live overdue counter (orange)
local COLOR_REACT    = { 1.0, 0.15, 0.10 }   -- reactivate alarm (red)

local PREVIEW_ALPHA  = 0.45   -- dimmed static preview shown while unlocked

-- =========================================================
-- State
-- =========================================================

local S = {
    reactive = false,   -- REACTIVATE alarm currently shown (drives the pulse)
    pulseTime = 0,
    lastCaption = "",
    lastValue = "",
    lastRegimeRed = nil,
}

local tracker = ExsarUI.GetAutoShotTracker()

-- =========================================================
-- Frame + visuals
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "AutoShotMonitorFrame", UIParent)
frame:SetSize(FRAME_W, FRAME_H)
ExsarUI.SetupMovableFrame(frame, asDB, { bgAlpha = 0 })
frame:Hide()

-- Overdue caption (small, top) + value (big) — the prominent readout.
local captionText = frame:CreateFontString(nil, "OVERLAY")
captionText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
captionText:SetPoint("TOP", frame, "TOP", 0, -2)
captionText:SetTextColor(1, 0.65, 0.1, 1)
captionText:Hide()

local valueText = frame:CreateFontString(nil, "OVERLAY")
valueText:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
valueText:SetPoint("TOP", captionText, "BOTTOM", 0, -1)
valueText:SetTextColor(1, 0.65, 0.1, 1)
valueText:Hide()

-- REACTIVATE AUTO! alarm (below the overdue readout, pulsing) — wrapped to two
-- lines so the alarm doesn't force the whole widget wide.
local reactText = frame:CreateFontString(nil, "OVERLAY")
reactText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE, THICKOUTLINE")
reactText:SetPoint("TOP", valueText, "BOTTOM", 0, -4)
reactText:SetJustifyH("CENTER")
reactText:SetTextColor(COLOR_REACT[1], COLOR_REACT[2], COLOR_REACT[3], 1)
reactText:SetText("REACTIVATE\nAUTO!")
reactText:Hide()

-- =========================================================
-- Group context + target helpers
-- =========================================================

local function GetGroupContext()
    if IsInRaid() then return "raid" end
    if IsInGroup() then return "party" end
    return "solo"
end

local function ContextEnabled()
    local db = asDB()
    return ExsarLogic.AggroAlertEnabled(
        GetGroupContext(),
        db.enableSolo ~= false,
        db.enableParty ~= false,
        db.enableRaid ~= false
    )
end

local function HasAttackableTarget()
    return UnitExists("target") and not UnitIsDead("target")
        and UnitCanAttack("player", "target")
end

-- =========================================================
-- Update
-- =========================================================

-- Element setters, cache-guarded so repeated polls don't churn SetText.
local function SetOverdueDisplay(caption, value, red)
    if not caption then
        if S.lastValue ~= "" then S.lastValue = ""; valueText:Hide() end
        if S.lastCaption ~= "" then S.lastCaption = ""; captionText:Hide() end
        return
    end
    if red ~= S.lastRegimeRed then
        S.lastRegimeRed = red
        local c = red and COLOR_CLIP or COLOR_OVERDUE
        captionText:SetTextColor(c[1], c[2], c[3], 1)
        valueText:SetTextColor(c[1], c[2], c[3], 1)
    end
    if caption ~= S.lastCaption then
        S.lastCaption = caption
        captionText:SetText(caption)
        captionText:Show()
    end
    if value ~= S.lastValue then
        S.lastValue = value
        valueText:SetText(value)
        valueText:Show()
    end
end

local function SetReact(react)
    if react ~= S.reactive then
        S.reactive = react
        if react then
            S.pulseTime = 0.25
            reactText:SetAlpha(1)
            reactText:Show()
        else
            reactText:Hide()
        end
    end
end

local function HideAll()
    SetOverdueDisplay(nil)
    S.reactive = false
    reactText:Hide()
end

-- Static, dimmed preview shown while unlocked so the widget's real footprint is
-- visible for positioning (both signals rendered with example values).
local function ShowPreviewContent()
    SetOverdueDisplay("Auto overdue", "+1.3", false)
    S.reactive = false        -- static in preview: the pulse OnUpdate stays idle
    reactText:SetAlpha(1)
    reactText:Show()
end

-- Mode gate: run the full clear only on a transition, so steady-state polls of a
-- static preview don't hide-then-show (which would flicker).
local function EnterMode(mode)
    if S.mode == mode then return false end
    S.mode = mode
    HideAll()
    return true
end

local function UpdateDisplay()
    local unlocked  = not asDB().locked
    local hasTarget = HasAttackableTarget()
    local active    = ContextEnabled() and UnitAffectingCombat("player") and hasTarget

    if active then
        EnterMode("live")
        frame:SetAlpha(1)
        frame:Show()

        local now = GetTime()
        local delay, predicted = tracker:Overdue(now, CLIP_PREDICT_GRACE, CLIP_OVERDUE_GRACE)
        if delay then
            SetOverdueDisplay(predicted and "CLIP" or "Auto overdue",
                predicted and string.format("%.2f", delay) or string.format("+%.1f", delay),
                predicted and true or false)
        else
            SetOverdueDisplay(nil)
        end

        local autoInRange = IsSpellInRange(tracker.autoShotName, "target")
        SetReact(ExsarLogic.ShouldReactivateAuto(autoInRange, tracker.autoRepeatOn, hasTarget))

    elseif unlocked then
        if EnterMode("preview") then ShowPreviewContent() end
        frame:SetAlpha(PREVIEW_ALPHA)
        frame:Show()

    else
        EnterMode("hidden")
        frame:Hide()
    end
end

-- =========================================================
-- Pulse (reactivate alarm only — the overdue number stays steady/readable)
-- =========================================================

frame:SetScript("OnUpdate", function(_, elapsed)
    if not S.reactive then return end
    S.pulseTime = S.pulseTime + elapsed
    reactText:SetAlpha(ExsarLogic.PulseAlpha(S.pulseTime, PULSE_HZ, PULSE_LO, PULSE_HI))
end)

-- =========================================================
-- Polling + events
-- =========================================================

ExsarUI.CreatePoller(nil, POLL_INTERVAL, UpdateDisplay)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, asDB, 0, -280)
        if not asDB().locked then frame:Show() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateDisplay()
    end
end)

-- =========================================================
-- Slash sub-command
-- =========================================================

ExsarUI.AddSlashReset("autoshotreset", frame, asDB, "Auto shot monitor", 0, -280)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Auto Shot Monitor",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateCheckbox(parent, "Enable in solo", 16, y,
            function() return asDB().enableSolo ~= false end,
            function(v) asDB().enableSolo = v; UpdateDisplay() end
        )
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Enable in party", 16, y,
            function() return asDB().enableParty ~= false end,
            function(v) asDB().enableParty = v; UpdateDisplay() end
        )
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Enable in raid", 16, y,
            function() return asDB().enableRaid ~= false end,
            function(v) asDB().enableRaid = v; UpdateDisplay() end
        )
        y = y - 30

        y = ExsarUI.AddScaleSlider(parent, y, asDB, frame)
        y = ExsarUI.AddLockCheckbox(parent, y, asDB, frame, function()
            UpdateDisplay()
        end)
        y = ExsarUI.AddResetButton(parent, y, asDB, frame, "Auto shot monitor", 0, -280)
        return y
    end,
})
