-- MeleeWeaveHelper module
-- A single binary "WEAVE NOW!" cue for melee weaving, plus a countdown of how
-- long the weave window stays open. This is a TRAINING tool, not a metronome:
-- it's meant to be a stable, forgiving target you grow into (the honest
-- correction lives in AutoShotMonitor's overdue readout, not here).
--
-- The cue is condition-based, NOT rotation-based (see ExsarLogic.WeaveNowState):
--   WEAVE NOW = melee swing ready · not casting · weaveCost < time-to-next-auto
--               · ( on GCD  OR  time-to-auto < hasted Steady cast )
-- The final OR is the crux — it lights the cue whenever weaving won't cost you a
-- shot: you're GCD-locked anyway (arcane/multi gap), OR there isn't room to fit a
-- shot before the auto (the slow post-cast tail AND the fast auto-auto gap). The
-- window countdown self-scales with haste for free (wide when slow, tight when
-- hasted). Hysteresis (ExsarLogic.HoldCue) holds the cue steady against input
-- jitter so it reads as "window open", not a strobing light.
--
-- Gated on being in weave range (<= 8yd — you can't weave from afar) and on the
-- solo/party/raid context, so it self-silences on pure-ranged fights with no
-- toggling. Settings stored under ExsarAddonDB.meleeWeave.

local ADDON_NAME = "ExsarAddon"

local mwDB = ExsarUI.MakeDB("meleeWeave")

-- =========================================================
-- Constants + tunable defaults (all overridable via config sliders)
-- =========================================================

local POLL_INTERVAL   = 0.05
local GCD_PROBE_SPELL = "Wing Clip"   -- no cooldown of its own → reports the GCD
local STEADY_BASE_CAST = 1.5
-- When the GCD jumps up (a new GCD just started) it may be the first frame of a
-- cast whose UNIT_SPELLCAST_START hasn't dispatched yet -- GetSpellCooldown can
-- report the GCD a frame before UnitCastingInfo sees the cast. Suppress the cue
-- for this long after a GCD jump so that race can't flash it at cast start.
local GCD_SETTLE = 0.15

-- Realistic defaults, grounded in the actual weave / auto-shot timings (tune at
-- the dummy). The cue still reads as forgiving because of the anti-flicker hold
-- and because AutoShotMonitor's overdue counter — not this cue — is the honest
-- scorecard. Knob directions: raising weaveCost/shotFitBuffer lights the cue in
-- MORE of the cycle; lowering them defers more to shooting.
local DEF_WEAVE_COST    = 0.4    -- in + swing + out (the timing reference's ~0.4s weave)
local DEF_SHOT_FIT_BUF  = 0.1    -- reaction/latency margin on "cast finishes before the auto is due"
local DEF_MELEE_LOOK    = 0.1    -- step-in lead so the swing is ready as you arrive
local DEF_CUE_MIN_ON    = 0.1    -- minimal anti-flicker hold (bridges event jitter)

local WEAVE_MAX_YD = 8           -- weave range = melee (<=5) + weave band (5-8)

-- In-weave-range probe: Wing Clip (5yd) + an 8yd item. Only these two thresholds
-- matter for the <=8yd gate; degrades to melee-only if the item is unavailable.
local WEAVE_CHECKERS = {
    { range = 5, spell = "Wing Clip" },
    { range = 8, item  = 34368 },        -- Attuned Crystal Cores
}

local FRAME_W = 140
local FRAME_H = 44
local BAR_MAX_W = FRAME_W - 16
local BAR_H = 12

local COLOR_CUE     = { 0.25, 0.95, 0.35 }   -- green "WEAVE NOW!"
local COLOR_BAR_OK  = { 0.20, 0.85, 0.30 }   -- bar green (plenty of window left)
local COLOR_BAR_LOW = { 1.00, 0.60, 0.10 }   -- bar orange (window closing)

local PREVIEW_ALPHA = 0.45   -- dimmed static preview shown while unlocked

-- Comic-pop feedback text (landed weave / late weave / missed window)
local COLOR_HIT   = { 0.30, 1.00, 0.35 }   -- green "WEAVE HIT!"
local COLOR_LATE  = { 1.00, 0.65, 0.10 }   -- orange "LATE - TAP STRAFE"
local COLOR_MISS  = { 1.00, 0.25, 0.20 }   -- red "WEAVE MISS!"
local POP_DUR       = 0.8  -- total pop lifetime (s)
local POP_RISE      = 35   -- how far the text floats up over its life (px)
local POP_FONT_SIZE = 30   -- default pop face
local POP_FONT_LATE = 18   -- the coaching cue is a long string

-- Stale-position melee retry (see CLAUDE.md "The Melee Retry Timer"). Press ->
-- landed-swing latency is bimodal: ~0.11s when the server's position snapshot
-- was fresh, ~0.61s when it was stale and `/startattack` had to wait out the
-- 500ms retry. RETRY_THRESHOLD sits in the empty gap between the two modes.
local RETRY_THRESHOLD  = 0.35   -- press->swing latency at or above this = a retry
local PRESS_ATTRIB_WIN = 3.0    -- a swing later than this belongs to no press

-- Windfury proc flourish: a quick slash animation + whoosh when a Windfury
-- extra-attack lands on your melee (Windfury Totem from a group shaman grants a
-- single extra attack — one SPELL_EXTRA_ATTACKS proc, so no de-dupe needed).
-- Pure celebration/feedback — gated behind its own config toggle.
local WINDFURY_SOUND = 568519  -- Whirlwind (FileDataID) — a sweeping "whoosh"
local SLASH_DURATION = 0.8     -- slash flourish lifetime (s) — a quick, punchy sweep

-- TEMP DIAGNOSTIC: persistent ring buffer for the Windfury-proc flourish, so a
-- rare shaman-grouped repro can be captured and inspected later via /exsar wfdump
-- (chat is useless mid-raid — see the diagnostic-persistence principle). Remove
-- once the proc flourish is confirmed working.
local WF_DEBUG_CAP = 80

-- A MISS is only true once the auto shot has actually FIRED: the weave window
-- closes ~weaveCost before the auto, and a retried swing can still land in that
-- gap. So arm the MISS at window close and resolve it when the auto lands (or a
-- swing cancels it). MISS_MAX_WAIT drops a pending MISS if no auto ever comes
-- (auto-repeat off, target died) rather than stranding it into the next pull.
local MISS_MAX_WAIT = 1.5

-- =========================================================
-- State
-- =========================================================

local S = {
    holdUntil     = 0,     -- ExsarLogic.HoldCue hysteresis timestamp
    shown         = false,
    windowMax     = 0.01,  -- window length captured when the cue opened (for the bar)
    weaveCost     = DEF_WEAVE_COST,  -- cached each poll so the per-frame render is cheap
    lastNumStr    = "",
    gcdRemPrev    = 0,     -- GCD remaining last poll (to detect a rising/refreshed GCD)
    gcdSettleUntil = 0,    -- suppress the cue until this time after a GCD jump (cast-start race)
    windowOpen      = false,  -- raw weave window open (for hit/miss feedback lifecycle)
    hitDuringWindow = false,  -- a melee landed while the current window was open
    missPending     = false,  -- window expired unweaved; waiting on the auto to confirm
    missAnchor      = 0,      -- auto.lastShotTime when the MISS was armed
    missDeadline    = 0,      -- give up on the pending MISS after this time
    wfPreviewNext   = 0,      -- next time to re-fire the unlocked Windfury preview slash
}

-- How often the Windfury slash re-fires in the unlocked preview loop. Leaves a
-- clear gap after the animation so each swipe reads as a distinct pulse.
local WF_PREVIEW_INTERVAL = SLASH_DURATION + 0.6

local results = {}   -- reused range-probe results
local auto  = ExsarUI.GetAutoShotTracker()
local melee = ExsarUI.GetMeleeSwingTracker()

-- =========================================================
-- Frame + visuals
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "MeleeWeaveFrame", UIParent)
frame:SetSize(FRAME_W, FRAME_H)
ExsarUI.SetupMovableFrame(frame, mwDB, { bgAlpha = 0 })
frame:Hide()

local weaveText = frame:CreateFontString(nil, "OVERLAY")
weaveText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE, THICKOUTLINE")
weaveText:SetPoint("TOP", frame, "TOP", 0, -3)
weaveText:SetTextColor(COLOR_CUE[1], COLOR_CUE[2], COLOR_CUE[3], 1)
weaveText:SetText("WEAVE NOW!")
weaveText:Hide()

-- Countdown bar (drains right→left as the window closes)
local barBg = frame:CreateTexture(nil, "ARTWORK")
barBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -26)
barBg:SetSize(BAR_MAX_W, BAR_H)
barBg:SetColorTexture(0.1, 0.1, 0.1, 0.7)
barBg:Hide()

