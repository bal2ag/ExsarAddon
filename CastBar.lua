-- CastBar module
-- Displays a cast bar for Hunter shots: Auto Shot, Aimed Shot, Steady Shot,
-- and Multi-Shot.  Each spell gets a distinct color; failed/interrupted casts
-- flash red briefly before the bar hides.
-- Settings are stored under ExsarAddonDB.castBar.

local ADDON_NAME = "ExsarAddon"

local cbDB = ExsarUI.MakeDB("castBar")

-- =========================================================
-- Constants
-- =========================================================

local DEFAULT_WIDTH  = 240
local DEFAULT_HEIGHT = 24
local ICON_SIZE      = DEFAULT_HEIGHT   -- icon is square, height of the bar
local FLASH_DURATION = 0.4
-- Two distinct Auto Shot timing windows:
-- AUTO_CLIP_TIME:  hasted clipping window for the standing-still natural aim
--                  bar (how long before cycle-end a new cast would clip).
-- AUTO_WIND_UP:    unhasted 0.5s + latency for movement-delayed aim bars
--                  (the actual wind-up time after the player stops moving).
local AUTO_CLIP_TIME = 0.65  -- default before first measurement
local AUTO_WIND_UP   = 0.65

-- Auto-shot HOLD warning: the window between the aim bar reaching its predicted
-- end (shot is due) and the shot actually firing. This gap is the hidden "retry
-- timer" (a 0.5s-cadence resume check) plus event latency — during it the player
-- must NOT act or they clip the pending auto. We keep the bar full + wrap it in a
-- pulsing orange glow until UNIT_SPELLCAST_SUCCEEDED lands (or movement/the cap
-- cancels it). Because the bar's end anchor and the fire event are both shifted
-- by the same latency, a clean cycle shows a near-zero glow and the glow duration
-- tracks the real delay. HOLD_MAX caps it so a missed fire event can't strand the
-- glow (retry ~0.5s + latency, with headroom).
local HOLD_MAX      = 0.85
local HOLD_PULSE_HZ = 2.6
local HOLD_MIN_A    = 0.34   -- never fully dim — the warning must stay legible at the trough
local HOLD_MAX_A    = 0.86
local HOLD_GLOW_SIZE = 7     -- halo spread beyond the widget (bigger = more prominent)
local HOLD_BAR_COLOR = { 0.95, 0.45, 0.05, 0.9 }  -- amber "still active, wait"
local HOLD_GLOW_COLOR = { 1.0, 0.45, 0.05 }

-- Used only to resolve localized spell names at login
local SPELL_ID_AUTO   = 75
local SPELL_ID_AIMED  = 19434   -- Rank 1 of Aimed Shot in TBC Classic (NOT 13954)
local SPELL_ID_STEADY = 34120
local SPELL_ID_MULTI  = 2643
local SPELL_ID_FEIGN  = 5384

-- Aimed Shot spell IDs across all TBC Classic ranks.
-- UNIT_SPELLCAST_START is unreliable for Aimed Shot; detection requires the
-- combat log SPELL_CAST_START event (see combatFrame below).
local AIMED_SHOT_IDS = {
    [19434] = true,   -- Rank 1
    [20900] = true,   -- Rank 2
    [20901] = true,   -- Rank 3
    [20902] = true,   -- Rank 4
    [20903] = true,   -- Rank 5
    [20904] = true,   -- Rank 6
    [27065] = true,   -- Rank 7
}

-- Multi-Shot spell IDs across all TBC Classic ranks.
-- UNIT_SPELLCAST_START does not fire for Multi-Shot; detection requires the
-- combat log SPELL_CAST_START event (see combatFrame below).
local MULTI_SHOT_IDS = {
    [2643]  = true,   -- Rank 1
    [14288] = true,   -- Rank 2
    [14289] = true,   -- Rank 3
    [14290] = true,   -- Rank 4
    [25294] = true,   -- Rank 5
    [27021] = true,   -- Rank 6
}

-- =========================================================
-- Runtime state
-- =========================================================

