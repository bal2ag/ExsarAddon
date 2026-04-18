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

local HAPPINESS_SOUND_ID = 7256    -- NsabbeyBell
local SOUND_COOLDOWN     = 5

local S = {
    estimate           = 0,       -- current estimated happiness points
    tier               = 0,       -- current API tier (1/2/3)
    lastUpdate         = GetTime(), -- GetTime() of last decay tick
    petActive          = false,   -- whether pet is currently out
    initialized        = false,   -- true after ADDON_LOADED has fired
    anchored           = false,   -- true once we know the exact value
    lastHappSoundTime  = 0,       -- GetTime() of last happiness sound
    wasDecayClamped    = false,   -- was last decay tick pinned at tier floor
}

-- =========================================================
-- Debug ring buffer (survives /reload)
-- =========================================================
-- Captures state transitions (seed, tier, feed, clamp, penalty) so the user
-- can run /exsar phdump after observing a surprising display to see what
-- produced it. Chat echo is gated on the same flag; default ON so that
-- when someone hits a stuck/unexpected state they already have the trail.

local PH_LOG_CAP = 30

local function IsDebugEnabled()
    local v = hDB().debug
    if v == nil then return true end
    return v
end

local function FormatPHEntry(e)
    local t = e.t or "?"
    local ev = e.event
    if ev == "seed" then
        local saved = "-"
        if e.savedTier then
            saved = string.format("(t=%d,est=%.1f,a=%s)",
                e.savedTier, e.savedEst or -1, e.savedAnchored and "Y" or "N")
        end
        return string.format("%s seed[%s] api=%d saved=%s -> est=%.1f a=%s",
            t, e.source, e.apiTier or 0, saved,
            e.newEst or -1, e.newAnchored and "Y" or "N")
    elseif ev == "tier" then
        return string.format("%s tier %d->%d trig=%s est %.1f->%.1f a %s->%s snap=%s sound=%s",
            t, e.oldTier or 0, e.newTier or 0, e.trigger or "?",
            e.estBefore or -1, e.estAfter or -1,
            e.anchoredBefore and "Y" or "N", e.anchoredAfter and "Y" or "N",
            e.snapped and "Y" or "N", e.soundFired and "Y" or "N")
    elseif ev == "feed" then
        return string.format("%s feed +%d est %.1f->%.1f tier=%d atMax=%s",
            t, e.amount or 0, e.estBefore or -1, e.estAfter or -1,
            e.tierBefore or 0, e.atMax and "Y" or "N")
    elseif ev == "clamp" then
        return string.format("%s clamp elapsed=%.2fs est %.3f->%.1f tier=%d",
            t, e.elapsed or 0, e.estBefore or -1, e.estAfter or -1, e.apiTier or 0)
    elseif ev == "penalty" then
        return string.format("%s penalty %s -%d est %.1f->%.1f",
            t, e.reason or "?", e.amount or 0, e.estBefore or -1, e.estAfter or -1)
    end
    return t .. " unknown event"
end

