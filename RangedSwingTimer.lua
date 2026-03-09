-- RangedSwingTimer module
-- Ranged auto shot cycle tracker. Displays a bar that drains toward the center
-- following each Auto Shot, with a pair of red reticules marking the aim window:
--   stop moving before the bar edge reaches the reticules or the shot will delay.
-- Settings are stored under ExsarAddonDB.rangedSwingTimer.

local ADDON_NAME = "ExsarAddon"

local function sDB()
    ExsarAddonDB.rangedSwingTimer = ExsarAddonDB.rangedSwingTimer or {}
    return ExsarAddonDB.rangedSwingTimer
end

-- =========================================================
-- Constants
-- =========================================================

local GCD_PROBE_SPELL = "Wing Clip"

local AUTO_SHOT_ID   = 75
-- Spells that reset the auto shot cycle on completion:
--   Aimed Shot  — server resets the ranged cooldown when the cast lands
--   Feign Death — cancels the current shot cycle; timer restarts on resumption
local AIMED_SHOT_ID  = 13954
local FEIGN_DEATH_ID = 5384

local DEFAULT_WIDTH  = 220
local DEFAULT_HEIGHT = 20
local RETICULE_W      = 3
local RETICULE_GLOW_W = 9
local EDGE_GLOW_W     = 8

-- =========================================================
-- Runtime state
-- =========================================================

local S = {
    shooting       = false,
    lastShotTime   = 0,
    speed          = 0,      -- hasted ranged weapon speed (seconds)
    aimWindow      = 0.5,    -- time before shot to stop moving (0.5s + latency)
    autoShotName   = "Auto Shot",
    aimedShotName  = "Aimed Shot",
    feignDeathName = "Feign Death",
    barZone        = -1,     -- last color zone (0=red,1=orange,2=blue); -1=unset
    castEnd        = 0,      -- absolute GetTime() when the player's current cast ends; 0 if not casting
    lastClipStr    = "",     -- cached clip text to avoid redundant SetText calls
    lastSpeedStr   = "",     -- cached countdown text to avoid redundant SetText calls
    refreshDelay   = 0,      -- seconds remaining before a deferred RefreshAll fires; 0 = inactive
}

-- =========================================================
-- Frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "RangedSwingFrame", UIParent)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    sDB().x = x
    sDB().y = y
end)

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.6)

-- The draining bar. Anchored to center; width shrinks toward center over the cycle.
local bar = frame:CreateTexture(nil, "ARTWORK")
bar:SetPoint("CENTER", frame, "CENTER", 0, 0)
bar:Hide()

-- Edge glow: bright stripe tracking each inner edge of the bar as it drains.
local edgeGlowL = frame:CreateTexture(nil, "OVERLAY")
local edgeGlowR = frame:CreateTexture(nil, "OVERLAY")
edgeGlowL:SetColorTexture(1, 1, 1, 0.55)
edgeGlowR:SetColorTexture(1, 1, 1, 0.55)
edgeGlowL:Hide()
edgeGlowR:Hide()

-- Inner reticule pair: stop-moving window (red)
local glowL  = frame:CreateTexture(nil, "ARTWORK")
local glowR  = frame:CreateTexture(nil, "ARTWORK")
glowL:SetColorTexture(0.9, 0.15, 0.15, 0.35)
glowR:SetColorTexture(0.9, 0.15, 0.15, 0.35)
glowL:Hide()
glowR:Hide()

local innerL = frame:CreateTexture(nil, "OVERLAY")
local innerR = frame:CreateTexture(nil, "OVERLAY")
innerL:SetColorTexture(0.9, 0.15, 0.15, 1)
innerR:SetColorTexture(0.9, 0.15, 0.15, 1)
innerL:Hide()
innerR:Hide()

-- Speed label: ranged attack speed at far left of bar
local speedText = frame:CreateFontString(nil, "OVERLAY")
speedText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
speedText:SetPoint("LEFT", frame, "LEFT", 4, 0)
speedText:SetTextColor(1, 1, 1, 0.9)
speedText:SetText("")

