-- PetInfoWidget module
-- A repositionable widget showing the active pet's portrait, name, level,
-- type, health, power, buffs, and debuffs.
-- Hidden when no pet is summoned; visibility also togglable via config.
-- Settings stored under ExsarAddonDB.petInfo.

local ADDON_NAME = "ExsarAddon"
local UNIT = "pet"

local pDB = ExsarUI.MakeDB("petInfo")

local DEFAULT_X, DEFAULT_Y = -460, 175
local C_enabled = true

-- =========================================================
-- Layout constants  (identical to TargetInfoWidget)
-- =========================================================

local FRAME_W        = 210
local PAD            = 7
local PORT_SIZE      = 44
local BAR_H          = 15
local ICON_SIZE      = 18
local ICON_GAP       = 2
local MAX_DEBUFFS    = 16
local MAX_BUFFS      = 32
local ICONS_PER_ROW  = math.floor((FRAME_W - PAD * 2 + ICON_GAP) / (ICON_SIZE + ICON_GAP))
local BARS_Y         = -(PAD + PORT_SIZE + 5)
local AURAS_Y        = BARS_Y - BAR_H - 3 - BAR_H - 5
local PRE_AURA_H     = PAD + PORT_SIZE + 5 + BAR_H + 3 + BAR_H

local POWER_COLORS = ExsarUI.POWER_COLORS
local FormatNumber = ExsarLogic.FormatNumber

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "PetInfoFrame", UIParent)
local tlState = ExsarUI.SetupTopleftFrame(frame, pDB, DEFAULT_X, DEFAULT_Y)
local ReAnchor = tlState.ReAnchor
frame:Hide()

-- =========================================================
-- Damage border (pulsating red on recent damage)
-- =========================================================

local DAMAGE_BORDER_W     = 3
local DAMAGE_GLOW_W       = 8
local DAMAGE_FADE_TIME    = 3.0
local DAMAGE_PULSE_FREQ   = 1.5
local DAMAGE_PULSE_MIN    = 0.35
local DAMAGE_PULSE_MAX    = 0.90

local dmgGlow   = {}  -- outer soft glow
local dmgBorder = {}  -- inner bright core

