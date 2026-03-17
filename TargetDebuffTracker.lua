-- TargetDebuffTracker module
-- Shows icons with a marching-ants yellow border and countdown timer for
-- tracked debuffs currently active on the player's target.
-- Single-column vertical layout; only shows debuffs that are present.
-- Settings stored under ExsarAddonDB.targetDebuffs.

local ADDON_NAME = "ExsarAddon"

local tDB = ExsarUI.MakeDB("targetDebuffs")

-- =========================================================
-- Debuff definitions
-- =========================================================
-- Each entry: { name = "Debuff Name", id = spellId }
-- Detection tries spell ID first, then falls back to name.
-- Set id = nil to match by name only (catches all ranks).

local TRACKED_DEBUFFS = {
    { name = "Hunter's Mark", id = nil },
    { name = "Serpent Sting", id = nil },
}

-- =========================================================
-- Layout constants
-- =========================================================

local ICON_SIZE  = 29
local ICON_GAP   = 4
local PADDING    = 6

-- Marching-ants border
local BORDER_W   = 2     -- border thickness in pixels
local DASH_COUNT = 16    -- total dashes around the perimeter (4 per side)
local DASH_SPEED = 1.5   -- full rotations per second
local TAIL_LEN   = 5     -- dashes in the bright trailing tail

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "TargetDebuffFrame", UIParent)
ExsarUI.SetupMovableFrame(frame, tDB)

local placeholderText = ExsarUI.CreatePlaceholder(frame, "Debuffs")

frame:Hide()

local C_locked = false

-- =========================================================
-- Icon slot construction
-- =========================================================

local function BuildDashes(iconFrame)
    return ExsarUI.BuildDashes(iconFrame, ICON_SIZE, DASH_COUNT, BORDER_W)
end

local function MakeSlot()
    local s = {
        active   = false,
        expTime  = 0,
        name     = nil,
        id       = nil,
        spellId  = nil,   -- populated during scan; used for tooltip
    }

    s.iconFrame = CreateFrame("Frame", nil, frame)
    s.iconFrame:SetSize(ICON_SIZE, ICON_SIZE)

    s.glow  = ExsarUI.CreateGlow(s.iconFrame)
    s.icon  = ExsarUI.CreateIcon(s.iconFrame)
    s.sweep = ExsarUI.CreateSweep(s.iconFrame, { reverse = true })

    -- Marching-ants border dashes
    s.dashes = BuildDashes(s.iconFrame)

    -- Countdown timer text
    s.text = s.iconFrame:CreateFontString(nil, "OVERLAY")
    s.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    s.text:SetPoint("CENTER", s.iconFrame, "CENTER", 0, 0)
    s.text:SetTextColor(1, 1, 1, 1)
    s.text:SetText("")

    s.iconFrame:EnableMouse(true)
    s.iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if s.spellId then
            GameTooltip:SetSpellByID(s.spellId)
        elseif s.name then
            local id = select(7, GetSpellInfo(s.name))
            if id then GameTooltip:SetSpellByID(id) end
        end
        GameTooltip:Show()
    end)
    s.iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    s.iconFrame:Hide()
    return s
end

local slots = {}
for _, debuff in ipairs(TRACKED_DEBUFFS) do
    local s = MakeSlot()
    s.name = debuff.name
    s.id   = debuff.id
    slots[#slots + 1] = s
end

-- =========================================================
-- Layout
-- =========================================================

local function ApplyLayout()
    local yOffset  = PADDING
    local anyShown = false

    for _, s in ipairs(slots) do
        if s.active then
            s.iconFrame:ClearAllPoints()
            s.iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -yOffset)
            s.iconFrame:Show()
            yOffset = yOffset + ICON_SIZE + ICON_GAP
            anyShown = true
        else
            s.iconFrame:Hide()
        end
    end

    if anyShown then
        frame:SetSize(ICON_SIZE + PADDING * 2, yOffset - ICON_GAP + PADDING)
        placeholderText:Hide()
        frame:Show()
    elseif not C_locked then
        frame:SetSize(ICON_SIZE + PADDING * 2, 40)
        placeholderText:Show()
        frame:Show()
    else
        placeholderText:Hide()
        frame:Hide()
    end
end

-- =========================================================
-- Debuff scanning
-- =========================================================

local lastTimeStrs = {}

local function UpdateDebuffs()
    local now = GetTime()

    -- Build lookup tables from the target's current debuffs
    local byId   = {}
    local byName = {}
    if UnitExists("target") then
        for i = 1, 40 do
            local bName, bIcon, _, _, bDuration, bExpTime, _, _, _, bSpellId =
                UnitDebuff("target", i, "PLAYER")
            if not bName then break end
            if bSpellId and bSpellId > 0 then
                byId[bSpellId] = { icon = bIcon, expTime = bExpTime or 0, duration = bDuration or 0, spellId = bSpellId }
            end
            if not byName[bName] then
                byName[bName] = { icon = bIcon, expTime = bExpTime or 0, duration = bDuration or 0, spellId = bSpellId }
            end
        end
    end

    local layoutChanged = false

    for i, s in ipairs(slots) do
        local match
        if s.id   then match = byId[s.id]     end
        if not match and s.name then match = byName[s.name] end

        local wasActive = s.active

        if match then
            s.active   = true
            s.expTime  = match.expTime
            s.spellId  = match.spellId
            s.icon:SetTexture(match.icon)
            s.glow:Show()

            if match.expTime > 0 and match.duration and match.duration > 0 then
                s.sweep:SetCooldown(match.expTime - match.duration, match.duration)
            else
                s.sweep:SetCooldown(0, 0)
            end

            local remaining = s.expTime > 0 and math.max(0, s.expTime - now) or nil
            local newStr
            if not remaining then
                newStr = ""
            else
                newStr = ExsarLogic.FormatCooldown(remaining)
            end
            if newStr ~= lastTimeStrs[i] then
                lastTimeStrs[i] = newStr
                s.text:SetText(newStr)
            end
        else
            s.active = false
            s.icon:SetTexture(nil)
            s.sweep:SetCooldown(0, 0)
            s.glow:Hide()
            s.text:SetText("")
            lastTimeStrs[i] = ""
        end

        if s.active ~= wasActive then layoutChanged = true end
    end

    if layoutChanged then ApplyLayout() end
end

-- =========================================================
-- Marching-ants animation (runs every frame via animTicker)
-- =========================================================

local function AnimateDashes()
    ExsarUI.AnimateDashes(slots, GetTime(), DASH_SPEED, DASH_COUNT, TAIL_LEN)
end

-- Dedicated always-on frame for smooth dash animation.
local animTicker = CreateFrame("Frame")
animTicker:Show()
animTicker:SetScript("OnUpdate", function() AnimateDashes() end)

-- =========================================================
-- OnUpdate: debuff state + timer text (every 0.1 s)
-- =========================================================

ExsarUI.CreatePoller(frame, 0.1, UpdateDebuffs)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, tDB, -300, 100)
        C_locked = tDB().locked and true or false
        ApplyLayout()

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateDebuffs()

    elseif event == "UNIT_AURA" then
        if arg1 == "target" then UpdateDebuffs() end

    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateDebuffs()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarUI.AddSlashReset("debuffsreset", frame, tDB, "Target debuff tracker", -300, 100)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Target Debuff Tracker",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, tDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, tDB, frame, function(v)
            C_locked = v
            ApplyLayout()
        end)

        y = ExsarUI.AddResetButton(parent, y, tDB, frame, "Target debuffs", -300, 100)

        return y
    end,
})