local C = {
    casting     = false,
    startTime   = 0,
    endTime     = 0,
    flashEnd    = 0,
    spellName   = "",
    lastTimeStr = "",
    autoActive   = false,  -- true while auto shot repeat is toggled on
    autoIcon     = nil,    -- cached icon texture for auto shot
    aimedIcon    = nil,    -- cached icon texture for aimed shot
    multiIcon    = nil,    -- cached icon texture for multi-shot
    lastAutoTime = 0,      -- GetTime() of the last swing-cycle anchor (Auto Shot fire or
                           -- Aimed Shot landing — both start a full cycle); drives aim-window detection
    autoSpeed    = 0,      -- hasted ranged weapon speed (seconds); from UnitRangedDamage
    baseSpeed    = 0,      -- base (unhasted) ranged weapon speed (seconds)
    inAutoAim    = false,  -- gate: true once the hasted aim window bar has been shown this cycle
    fdReset      = false,  -- Feign Death reset the cycle; re-anchor on attack resume
    locked       = false,  -- cached; updated on ADDON_LOADED and lock toggle
    holding      = false,  -- true during the auto-shot HOLD window (aim done, shot pending)
    holdEnd      = 0,      -- absolute safety-cap time for the current hold
    holdWarn     = true,   -- cached config flag; false disables the HOLD warning
    -- Resolved at PLAYER_ENTERING_WORLD:
    nameAuto    = "Auto Shot",
    nameAimed   = "Aimed Shot",
    nameSteady  = "Steady Shot",
    nameMulti   = "Multi-Shot",
    nameFeign   = "Feign Death",
    tracked     = {},     -- name -> true
}

local function RefreshAutoSpeed()
    local speed = select(1, UnitRangedDamage("player"))
    C.autoSpeed = (type(speed) == "number" and speed > 0) and speed or 0
end

local function RefreshBaseSpeed()
    C.baseSpeed = ExsarUI.GetBaseRangedSpeed()
end

local function RefreshAutoAimTime()
    AUTO_CLIP_TIME = ExsarUI.GetAutoShotClipWindow(C.autoSpeed, C.baseSpeed)
    AUTO_WIND_UP   = ExsarUI.GetAutoShotWindUpTime()
end

-- =========================================================
-- Frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "CastBarFrame", UIParent)
ExsarUI.SetupMovableFrame(frame, cbDB)

-- Spell icon (left side)
local iconTex = frame:CreateTexture(nil, "ARTWORK")
iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

-- Background of the cast bar area (right of icon)
local barBg = frame:CreateTexture(nil, "ARTWORK")
barBg:SetColorTexture(0.08, 0.08, 0.12, 0.8)

-- Fill bar — grows left to right as the cast progresses
local bar = frame:CreateTexture(nil, "OVERLAY")

-- Spell name — left-aligned inside bar area
local nameText = frame:CreateFontString(nil, "OVERLAY")
nameText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
nameText:SetJustifyH("LEFT")
nameText:SetTextColor(1, 1, 1, 1)

-- Time remaining — right-aligned
local timeText = frame:CreateFontString(nil, "OVERLAY")
timeText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
timeText:SetJustifyH("RIGHT")
timeText:SetTextColor(1, 1, 1, 0.9)

-- Placeholder label: shown when the widget is unlocked but no cast is active,
-- so the bar can be positioned even when it would normally be invisible.
local placeholderText = ExsarUI.CreatePlaceholder(frame, "Cast Bar")

-- HOLD glow: pulsing orange halo surrounding the whole widget during the
-- retry-timer window (aim bar done, auto shot not yet fired — "wait, don't act").
local holdGlow = ExsarUI.CreateGlow(frame,
    HOLD_GLOW_COLOR[1], HOLD_GLOW_COLOR[2], HOLD_GLOW_COLOR[3], HOLD_MAX_A, HOLD_GLOW_SIZE, "BACKGROUND")

frame:Hide()

-- =========================================================
-- Layout
-- =========================================================