local barFill = frame:CreateTexture(nil, "OVERLAY")
barFill:SetPoint("TOPLEFT", barBg, "TOPLEFT", 0, 0)
barFill:SetSize(BAR_MAX_W, BAR_H)
barFill:SetColorTexture(COLOR_BAR_OK[1], COLOR_BAR_OK[2], COLOR_BAR_OK[3], 0.9)
barFill:Hide()

local numText = frame:CreateFontString(nil, "OVERLAY")
numText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
numText:SetPoint("CENTER", barBg, "CENTER", 0, 0)
numText:SetTextColor(1, 1, 1, 1)
numText:Hide()

-- Comic-pop feedback text ("WEAVE HIT!" / "WEAVE MISS!"), on the shared helper's
-- own UIParent-child frame so it fires even when the widget frame is hidden
-- (e.g. locked with no cue up), while tracking the widget's position.
local pop = ExsarUI.CreateComicPop(frame, {
    duration = POP_DUR,
    rise     = POP_RISE,
    fontSize = POP_FONT_SIZE,
    getScale = function() return mwDB().scale or 1 end,
})

-- size defaults to POP_FONT_SIZE; the coaching cue is a longer string and needs
-- a smaller face to stay on screen.
local function TriggerPop(text, color, size)
    if mwDB().feedback == false then return end
    pop:Trigger(text, color, size)
