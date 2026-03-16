-- AspectTracker module
-- Shows the currently active hunter aspect as a single icon with a
-- marching-ants yellow border. Shows a red X when no aspect is active.
-- Settings stored under ExsarAddonDB.aspectTracker.

local ADDON_NAME = "ExsarAddon"

local aDB = ExsarUI.MakeDB("aspectTracker")

-- =========================================================
-- Aspect definitions
-- =========================================================

local PACK_BUFF_ID = 13159

local ASPECTS = {
    { name = "Aspect of the Hawk",    buffId = 27044 },
    { name = "Aspect of the Monkey",  buffId = 13163 },
    { name = "Aspect of the Pack",    buffId = 13159 },
    { name = "Aspect of the Cheetah", buffId = 5118  },
    { name = "Aspect of the Viper",   buffId = 34074 },
    { name = "Aspect of the Beast",   buffId = 13161 },
    { name = "Aspect of the Wild",    buffId = 27045 },
}

local aspectById = {}
for _, a in ipairs(ASPECTS) do
    aspectById[a.buffId] = a
end

-- =========================================================
-- Layout constants
-- =========================================================

local ICON_SIZE  = 29
local PADDING    = 6
local FRAME_W    = ICON_SIZE + PADDING * 2
local FRAME_H    = ICON_SIZE + PADDING * 2

local BORDER_W   = 2
local DASH_COUNT = 16
local DASH_SPEED = 1.5
local TAIL_LEN   = 5

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "AspectTrackerFrame", UIParent)
frame:SetSize(FRAME_W, FRAME_H)
ExsarUI.SetupMovableFrame(frame, aDB)

-- =========================================================
-- Icon slot
-- =========================================================

local iconFrame = CreateFrame("Frame", nil, frame)
iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)
iconFrame:EnableMouse(true)

local slotBg = iconFrame:CreateTexture(nil, "BACKGROUND")
slotBg:SetAllPoints()
slotBg:SetColorTexture(0, 0, 0, 1.0)

-- Red warning glow (extends beyond icon, pulsed when Pack is active in combat)
local warnGlow = iconFrame:CreateTexture(nil, "BORDER")
warnGlow:SetPoint("TOPLEFT",     iconFrame, "TOPLEFT",     -6,  6)
warnGlow:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT",  6, -6)
warnGlow:SetColorTexture(1, 0.1, 0.1, 1)
warnGlow:Hide()

local icon = ExsarUI.CreateIcon(iconFrame)

-- =========================================================
-- Marching-ants border
-- =========================================================

local dashes = ExsarUI.BuildDashes(iconFrame, ICON_SIZE, DASH_COUNT, BORDER_W)

-- =========================================================
-- Red X (shown when no aspect is active)
-- =========================================================

local xLine1 = iconFrame:CreateLine(nil, "OVERLAY")
xLine1:SetColorTexture(0.9, 0.15, 0.15, 1)
xLine1:SetThickness(3)
xLine1:SetStartPoint("TOPLEFT",     iconFrame, 4, -4)
xLine1:SetEndPoint("BOTTOMRIGHT",   iconFrame, -4, 4)

local xLine2 = iconFrame:CreateLine(nil, "OVERLAY")
xLine2:SetColorTexture(0.9, 0.15, 0.15, 1)
xLine2:SetThickness(3)
xLine2:SetStartPoint("TOPRIGHT",    iconFrame, -4, -4)
xLine2:SetEndPoint("BOTTOMLEFT",    iconFrame, 4, 4)

-- =========================================================
-- State
-- =========================================================

local C_aspectActive = false
local C_activeSpellId = nil
local C_inCombat = false

-- =========================================================
-- Tooltip
-- =========================================================

iconFrame:SetScript("OnEnter", function(self)
    if C_activeSpellId then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(C_activeSpellId)
        GameTooltip:Show()
    end
end)
iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- =========================================================
-- Update
-- =========================================================

local function UpdateAspect()
    local found = nil
    for i = 1, 40 do
        local _, bIcon, _, _, _, _, _, _, _, bSpellId = UnitBuff("player", i)
        if not bIcon then break end
        if bSpellId and aspectById[bSpellId] then
            found = { icon = bIcon, spellId = bSpellId }
            break
        end
    end

    if found then
        C_aspectActive  = true
        C_activeSpellId = found.spellId
        icon:SetTexture(found.icon)
        xLine1:Hide()
        xLine2:Hide()
    else
        C_aspectActive  = false
        C_activeSpellId = nil
        icon:SetTexture(nil)
        xLine1:Show()
        xLine2:Show()
        warnGlow:Hide()
        for _, d in ipairs(dashes) do d:SetAlpha(0) end
    end
end

-- =========================================================
-- Marching-ants animation
-- =========================================================

local animTicker = CreateFrame("Frame")
animTicker:Show()
animTicker:SetScript("OnUpdate", function()
    if not C_aspectActive then return end
    local packWarning = C_inCombat and C_activeSpellId == PACK_BUFF_ID
    local head = (GetTime() * DASH_SPEED * DASH_COUNT) % DASH_COUNT
    local dr, dg, db = packWarning and 1 or 1,
                       packWarning and 0.1 or 0.85,
                       packWarning and 0.1 or 0
    for j, d in ipairs(dashes) do
        local dist = (head - (j - 1) + DASH_COUNT) % DASH_COUNT
        if dist < TAIL_LEN then
            d:SetColorTexture(dr, dg, db, 1)
            d:SetAlpha(1.0 - (dist / TAIL_LEN) * 0.85)
        else
            d:SetAlpha(0)
        end
    end
    if packWarning then
        warnGlow:Show()
        warnGlow:SetAlpha(0.55 + math.sin(GetTime() * 4) * 0.25)
    else
        warnGlow:Hide()
    end
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, aDB, -350, 100)
        self:Show()
        UpdateAspect()

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_inCombat = InCombatLockdown()
        UpdateAspect()

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then UpdateAspect() end

    elseif event == "PLAYER_REGEN_DISABLED" then
        C_inCombat = true

    elseif event == "PLAYER_REGEN_ENABLED" then
        C_inCombat = false
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("aspectreset", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", -350, 100)
    aDB().x = nil
    aDB().y = nil
    print(ADDON_NAME .. ": Aspect tracker position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Aspect Tracker",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return aDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                aDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return aDB().locked and true or false end,
            function(v)
                aDB().locked = v
                frame:EnableMouse(not v)
            end
        )
        y = y - 30

        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", -350, 100)
            aDB().x = nil
            aDB().y = nil
            print(ADDON_NAME .. ": Aspect tracker position reset.")
        end)
        y = y - 30

        return y
    end,
})