-- Cached so OnUpdate never calls cbDB() or does arithmetic in the hot path
local cachedBarW = DEFAULT_WIDTH - ICON_SIZE - 2

local function ApplySize()
    local db   = cbDB()
    local w    = db.width or DEFAULT_WIDTH
    local h    = DEFAULT_HEIGHT
    local barX = ICON_SIZE + 2     -- bar starts this many pixels from the left

    cachedBarW = w - ICON_SIZE - 2
    frame:SetSize(w, h)

    iconTex:SetSize(h - 2, h - 2)
    iconTex:SetPoint("LEFT", frame, "LEFT", 1, 0)

    barBg:SetPoint("LEFT",  frame, "LEFT",  barX, 0)
    barBg:SetPoint("RIGHT", frame, "RIGHT", 0,    0)
    barBg:SetHeight(h)

    bar:SetPoint("LEFT", frame, "LEFT", barX, 0)
    bar:SetHeight(h - 4)

    -- nameText gets most of the bar; leave ~38 px on the right for timeText
    nameText:SetPoint("LEFT",  frame, "LEFT",  barX + 4, 0)
    nameText:SetPoint("RIGHT", frame, "RIGHT", -38,      0)

    timeText:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    timeText:SetWidth(34)
end

-- =========================================================
-- Bar color by spell
-- =========================================================

local function GetBarColor(name)
    if name == C.nameAuto   then return 0.25, 0.85, 0.25, 0.85 end  -- green
    if name == C.nameAimed  then return 0.90, 0.80, 0.10, 0.90 end  -- gold
    if name == C.nameSteady then return 0.65, 0.30, 0.95, 0.85 end  -- purple
    if name == C.nameMulti  then return 0.90, 0.50, 0.10, 0.90 end  -- orange
    return 0.60, 0.60, 0.90, 0.85                                    -- fallback
end

-- =========================================================
-- Cast state helpers
-- =========================================================

local inPlaceholder = false

-- When not casting: hide the frame if locked, or show a greyed placeholder if
-- unlocked so the widget can be repositioned even when no cast is active.
local function ShowPlaceholder()
    if C.locked then
        inPlaceholder = false
        frame:Hide()
        return
    end
    if inPlaceholder then return end  -- already in placeholder state; nothing to do
    inPlaceholder = true
    bar:Hide()
    iconTex:SetTexture(nil)
    nameText:SetText("")
    timeText:SetText("")
    placeholderText:Show()
    frame:Show()
end

local function ShowBar(name, icon, startSec, endSec)
    -- A new cast supersedes any pending HOLD glow.
    if C.holding then
        C.holding = false
        C.holdEnd = 0
        holdGlow:Hide()
    end
    inPlaceholder = false
    placeholderText:Hide()
    C.casting     = true
    C.flashEnd    = 0
    C.spellName   = name
    C.startTime   = startSec
    C.endTime     = endSec
    C.lastTimeStr = ""
    iconTex:SetTexture(icon)
    nameText:SetText(name)
    bar:SetColorTexture(GetBarColor(name))
    bar:SetWidth(0.01)
    bar:Show()
    timeText:SetText("")
    frame:Show()
end

-- Enter the HOLD state: the auto-shot aim bar has reached its predicted end but
-- the shot hasn't fired yet (retry-timer delay). Keep the bar full + amber and
-- show the pulsing orange glow until the shot lands or movement/the cap cancels.
local function BeginHold(now)
    C.casting   = false   -- the aim bar's fill is complete
    C.inAutoAim = false
    C.holding   = true
    C.holdEnd   = now + HOLD_MAX
    inPlaceholder = false
    placeholderText:Hide()
    bar:SetColorTexture(HOLD_BAR_COLOR[1], HOLD_BAR_COLOR[2], HOLD_BAR_COLOR[3], HOLD_BAR_COLOR[4])
    bar:SetWidth(math.max(0.01, cachedBarW))
    bar:Show()
    timeText:SetText("")
    holdGlow:Show()
    frame:Show()
end

