-- CastBar module
-- Displays a cast bar for Hunter shots: Auto Shot, Aimed Shot, Steady Shot,
-- and Multi-Shot.  Each spell gets a distinct color; failed/interrupted casts
-- flash red briefly before the bar hides.
-- Settings are stored under ExsarAddonDB.castBar.

local ADDON_NAME = "ExsarAddon"

local function cbDB()
    ExsarAddonDB.castBar = ExsarAddonDB.castBar or {}
    return ExsarAddonDB.castBar
end

-- =========================================================
-- Constants
-- =========================================================

local DEFAULT_WIDTH  = 240
local DEFAULT_HEIGHT = 24
local ICON_SIZE      = DEFAULT_HEIGHT   -- icon is square, height of the bar
local FLASH_DURATION = 0.4
-- Auto Shot aim duration: base 0.5s + network latency (same formula as
-- SwingTimer's aimWindow).  Updated on login and after each Auto Shot fires.
-- YaHT uses a fixed 0.65s; SwingTimerPro uses 0.52 + latency; we use 0.5 +
-- latency which adapts to the player's actual network conditions.
local AUTO_AIM_TIME  = 0.65  -- default before first latency measurement

-- Used only to resolve localized spell names at login
local SPELL_ID_AUTO   = 75
local SPELL_ID_AIMED  = 19434   -- Rank 1 of Aimed Shot in TBC Classic (NOT 13954)
local SPELL_ID_STEADY = 34120
local SPELL_ID_MULTI  = 2643

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
    lastAutoTime = 0,      -- GetTime() of the last Auto Shot fire; drives aim-window detection
    autoSpeed    = 0,      -- hasted ranged weapon speed (seconds); from UnitRangedDamage
    inAutoAim    = false,  -- gate: true once the 0.5s aim window bar has been shown this cycle
    locked       = false,  -- cached; updated on ADDON_LOADED and lock toggle
    -- Resolved at PLAYER_ENTERING_WORLD:
    nameAuto    = "Auto Shot",
    nameAimed   = "Aimed Shot",
    nameSteady  = "Steady Shot",
    nameMulti   = "Multi-Shot",
    tracked     = {},     -- name -> true
}

local function RefreshAutoSpeed()
    local speed = select(1, UnitRangedDamage("player"))
    C.autoSpeed = (type(speed) == "number" and speed > 0) and speed or 0
end

local function RefreshAutoAimTime()
    local _, _, homeMs, worldMs = GetNetStats()
    local latency = math.max(
        type(homeMs)  == "number" and homeMs  or 0,
        type(worldMs) == "number" and worldMs or 0
    ) / 1000
    AUTO_AIM_TIME = 0.5 + latency
end

-- =========================================================
-- Frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "CastBarFrame", UIParent)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    cbDB().x = x
    cbDB().y = y
end)

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.6)

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
local placeholderText = frame:CreateFontString(nil, "OVERLAY")
placeholderText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
placeholderText:SetPoint("CENTER", frame, "CENTER", 0, 0)
placeholderText:SetTextColor(0.55, 0.55, 0.55, 0.9)
placeholderText:SetText("Cast Bar")
placeholderText:Hide()

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
    if name == C.nameSteady then return 0.15, 0.55, 0.95, 0.85 end  -- blue
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