-- Outer glow: extends beyond frame edges
local function MakeGlowEdge(anchor1, anchor2, isHorizontal, outward)
    local t = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    if isHorizontal then
        t:SetPoint(anchor1, frame, anchor1, -DAMAGE_GLOW_W, outward)
        t:SetPoint(anchor2, frame, anchor2,  DAMAGE_GLOW_W, outward)
        t:SetHeight(DAMAGE_GLOW_W)
    else
        t:SetPoint(anchor1, frame, anchor1, outward, DAMAGE_GLOW_W)
        t:SetPoint(anchor2, frame, anchor2, outward, -DAMAGE_GLOW_W)
        t:SetWidth(DAMAGE_GLOW_W)
    end
    t:SetColorTexture(0.9, 0.10, 0.10, 0.35)
    t:Hide()
    dmgGlow[#dmgGlow + 1] = t
end
MakeGlowEdge("TOPLEFT",    "TOPRIGHT",    true,   DAMAGE_GLOW_W)
MakeGlowEdge("BOTTOMLEFT", "BOTTOMRIGHT", true,  -DAMAGE_GLOW_W)
MakeGlowEdge("TOPLEFT",    "BOTTOMLEFT",  false, -DAMAGE_GLOW_W)
MakeGlowEdge("TOPRIGHT",   "BOTTOMRIGHT", false,  DAMAGE_GLOW_W)

-- Inner core border
local function MakeBorderEdge(from1, from2, isHorizontal)
    local t = frame:CreateTexture(nil, "BORDER")
    t:SetPoint(from1, frame, from1)
    t:SetPoint(from2, frame, from2)
    if isHorizontal then
        t:SetHeight(DAMAGE_BORDER_W)
    else
        t:SetWidth(DAMAGE_BORDER_W)
    end
    t:SetColorTexture(1.0, 0.20, 0.15, 1)
    t:Hide()
    dmgBorder[#dmgBorder + 1] = t
end
MakeBorderEdge("TOPLEFT",    "TOPRIGHT",    true)
MakeBorderEdge("BOTTOMLEFT", "BOTTOMRIGHT", true)
MakeBorderEdge("TOPLEFT",    "BOTTOMLEFT",  false)
MakeBorderEdge("TOPRIGHT",   "BOTTOMRIGHT", false)

-- Full-frame red wash overlay (separate frame so it renders above StatusBar children)
local dmgOverlayFrame = CreateFrame("Frame", nil, frame)
dmgOverlayFrame:SetAllPoints()
dmgOverlayFrame:SetFrameLevel(frame:GetFrameLevel() + 10)
local dmgOverlay = dmgOverlayFrame:CreateTexture(nil, "OVERLAY")
dmgOverlay:SetAllPoints()
dmgOverlay:SetColorTexture(0.9, 0.08, 0.08, 1)
dmgOverlayFrame:Hide()

local dmgExpireTime = 0

local function ShowDamageBorder()
    dmgExpireTime = GetTime() + DAMAGE_FADE_TIME
    for _, t in ipairs(dmgGlow)   do t:Show() end
    for _, t in ipairs(dmgBorder) do t:Show() end
    dmgOverlayFrame:Show()
end

local function HideDamageBorder()
    dmgExpireTime = 0
    for _, t in ipairs(dmgGlow)   do t:Hide() end
    for _, t in ipairs(dmgBorder) do t:Hide() end
    dmgOverlayFrame:Hide()
end

local dmgPulseFrame = CreateFrame("Frame")
dmgPulseFrame:SetScript("OnUpdate", function()
    if dmgExpireTime == 0 then return end
    if GetTime() >= dmgExpireTime then
        HideDamageBorder()
        return
    end
    local pulse = DAMAGE_PULSE_MIN + (DAMAGE_PULSE_MAX - DAMAGE_PULSE_MIN) *
                  (0.5 + 0.5 * math.sin(GetTime() * 2 * math.pi * DAMAGE_PULSE_FREQ))
    for _, t in ipairs(dmgBorder) do t:SetAlpha(pulse) end
    for _, t in ipairs(dmgGlow)   do t:SetAlpha(pulse * 0.45) end
    dmgOverlayFrame:SetAlpha(pulse * 0.25)
end)

local dmgCombatFrame = CreateFrame("Frame")
dmgCombatFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
dmgCombatFrame:SetScript("OnEvent", function()
    local _, subEvent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
    if destGUID ~= UnitGUID(UNIT) then return end
    if subEvent == "SWING_DAMAGE"
        or subEvent == "SPELL_DAMAGE"
        or subEvent == "SPELL_PERIODIC_DAMAGE"
        or subEvent == "RANGE_DAMAGE"
        or subEvent == "DAMAGE_SHIELD"
        or subEvent == "ENVIRONMENTAL_DAMAGE" then
        ShowDamageBorder()
    end
end)

-- =========================================================
-- Portrait
-- =========================================================

local portRing = frame:CreateTexture(nil, "BACKGROUND")
portRing:SetPoint("TOPLEFT",     frame, "TOPLEFT",     PAD - 1, -(PAD - 1))
portRing:SetSize(PORT_SIZE + 2, PORT_SIZE + 2)
portRing:SetColorTexture(0.45, 0.45, 0.45, 0.9)

local portrait = frame:CreateTexture(nil, "ARTWORK")
portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)
portrait:SetSize(PORT_SIZE, PORT_SIZE)

-- =========================================================
-- Name, level, type
-- =========================================================

local nameText = frame:CreateFontString(nil, "OVERLAY")
nameText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
nameText:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD + PORT_SIZE + 6, -PAD)
nameText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -PAD)
nameText:SetJustifyH("LEFT")
nameText:SetWordWrap(false)
nameText:SetTextColor(1, 1, 1, 1)