-- Leave the HOLD state (shot fired, movement, toggle off, or safety cap).
local function EndHold()
    if not C.holding then return end
    C.holding = false
    C.holdEnd = 0
    holdGlow:Hide()
end


-- Aimed Shot and Multi-Shot cast bars: UNIT_SPELLCAST_START is unreliable for
-- these spells in TBC Classic Anniversary, so we detect them via the combat log.
-- CombatLogGetCurrentEventInfo() is required on the modern client; the older
-- variadic-args approach (select(N, ...)) does not work here.
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
combatFrame:SetScript("OnEvent", function(self, event)
    local _, subEvent, _, casterGUID, _, _, _, _, _, _, _, spellId =
        CombatLogGetCurrentEventInfo()
    if casterGUID ~= UnitGUID("player") then return end
    if subEvent == "SPELL_CAST_START" then
        if MULTI_SHOT_IDS[spellId] then
            local now = GetTime()
            -- Multi-Shot has a 0.5s base cast, reduced by haste (same as Auto Shot wind-up)
            local multiDur = (C.baseSpeed > 0 and C.autoSpeed > 0)
                and 0.5 * C.autoSpeed / C.baseSpeed
                or 0.5
            ShowBar(C.nameMulti, C.multiIcon, now, now + multiDur)
        elseif AIMED_SHOT_IDS[spellId] then
            -- Prefer UnitCastingInfo for the accurate hasted cast duration.
            -- Fall back to ranged weapon speed if the cast info isn't populated yet.
            local name, _, icon, startMS, endMS = UnitCastingInfo("player")
            if name and C.tracked[name] then
                ShowBar(name, icon, startMS / 1000, endMS / 1000)
            else
                local speed = select(1, UnitRangedDamage("player"))
                local now   = GetTime()
                ShowBar(C.nameAimed, C.aimedIcon, now,
                    now + (type(speed) == "number" and speed > 0 and speed or 3.0))
            end
        end
    end
end)

-- Movement state for auto-aim detection (module-level so the event handler can
-- also write to these when auto shot is first enabled).
local autoAimMoving   = false   -- player was moving on the previous ticker tick
local autoAimStopTime = 0       -- GetTime() when the player most recently stopped

-- Forward declaration: EndCast is defined after the autoAimTicker closure that
-- calls it, so we need a local variable in scope before the closure is created.
local EndCast

