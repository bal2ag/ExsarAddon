-- MeleeSwingTimer module
-- Countdown bar for the main-hand melee swing timer.
-- Starts full after each swing and empties left-to-right as the next swing approaches.
-- Raptor Strike (fires on the next melee swing and resets the timer) is also detected.
-- Settings stored under ExsarAddonDB.meleeSwingTimer.

local ADDON_NAME = "ExsarAddon"

local function mDB()
    ExsarAddonDB.meleeSwingTimer = ExsarAddonDB.meleeSwingTimer or {}
    return ExsarAddonDB.meleeSwingTimer
end

-- =========================================================
-- Spell IDs
-- =========================================================

-- Raptor Strike fires on the next melee swing and resets the swing timer.
local RAPTOR_STRIKE_IDS = {
    [2973]  = true,   -- Rank 1
    [14260] = true,   -- Rank 2
    [14261] = true,   -- Rank 3
    [14262] = true,   -- Rank 4
    [14263] = true,   -- Rank 5
    [14264] = true,   -- Rank 6
    [27014] = true,   -- Rank 7
}

-- =========================================================
-- Layout constants
-- =========================================================

local DEFAULT_WIDTH  = 200
local DEFAULT_HEIGHT = 14
local PADDING        = 6

-- Amber, distinct from the blue ranged swing timer
local BAR_R, BAR_G, BAR_B, BAR_A = 0.95, 0.75, 0.10, 0.85

-- =========================================================
-- Runtime state
-- =========================================================

local M = {
    speed     = 0,     -- hasted main-hand attack speed (seconds)
    lastSwing = 0,     -- GetTime() when the last melee swing fired
    active    = false, -- true once we've seen at least one swing this session
}

local function RefreshSpeed()
    -- UnitAttackSpeed returns mainHandSpeed, offHandSpeed; select(1,...) makes
    -- the main-hand intent explicit when dual wielding.
    local speed = select(1, UnitAttackSpeed("player"))
    if type(speed) == "number" and speed > 0 then
        M.speed = speed
    end
end

-- =========================================================
-- Frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "MeleeSwingFrame", UIParent)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    mDB().x = x
    mDB().y = y
end)
frame:Hide()

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.6)

local barBg = frame:CreateTexture(nil, "ARTWORK")

local bar = frame:CreateTexture(nil, "OVERLAY")
bar:SetColorTexture(BAR_R, BAR_G, BAR_B, BAR_A)

local timeText = frame:CreateFontString(nil, "OVERLAY")
timeText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
timeText:SetPoint("CENTER", frame, "CENTER", 0, 0)
timeText:SetTextColor(1, 1, 1, 0.9)
timeText:SetText("")

-- =========================================================
-- Layout
-- =========================================================

local cachedMaxBarW = DEFAULT_WIDTH - PADDING * 2

local function ApplySize()
    local db = mDB()
    local w  = db.width or DEFAULT_WIDTH
    local h  = DEFAULT_HEIGHT
    frame:SetSize(w, h + PADDING * 2)
    cachedMaxBarW = w - PADDING * 2

    barBg:SetPoint("LEFT",  frame, "LEFT",   PADDING, 0)
    barBg:SetPoint("RIGHT", frame, "RIGHT", -PADDING, 0)
    barBg:SetHeight(h)
    barBg:SetColorTexture(0.08, 0.08, 0.12, 0.8)

    -- Right-anchored: as remaining time decreases, the left edge moves right,
    -- creating a left-to-right emptying effect.
    bar:SetPoint("RIGHT", frame, "RIGHT", -PADDING, 0)
    bar:SetHeight(h - 2)
    bar:SetWidth(cachedMaxBarW)
end

-- =========================================================
-- Swing detection
-- =========================================================

local function OnSwing()
    local now = GetTime()
    -- Debounce: Raptor Strike and the normal white-hit both fire for the same
    -- swing within a few ms of each other; ignore a second reset within 0.15 s.
    if now - M.lastSwing < 0.15 then return end
    M.lastSwing = now
    M.active    = true
    frame:Show()
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
-- OnUpdate: advance the bar
-- =========================================================

local lastTimeStr = ""

frame:SetScript("OnUpdate", function(self, elapsed)
    if not M.active or M.speed <= 0 then return end

    local now       = GetTime()
    local remaining = math.max(0, M.speed - (now - M.lastSwing))
    local frac      = remaining / M.speed   -- 1 = full (just swung), 0 = empty (ready to fire)

    bar:SetWidth(math.max(0.01, frac * cachedMaxBarW))

    local newStr
    if remaining <= 0 then
        newStr = string.format("%.1fs", M.speed)  -- show attack speed when ready
    elseif remaining >= 10 then
        newStr = string.format("%d",   math.ceil(remaining))
    else
        newStr = string.format("%.1f", remaining)
    end
    if newStr ~= lastTimeStr then
        lastTimeStr = newStr
        timeText:SetText(newStr)
    end
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_DEAD")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        local db = mDB()
        if db.x and db.y then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        else
            self:SetPoint("CENTER", UIParent, "CENTER", 0, -230)
        end
        ApplySize()
        frame:SetScale(db.scale or 1.0)
        frame:EnableMouse(not db.locked)

    elseif event == "PLAYER_ENTERING_WORLD" then
        RefreshSpeed()
        if M.speed > 0 then
            M.active    = true
            M.lastSwing = 0   -- no swing recorded; bar shows empty (ready state)
            frame:Show()
        end

    elseif event == "PLAYER_DEAD" then
        M.active    = false
        M.lastSwing = 0
        frame:Hide()

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then RefreshSpeed() end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        RefreshSpeed()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("meleereset", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -230)
    mDB().x = nil
    mDB().y = nil
    print(ADDON_NAME .. ": Melee swing timer position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Melee Swing Timer",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return mDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                mDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateSlider(parent, "Bar Width", 16, y, 100, 400, 1,
            function() return mDB().width or DEFAULT_WIDTH end,
            function(v)
                local w = math.floor(v + 0.5)
                mDB().width = w
                ApplySize()
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return mDB().locked and true or false end,
            function(v)
                mDB().locked = v
                frame:EnableMouse(not v)
            end
        )
        y = y - 30

        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, -230)
            mDB().x = nil
            mDB().y = nil
            print(ADDON_NAME .. ": Melee swing timer position reset.")
        end)
        y = y - 30

        return y
    end,
})