local levelText = frame:CreateFontString(nil, "OVERLAY")
levelText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
levelText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
levelText:SetTextColor(1, 1, 1, 1)

local typeText = frame:CreateFontString(nil, "OVERLAY")
typeText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
typeText:SetPoint("TOPLEFT", levelText, "BOTTOMLEFT", 0, -3)
typeText:SetTextColor(0.72, 0.72, 0.72, 1)

-- =========================================================
-- Health bar
-- =========================================================

local healthBar = CreateFrame("StatusBar", nil, frame)
healthBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD, BARS_Y)
healthBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, BARS_Y)
healthBar:SetHeight(BAR_H)
healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
healthBar:SetStatusBarColor(0.20, 0.75, 0.20)
healthBar:SetMinMaxValues(0, 100)
healthBar:SetValue(100)

local healthBg = healthBar:CreateTexture(nil, "BACKGROUND")
healthBg:SetAllPoints()
healthBg:SetColorTexture(0, 0, 0, 0.55)

local healthText = healthBar:CreateFontString(nil, "OVERLAY")
healthText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
healthText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
healthText:SetTextColor(1, 1, 1, 1)

-- =========================================================
-- Power bar
-- =========================================================

local powerBar = CreateFrame("StatusBar", nil, frame)
powerBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  PAD, BARS_Y - BAR_H - 3)
powerBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, BARS_Y - BAR_H - 3)
powerBar:SetHeight(BAR_H)
powerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
powerBar:SetMinMaxValues(0, 100)
powerBar:SetValue(0)

local powerBg = powerBar:CreateTexture(nil, "BACKGROUND")
powerBg:SetAllPoints()
powerBg:SetColorTexture(0, 0, 0, 0.55)

local powerText = powerBar:CreateFontString(nil, "OVERLAY")
powerText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
powerText:SetPoint("CENTER", powerBar, "CENTER", 0, 0)
powerText:SetTextColor(1, 1, 1, 1)

-- =========================================================
-- Aura icons
-- =========================================================

local debuffIcons = {}
local buffIcons   = {}
for i = 1, MAX_DEBUFFS do debuffIcons[i] = ExsarUI.CreateAuraIcon(frame, ICON_SIZE, true)  end
for i = 1, MAX_BUFFS   do buffIcons[i]   = ExsarUI.CreateAuraIcon(frame, ICON_SIZE, false) end

-- =========================================================
-- Layout / resize
-- =========================================================

local function ApplyLayout(numDebuffs, numBuffs)
    local debuffRows = numDebuffs > 0 and math.ceil(numDebuffs / ICONS_PER_ROW) or 0
    local buffRows   = numBuffs   > 0 and math.ceil(numBuffs   / ICONS_PER_ROW) or 0

    for i, f in ipairs(debuffIcons) do
        if i <= numDebuffs then
            local col = (i - 1) % ICONS_PER_ROW
            local row = math.floor((i - 1) / ICONS_PER_ROW)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", frame, "TOPLEFT",
                PAD + col * (ICON_SIZE + ICON_GAP),
                AURAS_Y - row * (ICON_SIZE + ICON_GAP))
            f:Show()
        else
            f:Hide()
        end
    end

    local buffStartY = AURAS_Y
    if debuffRows > 0 then
        buffStartY = buffStartY - debuffRows * (ICON_SIZE + ICON_GAP) - (buffRows > 0 and 4 or 0)
    end

    for i, f in ipairs(buffIcons) do
        if i <= numBuffs then
            local col = (i - 1) % ICONS_PER_ROW
            local row = math.floor((i - 1) / ICONS_PER_ROW)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", frame, "TOPLEFT",
                PAD + col * (ICON_SIZE + ICON_GAP),
                buffStartY - row * (ICON_SIZE + ICON_GAP))
            f:Show()
        else
            f:Hide()
        end
    end

    local auraH = 0
    if debuffRows + buffRows > 0 then
        auraH = (debuffRows + buffRows) * (ICON_SIZE + ICON_GAP) - ICON_GAP
        if debuffRows > 0 and buffRows > 0 then auraH = auraH + 4 end
    end

    local totalH = PRE_AURA_H + (auraH > 0 and (5 + auraH) or 0) + PAD
    frame:SetSize(FRAME_W, totalH)
    ReAnchor()
