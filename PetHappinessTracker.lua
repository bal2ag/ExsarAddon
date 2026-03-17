-- PetHappinessTracker module
-- Granular happiness gauge that estimates exact happiness points (0-1050) by
-- tracking passive decay, feeding bites, pet death, and dismiss events.
-- The WoW API only exposes the tier (1-3), so we seed at mid-tier and refine
-- via combat log events and tier-boundary corrections.
-- Settings stored under ExsarAddonDB.petHappiness.

local ADDON_NAME = "ExsarAddon"

local hDB = ExsarUI.MakeDB("petHappiness")

-- =========================================================
-- Happiness model constants (reverse-engineered)
-- =========================================================

local TIER_SIZE     = 350          -- points per tier
local MAX_HAPPINESS = TIER_SIZE * 3  -- 1050
local DECAY_PER_MIN = 50 / 6      -- ~8.33 pts/min (50 per 6 min)
-- Feed per bite varies by food quality: 8, 17, or 35 per bite.
-- We read the actual amount from the combat log rather than assuming.
local DEATH_LOSS    = 350          -- one full tier
local DISMISS_LOSS  = 50

-- Tier boundaries: [0,350) = unhappy, [350,700) = content, [700,1050] = happy
local TIER_MIN = { [1] = 0, [2] = 350, [3] = 700 }
local TIER_MAX = { [1] = 349, [2] = 699, [3] = 1050 }

-- =========================================================
-- Layout constants
-- =========================================================

local ICON_SIZE = 36
local FRAME_SIZE = ICON_SIZE + 4

-- Happiness icon texture (3 icons packed horizontally)
local HAPPINESS_TEXTURE = "Interface\\PetPaperDollFrame\\UI-PetHappiness"
local HAPPINESS_COORDS = {
    [1] = { 0.375, 0.5625, 0, 0.359375 },  -- Unhappy
    [2] = { 0.1875, 0.375, 0, 0.359375 },   -- Content
    [3] = { 0, 0.1875, 0, 0.359375 },        -- Happy
}

local TIER_BELOW_LABELS = {
    [2] = "Unhappy",
    [3] = "Content",
}

-- =========================================================
-- State
-- =========================================================

local S = {
    estimate     = 0,       -- current estimated happiness points
    tier         = 0,       -- current API tier (1/2/3)
    lastUpdate   = GetTime(), -- GetTime() of last decay tick
    petActive    = false,   -- whether pet is currently out
    initialized  = false,   -- true after ADDON_LOADED has fired
    anchored     = false,   -- true once we know the exact value
}

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "PetHappinessFrame", UIParent)
frame:SetSize(FRAME_SIZE, FRAME_SIZE)
ExsarUI.SetupMovableFrame(frame, hDB, { bgAlpha = 0 })
frame:Hide()

-- =========================================================
-- Visuals
-- =========================================================

-- Icon container (for sweep to overlay on)
local iconFrame = CreateFrame("Frame", nil, frame)
iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
iconFrame:SetPoint("CENTER", frame, "CENTER", 0, 0)

-- Happiness icon
local icon = iconFrame:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()
icon:SetTexture(HAPPINESS_TEXTURE)

-- Red pulsing glow (4 edges) for content/unhappy warning
local GLOW_SIZE = 3
local GLOW_PULSE_HZ  = 1.2
local GLOW_PULSE_MIN = 0.45
local GLOW_PULSE_MAX = 1.0
local PulseAlpha = ExsarLogic.PulseAlpha

local glow = {}
local function MakeGlowEdge(p1, r1, p2, r2, isHoriz)
    local tex = iconFrame:CreateTexture(nil, "BACKGROUND")
    tex:SetColorTexture(0.90, 0.15, 0.15, 0.85)
    tex:SetPoint(p1, iconFrame, r1)
    tex:SetPoint(p2, iconFrame, r2)
    if isHoriz then tex:SetHeight(GLOW_SIZE) else tex:SetWidth(GLOW_SIZE) end
    tex:Hide()
    return tex
