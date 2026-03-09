-- PlayerInfoWidget module
-- A repositionable widget showing the player's portrait, name, level,
-- class, health, power, buffs, and debuffs.
-- Always visible when enabled. Visibility togglable via config.
-- Settings stored under ExsarAddonDB.playerInfo.

local ADDON_NAME = "ExsarAddon"
local UNIT = "player"

local function pDB()
    ExsarAddonDB.playerInfo = ExsarAddonDB.playerInfo or {}
    return ExsarAddonDB.playerInfo
end

local anchorX, anchorY = -460, 280
local C_dragging = false
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

local POWER_COLORS = {
    [0] = {0.00, 0.44, 0.87},
    [1] = {0.78, 0.25, 0.25},
    [2] = {1.00, 0.54, 0.00},
    [3] = {1.00, 0.82, 0.00},
    [4] = {0.25, 0.75, 0.25},
}

local function FormatNumber(n)
    if n >= 1000 then return string.format("%.1fk", n / 1000) end
    return tostring(n)
end

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "PlayerInfoFrame", UIParent)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)

local function ReAnchor()
    if C_dragging then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "CENTER", anchorX, anchorY)
end

frame:SetScript("OnDragStart", function(self)
    C_dragging = true
    self:StartMoving()
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    C_dragging = false
    local left = self:GetLeft()
    local top  = self:GetTop()
    if left and top then
        local s = self:GetScale()
        anchorX = left - UIParent:GetWidth()  / (2 * s)
        anchorY = top  - UIParent:GetHeight() / (2 * s)
        ReAnchor()
        pDB().x = anchorX
        pDB().y = anchorY
    end
end)
frame:Hide()

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0.05, 0.05, 0.05, 0.82)

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
    -- Any damage suffix triggers the border
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
healthBar:SetStatusBarColor(0.20, 0.75, 0.20)  -- default; updated dynamically in UpdateBars
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
-- Aura icon factory
-- =========================================================

local function CreateAuraIcon(isDebuff)
    local f = CreateFrame("Frame", nil, frame)
    f:SetSize(ICON_SIZE, ICON_SIZE)
    local ring = f:CreateTexture(nil, "BACKGROUND")
    ring:SetPoint("TOPLEFT",     f, "TOPLEFT",     -1,  1)
    ring:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  1, -1)
    if isDebuff then
        ring:SetColorTexture(0.80, 0.12, 0.12, 1.0)
    else
        ring:SetColorTexture(0.45, 0.45, 0.45, 0.85)
    end
    local fill = f:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    fill:SetColorTexture(0, 0, 0, 1)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon
    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:EnableMouse(false)
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    f.cooldown = cd
    local stackText = f:CreateFontString(nil, "OVERLAY")
    stackText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    stackText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, 1)
    stackText:SetTextColor(1, 1, 0.8, 1)
    f.stackText = stackText
    f:Hide()
    return f
end

local debuffIcons = {}
local buffIcons   = {}
for i = 1, MAX_DEBUFFS do debuffIcons[i] = CreateAuraIcon(true)  end
for i = 1, MAX_BUFFS   do buffIcons[i]   = CreateAuraIcon(false) end

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
        else
            local pct = math.floor(hp / hpMax * 100 + 0.5)
            healthText:SetText(pct .. "%")
            healthBar:SetStatusBarColor(HealthColor(pct))
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
    local _, class = UnitClass(UNIT)
    typeText:SetText(class or "")
    local pwType = UnitPowerType(UNIT)
    local pc = POWER_COLORS[pwType] or POWER_COLORS[0]
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
    if not C_enabled then frame:Hide(); return end
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
        if C_enabled then UpdateBars() end
    end
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("UNIT_MAXHEALTH")
frame:RegisterEvent("UNIT_POWER_UPDATE")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
frame:RegisterEvent("PLAYER_LEVEL_UP")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        local db = pDB()
        anchorX   = db.x or -460
        anchorY   = db.y or  280
        C_enabled = db.enabled ~= false
        self:SetScale(db.scale or 1.0)
        self:EnableMouse(not db.locked)
        ReAnchor()
        if C_enabled then
            UpdateUnit()
            UpdateAuras()
            self:Show()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        Refresh()

    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if arg1 == UNIT and C_enabled then UpdateBars() end

    elseif event == "UNIT_POWER_UPDATE" then
        if arg1 == UNIT and C_enabled then UpdateBars() end

    elseif event == "UNIT_AURA" then
        if arg1 == UNIT and C_enabled then UpdateAuras() end

    elseif event == "UNIT_PORTRAIT_UPDATE" then
        if arg1 == UNIT and C_enabled then SetPortraitTexture(portrait, UNIT) end

    elseif event == "PLAYER_LEVEL_UP" then
        if C_enabled then UpdateUnit() end
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("playerinforeset", function()
    anchorX = -460
    anchorY =  280
    ReAnchor()
    pDB().x = nil
    pDB().y = nil
    print(ADDON_NAME .. ": Player info widget position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Player Info",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateCheckbox(parent, "Show widget", 16, y,
            function() return C_enabled end,
            function(v)
                C_enabled = v
                pDB().enabled = v
                if v then
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

        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return pDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                pDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return pDB().locked and true or false end,
            function(v)
                pDB().locked = v
                frame:EnableMouse(not v)
            end
        )
        y = y - 30

        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            anchorX = -460
            anchorY =  280
            ReAnchor()
            pDB().x = nil
            pDB().y = nil
            print(ADDON_NAME .. ": Player info widget position reset.")
        end)
        y = y - 30

        return y
    end,
})