-- Aimed Shot and Multi-Shot cast bars: UNIT_SPELLCAST_START is unreliable for
-- these spells in TBC Classic Anniversary, so we detect them via the combat log.
-- CombatLogGetCurrentEventInfo() is required on the modern client; the older
-- variadic-args approach (select(N, ...)) does not work here.
local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
combatFrame:SetScript("OnEvent", function(self, event)
    local _, subEvent, _, casterGUID, _, _, _, _, _, _, _, spellId, spellName =
        CombatLogGetCurrentEventInfo()
    if casterGUID ~= UnitGUID("player") then return end
    if subEvent == "SPELL_CAST_START" then
        if MULTI_SHOT_IDS[spellId] then
            local now = GetTime()
            ShowBar(C.nameMulti, C.multiIcon, now, now + 0.5)
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

-- Auto Shot aim-window ticker.
-- The main cast bar frame is hidden between casts, so its OnUpdate does not fire
-- and cannot detect the start of the aim window.  This separate frame is always
-- shown so it ticks every frame and can trigger ShowBar at the right moment.
-- Two cases are handled:
--   A) Normal (no movement delay): autoRemaining is in (0, AUTO_AIM_TIME].
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
        local naturalStart = naturalEnd - AUTO_AIM_TIME
        local autoRemaining = naturalEnd - now
        if autoRemaining > 0 and autoRemaining <= AUTO_AIM_TIME then
            if autoAimStopTime > naturalStart then
                -- Aim was interrupted by movement and restarted at the new stop time.
                barStart = autoAimStopTime
                barEnd   = autoAimStopTime + AUTO_AIM_TIME
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
    if not inAim and autoAimStopTime > 0 then
        local autoOverdue = (C.lastAutoTime == 0)
            or (C.autoSpeed > 0 and (C.autoSpeed - (now - C.lastAutoTime)) <= 0)
        if autoOverdue then
            barStart = autoAimStopTime
            barEnd   = autoAimStopTime + AUTO_AIM_TIME
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

local function EndCast(failed)
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

frame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        local db = cbDB()
        if db.x and db.y then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        else
            self:SetPoint("CENTER", UIParent, "CENTER", 0, -270)
        end
        ApplySize()
        frame:SetScale(db.scale or 1.0)
        frame:EnableMouse(not db.locked)
        C.locked = db.locked and true or false
        if not C.locked then ShowPlaceholder() end

    elseif event == "PLAYER_ENTERING_WORLD" then
        C.nameAuto   = GetSpellInfo(SPELL_ID_AUTO)   or "Auto Shot"
        C.nameAimed  = GetSpellInfo(SPELL_ID_AIMED)  or "Aimed Shot"
        C.nameSteady = GetSpellInfo(SPELL_ID_STEADY) or "Steady Shot"
        C.nameMulti  = GetSpellInfo(SPELL_ID_MULTI)  or "Multi-Shot"
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
        RefreshAutoSpeed()
        RefreshAutoAimTime()

    elseif event == "START_AUTOREPEAT_SPELL" then
        C.autoActive  = true
        autoAimMoving = GetUnitSpeed("player") > 0
        if not autoAimMoving then
            autoAimStopTime = GetTime()  -- already stationary; seed the stop time
        end

    elseif event == "STOP_AUTOREPEAT_SPELL" then
        C.autoActive  = false
        C.inAutoAim   = false
        autoAimMoving = false
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
                -- Resync shot timestamp; resets the inAutoAim gate for the next cycle
                C.lastAutoTime = GetTime()
                C.inAutoAim    = false
                -- Refresh speed and aim time; haste or latency may have changed
                RefreshAutoSpeed()
                RefreshAutoAimTime()
            end
            -- Multi-Shot bar was started by combatFrame on SPELL_CAST_START;
            -- EndCast(false) clears it when the shot fires.
            EndCast(false)
        end

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then RefreshAutoSpeed() end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        RefreshAutoSpeed()
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

ExsarAddon.AddSlashCommand("castbarreset", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -270)
    cbDB().x = nil
    cbDB().y = nil
    print(ADDON_NAME .. ": Cast bar position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Cast Bar",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return cbDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                cbDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateSlider(parent, "Bar Width", 16, y, 100, 400, 1,
            function() return cbDB().width or DEFAULT_WIDTH end,
            function(v)
                local w = math.floor(v + 0.5)
                cbDB().width = w
                ApplySize()
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return cbDB().locked and true or false end,
            function(v)
                cbDB().locked = v
                C.locked = v
                frame:EnableMouse(not v)
                if not C.casting then
                    inPlaceholder = false
                    ShowPlaceholder()
                end
            end
        )
        y = y - 30

        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, -270)
            cbDB().x = nil
            cbDB().y = nil
            print(ADDON_NAME .. ": Cast bar position reset.")
        end)
        y = y - 30

        return y
    end,
})
