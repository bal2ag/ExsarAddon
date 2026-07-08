-- MeleeRangeIndicator module
-- Shows two crossed gold swords when the player is in melee range of their target.
-- Also tracks the melee swing timer cooldown with a sweep effect and alpha reduction.
-- When out of range, shows green up-arrows on a grey background (plus the
-- cooldown sweep + timer when the swing is on cooldown).
-- Settings are stored under ExsarAddonDB.meleeRange.

local ADDON_NAME = "ExsarAddon"

local mrDB = ExsarUI.MakeDB("meleeRange")

-- =========================================================
-- Raptor Strike spell IDs (fires on next melee swing)
-- =========================================================

local RAPTOR_STRIKE_IDS = {
    [2973]  = true,   -- Rank 1
    [14260] = true,   -- Rank 2
    [14261] = true,   -- Rank 3
    [14262] = true,   -- Rank 4
    [14263] = true,   -- Rank 5
    [14264] = true,   -- Rank 6
    [27014] = true,   -- Rank 7
}

-- Feign Death cancels the current melee swing cycle (auto-attack stops while
-- feigning). The cycle restarts when the FD buff fades, mirroring the ranged
-- swing timer's FD handling.
local FEIGN_DEATH_ID = 5384

-- Aimed Shot resets the melee swing timer when it lands (verified in-game): the
-- server restarts the auto-attack swing cycle, just as it resets the ranged
-- cooldown (see RangedSwingTimer's AIMED_SHOT_IDS). So on an Aimed Shot success
-- we restart the melee cycle a full weapon speed from now. Keep this table in
-- sync with RangedSwingTimer.lua / CastBar.lua. Rank 1 is 19434 — NOT 13954.
local AIMED_SHOT_IDS = {
    [19434] = true,   -- Rank 1
    [20900] = true,   -- Rank 2
    [20901] = true,   -- Rank 3
    [20902] = true,   -- Rank 4
    [20903] = true,   -- Rank 5
    [20904] = true,   -- Rank 6
    [27065] = true,   -- Rank 7
}
local AIMED_SHOT_NAME_ID = 19434   -- used only to resolve the localized name

-- =========================================================
-- Runtime state
-- =========================================================

local M = {
    inRange     = false,
    pollElapsed = 0,
    -- Swing timer state
    speed       = 0,      -- hasted main-hand attack speed (seconds)
    lastSwing   = 0,      -- GetTime() when the last melee swing fired
    swingActive = false,   -- true once we've seen at least one swing this session
    feigning    = false,   -- Feign Death buff is up; cycle restarts when it fades
    feignDeathName = "Feign Death",
    aimedShotName  = "Aimed Shot",
}

local function RefreshSpeed()
    local speed = select(1, UnitAttackSpeed("player"))
    if type(speed) == "number" and speed > 0 then
        M.speed = speed
    end
end

-- =========================================================
-- Color tables: normal (in-range) and greyed (out-of-range)
-- =========================================================

local SWORD_COLOR_BLADE  = { 1.0,  0.85, 0.10, 1.0 }    -- bright gold blade
local SWORD_COLOR_EDGE   = { 1.0,  0.65, 0.0,  0.45 }   -- warm glow behind blade
local SWORD_COLOR_GUARD  = { 0.70, 0.55, 0.25, 1.0 }    -- bronze crossguard
local SWORD_COLOR_HANDLE = { 0.50, 0.35, 0.15, 1.0 }    -- brown handle

-- High-contrast "ready" palette: bright cyan-white pops against warm spell FX
-- (fire/lava/gold particles) where the normal gold blade would blend in.
local READY_COLOR_BLADE  = { 0.60, 1.0,  1.0,  1.0 }    -- bright cyan-white blade
local READY_COLOR_EDGE   = { 0.25, 0.85, 1.0,  0.55 }   -- cyan glow behind blade
local READY_COLOR_GUARD  = { 0.40, 0.85, 0.95, 1.0 }    -- cyan crossguard
local READY_COLOR_HANDLE = { 0.30, 0.60, 0.72, 1.0 }    -- muted cyan handle

local GREY_COLOR_BLADE   = { 0.45, 0.45, 0.45, 1.0 }
local GREY_COLOR_EDGE    = { 0.35, 0.35, 0.35, 0.45 }
local GREY_COLOR_GUARD   = { 0.40, 0.40, 0.40, 1.0 }
local GREY_COLOR_HANDLE  = { 0.30, 0.30, 0.30, 1.0 }

-- =========================================================
-- Frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "MeleeRangeFrame", UIParent)
frame:SetSize(80, 80)
ExsarUI.SetupMovableFrame(frame, mrDB, { bgAlpha = 0 })
frame:Hide()