-- Auto Shot aim-window ticker.
-- The main cast bar frame is hidden between casts, so its OnUpdate does not fire
-- and cannot detect the start of the aim window.  This separate frame is always
-- shown so it ticks every frame and can trigger ShowBar at the right moment.
-- Two cases are handled:
--   A) Normal (no movement delay): autoRemaining is in (0, AUTO_CLIP_TIME].
--   B) Overdue (shot delayed by movement): autoRemaining <= 0 but the weapon
--      cooldown (GetSpellCooldown) has expired and the player just stopped moving.
local autoAimTicker = CreateFrame("Frame")
autoAimTicker:Show()
autoAimTicker:SetScript("OnUpdate", function(self, elapsed)
    if not C.autoActive then
        C.inAutoAim   = false
        autoAimMoving = false
        return
    end

    local now    = GetTime()
    local moving = GetUnitSpeed("player") > 0

    -- Track player stop-time even while another spell is casting, so the
    -- delayed-aim calculation is accurate when the Steady/Aimed Shot finishes.
    if autoAimMoving and not moving then
        autoAimStopTime = now
    end
    autoAimMoving = moving

    -- During the HOLD window the aim bar is already resolved; the frame's
    -- OnUpdate owns the glow and its exit conditions (including movement).
    -- Don't let the aim detection re-show a bar over the hold.
    if C.holding then return end

    -- Don't replace another spell's cast bar.
    if C.casting and C.spellName ~= C.nameAuto then return end

    if moving then
        -- Player started moving: reset aim state and cancel the bar if it is
        -- showing.  Do not gate on C.inAutoAim — the bar may have been shown via
        -- a code path that did not set that flag, and we always want to cancel.
        C.inAutoAim = false
        if C.casting and C.spellName == C.nameAuto then
            EndCast(false)
        end
        return
    end

    -- Player is stationary.  Check whether the aim window is active.
    local inAim  = false
    local barStart, barEnd

    -- Case A: within the natural aim window.
    -- If the player moved and stopped after the window began, the aim restarted
    -- at autoAimStopTime rather than at the original naturalStart, so we anchor
    -- the bar to the new stop time instead of the stale schedule.
    if C.autoSpeed > 0 and C.lastAutoTime > 0 then
        local naturalEnd   = C.lastAutoTime + C.autoSpeed
        local naturalStart = naturalEnd - AUTO_CLIP_TIME
        local autoRemaining = naturalEnd - now
        if autoRemaining > 0 and autoRemaining <= AUTO_CLIP_TIME then
            if autoAimStopTime > naturalStart then
                -- Aim was interrupted by movement and restarted at the new stop time.
                -- Use the unhasted wind-up: the full 0.5s animation plays after stopping.
                barStart = autoAimStopTime
                barEnd   = autoAimStopTime + AUTO_WIND_UP
            else
                -- Aim has been uninterrupted; use the natural window.
                barStart = naturalStart
                barEnd   = naturalEnd
            end
            inAim = now <= barEnd
        end
    end

    -- Case B: shot is overdue (timer expired due to movement) or this is the
    -- very first shot (no lastAutoTime yet).  Aim starts when the player stops.
    -- We do NOT use GetSpellCooldown here — it returns (0,0) for auto-attack
    -- weapon cooldowns in TBC Classic even while the cooldown is active, making
    -- it useless for distinguishing "weapon ready" from "weapon on cooldown".
    -- Skipped while a Feign Death reset is pending (lastAutoTime == 0 then
    -- means "cycle restarts on attack resume", not "first shot fires on stop").
    if not inAim and autoAimStopTime > 0 and not C.fdReset then
        local autoOverdue = (C.lastAutoTime == 0)
            or (C.autoSpeed > 0 and (C.autoSpeed - (now - C.lastAutoTime)) <= 0)
        if autoOverdue then
            barStart = autoAimStopTime
            barEnd   = autoAimStopTime + AUTO_WIND_UP
            inAim    = now <= barEnd
        end
    end

    if inAim then
        -- Gate: only call ShowBar if the bar isn't already showing.
        -- We check C.casting rather than C.inAutoAim because UNIT_SPELLCAST_STOP
        -- can set C.casting=false without resetting C.inAutoAim, leaving the gate
        -- stuck and preventing the bar from re-appearing while the aim is active.
        if not C.casting then
            C.inAutoAim = true
            ShowBar(C.nameAuto, C.autoIcon, barStart, barEnd)
        end
    else
        -- Aim window expired without a shot firing (e.g. movement delay).
        -- Cancel the bar if it is up, regardless of C.inAutoAim.
        C.inAutoAim = false
        if C.casting and C.spellName == C.nameAuto then
            EndCast(false)
        end
    end
end)

-- Regular casts (Aimed Shot, Steady Shot, and Multi-Shot as fallback).
-- eventSpellName is arg2 from UNIT_SPELLCAST_START (old TBC API = spell name).
local function StartCast(eventSpellName)
    local name, _, icon, startMS, endMS = UnitCastingInfo("player")

    if name then
        -- Normal path: UnitCastingInfo populated (Aimed Shot, Steady Shot)
        if not C.tracked[name] then return end
        ShowBar(name, icon, startMS / 1000, endMS / 1000)
    else
        -- Fallback: UnitCastingInfo returned nil (can happen for Multi-Shot).
        -- Use the event spell name + GetSpellInfo for timing.
        name = eventSpellName
        if not name or not C.tracked[name] then return end
        if name == C.nameAuto then return end  -- auto shot handled separately

        local _, _, spellIcon, castTimeMs = GetSpellInfo(name)
        if type(castTimeMs) ~= "number" or castTimeMs <= 0 then return end
        local now = GetTime()
        ShowBar(name, spellIcon, now, now + castTimeMs / 1000)
    end
