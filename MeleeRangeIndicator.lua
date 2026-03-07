-- MeleeRangeIndicator module
-- Shows two crossed red swords when the player is in melee range of their target.
-- Settings are stored under ExsarAddonDB.meleeRange.

local ADDON_NAME = "ExsarAddon"

local function mrDB()
    ExsarAddonDB.meleeRange = ExsarAddonDB.meleeRange or {}
    return ExsarAddonDB.meleeRange
end

-- =========================================================
-- Runtime state
-- =========================================================

local M = {
    inRange = false,
    pollElapsed = 0,
}

-- =========================================================
-- Frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "MeleeRangeFrame", UIParent)
frame:SetSize(80, 80)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    mrDB().x = x
    mrDB().y = y
end)
frame:Hide()

-- =========================================================
-- Crossed swords visuals
-- =========================================================
-- Each sword: blade + crossguard + handle, drawn with CreateLine.
-- Sword 1 goes from top-left to bottom-right.
-- Sword 2 goes from top-right to bottom-left (mirrored).

local SWORD_COLOR_BLADE  = { 1.0,  0.85, 0.10, 1.0 }    -- bright gold blade
local SWORD_COLOR_EDGE   = { 1.0,  0.65, 0.0,  0.45 }   -- warm glow behind blade
local SWORD_COLOR_GUARD  = { 0.70, 0.55, 0.25, 1.0 }    -- bronze crossguard
local SWORD_COLOR_HANDLE = { 0.50, 0.35, 0.15, 1.0 }    -- brown handle

local function MakeLine(layer, x1, y1, x2, y2, thickness, color)
    local line = frame:CreateLine(nil, layer)
    line:SetStartPoint("CENTER", frame, x1, y1)
    line:SetEndPoint("CENTER", frame, x2, y2)
    line:SetThickness(thickness)
    line:SetColorTexture(color[1], color[2], color[3], color[4])
    return line
end

local function BuildSword(sign)
    -- sign=1: top-left to bottom-right; sign=-1: mirrored (top-right to bottom-left)
    -- Blade: from upper-outer to lower-inner
    local bx1, by1 = -28 * sign,  28   -- tip (top)
    local bx2, by2 =  28 * sign, -28   -- base (bottom)

    -- Warm glow behind blade
    MakeLine("ARTWORK", bx1, by1, bx2, by2, 14, SWORD_COLOR_EDGE)
    -- Blade core
    MakeLine("OVERLAY", bx1, by1, bx2, by2, 5, SWORD_COLOR_BLADE)

    -- Crossguard: perpendicular to blade, near the lower third
    local gx, gy = 10 * sign, -10  -- center of crossguard
    local gdx, gdy = 10 * sign, 10  -- perpendicular offset (rotated 90 degrees)
    MakeLine("OVERLAY", gx - gdx, gy - gdy, gx + gdx, gy + gdy, 5, SWORD_COLOR_GUARD)

    -- Handle: short extension below crossguard
    local hx1, hy1 = 14 * sign, -14
    local hx2, hy2 = 22 * sign, -22
    MakeLine("OVERLAY", hx1, hy1, hx2, hy2, 4, SWORD_COLOR_HANDLE)

    -- Pommel: small dot at end of handle
    MakeLine("OVERLAY", hx2 - 1 * sign, hy2 + 1, hx2 + 1 * sign, hy2 - 1, 6, SWORD_COLOR_GUARD)
end

BuildSword( 1)
BuildSword(-1)

-- =========================================================
-- Range check
-- =========================================================

local function CheckMeleeRange()
    if not UnitAffectingCombat("player") then return false end
    if not UnitExists("target") or UnitIsDead("target") or not UnitCanAttack("player", "target") then
        return false
    end
    -- Wing Clip is an instant melee ability that works with IsSpellInRange (unlike
    -- "next melee" abilities like Raptor Strike which always report in range).
    return IsSpellInRange("Wing Clip", "target") == 1
end

local function UpdateVisibility()
    local inRange = CheckMeleeRange()
    M.inRange = inRange
    local shouldShow = inRange or not mrDB().locked
    if shouldShow then
        frame:Show()
    else
        frame:Hide()
    end
end

-- =========================================================
-- Polling (range checks have no event; poll at 0.1s)
-- =========================================================

local pollFrame = CreateFrame("Frame")
pollFrame:SetScript("OnUpdate", function(self, elapsed)
    M.pollElapsed = M.pollElapsed + elapsed
    if M.pollElapsed < 0.1 then return end
    M.pollElapsed = 0
    UpdateVisibility()
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        local db = mrDB()
        if db.x and db.y then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        else
            self:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
        end
        self:SetScale(db.scale or 1.0)
        self:EnableMouse(not db.locked)
        if not db.locked then
            frame:Show()
        end

    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TARGET_CHANGED"
        or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        UpdateVisibility()
    end
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Melee Range Indicator",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return mrDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                mrDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return mrDB().locked and true or false end,
            function(v)
                mrDB().locked = v
                frame:EnableMouse(not v)
                UpdateVisibility()
            end
        )
        y = y - 30

        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
            mrDB().x = nil
            mrDB().y = nil
            print(ADDON_NAME .. ": Melee Range Indicator position reset.")
        end)
        y = y - 30

        return y
    end,
})