end
glow[1] = MakeGlowEdge("TOPLEFT", "TOPLEFT", "TOPRIGHT", "TOPRIGHT", true)
glow[1]:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
glow[1]:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", GLOW_SIZE, GLOW_SIZE)
glow[2] = MakeGlowEdge("BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT", true)
glow[2]:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", -GLOW_SIZE, -GLOW_SIZE)
glow[2]:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
glow[3] = MakeGlowEdge("TOPLEFT", "TOPLEFT", "BOTTOMLEFT", "BOTTOMLEFT", false)
glow[3]:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
glow[3]:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", -GLOW_SIZE, -GLOW_SIZE)
glow[4] = MakeGlowEdge("TOPRIGHT", "TOPRIGHT", "BOTTOMRIGHT", "BOTTOMRIGHT", false)
glow[4]:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", GLOW_SIZE, GLOW_SIZE)
glow[4]:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)

local glowActive = false

-- Reverse sweep: starts clear (100%) and fills with grey as it drains to 0%
local sweep = ExsarUI.CreateSweep(iconFrame, { reverse = true })

-- Glow pulse animation
local glowPulseFrame = CreateFrame("Frame")
glowPulseFrame:SetScript("OnUpdate", function()
    if not glowActive then return end
    local alpha = PulseAlpha(GetTime(), GLOW_PULSE_HZ, GLOW_PULSE_MIN, GLOW_PULSE_MAX)
    for _, tex in ipairs(glow) do tex:SetAlpha(alpha) end
end)

-- Timer text (above the sweep)
local textFrame = CreateFrame("Frame", nil, iconFrame)
textFrame:SetAllPoints()
textFrame:SetFrameLevel(sweep:GetFrameLevel() + 5)
local text = textFrame:CreateFontString(nil, "OVERLAY")
text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
text:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)

-- Sweep state: track the last cooldown we set to avoid re-applying unnecessarily
local lastSweepStart = 0
local lastSweepDuration = 0

-- =========================================================
-- Estimate management
-- =========================================================

local function FormatTime(seconds)
    if seconds >= 60 then
        return math.ceil(seconds / 60) .. "m"
    elseif seconds >= 10 then
        return math.ceil(seconds) .. "s"
    else
        return string.format("%.1fs", seconds)
    end
end

local function ClampEstimate()
    if S.estimate < 0 then S.estimate = 0 end
    if S.estimate > MAX_HAPPINESS then S.estimate = MAX_HAPPINESS end
end

local function SaveEstimate()
    if S.tier == 0 then return end  -- don't overwrite good data with uninitialized state
    local db = hDB()
    db.savedEstimate = S.estimate
    db.savedTier = S.tier
    db.savedAnchored = S.anchored
end

local function SeedEstimate()
    local happiness = GetPetHappiness()
    if not happiness then
        S.estimate = 0
        S.tier = 0
        S.anchored = false
        return
    end
    S.tier = happiness

    -- Try to restore from saved data
    local db = hDB()
    if db.savedEstimate and db.savedTier then
        if db.savedTier == happiness then
            -- Saved tier matches — use the saved estimate (no offline decay)
            S.estimate = db.savedEstimate
            S.anchored = db.savedAnchored or false
            -- Ensure still within tier bounds
            if S.estimate < TIER_MIN[happiness] then
                S.estimate = TIER_MIN[happiness]
            elseif S.estimate > TIER_MAX[happiness] then
                S.estimate = TIER_MAX[happiness]
            end
        else
            -- Tier changed while logged out — anchor at boundary
            if db.savedTier > happiness then
                -- Dropped tier(s): set to top of new tier
                S.estimate = TIER_MAX[happiness]
            else
                -- Gained tier(s): set to bottom of new tier
                S.estimate = TIER_MIN[happiness]
            end
            S.anchored = true
            SaveEstimate()
        end
    else
        -- No saved data — guess midpoint
        S.estimate = TIER_MIN[happiness] + TIER_SIZE / 2
        S.anchored = false
    end
    S.lastUpdate = GetTime()
end