end

-- =========================================================
-- Low-health danger callout
-- =========================================================

local LOW_HP_THRESHOLD   = 30  -- default, overridden from DB on load
local LOW_HP_PULSE_FREQ  = 2.0
local LOW_HP_PULSE_MIN   = 0.3
local LOW_HP_PULSE_MAX   = 0.9

-- Container frame for all burst visuals
local burstFrame = CreateFrame("Frame", nil, frame)
burstFrame:SetAllPoints()
burstFrame:SetFrameLevel(frame:GetFrameLevel() + 12)
burstFrame:Hide()

-- Radiating lines shooting outward from the frame border.
local burstLines = {}
local BURST_DEFS = {
    -- Top edge
    { "T", 0.10, 22 },
    { "T", 0.25, 28 },
    { "T", 0.40, 25 },
    { "T", 0.50, 32 },
    { "T", 0.60, 25 },
    { "T", 0.75, 28 },
    { "T", 0.90, 22 },
    -- Bottom edge
    { "B", 0.10, 22 },
    { "B", 0.25, 28 },
    { "B", 0.40, 25 },
    { "B", 0.50, 32 },
    { "B", 0.60, 25 },
    { "B", 0.75, 28 },
    { "B", 0.90, 22 },
    -- Left edge
    { "L", 0.15, 22 },
    { "L", 0.40, 26 },
    { "L", 0.60, 26 },
    { "L", 0.85, 22 },
    -- Right edge
    { "R", 0.15, 22 },
    { "R", 0.40, 26 },
    { "R", 0.60, 26 },
    { "R", 0.85, 22 },
}

