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
local warnGlow = ExsarUI.CreateGlow(iconFrame, 1, 0.1, 0.1, 1, 6, "BORDER")

local icon = ExsarUI.CreateIcon(iconFrame)

-- =========================================================
-- Marching-ants border
-- =========================================================

local dashes = ExsarUI.BuildDashes(iconFrame, ICON_SIZE, DASH_COUNT, BORDER_W)

-- Red X (shown when no aspect is active)
local xLine1, xLine2 = ExsarUI.CreateRedX(iconFrame)

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
    local now = GetTime()
    local packWarning = C_inCombat and C_activeSpellId == PACK_BUFF_ID
    local head = ExsarLogic.MarchingAntHead(now, DASH_SPEED, DASH_COUNT)
    local dr, dg, db = packWarning and 1 or 1,
                       packWarning and 0.1 or 0.85,
                       packWarning and 0.1 or 0
    for j, d in ipairs(dashes) do
        local alpha = ExsarLogic.MarchingAntAlpha(j - 1, head, DASH_COUNT, TAIL_LEN)
        if alpha > 0 then
            d:SetColorTexture(dr, dg, db, 1)
        end
        d:SetAlpha(alpha)
    end
    if packWarning then
        warnGlow:Show()
        warnGlow:SetAlpha(ExsarLogic.PulseAlpha(now, 0.64, 0.30, 0.80))
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

ExsarUI.AddSlashReset("aspectreset", frame, aDB, "Aspect tracker", -350, 100)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Aspect Tracker",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, aDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, aDB, frame)

        y = ExsarUI.AddResetButton(parent, y, aDB, frame, "Aspect tracker", -350, 100)

        return y
    end,
})