end

-- Windfury proc flourish: a blade-slash streaking up-and-forward, on the shared
-- helper's own UIParent-child frame (fires even when the widget frame is hidden).
local slash = ExsarUI.CreateSlashEffect(frame, {
    duration = SLASH_DURATION,
    getScale = function() return mwDB().scale or 1 end,
})

-- =========================================================
-- Config accessors (read live so slider edits apply immediately)
-- =========================================================

local function num(key, default)
    local v = mwDB()[key]
    return type(v) == "number" and v or default
end

-- =========================================================
-- Group context + target helpers
-- =========================================================

local function GetGroupContext()
    if IsInRaid() then return "raid" end
    if IsInGroup() then return "party" end
    return "solo"
end

local function ContextEnabled()
    local db = mwDB()
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

-- Fired by the shared melee tracker when a melee attack lands (white swing or
-- Raptor Strike connects), with the landing time. Confirms a landed weave and
-- suppresses the MISS for the current window — including a MISS already armed
-- and waiting on the auto shot, since a retried swing lands inside that gap.
--
-- The pop distinguishes a clean weave from a stale-position retry: a swing that
-- took >= RETRY_THRESHOLD from the macro press only landed because the 500ms
-- melee retry timer fired, which the player can avoid by tapping a movement key
-- before the macro (it re-snapshots position server-side).
local function OnMeleeLanded(landedTime)
    S.hitDuringWindow = true
    S.missPending     = false          -- a landed swing is never a miss
    if not (ContextEnabled() and UnitAffectingCombat("player") and HasAttackableTarget()) then
        return
    end
    local _, isRetry = ExsarLogic.MeleeRetryDelay(
        melee.lastPress, landedTime or GetTime(), RETRY_THRESHOLD, PRESS_ATTRIB_WIN)
    if isRetry then
        TriggerPop("LATE - TAP STRAFE", COLOR_LATE, POP_FONT_LATE)
    else
        TriggerPop("WEAVE HIT!", COLOR_HIT)
    end