for _, def in ipairs(BURST_DEFS) do
    local entry = { edge = def[1], pos = def[2], len = def[3] }

    local line = burstFrame:CreateLine(nil, "OVERLAY")
    line:SetThickness(3)
    line:SetColorTexture(1.0, 0.15, 0.10, 1)
    entry.core = line

    local glow = burstFrame:CreateLine(nil, "ARTWORK")
    glow:SetThickness(10)
    glow:SetColorTexture(1.0, 0.10, 0.05, 0.3)
    entry.glow = glow

    burstLines[#burstLines + 1] = entry
end

-- Large pulsating "!" marker above the frame
local bangText = burstFrame:CreateFontString(nil, "OVERLAY")
bangText:SetFont("Fonts\\FRIZQT__.TTF", 80, "OUTLINE, THICKOUTLINE")
bangText:SetPoint("CENTER", frame, "CENTER", 0, 0)
bangText:SetTextColor(1.0, 0.20, 0.15, 1)
bangText:SetText("!")

local function UpdateBurstPositions()
    local fw = frame:GetWidth()
    local fh = frame:GetHeight()
    if not fw or fw < 1 then fw = FRAME_W end
    if not fh or fh < 1 then fh = PRE_AURA_H + PAD end
    local hw, hh = fw / 2, fh / 2

    for _, b in ipairs(burstLines) do
        local bx, by
        if b.edge == "T" then
            bx = -hw + b.pos * fw
            by = hh
        elseif b.edge == "B" then
            bx = -hw + b.pos * fw
            by = -hh
        elseif b.edge == "L" then
            bx = -hw
            by = -hh + b.pos * fh
        else -- R
            bx = hw
            by = -hh + b.pos * fh
        end
        local mag = math.sqrt(bx * bx + by * by)
        if mag < 0.01 then mag = 1 end
        local dx, dy = bx / mag, by / mag
        local ex = bx + dx * b.len
        local ey = by + dy * b.len
        b.core:SetStartPoint("CENTER", burstFrame, bx, by)
        b.core:SetEndPoint("CENTER", burstFrame, ex, ey)
        b.glow:SetStartPoint("CENTER", burstFrame, bx, by)
        b.glow:SetEndPoint("CENTER", burstFrame, ex, ey)
    end
end

local lowHpActive = false

local function ShowLowHpWarning()
    if not lowHpActive then
        lowHpActive = true
        burstFrame:Show()
    end
    UpdateBurstPositions()
end

local function HideLowHpWarning()
    if not lowHpActive then return end
    lowHpActive = false
    burstFrame:Hide()
end

local lowHpPulseFrame = CreateFrame("Frame")
lowHpPulseFrame:SetScript("OnUpdate", function()
    if not lowHpActive then return end
    local pulse = LOW_HP_PULSE_MIN + (LOW_HP_PULSE_MAX - LOW_HP_PULSE_MIN) *
                  (0.5 + 0.5 * math.sin(GetTime() * 2 * math.pi * LOW_HP_PULSE_FREQ))
    burstFrame:SetAlpha(pulse)
end)

-- =========================================================
-- Update functions
-- =========================================================

local function HealthColor(pct)
    if pct > 50 then
        return 0.20, 0.75, 0.20
    elseif pct > 20 then
        return 0.90, 0.90, 0.10
    else
        return 0.80, 0.15, 0.15
    end
end

local function UpdateBars()
    local hp    = UnitHealth(UNIT)
    local hpMax = UnitHealthMax(UNIT)
    if hpMax > 0 then
        healthBar:SetMinMaxValues(0, hpMax)
        healthBar:SetValue(hp)
        if hp == 0 then
            healthText:SetText("Dead")
            HideLowHpWarning()
        else
            local pct = math.floor(hp / hpMax * 100 + 0.5)
            healthText:SetText(pct .. "%")
            healthBar:SetStatusBarColor(HealthColor(pct))
            if pct <= LOW_HP_THRESHOLD then
                ShowLowHpWarning()
            else
                HideLowHpWarning()
            end
        end
    end

    local pw    = UnitPower(UNIT)
    local pwMax = UnitPowerMax(UNIT)
    if pwMax > 0 then
        powerBar:SetMinMaxValues(0, pwMax)
        powerBar:SetValue(pw)
        powerText:SetText(FormatNumber(pw) .. " / " .. FormatNumber(pwMax))
    else
        powerBar:SetMinMaxValues(0, 1)
        powerBar:SetValue(0)
        powerText:SetText("")
    end
end

local function UpdateUnit()
    SetPortraitTexture(portrait, UNIT)
    nameText:SetText(UnitName(UNIT) or "Unknown")
    local level = UnitLevel(UNIT)
    levelText:SetText(level >= 0 and tostring(level) or "??")
    typeText:SetText(UnitCreatureType(UNIT) or "")
    local pwType = UnitPowerType(UNIT)
    local pc = POWER_COLORS[pwType] or POWER_COLORS[2]  -- default to focus for pets
    powerBar:SetStatusBarColor(pc[1], pc[2], pc[3])
    UpdateBars()
end

local function UpdateAuras()
    local numDebuffs = 0
    for i = 1, MAX_DEBUFFS do
        local name, icon, count, _, duration, expTime = UnitDebuff(UNIT, i)
        if not name then break end
        numDebuffs = numDebuffs + 1
        local f = debuffIcons[numDebuffs]
        if f then
            f.icon:SetTexture(icon)
            if duration and duration > 0 then
                f.cooldown:SetCooldown(expTime - duration, duration)
            else
                f.cooldown:SetCooldown(0, 0)
            end
            f.stackText:SetText(count and count > 1 and tostring(count) or "")
        end
    end

    local numBuffs = 0
    for i = 1, MAX_BUFFS do
        local name, icon, count, _, duration, expTime = UnitBuff(UNIT, i)
        if not name then break end
        numBuffs = numBuffs + 1
        local f = buffIcons[numBuffs]
        if f then
            f.icon:SetTexture(icon)
            if duration and duration > 0 then
                f.cooldown:SetCooldown(expTime - duration, duration)
            else
                f.cooldown:SetCooldown(0, 0)
            end
            f.stackText:SetText(count and count > 1 and tostring(count) or "")
        end
    end

    ApplyLayout(numDebuffs, numBuffs)
end

local function Refresh()
    if not C_enabled or not UnitExists(UNIT) then frame:Hide(); return end
    frame:Show()
    UpdateUnit()
    UpdateAuras()
end

-- =========================================================
-- OnUpdate: bar polling (every 0.1 s)
-- =========================================================

local scanElapsed = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    scanElapsed = scanElapsed + elapsed
    if scanElapsed >= 0.1 then
        scanElapsed = 0
        if C_enabled and UnitExists(UNIT) then UpdateBars() end
    end
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_PET")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("UNIT_MAXHEALTH")
frame:RegisterEvent("UNIT_POWER_UPDATE")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("UNIT_PORTRAIT_UPDATE")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestoreTopleftPosition(self, pDB, tlState)
        C_enabled = pDB().enabled ~= false
        LOW_HP_THRESHOLD = pDB().lowHpThreshold or 30
        if C_enabled and UnitExists(UNIT) then
            UpdateUnit()
            UpdateAuras()
            self:Show()
        end

    elseif event == "PLAYER_ENTERING_WORLD" or event == "UNIT_PET" then
        Refresh()

    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if arg1 == UNIT and C_enabled and UnitExists(UNIT) then UpdateBars() end

    elseif event == "UNIT_POWER_UPDATE" then
        if arg1 == UNIT and C_enabled and UnitExists(UNIT) then UpdateBars() end

    elseif event == "UNIT_AURA" then
        if arg1 == UNIT and C_enabled and UnitExists(UNIT) then UpdateAuras() end

    elseif event == "UNIT_PORTRAIT_UPDATE" then
        if arg1 == UNIT and C_enabled and UnitExists(UNIT) then
            SetPortraitTexture(portrait, UNIT)
        end
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("petinforeset", function()
    tlState.x = DEFAULT_X
    tlState.y = DEFAULT_Y
    ReAnchor()
    pDB().x = nil
    pDB().y = nil
    print(ADDON_NAME .. ": Pet info widget position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Pet Info",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateCheckbox(parent, "Show widget", 16, y,
            function() return C_enabled end,
            function(v)
                C_enabled = v
                pDB().enabled = v
                if v and UnitExists(UNIT) then
                    ReAnchor()
                    UpdateUnit()
                    UpdateAuras()
                    frame:Show()
                else
                    frame:Hide()
                end
            end
        )
        y = y - 30

        y = ExsarUI.AddScaleSlider(parent, y, pDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, pDB, frame)

        ExsarAddon.CreateSlider(parent, "Low HP Alert (%)", 16, y, 5, 100, 1,
            function() return pDB().lowHpThreshold or 30 end,
            function(v)
                local rounded = math.floor(v + 0.5)
                pDB().lowHpThreshold = rounded
                LOW_HP_THRESHOLD = rounded
                UpdateUnit()
            end
        )
        y = y - 55

        y = ExsarUI.AddTopleftResetButton(parent, y, pDB, tlState, "Pet info", DEFAULT_X, DEFAULT_Y)

        return y
    end,
})
