-- GlobalCooldownTracker module
-- Shows a sweep effect during the Global Cooldown.
-- Useful for timing abilities like Steady Shot during rotations.
-- Settings are stored under ExsarAddonDB.globalCooldown.

local ADDON_NAME = "ExsarAddon"

local function gDB()
    ExsarAddonDB.globalCooldown = ExsarAddonDB.globalCooldown or {}
    return ExsarAddonDB.globalCooldown
end

-- =========================================================
-- Constants
-- =========================================================

-- Wing Clip has no cooldown of its own, so GetSpellCooldown only
-- ever returns the GCD when it's active.
local GCD_PROBE_SPELL = "Wing Clip"

local ICON_SIZE = 29
local PADDING   = 6

-- =========================================================
-- Frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "GCDFrame", UIParent)
frame:SetSize(ICON_SIZE + PADDING * 2, ICON_SIZE + PADDING * 2)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    gDB().x = x
    gDB().y = y
end)
frame:Hide()

-- Placeholder: background + label shown only when unlocked and GCD inactive
local placeholderBg = frame:CreateTexture(nil, "BACKGROUND")
placeholderBg:SetAllPoints()
placeholderBg:SetColorTexture(0, 0, 0, 0.6)
placeholderBg:Hide()

local placeholderText = frame:CreateFontString(nil, "OVERLAY")
placeholderText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
placeholderText:SetPoint("CENTER", frame, "CENTER", 0, 0)
placeholderText:SetTextColor(0.55, 0.55, 0.55, 0.9)
placeholderText:SetText("GCD")
placeholderText:Hide()

-- =========================================================
-- Sweep area (just the cooldown sweep, no background)
-- =========================================================

local sweepFrame = CreateFrame("Frame", nil, frame)
sweepFrame:SetSize(ICON_SIZE, ICON_SIZE)
sweepFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)

local cooldown = CreateFrame("Cooldown", nil, sweepFrame, "CooldownFrameTemplate")
cooldown:SetAllPoints()
cooldown:SetDrawEdge(false)
if cooldown.SetHideCountdownNumbers then
    cooldown:SetHideCountdownNumbers(true)
end

sweepFrame:Hide()

-- =========================================================
-- Runtime state
-- =========================================================

local lastGCDStart = 0
local C_locked     = false

local function UpdateGCD()
    local start, duration = GetSpellCooldown(GCD_PROBE_SPELL)
    local onGCD = start and start > 0 and duration and duration > 0

    if onGCD then
        -- New GCD detected when start time changes
        if start ~= lastGCDStart then
            cooldown:SetCooldown(start, duration)
            lastGCDStart = start
        end
        placeholderBg:Hide()
        placeholderText:Hide()
        sweepFrame:Show()
        frame:Show()
    else
        lastGCDStart = 0
        cooldown:SetCooldown(0, 0)
        sweepFrame:Hide()

        if not C_locked then
            placeholderBg:Show()
            placeholderText:Show()
            frame:Show()
        else
            placeholderBg:Hide()
            placeholderText:Hide()
            frame:Hide()
        end
    end
end

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        local db = gDB()
        if db.x and db.y then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        else
            self:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
        end
        self:SetScale(db.scale or 1.0)
        self:EnableMouse(not db.locked)
        C_locked = db.locked and true or false
        UpdateGCD()

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateGCD()

    elseif event == "SPELL_UPDATE_COOLDOWN" then
        UpdateGCD()
    end
end)

-- =========================================================
-- Slash sub-command
-- =========================================================

ExsarAddon.AddSlashCommand("gcdreset", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    gDB().x = nil
    gDB().y = nil
    print(ADDON_NAME .. ": GCD tracker position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Global Cooldown Tracker",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return gDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                gDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return gDB().locked and true or false end,
            function(v)
                gDB().locked = v
                C_locked = v
                frame:EnableMouse(not v)
                UpdateGCD()
            end
        )
        y = y - 30

        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
            gDB().x = nil
            gDB().y = nil
            print(ADDON_NAME .. ": GCD tracker position reset.")
        end)
        y = y - 30

        return y
    end,
})
