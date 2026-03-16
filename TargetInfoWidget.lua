-- TargetInfoWidget module
-- A repositionable widget showing the current target's portrait, name,
-- level, classification, health, power, buffs, and debuffs.
-- Complements (does not replace) the default UI target frame.
-- Settings stored under ExsarAddonDB.targetInfo.

local ADDON_NAME = "ExsarAddon"

local tDB = ExsarUI.MakeDB("targetInfo")

local DEFAULT_X, DEFAULT_Y = -280, 175

-- =========================================================
-- Layout constants
-- =========================================================

local FRAME_W     = 210
local PAD         = 7
local PORT_SIZE   = 44
local BAR_H       = 15
local ICON_SIZE   = 18
local ICON_GAP    = 2

-- TBC Classic debuff cap per target: 16; buff cap: 32
local MAX_DEBUFFS = 16
local MAX_BUFFS   = 32

-- Icons that fit in one row (integer)
local ICONS_PER_ROW = math.floor((FRAME_W - PAD * 2 + ICON_GAP) / (ICON_SIZE + ICON_GAP))

-- Y (from frame top, negative = downward) where the health bar begins
local BARS_Y  = -(PAD + PORT_SIZE + 5)

-- Y where the aura section begins (below both bars)
local AURAS_Y = BARS_Y - BAR_H - 3 - BAR_H - 5

-- Height of everything above the aura section
local PRE_AURA_H = PAD + PORT_SIZE + 5 + BAR_H + 3 + BAR_H

-- =========================================================
-- Power type colours
-- =========================================================

local POWER_COLORS = ExsarUI.POWER_COLORS

-- =========================================================
-- Helpers
-- =========================================================

local function GetReactionColor(unit)
    if UnitIsEnemy("player", unit) then
        return 0.80, 0.15, 0.15
    elseif UnitIsFriend("player", unit) then
        return 0.20, 0.75, 0.20
    else
        return 0.90, 0.90, 0.10
    end
end

local function LevelColor(targetLevel)
    return ExsarLogic.LevelColor(targetLevel, UnitLevel("player"))
end

local FormatNumber = ExsarLogic.FormatNumber

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "TargetInfoFrame", UIParent)
local tlState = ExsarUI.SetupTopleftFrame(frame, tDB, DEFAULT_X, DEFAULT_Y)
local ReAnchor = tlState.ReAnchor
frame:Hide()

-- =========================================================
-- Portrait
-- =========================================================

-- 1px grey ring around the portrait
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

local levelText = frame:CreateFontString(nil, "OVERLAY")
levelText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
levelText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)

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

    -- Buff section sits below debuff rows (extra 4px gap when both present)
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

local HealthColor = ExsarLogic.HealthColorThreshold

local function UpdateBars()
    local hp    = UnitHealth("target")
    local hpMax = UnitHealthMax("target")
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

    local pw    = UnitPower("target")
    local pwMax = UnitPowerMax("target")
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

local function UpdateTarget()
    if not UnitExists("target") then
        frame:Hide()
        return
    end

    frame:Show()

    -- Portrait (2D texture)
    SetPortraitTexture(portrait, "target")

    -- Name coloured by reaction
    local name = UnitName("target") or "Unknown"
    local r, g, b = GetReactionColor("target")
    nameText:SetText(name)
    nameText:SetTextColor(r, g, b, 1)

    -- Level + classification suffix
    local level  = UnitLevel("target")
    local classif = UnitClassification("target")
    local lvlStr  = level >= 0 and tostring(level) or "??"
    if     classif == "worldboss" then lvlStr = lvlStr .. " Boss"
    elseif classif == "rareelite" then lvlStr = lvlStr .. " Rare Elite"
    elseif classif == "elite"     then lvlStr = lvlStr .. " Elite"
    elseif classif == "rare"      then lvlStr = lvlStr .. " Rare"
    end
    levelText:SetText(lvlStr)
    local lr, lg, lb, la = LevelColor(level)
    levelText:SetTextColor(lr, lg, lb, la)

    -- Portrait ring color: gold for elite/boss, silver for rare, grey for normal
    if classif == "worldboss" or classif == "elite" or classif == "rareelite" then
        portRing:SetColorTexture(1.00, 0.82, 0.00, 1.0)
    elseif classif == "rare" then
        portRing:SetColorTexture(0.75, 0.75, 0.75, 1.0)
    else
        portRing:SetColorTexture(0.45, 0.45, 0.45, 0.9)
    end

    -- Creature type or player class
    if UnitIsPlayer("target") then
        local _, class = UnitClass("target")
        typeText:SetText(class or "")
    else
        typeText:SetText(UnitCreatureType("target") or "")
    end

    -- Bar colours
    local pwType = UnitPowerType("target")
    local pc = POWER_COLORS[pwType] or POWER_COLORS[0]
    powerBar:SetStatusBarColor(pc[1], pc[2], pc[3])

    UpdateBars()
end

local function UpdateAuras()
    if not UnitExists("target") then return end

    -- Debuffs: name, icon, count, debuffType, duration, expirationTime, ...
    local numDebuffs = 0
    for i = 1, MAX_DEBUFFS do
        local name, icon, count, _, duration, expTime = UnitDebuff("target", i)
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

    -- Buffs: same return layout
    local numBuffs = 0
    for i = 1, MAX_BUFFS do
        local name, icon, count, _, duration, expTime = UnitBuff("target", i)
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

-- =========================================================
-- OnUpdate: smooth bar polling (every 0.1 s)
-- =========================================================

local scanElapsed = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    scanElapsed = scanElapsed + elapsed
    if scanElapsed >= 0.1 then
        scanElapsed = 0
        if UnitExists("target") then UpdateBars() end
    end
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("UNIT_MAXHEALTH")
frame:RegisterEvent("UNIT_POWER_UPDATE")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("UNIT_LEVEL")
frame:RegisterEvent("UNIT_PORTRAIT_UPDATE")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestoreTopleftPosition(self, tDB, tlState)
        if UnitExists("target") then
            UpdateTarget()
            UpdateAuras()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if UnitExists("target") then
            UpdateTarget()
            UpdateAuras()
        else
            frame:Hide()
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") then
            UpdateTarget()
            UpdateAuras()
        else
            frame:Hide()
        end

    elseif event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if arg1 == "target" then UpdateBars() end

    elseif event == "UNIT_POWER_UPDATE" then
        if arg1 == "target" then UpdateBars() end

    elseif event == "UNIT_AURA" then
        if arg1 == "target" then UpdateAuras() end

    elseif event == "UNIT_LEVEL" then
        if arg1 == "target" then UpdateTarget() end

    elseif event == "UNIT_PORTRAIT_UPDATE" then
        if arg1 == "target" then SetPortraitTexture(portrait, "target") end
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("targetinforeset", function()
    tlState.x = DEFAULT_X
    tlState.y = DEFAULT_Y
    ReAnchor()
    tDB().x = nil
    tDB().y = nil
    print(ADDON_NAME .. ": Target info widget position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Target Info",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, tDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, tDB, frame)

        y = ExsarUI.AddTopleftResetButton(parent, y, tDB, tlState, "Target info", DEFAULT_X, DEFAULT_Y)

        return y
    end,
})