local function CorrectToTier()
    -- If the API tier disagrees with our estimate's tier, snap to boundary
    local happiness = GetPetHappiness()
    if not happiness then return end

    local oldTier = S.tier
    S.tier = happiness

    if happiness ~= oldTier then
        -- Tier changed — we know the exact value at the boundary
        if happiness > oldTier then
            S.estimate = TIER_MIN[happiness]
        else
            S.estimate = TIER_MAX[happiness]
        end
        S.anchored = true
        SaveEstimate()
    else
        -- Same tier — make sure estimate stays within tier bounds
        if S.estimate < TIER_MIN[happiness] then
            S.estimate = TIER_MIN[happiness]
        elseif S.estimate > TIER_MAX[happiness] then
            S.estimate = TIER_MAX[happiness]
        end
    end
end

-- =========================================================
-- Display update
-- =========================================================

local function UpdateVisuals()
    if not S.petActive then
        glowActive = false
        for _, tex in ipairs(glow) do tex:Hide() end
        if not hDB().locked then
            -- Placeholder when unlocked
            icon:SetTexCoord(unpack(HAPPINESS_COORDS[3]))
            icon:SetDesaturated(true)
            icon:SetAlpha(0.5)
            sweep:Clear()
            text:SetText("")
            frame:Show()
        else
            frame:Hide()
        end
        return
    end

    local tier = S.tier
    if tier == 0 then
        glowActive = false
        for _, tex in ipairs(glow) do tex:Hide() end
        frame:Hide()
        return
    end

    -- Icon
    icon:SetTexCoord(unpack(HAPPINESS_COORDS[tier]))
    icon:SetDesaturated(false)
    icon:SetAlpha(1)

    -- Red pulsing glow for content or unhappy
    if tier <= 2 then
        glowActive = true
        for _, tex in ipairs(glow) do tex:Show() end
    else
        glowActive = false
        for _, tex in ipairs(glow) do tex:Hide() end
    end

    -- Sweep + timer
    local belowLabel = TIER_BELOW_LABELS[tier]
    if belowLabel then
        local ptsAboveTier = S.estimate - TIER_MIN[tier]
        local secsToDown = ptsAboveTier / DECAY_PER_MIN * 60
        if secsToDown < 0 then secsToDown = 0 end

        -- Reverse sweep: grey overlay fills as time runs out.
        -- Total duration = time for full tier to decay.
        -- Start = now - (time already elapsed in this tier).
        local fullTierSecs = TIER_SIZE / DECAY_PER_MIN * 60
        local sweepStart = GetTime() - (fullTierSecs - secsToDown)

        -- Only re-apply if start/duration changed significantly (avoids flicker)
        if math.abs(sweepStart - lastSweepStart) > 2 or lastSweepDuration ~= fullTierSecs then
            sweep:SetCooldown(sweepStart, fullTierSecs)
            lastSweepStart = sweepStart
            lastSweepDuration = fullTierSecs
        end

        local approx = S.anchored and "" or "~"
        text:SetText(approx .. FormatTime(secsToDown))
    else
        -- Unhappy — no lower tier, fully grey
        sweep:Clear()
        text:SetText("")
    end
    text:SetTextColor(1, 1, 1)

    frame:Show()
end

-- =========================================================
-- Initialization (may run from event or poller, whichever fires first)
-- =========================================================

local function DoInit(self)
    if S.initialized then return end
    S.initialized = true
    if ExsarAddonDB then
        ExsarUI.RestorePosition(self, hDB, 0, 100)
    end
    S.petActive = UnitExists("pet")
    if S.petActive then
        SeedEstimate()
    end
    S.lastUpdate = GetTime()
    UpdateVisuals()
end

-- =========================================================
-- Decay + visual update
-- =========================================================

local UPDATE_INTERVAL = 1.0  -- decay/visual tick interval (seconds)

-- Poller handles both lazy init and ongoing decay/visual updates.
-- This catches the case where ADDON_LOADED and PLAYER_ENTERING_WORLD
-- have already fired before this file is processed.
ExsarUI.CreatePoller(nil, UPDATE_INTERVAL, function()
    if not S.initialized and ExsarAddonDB then
        DoInit(frame)
    end
    if not S.initialized then return end
    -- Re-check pet state each tick (pet data may not be ready on first tick)
    S.petActive = UnitExists("pet")
    if not S.petActive then
        UpdateVisuals()
        return
    end
    if S.tier == 0 then
        SeedEstimate()
        if S.tier == 0 then return end  -- still not ready
    end
    local now = GetTime()
    local elapsed = now - S.lastUpdate
    if elapsed > 0 then
        local decayPts = DECAY_PER_MIN * (elapsed / 60)
        S.estimate = S.estimate - decayPts
        ClampEstimate()
    end
    S.lastUpdate = now
    SaveEstimate()
    UpdateVisuals()
end)