-- =========================================================
-- Background
-- =========================================================
-- Dark warm-tinted circle behind the swords for contrast.

local CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- Ready-state pulsating glow ring (behind everything)
local GLOW_PULSE_HZ  = 3.0
local GLOW_PULSE_MIN = 0.45
local GLOW_PULSE_MAX = 1.0

-- Muted glow for in-range + cooldown (move away!)
local GLOW_MUTED_HZ  = 1.5
local GLOW_MUTED_MIN = 0.25
local GLOW_MUTED_MAX = 0.6

local glowRing = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
glowRing:SetPoint("CENTER")
glowRing:SetSize(100, 100)
glowRing:SetTexture(CIRCLE_MASK)
glowRing:SetVertexColor(1.0, 0.95, 0.75, 0.85)
glowRing:Hide()

local glowRingActive = false
local glowRingMuted  = false  -- true = muted gold, false = bright white

local glowPulseFrame = CreateFrame("Frame")
glowPulseFrame:SetScript("OnUpdate", function()
    if not glowRingActive then return end
    if glowRingMuted then
        glowRing:SetAlpha(ExsarLogic.PulseAlpha(GetTime(), GLOW_MUTED_HZ, GLOW_MUTED_MIN, GLOW_MUTED_MAX))
    else
        glowRing:SetAlpha(ExsarLogic.PulseAlpha(GetTime(), GLOW_PULSE_HZ, GLOW_PULSE_MIN, GLOW_PULSE_MAX))
    end
end)

-- Outer ring (slightly larger, lighter) for a subtle border
local bgRing = frame:CreateTexture(nil, "BACKGROUND")
bgRing:SetPoint("CENTER")
bgRing:SetSize(78, 78)
bgRing:SetTexture(CIRCLE_MASK)
bgRing:SetVertexColor(0.35, 0.28, 0.10, 0.9)

-- Inner fill
local bg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
bg:SetPoint("CENTER")
bg:SetSize(74, 74)
bg:SetTexture(CIRCLE_MASK)
bg:SetVertexColor(0.10, 0.08, 0.05, 0.97)

-- Background color modes: warm gold (normal) vs neutral grey (out-of-range idle).
-- Near-opaque so spell/particle FX behind the widget can't bleed through and
-- wash out the readout during busy fights.
local BG_NORMAL_RING = { 0.35, 0.28, 0.10, 0.9  }
local BG_NORMAL_FILL = { 0.10, 0.08, 0.05, 0.97 }
local BG_GREY_RING   = { 0.28, 0.28, 0.28, 0.9  }
local BG_GREY_FILL   = { 0.08, 0.08, 0.08, 0.97 }

local currentBgMode = "normal"

local function SetBackgroundMode(mode)
    if mode == currentBgMode then return end
    currentBgMode = mode
    local ring = mode == "grey" and BG_GREY_RING or BG_NORMAL_RING
    local fill = mode == "grey" and BG_GREY_FILL or BG_NORMAL_FILL
    bgRing:SetVertexColor(ring[1], ring[2], ring[3], ring[4])
    bg:SetVertexColor(fill[1], fill[2], fill[3], fill[4])
end

-- =========================================================
-- Crossed swords visuals
-- =========================================================

local allLines = {}  -- track all lines for color swapping
local glowLines = {} -- extra glow lines shown only when "ready"