-- Clip label: shown between the reticules when the current cast will delay the auto shot
local clipText = frame:CreateFontString(nil, "OVERLAY")
clipText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
clipText:SetPoint("CENTER", frame, "CENTER", 0, 0)
clipText:SetTextColor(1, 0.3, 0.3, 1)
clipText:Hide()


-- =========================================================
-- Layout helpers
-- =========================================================

-- Cached so OnUpdate never calls sDB() in the hot path
local cachedMaxBarW = DEFAULT_WIDTH - 4

local function ApplySize()
    local db = sDB()
    local w = db.width  or DEFAULT_WIDTH
    local h = db.height or DEFAULT_HEIGHT
    cachedMaxBarW = w - 4
    frame:SetSize(w, h)
    bar:SetHeight(h - 4)
    edgeGlowL:SetSize(EDGE_GLOW_W, h - 2)
    edgeGlowR:SetSize(EDGE_GLOW_W, h - 2)
    glowL:SetSize(RETICULE_GLOW_W, h)
    glowR:SetSize(RETICULE_GLOW_W, h)
    innerL:SetSize(RETICULE_W, h)
    innerR:SetSize(RETICULE_W, h)
end

local function UpdateReticulePositions()
    local speed = S.speed
    if speed <= 0 then
        glowL:Hide();  glowR:Hide()
        innerL:Hide(); innerR:Hide()
        speedText:Hide()
        return
    end

    local halfW = (sDB().width or DEFAULT_WIDTH) / 2

    speedText:SetText(string.format("%.1fs", speed))
    speedText:Show()

    -- Stop-moving reticule at aimWindow seconds from shot
    local innerX = math.min(S.aimWindow / speed, 0.98) * halfW
    glowL:ClearAllPoints()
    glowR:ClearAllPoints()
    glowL:SetPoint("CENTER", frame, "CENTER", -innerX, 0)
    glowR:SetPoint("CENTER", frame, "CENTER",  innerX, 0)
    glowL:Show()
    glowR:Show()
    innerL:ClearAllPoints()
    innerR:ClearAllPoints()
    innerL:SetPoint("CENTER", frame, "CENTER", -innerX, 0)
    innerR:SetPoint("CENTER", frame, "CENTER",  innerX, 0)
    innerL:Show()
    innerR:Show()
end

-- =========================================================
-- State refresh
-- =========================================================

local function RefreshSpeed()
    local speed = select(1, UnitRangedDamage("player"))
    S.speed = (type(speed) == "number" and speed > 0) and speed or 0
end

local function RefreshAimWindow()
    -- Stop-moving window = ~0.5s shot wind-up + server latency
    local _, _, homeMs, worldMs = GetNetStats()
    local latency = math.max(
        type(homeMs)  == "number" and homeMs  or 0,
        type(worldMs) == "number" and worldMs or 0
    ) / 1000
    S.aimWindow = 0.5 + latency
end

local function RefreshAll()
    RefreshSpeed()
    RefreshAimWindow()
    UpdateReticulePositions()
end

-- =========================================================
-- OnUpdate: bar drain
-- =========================================================