end
melee:OnLanded(OnMeleeLanded)

-- Fired by the shared melee tracker on a Windfury extra-attack proc. Optional
-- eye-candy (own config toggle, default ON): a quick up-and-forward slash + a
-- "whoosh". Windfury Totem grants a single extra attack, so one proc = one
-- flourish (no de-dupe needed).
-- ==========================================================================
-- TEMP DIAGNOSTIC: Windfury-proc capture (remove once confirmed working)
-- ==========================================================================
-- Persists to ExsarAddonDB.meleeWeave.wfDebugLog so a rare shaman repro can be
-- reviewed after the fact with /exsar wfdump. Captures the whole chain:
--   raw     — every player SPELL_EXTRA_ATTACKS seen by an INDEPENDENT combat-log
--             frame (does the event even arrive live? does the name match?)
--   proc    — the shared melee tracker's OnWindfury callback actually fired
--   gate    — gating result inside OnWindfuryProc (effect/context/combat)
--   fire    — slash+sound dispatched
--   test    — /exsar wftest force-fire
local function wfLog(msg)
    local db = mwDB()
    local log = db.wfDebugLog or {}
    log[#log + 1] = date("%H:%M:%S") .. "  " .. msg
    while #log > WF_DEBUG_CAP do table.remove(log, 1) end
    db.wfDebugLog = log
    if db.wfDebugEcho then print("|cffffcc00[WeaveWF]|r " .. msg) end
end

-- Independent listener: proves whether the SPELL_EXTRA_ATTACKS event is delivered
-- live and whether ExsarLogic.IsWindfuryProc matches its name — separate from the
-- shared tracker, so we can tell "event never arrived" from "arrived, name didn't
-- match" from "matched, but tracker/gating dropped it".
local wfDiag = CreateFrame("Frame")
wfDiag:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
wfDiag:SetScript("OnEvent", function()
    local _, subEvent, _, srcGUID, _, _, _, _, _, _, _, spellId, spellName =
        CombatLogGetCurrentEventInfo()
    if subEvent ~= "SPELL_EXTRA_ATTACKS" then return end
    if srcGUID ~= UnitGUID("player") then return end
    wfLog(string.format("raw SPELL_EXTRA_ATTACKS id=%s name=%q matched=%s",
        tostring(spellId), tostring(spellName),
        tostring(ExsarLogic.IsWindfuryProc(subEvent, spellName))))
end)

local function OnWindfuryProc()
    local effect = mwDB().windfuryEffect
    local ctx    = ContextEnabled()
    local combat = UnitAffectingCombat("player")
    wfLog(string.format("proc callback fired: effect=%s ctx=%s combat=%s",
        tostring(effect), tostring(ctx), tostring(combat)))
    if effect == false then wfLog("gate: DROPPED (effect off)"); return end
    if not (ctx and combat) then wfLog("gate: DROPPED (context/combat)"); return end
    wfLog("fire: slash + whoosh dispatched")
    slash:Trigger()
    PlaySoundFile(WINDFURY_SOUND, "Master")
end
melee:OnWindfury(OnWindfuryProc)

-- /exsar wftest — force-fire the flourish (bypasses detection + gating) to bisect
-- "effect broken" vs "detection broken". Named local so the config button reuses it.
local function WFTest()
    wfLog(string.format("test: force-fire (effect=%s ctx=%s combat=%s scale=%s)",
        tostring(mwDB().windfuryEffect), tostring(ContextEnabled()),
        tostring(UnitAffectingCombat("player")), tostring(mwDB().scale)))
    slash:Trigger()
    PlaySoundFile(WINDFURY_SOUND, "Master")
    print("|cffffcc00[WeaveWF]|r wftest fired — did you see a slash + hear a whoosh?")
end
ExsarAddon.AddSlashCommand("wftest", WFTest)

-- /exsar wfdump — open the captured log in a copy-paste window.
local function WFDump()
    local log = mwDB().wfDebugLog
    if not log or #log == 0 then
        print(ADDON_NAME .. ": no Windfury events captured yet.")
        return
    end
    local lines = { ADDON_NAME .. " — " .. #log .. " Windfury diagnostic event(s)",
        string.rep("-", 72) }
    for _, line in ipairs(log) do lines[#lines + 1] = line end
    ExsarUI.ShowCopyableText(table.concat(lines, "\n"),
        { title = "ExsarAddon — Windfury Diagnostics" })
end
ExsarAddon.AddSlashCommand("wfdump", WFDump)

-- /exsar wfclear — wipe the capture; /exsar wfecho — toggle live chat echo.
ExsarAddon.AddSlashCommand("wfclear", function()
    mwDB().wfDebugLog = nil
    print(ADDON_NAME .. ": Windfury diagnostic log cleared.")
end)
ExsarAddon.AddSlashCommand("wfecho", function()
    local db = mwDB()
    db.wfDebugEcho = not db.wfDebugEcho
    print(ADDON_NAME .. ": Windfury live chat echo " ..
        (db.wfDebugEcho and "ON" or "OFF") .. " (capture always persists).")
end)
-- ==========================================================================
-- END TEMP DIAGNOSTIC
-- ==========================================================================

-- =========================================================
-- Cue rendering
-- =========================================================

local function HideCue()
    if S.lastNumStr ~= "" then S.lastNumStr = ""; numText:Hide() end
    weaveText:Hide()
    barBg:Hide()
    barFill:Hide()
end

local function ShowCue(windowRem)
    weaveText:Show()
    barBg:Show()

    local frac = 0
    if S.windowMax > 0 then
        frac = windowRem / S.windowMax
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    end
    barFill:SetWidth(math.max(0.01, frac * BAR_MAX_W))
    local c = frac > 0.33 and COLOR_BAR_OK or COLOR_BAR_LOW
    barFill:SetColorTexture(c[1], c[2], c[3], 0.9)
    barFill:Show()

    local rem = windowRem > 0 and windowRem or 0
    local str = string.format("%.1fs", rem)
    if str ~= S.lastNumStr then
        S.lastNumStr = str
        numText:SetText(str)
        numText:Show()
    end
end

-- Static, dimmed preview shown while unlocked so the widget's real footprint
-- (cue text + a partly-full countdown bar) is visible for positioning.
local function ShowPreviewContent()
    S.windowMax = 1.0
    ShowCue(0.6)
end

-- =========================================================
-- Update
-- =========================================================

local function UpdateDisplay()
    local unlocked = not mwDB().locked
    local now = GetTime()
    S.weaveCost = num("weaveCost", DEF_WEAVE_COST)

    -- GCD tracking runs every poll (not just in weave range) so the jump-detection
    -- state stays fresh. A GCD that jumps UP means a new GCD just started, which
    -- may be a cast whose UNIT_SPELLCAST_START hasn't dispatched yet — arm a short
    -- settle so the cast-start race can't flash the cue.
    local gcdStart, gcdDur = GetSpellCooldown(GCD_PROBE_SPELL)
    local gcdRem = 0
    if gcdStart and gcdStart > 0 and gcdDur and gcdDur > 0 then
        gcdRem = (gcdStart + gcdDur) - now
        if gcdRem < 0 then gcdRem = 0 end
    end
    if gcdRem > S.gcdRemPrev + 0.05 then
        S.gcdSettleUntil = now + GCD_SETTLE
    end
    S.gcdRemPrev = gcdRem
    local casting = UnitCastingInfo("player") ~= nil or now < S.gcdSettleUntil
    local timeToAuto = auto:TimeToNextAuto(now)

    local rawOn, windowRem = false, 0
    if ContextEnabled() and UnitAffectingCombat("player") and HasAttackableTarget() then
        local _, maxR = ExsarUI.ProbeRangeBracket("target", WEAVE_CHECKERS, results)
        if maxR ~= nil and maxR <= WEAVE_MAX_YD then
            local steadyCast = ExsarLogic.HastedCastTime(STEADY_BASE_CAST, auto.speed, auto.baseSpeed)
                + num("shotFitBuffer", DEF_SHOT_FIT_BUF)
            rawOn, windowRem = ExsarLogic.WeaveNowState({
                meleeReady     = melee:Ready(now, num("meleeReadyLookahead", DEF_MELEE_LOOK)),
                casting        = casting,
                gcdRemaining   = gcdRem,
                timeToAuto     = timeToAuto,
                weaveCost      = S.weaveCost,
                steadyCastTime = steadyCast,
            })
        end
    end

    -- Hit/miss feedback lifecycle, keyed on the RAW window (not the hysteresis
    -- display). MISS fires only when the window truly EXPIRED (the countdown
    -- reached 0: timeToAuto fell to weaveCost) with no landed swing during it —
    -- not when it closed because you cast or stepped out of range.
    if mwDB().feedback == false then
        S.windowOpen  = false
        S.missPending = false
    elseif rawOn then
        if not S.windowOpen then
            S.windowOpen = true
            S.hitDuringWindow = false
        end
    elseif S.windowOpen then
        S.windowOpen = false
        local expired = (not casting)
            and (timeToAuto == nil or timeToAuto <= S.weaveCost + 0.05)
        if expired and not S.hitDuringWindow then
            -- Don't call it yet. The window closes ~weaveCost before the auto
            -- fires, and a swing delayed by the melee retry timer can still land
            -- in that gap. Wait for the auto to actually fire (or a swing to
            -- cancel this) before declaring a miss.
            S.missPending  = true
            S.missAnchor   = auto.lastShotTime
            S.missDeadline = now + MISS_MAX_WAIT
        end
    end

    -- Resolve a pending MISS: the auto shot firing is what truly closed the
    -- window. If no auto arrives (auto-repeat off, target lost), drop it quietly.
    if S.missPending then
        if auto.lastShotTime > S.missAnchor then
            S.missPending = false
            TriggerPop("WEAVE MISS!", COLOR_MISS)
        elseif now >= S.missDeadline then
            S.missPending = false
        end
    end

    local shown
    shown, S.holdUntil = ExsarLogic.HoldCue(rawOn, now, S.holdUntil, num("cueMinOnTime", DEF_CUE_MIN_ON))

    -- Capture the window length as the cue opens, so the bar drains from full.
    if shown and not S.shown then
        S.windowMax = windowRem > 0 and windowRem or 0.01
    end
    S.shown = shown

    if shown then
        frame:SetAlpha(1)
        frame:Show()
        ShowCue(windowRem)
    elseif unlocked then
        frame:SetAlpha(PREVIEW_ALPHA)
        ShowPreviewContent()
        frame:Show()
        -- Loop the Windfury slash (silently) so its placement can be previewed
        -- while positioning the widget. Only when the effect is enabled.
        if mwDB().windfuryEffect ~= false then
            if now >= S.wfPreviewNext then
                slash:Trigger()
                S.wfPreviewNext = now + WF_PREVIEW_INTERVAL
            end
        end
    else
        HideCue()
        frame:Hide()
    end
end

-- =========================================================
-- Polling + events
-- =========================================================

ExsarUI.CreatePoller(nil, POLL_INTERVAL, UpdateDisplay)

-- Render the countdown bar every frame: the 0.05s poll only makes the show/hide
-- decision (range/GCD/cast checks don't need 60fps), but windowRemaining is
-- recomputed live from the auto cycle here so the bar drains smoothly, not steppy.
frame:SetScript("OnUpdate", function()
    if not S.shown then return end
    local tta = auto:TimeToNextAuto(GetTime())
    ShowCue(tta and (tta - S.weaveCost) or 0)
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, mwDB, 0, -180)
        if not mwDB().locked then frame:Show() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateDisplay()
    end
end)

-- =========================================================
-- Slash sub-command
-- =========================================================

ExsarUI.AddSlashReset("weavereset", frame, mwDB, "Melee weave helper", 0, -180)

-- =========================================================
-- Register with Core
-- =========================================================

local function AddKnobSlider(parent, y, label, key, minV, maxV, default)
    ExsarAddon.CreateSlider(parent, label, 16, y, minV, maxV, 0.05,
        function() return num(key, default) end,
        function(v) mwDB()[key] = math.floor(v * 20 + 0.5) / 20 end
    )
    return y - 55
end

ExsarAddon.RegisterModule({
    name = "Melee Weave Helper",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateCheckbox(parent, "Enable in solo", 16, y,
            function() return mwDB().enableSolo ~= false end,
            function(v) mwDB().enableSolo = v; UpdateDisplay() end
        )
        y = y - 30
        ExsarAddon.CreateCheckbox(parent, "Enable in party", 16, y,
            function() return mwDB().enableParty ~= false end,
            function(v) mwDB().enableParty = v; UpdateDisplay() end
        )
        y = y - 30
        ExsarAddon.CreateCheckbox(parent, "Enable in raid", 16, y,
            function() return mwDB().enableRaid ~= false end,
            function(v) mwDB().enableRaid = v; UpdateDisplay() end
        )
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Hit / miss feedback text", 16, y,
            function() return mwDB().feedback ~= false end,
            function(v) mwDB().feedback = v end
        )
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Windfury proc flourish (slash + whoosh)", 16, y,
            function() return mwDB().windfuryEffect ~= false end,
            function(v) mwDB().windfuryEffect = v end
        )
        y = y - 34

        -- TEMP DIAGNOSTIC: Windfury-proc capture help + dump. Remove with the
        -- rest of the WF diagnostic block once the flourish is confirmed working.
        local wfNote = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        wfNote:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
        wfNote:SetWidth(360)
        wfNote:SetJustifyH("LEFT")
        wfNote:SetText("|cffffcc00Windfury diagnostics (temporary):|r the flourish only "
            .. "fires on a real Windfury Totem proc (needs a grouped shaman). Each proc "
            .. "is captured to SavedVariables so it survives the fight and /reload.\n"
            .. "  /exsar wftest  — force-fire the slash+whoosh now (no shaman needed)\n"
            .. "  /exsar wfdump  — show the captured proc log (copy-paste window)\n"
            .. "  /exsar wfclear — wipe the log   /exsar wfecho — live chat echo on/off\n"
            .. "When you group with a shaman: /exsar wfclear, weave the fight, then "
            .. "/exsar wfdump and send it over.")
        y = y - 108

        ExsarAddon.CreateButton(parent, "Test flourish now", 16, y, WFTest)
        ExsarAddon.CreateButton(parent, "Show Windfury log", 190, y, WFDump)
        y = y - 34

        y = AddKnobSlider(parent, y, "Weave cost (window/clip buffer, s)", "weaveCost", 0.2, 0.8, DEF_WEAVE_COST)
        y = AddKnobSlider(parent, y, "Shot-fit buffer (s)", "shotFitBuffer", 0.0, 0.5, DEF_SHOT_FIT_BUF)
        y = AddKnobSlider(parent, y, "Melee-ready lookahead (s)", "meleeReadyLookahead", 0.0, 0.4, DEF_MELEE_LOOK)
        y = AddKnobSlider(parent, y, "Cue hold / anti-flicker (s)", "cueMinOnTime", 0.0, 0.5, DEF_CUE_MIN_ON)

        y = ExsarUI.AddScaleSlider(parent, y, mwDB, frame)
        y = ExsarUI.AddLockCheckbox(parent, y, mwDB, frame, function()
            UpdateDisplay()
        end)
        y = ExsarUI.AddResetButton(parent, y, mwDB, frame, "Melee weave helper", 0, -180)
        return y
    end,
})