-- =========================================================
-- Combat log: detect Feed Pet bites
-- =========================================================

-- Detect Feed Pet bites via combat log. SPELL_PERIODIC_ENERGIZE carries the
-- actual happiness amount per bite (8, 17, or 35 depending on food quality).
-- Layout: ..., destGUID(8), ..., spellId(12), spellName(13), spellSchool(14),
--         amount(15), overEnergize(16), powerType(17)
local POWER_TYPE_HAPPINESS = 27
local feedFrame = CreateFrame("Frame")
feedFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
feedFrame:SetScript("OnEvent", function()
    if not S.petActive then return end
    local _, subEvent, _, _, _, _, _, destGUID,
          _, _, _, _, _, _, amount, _, powerType =
        CombatLogGetCurrentEventInfo()

    if subEvent ~= "SPELL_PERIODIC_ENERGIZE" then return end

    local petGUID = UnitGUID("pet")
    if not petGUID or destGUID ~= petGUID then return end

    -- Only count happiness energize, not mana/focus/etc.
    if powerType == POWER_TYPE_HAPPINESS and amount and amount > 0 then
        if amount < 1 then
            -- Server is clamping the gain — pet is at max happiness
            S.estimate = MAX_HAPPINESS
            S.anchored = true
            SaveEstimate()
        else
            S.estimate = S.estimate + amount
            ClampEstimate()
            -- Feeding amount is exact, so if already anchored we stay anchored
        end
        CorrectToTier()
    end
end)

-- =========================================================
-- Events
-- Note: no mount tracking needed — pet despawns when mounted, so
-- S.petActive becomes false and decay stops automatically.
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_PET")
frame:RegisterEvent("UNIT_HAPPINESS")
frame:RegisterEvent("PLAYER_DEAD")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        DoInit(self)

    elseif event == "PLAYER_ENTERING_WORLD" then
        DoInit(self)
        -- Refresh pet state (but don't re-seed — DoInit already loaded from DB)
        S.petActive = UnitExists("pet")
        if S.petActive and S.tier == 0 then
            SeedEstimate()
        end
        S.lastUpdate = GetTime()
        UpdateVisuals()

    elseif event == "UNIT_PET" then
        if arg1 == "player" then
            local wasActive = S.petActive
            S.petActive = UnitExists("pet")
            if S.petActive and not wasActive then
                -- Pet just appeared: seed estimate
                SeedEstimate()
            elseif not S.petActive and wasActive then
                -- Pet just disappeared — could be dismiss or death
                -- If pet died, UNIT_HAPPINESS likely already fired
                -- For dismiss, subtract the penalty
                if not UnitIsDead("pet") then
                    S.estimate = S.estimate - DISMISS_LOSS
                    ClampEstimate()
                    SaveEstimate()
                end
            end
            UpdateVisuals()
        end

    elseif event == "UNIT_HAPPINESS" then
        CorrectToTier()
        UpdateVisuals()

    elseif event == "PLAYER_DEAD" then
        -- Check if pet also died
        if S.petActive and UnitIsDead("pet") then
            S.estimate = S.estimate - DEATH_LOSS
            ClampEstimate()
            CorrectToTier()
            SaveEstimate()
        end
    end
end)

-- =========================================================
-- Slash sub-command
-- =========================================================

ExsarUI.AddSlashReset("happinessreset", frame, hDB, "Pet Happiness", 0, 100)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Pet Happiness",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, hDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, hDB, frame, function()
            UpdateVisuals()
        end)

        y = ExsarUI.AddResetButton(parent, y, hDB, frame, "Pet Happiness", 0, 100)

        return y
    end,
})