frame:SetScript("OnUpdate", function(self, elapsed)
    -- Deferred stat refresh: allow the engine time to finish recalculating stats
    -- after a talent/spec change before reading UnitRangedDamage.
    if S.refreshDelay > 0 then
        S.refreshDelay = S.refreshDelay - elapsed
        if S.refreshDelay <= 0 then
            S.refreshDelay = 0
            RefreshAll()
        end
    end

    if S.speed <= 0 or S.lastShotTime == 0 then
        bar:Hide()
        edgeGlowL:Hide()
        edgeGlowR:Hide()
        if S.lastClipStr ~= "" then
            S.lastClipStr = ""
            S.castEnd     = 0
            clipText:Hide()
        end
        if S.lastSpeedStr ~= "" then
            S.lastSpeedStr = ""
            if S.speed > 0 then
                speedText:SetText(string.format("%.1fs", S.speed))
            end
        end
        return
    end

    -- Clear clip text when auto shot is off (no cast in progress anyway)
    if not S.shooting and S.lastClipStr ~= "" then
        S.lastClipStr = ""
        S.castEnd     = 0
        clipText:Hide()
    end

    local now       = GetTime()
    local remaining = math.max(0, S.speed - (now - S.lastShotTime))
    local frac      = remaining / S.speed

    local barW    = math.max(0.01, frac * cachedMaxBarW)
    local halfBarW = barW / 2
    bar:SetWidth(barW)
    if remaining > 0 then
        edgeGlowL:ClearAllPoints()
        edgeGlowR:ClearAllPoints()
        edgeGlowL:SetPoint("CENTER", frame, "CENTER", -halfBarW, 0)
        edgeGlowR:SetPoint("CENTER", frame, "CENTER",  halfBarW, 0)
        edgeGlowL:Show()
        edgeGlowR:Show()
    else
        edgeGlowL:Hide()
        edgeGlowR:Hide()
    end

    -- Countdown label: remaining seconds before the next auto shot
    local newSpeedStr = string.format("%.1fs", remaining)
    if newSpeedStr ~= S.lastSpeedStr then
        S.lastSpeedStr = newSpeedStr
        speedText:SetText(newSpeedStr)
    end

    -- Only call SetColorTexture on zone transitions; it's expensive every frame
    -- Zone 0=red (aim window), 1=blue (safe), 2=grey (GCD active)
    local gcdStart, gcdDur = GetSpellCooldown(GCD_PROBE_SPELL)
    local onGCD = gcdStart and gcdStart > 0 and gcdDur and gcdDur > 0
    local zone
    if onGCD then
        zone = 2
    elseif remaining <= S.aimWindow then
        zone = 0
    else
        zone = 1
    end
    if zone ~= S.barZone then
        S.barZone = zone
        if zone == 0 then
            bar:SetColorTexture(0.9, 0.15, 0.15, 0.9)       -- red:  stop moving
        elseif zone == 2 then
            bar:SetColorTexture(0.45, 0.45, 0.45, 0.75)     -- grey: GCD active
        else
            bar:SetColorTexture(0.15, 0.55, 0.95, 0.85)     -- blue: safe
        end
    end

    bar:Show()

    -- Clip indicator: show when the active cast will push the auto shot past its due time.
    -- castEnd expires naturally at its own timestamp; clear it here to avoid stale values.
    if S.castEnd > 0 and now >= S.castEnd then
        S.castEnd = 0
    end

    local clipStr = ""
    if S.castEnd > 0 then
        -- due = absolute time the next auto shot would fire if unimpeded
        local due     = now + remaining
        local clipAmt = S.castEnd - due
        if clipAmt > 0.02 then   -- 0.02s threshold avoids noise at boundary
            clipStr = string.format("(%.1f)", clipAmt)
        end
    end

    if clipStr ~= S.lastClipStr then
        S.lastClipStr = clipStr
        if clipStr ~= "" then
            clipText:SetText(clipStr)
            clipText:Show()
        else
            clipText:Hide()
        end
    end
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("START_AUTOREPEAT_SPELL")
frame:RegisterEvent("STOP_AUTOREPEAT_SPELL")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
-- UNIT_SPELLCAST_STOP clears castEnd as a safety net; not present in all builds
pcall(function() frame:RegisterEvent("UNIT_SPELLCAST_STOP") end)
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")

frame:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        local db = sDB()
        if db.x and db.y then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        else
            self:SetPoint("CENTER", UIParent, "CENTER", 0, -240)
        end
        ApplySize()
        frame:SetScale(db.scale or 1.0)
        frame:EnableMouse(not sDB().locked)

    elseif event == "PLAYER_ENTERING_WORLD" then
        S.autoShotName   = GetSpellInfo(AUTO_SHOT_ID)   or "Auto Shot"
        S.aimedShotName  = GetSpellInfo(AIMED_SHOT_ID)  or "Aimed Shot"
        S.feignDeathName = GetSpellInfo(FEIGN_DEATH_ID) or "Feign Death"
        RefreshAll()

    elseif event == "START_AUTOREPEAT_SPELL" then
        S.shooting = true
        -- Seed lastShotTime so the bar shows something until the first real sync
        if S.lastShotTime == 0 then
            S.lastShotTime = GetTime()
        end

    elseif event == "STOP_AUTOREPEAT_SPELL" then
        S.shooting = false
        -- Don't hide the bar: the ranged weapon cooldown is still running.
        -- OnUpdate continues draining based on lastShotTime.

    elseif event == "UNIT_SPELLCAST_START" then
        if arg1 == "player" then
            -- Capture the cast end time for clip detection.
            local _, _, _, startMS, endMS = UnitCastingInfo("player")
            if type(endMS) == "number" and endMS > 0 then
                S.castEnd = endMS / 1000
            end
        end

    elseif event == "UNIT_SPELLCAST_STOP"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if arg1 == "player" then
            S.castEnd = 0
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" then
            S.castEnd = 0   -- cast finished; clip display will clear on next frame
            -- Support both old TBC API (arg2 = spellName) and modern API (arg3 = spellID)
            local isAutoShot = (arg2 == S.autoShotName)
                or (arg3 == AUTO_SHOT_ID)
                or (arg5 == AUTO_SHOT_ID)
            if isAutoShot then
                S.lastShotTime = GetTime()
                S.barZone      = -1   -- force color re-evaluation on next frame
                -- Resync speed in case haste changed mid-cycle
                RefreshSpeed()
                UpdateReticulePositions()
            end

            -- Aimed Shot landing resets the server-side auto shot cooldown.
            -- Treat it the same as an Auto Shot firing: the next shot is a full
            -- weapon cycle away from now.
            local isAimedShot = (arg2 == S.aimedShotName)
                or (arg3 == AIMED_SHOT_ID)
                or (arg5 == AIMED_SHOT_ID)
            if isAimedShot then
                S.lastShotTime = GetTime()
                S.barZone      = -1
                RefreshSpeed()
                UpdateReticulePositions()
            end

            -- Feign Death cancels the current shot cycle.  Reset lastShotTime so
            -- that START_AUTOREPEAT_SPELL re-seeds it cleanly when auto shot
            -- resumes.  Also hide the bar immediately rather than waiting for
            -- STOP_AUTOREPEAT_SPELL (which may arrive in the same or next frame).
            local isFeignDeath = (arg2 == S.feignDeathName)
                or (arg3 == FEIGN_DEATH_ID)
                or (arg5 == FEIGN_DEATH_ID)
            if isFeignDeath then
                S.lastShotTime = 0
                S.shooting     = false
                bar:Hide()
                edgeGlowL:Hide()
                edgeGlowR:Hide()
            end
        end

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then
            RefreshAll()
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        RefreshAll()

    elseif event == "SPELLS_CHANGED" then
        -- Stats may not be updated immediately; wait 0.5s before re-reading speed.
        S.refreshDelay = 0.5
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("rangedswingreset", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -240)
    sDB().x = nil
    sDB().y = nil
    print(ADDON_NAME .. ": Ranged swing timer position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Ranged Swing Timer",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return sDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                sDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateSlider(parent, "Bar Width", 16, y, 100, 400, 1,
            function() return sDB().width or DEFAULT_WIDTH end,
            function(v)
                local w = math.floor(v + 0.5)
                sDB().width = w
                cachedMaxBarW = w - 4
                frame:SetWidth(w)
                UpdateReticulePositions()
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return sDB().locked and true or false end,
            function(v)
                sDB().locked = v
                frame:EnableMouse(not v)
            end
        )
        y = y - 30

        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, -240)
            sDB().x = nil
            sDB().y = nil
            print(ADDON_NAME .. ": Ranged swing timer position reset.")
        end)
        y = y - 30

        return y
    end,
})