end

EndCast = function(failed)
    if not C.casting then return end
    if not failed then
        -- Guard: some spells (Aimed Shot in TBC Classic) fire
        -- UNIT_SPELLCAST_SUCCEEDED immediately at cast start rather than at cast
        -- completion.  If significant time remains on the bar, don't clear it here;
        -- the safety timeout in OnUpdate will handle cleanup at the right time.
        local now = GetTime()
        if C.endTime > 0 and now < C.endTime - 0.2 then return end
    end
    C.casting = false
    if failed then
        -- Brief red flash before hiding
        C.flashEnd = GetTime() + FLASH_DURATION
        bar:SetWidth(math.max(0.01, cachedBarW))
        bar:SetColorTexture(0.9, 0.15, 0.15, 0.9)
    end
    -- On success or cancel: OnUpdate hides the frame next tick
end

-- =========================================================
-- OnUpdate: advance the fill bar
-- =========================================================

frame:SetScript("OnUpdate", function(self, elapsed)
    local now = GetTime()

    -- HOLD state: the auto-shot aim bar finished but the shot hasn't fired yet
    -- (retry-timer window). Pulse the orange glow until the shot lands (cleared
    -- in UNIT_SPELLCAST_SUCCEEDED) or an exit condition is hit.
    if C.holding then
        local moving = GetUnitSpeed("player") > 0
        if not ExsarLogic.ShouldShowHoldWarning(C.autoActive, moving, now, C.holdEnd) then
            EndHold()
            ShowPlaceholder()
            return
        end
        holdGlow:SetAlpha(ExsarLogic.PulseAlpha(now, HOLD_PULSE_HZ, HOLD_MIN_A, HOLD_MAX_A))
        return
    end

    -- Flash state: hold the bar at full red briefly, then show placeholder/hide
    if C.flashEnd > 0 then
        if now >= C.flashEnd then
            C.flashEnd = 0
            ShowPlaceholder()
        end
        return
    end

    -- Cancel the Auto Shot aim bar the instant the player starts moving.
    -- Checked here (same OnUpdate that advances the fill) so cancellation is
    -- never one frame behind the visual.
    if C.casting and C.spellName == C.nameAuto and GetUnitSpeed("player") > 0 then
        C.casting   = false
        C.inAutoAim = false
        ShowPlaceholder()
        return
    end

    -- Safety: if a bar is still up after its expected end time, hide it.
    -- Covers Auto Shot (aim window expiry) and Multi-Shot (post-fire animation).
    if C.casting and now >= C.endTime then
        -- Auto Shot: the aim bar reached its predicted end but the shot may not
        -- have fired yet (retry timer). Enter the HOLD glow instead of hiding,
        -- so the player waits out the hidden delay. Only while still stationary
        -- and auto-repeat is on — movement/toggle-off just clears the bar.
        if C.spellName == C.nameAuto and C.holdWarn and C.autoActive
            and GetUnitSpeed("player") <= 0 then
            BeginHold(now)
            return
        end
        C.casting   = false
        C.inAutoAim = false
        ShowPlaceholder()
        return
    end

    if not C.casting then
        ShowPlaceholder()
        return
    end

    local duration = C.endTime - C.startTime
    if duration <= 0 then
        C.casting = false
        frame:Hide()
        return
    end

    local frac      = math.min((now - C.startTime) / duration, 1)
    local remaining = math.max(0, C.endTime - now)

    bar:SetWidth(math.max(0.01, frac * cachedBarW))

    -- Only call SetText when the displayed string would change; SetText triggers
    -- a full font layout pass in WoW's engine every call, causing micro-hitches.
    local newStr = remaining >= 10
        and string.format("%d",   math.ceil(remaining))
        or  string.format("%.1f", remaining)
    if newStr ~= C.lastTimeStr then
        C.lastTimeStr = newStr
        timeText:SetText(newStr)
    end
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("START_AUTOREPEAT_SPELL")
frame:RegisterEvent("STOP_AUTOREPEAT_SPELL")
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

frame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, _, arg5)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, cbDB, 0, -270)
        ApplySize()
        C.locked   = cbDB().locked and true or false
        C.holdWarn = cbDB().holdWarning ~= false
        if not C.locked then ShowPlaceholder() end

    elseif event == "PLAYER_ENTERING_WORLD" then
        C.nameAuto   = GetSpellInfo(SPELL_ID_AUTO)   or "Auto Shot"
        C.nameAimed  = GetSpellInfo(SPELL_ID_AIMED)  or "Aimed Shot"
        C.nameSteady = GetSpellInfo(SPELL_ID_STEADY) or "Steady Shot"
        C.nameMulti  = GetSpellInfo(SPELL_ID_MULTI)  or "Multi-Shot"
        C.nameFeign  = GetSpellInfo(SPELL_ID_FEIGN)  or "Feign Death"
        C.tracked = {
            [C.nameAuto]   = true,
            [C.nameAimed]  = true,
            [C.nameSteady] = true,
            [C.nameMulti]  = true,
        }
        -- Cache icons so event handlers never call GetSpellInfo in the hot path
        local _, _, autoIcon  = GetSpellInfo(SPELL_ID_AUTO)
        local _, _, aimedIcon = GetSpellInfo(SPELL_ID_AIMED)
        local _, _, multiIcon = GetSpellInfo(SPELL_ID_MULTI)
        C.autoIcon  = autoIcon
        C.aimedIcon = aimedIcon
        C.multiIcon = multiIcon
        RefreshBaseSpeed()
        RefreshAutoSpeed()
        RefreshAutoAimTime()

    elseif event == "START_AUTOREPEAT_SPELL" then
        C.autoActive  = true
        autoAimMoving = GetUnitSpeed("player") > 0
        if not autoAimMoving then
            autoAimStopTime = GetTime()  -- already stationary; seed the stop time
        end
        if C.fdReset then
            -- Resuming attack after Feign Death: the swing cycle restarted, so
            -- the next auto is a full weapon cycle from now (matches the
            -- RangedSwingTimer model). Without this anchor, lastAutoTime == 0
            -- would take the first-shot fast path and show the aim bar
            -- immediately, a full cycle early.
            C.fdReset      = false
            C.lastAutoTime = GetTime()
        end

    elseif event == "STOP_AUTOREPEAT_SPELL" then
        C.autoActive  = false
        C.inAutoAim   = false
        autoAimMoving = false
        EndHold()
        if C.casting and C.spellName == C.nameAuto then
            C.casting = false   -- frame hides on next OnUpdate tick
        end

    elseif event == "UNIT_SPELLCAST_START" then
        if arg1 == "player" then
            -- Auto Shot does NOT fire UNIT_SPELLCAST_START in TBC Classic; its aim
            -- window is detected in OnUpdate using the last-shot timestamp + weapon
            -- speed.  arg2 is the spell name in the old TBC API.
            StartCast(arg2)
        end

    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if arg1 == "player" then EndCast(true) end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" then
            local isAuto = (arg2 == C.nameAuto) or (arg3 == SPELL_ID_AUTO) or (arg5 == SPELL_ID_AUTO)
            if isAuto then
                -- The shot landed: end any HOLD glow (its whole purpose was to
                -- bridge the gap until this event). Also close out the aim bar
                -- itself — if the fire event beat the predicted endTime (latency
                -- jitter), leaving it up would spuriously BeginHold after the
                -- shot already fired.
                EndHold()
                if C.casting and C.spellName == C.nameAuto then
                    C.casting = false
                end
                -- Resync shot timestamp; resets the inAutoAim gate for the next cycle
                C.lastAutoTime = GetTime()
                C.inAutoAim    = false
                -- Refresh speed and aim time; haste or latency may have changed
                RefreshAutoSpeed()
                RefreshAutoAimTime()
            end

            -- Aimed Shot landing resets the server-side auto shot cooldown:
            -- the next auto (and its aim window) is a full weapon cycle from
            -- the landing, not from the last auto. Without this re-anchor the
            -- aim bar appears on the stale schedule and no shot follows.
            local isAimed = (arg2 == C.nameAimed)
                or AIMED_SHOT_IDS[arg3]
                or AIMED_SHOT_IDS[arg5]
            if isAimed then
                C.lastAutoTime = GetTime()
                C.inAutoAim    = false
                RefreshAutoSpeed()
                RefreshAutoAimTime()
            end

            -- Feign Death cancels the shot cycle; it restarts when attacking
            -- resumes (START_AUTOREPEAT_SPELL anchors a full cycle from the
            -- resume — see fdReset there).
            local isFeign = (arg2 == C.nameFeign)
                or (arg3 == SPELL_ID_FEIGN)
                or (arg5 == SPELL_ID_FEIGN)
            if isFeign then
                EndHold()
                C.fdReset      = true
                C.lastAutoTime = 0
                C.inAutoAim    = false
                if C.casting and C.spellName == C.nameAuto then
                    C.casting = false   -- stale aim bar; frame hides next tick
                end
            end

            -- Multi-Shot bar was started by combatFrame on SPELL_CAST_START;
            -- EndCast(false) clears it when the shot fires.
            EndCast(false)
        end

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then
            -- Feign Death ended (buff faded): the swing cycle restarts now, so
            -- anchor the aim-window prediction a full cycle from this moment.
            -- (START_AUTOREPEAT_SPELL keeps a fallback anchor in case the
            -- fade was missed, but it does not reliably fire after FD.)
            if C.fdReset and not ExsarUI.PlayerHasBuff(C.nameFeign) then
                C.fdReset      = false
                C.lastAutoTime = GetTime()
            end
            RefreshAutoSpeed()
            RefreshAutoAimTime()
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        RefreshBaseSpeed()
        RefreshAutoSpeed()
        RefreshAutoAimTime()
    end