local function LogPH(entry)
    if not IsDebugEnabled() then return end
    entry.t = date("%H:%M:%S")
    local line = FormatPHEntry(entry)
    print("|cffff8800[ExsarPH]|r " .. line)
    local db = hDB()
    local log = db.debugLog or {}
    log[#log + 1] = entry
    while #log > PH_LOG_CAP do
        table.remove(log, 1)
    end
    db.debugLog = log
end

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

    local db = hDB()
    local source, savedTier, savedEst, savedAnchored
    if db.savedEstimate and db.savedTier then
        savedTier     = db.savedTier
        savedEst      = db.savedEstimate
        savedAnchored = db.savedAnchored or false
        if db.savedTier == happiness then
            source = "saved"
            S.estimate = db.savedEstimate
            S.anchored = db.savedAnchored or false
            if S.estimate < TIER_MIN[happiness] then
                S.estimate = TIER_MIN[happiness]
            elseif S.estimate > TIER_MAX[happiness] then
                S.estimate = TIER_MAX[happiness]
            end
        else
            source = "mismatch"
            -- Tier changed while logged out — anchor at boundary
            if db.savedTier > happiness then
                S.estimate = TIER_MAX[happiness]
            else
                S.estimate = TIER_MIN[happiness]
            end
            S.anchored = true
            SaveEstimate()
        end
    else
        source = "cold"
        S.estimate = TIER_MIN[happiness] + TIER_SIZE / 2
        S.anchored = false
    end
    S.lastUpdate = GetTime()
    S.wasDecayClamped = false

    LogPH({
        event = "seed", source = source, apiTier = happiness,
        savedTier = savedTier, savedEst = savedEst, savedAnchored = savedAnchored,
        newEst = S.estimate, newAnchored = S.anchored,
    })
end

local function CorrectToTier(trigger)
    -- Reconcile our estimate against the authoritative API tier.
    if S.tier == 0 then return end  -- not seeded yet; avoid clobbering saved data
    local happiness = GetPetHappiness()
    if not happiness then return end

    local oldTier = S.tier
    local estBefore = S.estimate
    local anchoredBefore = S.anchored
    S.tier = happiness

    local soundFired = false
    if happiness ~= oldTier and happiness <= 2 and oldTier > 0
            and hDB().happinessSound ~= false then
        local now = GetTime()
        if now - S.lastHappSoundTime >= SOUND_COOLDOWN then
            PlaySound(HAPPINESS_SOUND_ID, "Master")
            S.lastHappSoundTime = now
            soundFired = true
        end
    end

    local newEst, newAnchored = ExsarLogic.ReconcileHappinessTier(
        S.estimate, happiness, S.anchored, TIER_MIN, TIER_MAX)
    local snapped = newEst ~= S.estimate
    local changed = snapped or newAnchored ~= S.anchored
    S.estimate = newEst
    S.anchored = newAnchored
    if changed or happiness ~= oldTier then
        SaveEstimate()
    end
    if happiness ~= oldTier or snapped then
        LogPH({
            event = "tier", trigger = trigger or "?",
            oldTier = oldTier, newTier = happiness,
            estBefore = estBefore, estAfter = newEst,
            anchoredBefore = anchoredBefore, anchoredAfter = newAnchored,
            snapped = snapped, soundFired = soundFired,
        })
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
        local estBefore = S.estimate
        local newEst, clamped = ExsarLogic.ApplyHappinessDecay(
            S.estimate, elapsed, DECAY_PER_MIN, S.tier, TIER_MIN, MAX_HAPPINESS)
        S.estimate = newEst
        -- Log the transition into clamped state only; subsequent pinned ticks
        -- would flood the buffer without adding information.
        if clamped and not S.wasDecayClamped then
            LogPH({
                event = "clamp", elapsed = elapsed,
                estBefore = estBefore, estAfter = newEst, apiTier = S.tier,
            })
        end
        S.wasDecayClamped = clamped
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
        local estBefore = S.estimate
        local tierBefore = S.tier
        local atMax = amount < 1
        if atMax then
            -- Server is clamping the gain — pet is at max happiness
            S.estimate = MAX_HAPPINESS
            S.anchored = true
            SaveEstimate()
        else
            S.estimate = S.estimate + amount
            ClampEstimate()
            -- Feeding amount is exact, so if already anchored we stay anchored
        end
        LogPH({
            event = "feed", amount = amount, estBefore = estBefore,
            estAfter = S.estimate, tierBefore = tierBefore, atMax = atMax,
        })
        CorrectToTier("feed")
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
                    local estBefore = S.estimate
                    S.estimate = S.estimate - DISMISS_LOSS
                    ClampEstimate()
                    SaveEstimate()
                    LogPH({
                        event = "penalty", reason = "dismiss",
                        amount = DISMISS_LOSS,
                        estBefore = estBefore, estAfter = S.estimate,
                    })
                end
            end
            UpdateVisuals()
        end

    elseif event == "UNIT_HAPPINESS" then
        CorrectToTier("happiness_event")
        UpdateVisuals()

    elseif event == "PLAYER_DEAD" then
        -- Check if pet also died
        if S.petActive and UnitIsDead("pet") then
            local estBefore = S.estimate
            S.estimate = S.estimate - DEATH_LOSS
            ClampEstimate()
            LogPH({
                event = "penalty", reason = "death",
                amount = DEATH_LOSS,
                estBefore = estBefore, estAfter = S.estimate,
            })
            CorrectToTier("post_death")
            SaveEstimate()
        end
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarUI.AddSlashReset("happinessreset", frame, hDB, "Pet Happiness", 0, 100)

ExsarAddon.AddSlashCommand("phdebug", function()
    local nowOn = not IsDebugEnabled()
    hDB().debug = nowOn
    print(ADDON_NAME .. ": Pet happiness debug logging " .. (nowOn and "ON" or "OFF"))
end)

ExsarAddon.AddSlashCommand("phdump", function()
    local log = hDB().debugLog
    if not log or #log == 0 then
        print(ADDON_NAME .. ": no pet happiness events logged.")
        return
    end
    local lines = {}
    lines[#lines + 1] = ADDON_NAME .. " — " .. #log .. " pet happiness event(s)"
    lines[#lines + 1] = string.rep("-", 72)
    for i, entry in ipairs(log) do
        lines[#lines + 1] = string.format("#%d %s", i, FormatPHEntry(entry))
    end
    ExsarUI.ShowCopyableText(table.concat(lines, "\n"),
        { title = "ExsarAddon — Pet Happiness Events" })
end)

ExsarAddon.AddSlashCommand("phclear", function()
    hDB().debugLog = nil
    print(ADDON_NAME .. ": pet happiness event log cleared.")
end)

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

        ExsarAddon.CreateCheckbox(parent, "Happiness drop alert sound", 16, y,
            function() return hDB().happinessSound ~= false end,
            function(v) hDB().happinessSound = v end
        )
        y = y - 30

        y = ExsarUI.AddResetButton(parent, y, hDB, frame, "Pet Happiness", 0, 100)

        return y
    end,
})