local function MakeLine(layer, x1, y1, x2, y2, thickness, color, colorKey)
    local line = frame:CreateLine(nil, layer)
    line:SetStartPoint("CENTER", frame, x1, y1)
    line:SetEndPoint("CENTER", frame, x2, y2)
    line:SetThickness(thickness)
    line:SetColorTexture(color[1], color[2], color[3], color[4])
    allLines[#allLines + 1] = { line = line, colorKey = colorKey }
    return line
end

local function BuildSword(sign)
    local bx1, by1 = -28 * sign,  28
    local bx2, by2 =  28 * sign, -28

    -- Wide soft glow behind blade (only visible in ready state)
    local glow = frame:CreateLine(nil, "BORDER")
    glow:SetStartPoint("CENTER", frame, bx1, by1)
    glow:SetEndPoint("CENTER", frame, bx2, by2)
    glow:SetThickness(24)
    glow:SetColorTexture(0.35, 0.9, 1.0, 0.30)  -- cyan blade glow (ready state only)
    glow:Hide()
    glowLines[#glowLines + 1] = glow

    MakeLine("ARTWORK", bx1, by1, bx2, by2, 14, SWORD_COLOR_EDGE, "edge")
    MakeLine("OVERLAY", bx1, by1, bx2, by2, 5, SWORD_COLOR_BLADE, "blade")

    local gx, gy = 10 * sign, -10
    local gdx, gdy = 10 * sign, 10
    MakeLine("OVERLAY", gx - gdx, gy - gdy, gx + gdx, gy + gdy, 5, SWORD_COLOR_GUARD, "guard")

    local hx1, hy1 = 14 * sign, -14
    local hx2, hy2 = 22 * sign, -22
    MakeLine("OVERLAY", hx1, hy1, hx2, hy2, 4, SWORD_COLOR_HANDLE, "handle")

    MakeLine("OVERLAY", hx2 - 1 * sign, hy2 + 1, hx2 + 1 * sign, hy2 - 1, 6, SWORD_COLOR_GUARD, "guard")
end

BuildSword( 1)
BuildSword(-1)

local function SetGlowVisible(show)
    for _, gl in ipairs(glowLines) do
        if show then gl:Show() else gl:Hide() end
    end
end

local function SetSwordsVisible(show)
    for _, entry in ipairs(allLines) do
        if show then entry.line:Show() else entry.line:Hide() end
    end
end

-- =========================================================
-- Status overlays
-- =========================================================
-- Green up-arrows: shown in all out-of-range states (swing ready or on
-- cooldown) as a "step in" cue. When the swing is on cooldown the arrows are
-- accompanied by the cooldown sweep + timer.

local overlayFrame = CreateFrame("Frame", nil, frame)
overlayFrame:SetAllPoints()
if overlayFrame.SetIgnoreParentAlpha then
    overlayFrame:SetIgnoreParentAlpha(true)
end

local upArrows = ExsarUI.CreateUpArrows(overlayFrame, { color = { 0.2, 0.9, 0.25, 1.0 } })
for _, line in ipairs(upArrows) do
    line:Hide()
end

local function SetArrowsVisible(show)
    for _, line in ipairs(upArrows) do
        if show then line:Show() else line:Hide() end
    end
end

-- =========================================================
-- Cooldown sweep overlay
-- =========================================================
-- Sweep container sized to match the glow ring so the pie-chart
-- animation covers both the icon and the pulsating border.

local sweepHolder = CreateFrame("Frame", nil, frame)
sweepHolder:SetSize(100, 100)
sweepHolder:SetPoint("CENTER")

local cooldown = ExsarUI.CreateSweep(sweepHolder)
if cooldown.SetSwipeColor then
    -- Translucent so the arrows underneath stay readable through the sweep.
    cooldown:SetSwipeColor(0.55, 0.55, 0.55, 0.55)
end
if cooldown.SetSwipeTexture then
    cooldown:SetSwipeTexture(CIRCLE_MASK)
end

-- Draw the green up-arrows above the sweep so the pie-chart darkens the
-- background behind them rather than masking them out.
overlayFrame:SetFrameLevel(cooldown:GetFrameLevel() + 1)

-- Timer text frame (above the cooldown overlay, ignores parent alpha)
local timerFrame = CreateFrame("Frame", nil, frame)
timerFrame:SetAllPoints()
timerFrame:SetFrameLevel(cooldown:GetFrameLevel() + 5)
if timerFrame.SetIgnoreParentAlpha then
    timerFrame:SetIgnoreParentAlpha(true)
end
local timerText = timerFrame:CreateFontString(nil, "OVERLAY")
timerText:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
timerText:SetPoint("CENTER", frame, "CENTER", 0, 0)
timerText:SetTextColor(1, 1, 1, 1)
timerText:SetText("")

-- =========================================================
-- Color management
-- =========================================================

local COLOR_NORMAL = {
    blade  = SWORD_COLOR_BLADE,
    edge   = SWORD_COLOR_EDGE,
    guard  = SWORD_COLOR_GUARD,
    handle = SWORD_COLOR_HANDLE,
}
local COLOR_GREY = {
    blade  = GREY_COLOR_BLADE,
    edge   = GREY_COLOR_EDGE,
    guard  = GREY_COLOR_GUARD,
    handle = GREY_COLOR_HANDLE,
}
local COLOR_READY = {
    blade  = READY_COLOR_BLADE,
    edge   = READY_COLOR_EDGE,
    guard  = READY_COLOR_GUARD,
    handle = READY_COLOR_HANDLE,
}
local PALETTES = { normal = COLOR_NORMAL, grey = COLOR_GREY, ready = COLOR_READY }

local currentColorMode = "normal"

local function SetSwordColors(mode)
    if mode == currentColorMode then return end
    currentColorMode = mode
    local palette = PALETTES[mode] or COLOR_NORMAL
    for _, entry in ipairs(allLines) do
        local c = palette[entry.colorKey]
        entry.line:SetColorTexture(c[1], c[2], c[3], c[4])
    end
end

-- =========================================================
-- Swing detection (from MeleeSwingTimer)
-- =========================================================

local function OnSwing()
    local now = GetTime()
    if now - M.lastSwing < 0.15 then return end
    M.lastSwing   = now
    M.swingActive = true
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
combatFrame:SetScript("OnEvent", function()
    local _, subEvent, _, casterGUID, _, _, _, _, _, _, _, spellId =
        CombatLogGetCurrentEventInfo()
    if casterGUID ~= UnitGUID("player") then return end

    if subEvent == "SWING_DAMAGE" or subEvent == "SWING_MISSED" then
        OnSwing()
    elseif subEvent == "SPELL_DAMAGE" or subEvent == "SPELL_MISSED" then
        if RAPTOR_STRIKE_IDS[spellId] then
            OnSwing()
        end
    end
end)

-- =========================================================
-- Range check
-- =========================================================

local function CheckMeleeRange()
    if not UnitAffectingCombat("player") then return false end
    if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then
        return false
    end
    return IsSpellInRange("Wing Clip", "target") == 1
end

-- =========================================================
-- Swing timer state helpers
-- =========================================================

local function IsSwingOnCooldown()
    if not M.swingActive or M.speed <= 0 then return false end
    local remaining = M.speed - (GetTime() - M.lastSwing)
    return remaining > 0
end

-- =========================================================
-- Update: visibility, colors, cooldown sweep, alpha
-- =========================================================

-- ENTER is a FileDataID (played via PlaySoundFile); LEAVE is a SoundKit ID (played via PlaySound)
local ENTER_RANGE_SOUND = 567947  -- BullWhipHit1 (FileDataID)
local LEAVE_RANGE_SOUND = 1024     -- ChickenDeath (SoundKit ID)

local function UpdateState()
    local inRange     = CheckMeleeRange()
    local onCooldown  = IsSwingOnCooldown()
    local inCombat    = UnitAffectingCombat("player")
    local wasInRange  = M.inRange
    M.inRange = inRange

    -- Range transition sounds
    if inRange and not wasInRange and mrDB().rangeSound ~= false then
        PlaySoundFile(ENTER_RANGE_SOUND, "Master")
    elseif not inRange and wasInRange and mrDB().rangeSound ~= false then
        PlaySound(LEAVE_RANGE_SOUND, "Master")
    end

    local unlocked = not mrDB().locked

    -- Determine visibility
    -- Show when: in range, OR swing on cooldown, OR in combat (always-on
    -- out-of-range cue), OR unlocked
    local shouldShow = inRange or onCooldown or inCombat or unlocked

    if not shouldShow then
        frame:Hide()
        return
    end

    frame:Show()

    -- Out-of-range states share the green up-arrows on a grey circular
    -- background. Idle = swing ready (always-on in-combat cue); on-cooldown
    -- adds the cooldown sweep + timer.
    local outOfRangeOnCd = not inRange and onCooldown
    local outOfRangeIdle = inCombat and not inRange and not onCooldown

    -- Determine color mode, alpha, and glow
    local ready = inRange and not onCooldown
    if inRange then
        SetSwordsVisible(true)
        SetBackgroundMode("normal")
        if onCooldown then
            SetSwordColors("normal")
            frame:SetAlpha(0.5)
        else
            -- Ready to swing: high-contrast cyan blades so the "hit now" cue
            -- pops against warm spell FX instead of blending with gold.
            SetSwordColors("ready")
            frame:SetAlpha(1.0)
        end
    elseif outOfRangeOnCd or outOfRangeIdle then
        -- Out of range (swing ready or on cooldown): green up-arrows on grey
        -- background. The cooldown sweep distinguishes the on-cooldown case;
        -- the arrows are dimmed slightly while the sweep is up so they blend.
        SetSwordsVisible(false)
        SetBackgroundMode("grey")
        frame:SetAlpha(1.0)
        overlayFrame:SetAlpha(outOfRangeOnCd and 0.8 or 1.0)
    else
        -- Unlocked edit mode, not in combat scenario
        SetSwordColors("normal")
        SetSwordsVisible(true)
        SetBackgroundMode("normal")
        frame:SetAlpha(1.0)
    end
    SetGlowVisible(ready)
    SetArrowsVisible(outOfRangeOnCd or outOfRangeIdle)

    -- Pulsating border glow ring:
    -- bright white when ready, muted gold when in range + cooldown (move away!)
    if ready then
        glowRingActive = true
        glowRingMuted  = false
        glowRing:SetVertexColor(0.55, 0.95, 1.0, 0.9)
        glowRing:Show()
    elseif inRange and onCooldown then
        glowRingActive = true
        glowRingMuted  = true
        glowRing:SetVertexColor(0.75, 0.60, 0.15, 0.65)
        glowRing:Show()
    else
        glowRingActive = false
        glowRing:Hide()
    end

    -- Drive the cooldown sweep and timer text
    if onCooldown and M.speed > 0 then
        cooldown:SetCooldown(M.lastSwing, M.speed)
        local remaining = M.speed - (GetTime() - M.lastSwing)
        if remaining > 0 then
            timerText:SetText(string.format("%.1f", remaining))
        else
            timerText:SetText("")
        end
    else
        cooldown:SetCooldown(0, 0)
        timerText:SetText("")
    end
end

-- =========================================================
-- Polling (range checks have no event; poll at 0.03s for tight melee weaving)
-- =========================================================

local pollFrame = CreateFrame("Frame")
pollFrame:SetScript("OnUpdate", function(self, elapsed)
    M.pollElapsed = M.pollElapsed + elapsed
    if M.pollElapsed < 0.03 then return end
    M.pollElapsed = 0
    UpdateState()
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

frame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, _, arg5)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, mrDB, 0, -150)
        if not mrDB().locked then
            frame:Show()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        M.feignDeathName = GetSpellInfo(FEIGN_DEATH_ID) or "Feign Death"
        M.aimedShotName  = GetSpellInfo(AIMED_SHOT_NAME_ID) or "Aimed Shot"
        RefreshSpeed()
        UpdateState()

    elseif event == "PLAYER_DEAD" then
        M.swingActive = false
        M.lastSwing   = 0
        UpdateState()

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" then
            -- Feign Death cancels the current melee swing cycle. Clear the
            -- swing state so the cooldown sweep doesn't linger on a stale
            -- swing while feigning; the cycle restarts when the FD buff fades
            -- (handled in UNIT_AURA via M.feigning), mirroring RangedSwingTimer.
            local isFeignDeath = (arg2 == M.feignDeathName)
                or (arg3 == FEIGN_DEATH_ID)
                or (arg5 == FEIGN_DEATH_ID)
            if isFeignDeath then
                M.feigning    = true
                M.swingActive = false
                M.lastSwing   = 0
                UpdateState()
                return
            end

            -- Aimed Shot landing resets the melee swing cycle (verified
            -- in-game): restart it a full weapon speed from now so the sweep
            -- counts down to the next real swing rather than lingering on the
            -- pre-Aimed timer. Mirrors RangedSwingTimer's Aimed Shot reset.
            local isAimedShot = (arg2 == M.aimedShotName)
                or AIMED_SHOT_IDS[arg3]
                or AIMED_SHOT_IDS[arg5]
            if isAimedShot then
                M.lastSwing   = GetTime()
                M.swingActive = true
                UpdateState()
            end
        end

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then
            -- Feign Death ended (buff faded): restart the swing cycle a full
            -- weapon speed from now, so the sweep counts down to the first
            -- post-FD swing rather than waiting for it to land.
            if M.feigning and not ExsarUI.PlayerHasBuff(M.feignDeathName) then
                M.feigning    = false
                M.lastSwing   = GetTime()
                M.swingActive = true
            end
            RefreshSpeed()
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        RefreshSpeed()

    elseif event == "PLAYER_TARGET_CHANGED"
        or event == "PLAYER_REGEN_ENABLED"
        or event == "PLAYER_REGEN_DISABLED" then
        UpdateState()
    end
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Melee Range Indicator",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, mrDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, mrDB, frame)

        ExsarAddon.CreateCheckbox(parent, "Range change sound effects", 16, y,
            function() return mrDB().rangeSound ~= false end,
            function(v) mrDB().rangeSound = v end
        )
        y = y - 30

        y = ExsarUI.AddResetButton(parent, y, mrDB, frame, "Melee range", 0, -150)

        return y
    end,
})