end)

-- =========================================================
-- Suppress the default cast bar for spells we handle ourselves
-- =========================================================
-- CastingBarFrame.Show is a C-level method; replacing it in Lua doesn't
-- intercept C-side calls.  HookScript("OnShow") fires from the WoW engine
-- immediately after the frame becomes visible (before the next render),
-- so we can hide it with no visible flash.
if PlayerCastingBarFrame then
    -- OnShow: suppress when the bar first appears for a tracked spell.
    PlayerCastingBarFrame:HookScript("OnShow", function(self)
        local name = UnitCastingInfo("player")
        if name and C.tracked[name] then
            self:Hide()
        end
    end)

    -- OnUpdate: keep suppressed every frame while our bar is active.
    -- Handles cast-to-cast transitions where the default bar stays visible
    -- between casts and never re-triggers OnShow, and also covers the race
    -- where UnitCastingInfo is nil at the moment OnShow fires.
    PlayerCastingBarFrame:HookScript("OnUpdate", function(self)
        if C.casting and C.spellName ~= C.nameAuto then
            self:Hide()
        end
    end)
end

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarUI.AddSlashReset("castbarreset", frame, cbDB, "Cast bar", 0, -270)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Cast Bar",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, cbDB, frame)

        ExsarAddon.CreateSlider(parent, "Bar Width", 16, y, 100, 400, 1,
            function() return cbDB().width or DEFAULT_WIDTH end,
            function(v)
                local w = math.floor(v + 0.5)
                cbDB().width = w
                ApplySize()
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Auto-shot HOLD warning (orange glow)", 16, y,
            function() return cbDB().holdWarning ~= false end,
            function(v)
                cbDB().holdWarning = v
                C.holdWarn = v
                if not v then EndHold() end
            end
        )
        y = y - 30

        y = ExsarUI.AddLockCheckbox(parent, y, cbDB, frame, function(v)
            C.locked = v
            if not C.casting then ShowPlaceholder() end
        end)

        y = ExsarUI.AddResetButton(parent, y, cbDB, frame, "Cast bar", 0, -270)

        return y
    end,
})
