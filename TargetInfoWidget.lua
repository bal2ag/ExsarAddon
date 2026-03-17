-- TargetInfoWidget module
-- A repositionable widget showing the current target's portrait, name,
-- level, classification, health, power, buffs, and debuffs.
-- Complements (does not replace) the default UI target frame.
-- Settings stored under ExsarAddonDB.targetInfo.

local ADDON_NAME = "ExsarAddon"

local tDB = ExsarUI.MakeDB("targetInfo")

local DEFAULT_X, DEFAULT_Y = -280, 175

-- =========================================================
-- Layout constants (shared via ExsarUI.INFO_LAYOUT)
-- =========================================================

local IL        = ExsarUI.INFO_LAYOUT
local FRAME_W   = IL.FRAME_W
local PAD       = IL.PAD
local PORT_SIZE = IL.PORT_SIZE
local BAR_H     = IL.BAR_H
local ICON_SIZE = IL.ICON_SIZE
local BARS_Y    = IL.BARS_Y

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

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "TargetInfoFrame", UIParent)
local tlState = ExsarUI.SetupTopleftFrame(frame, tDB, DEFAULT_X, DEFAULT_Y)
local ReAnchor = tlState.ReAnchor
frame:Hide()

-- =========================================================
-- Portrait, text, bars
-- =========================================================

local portrait = ExsarUI.CreateInfoPortrait(frame)
local nameText, levelText, typeText = ExsarUI.CreateInfoText(frame)
local healthBar, healthText = ExsarUI.CreateInfoBar(frame, BARS_Y)
local powerBar,  powerText  = ExsarUI.CreateInfoBar(frame, BARS_Y - BAR_H - 3)
healthBar:SetValue(100)

local debuffIcons, buffIcons = ExsarUI.CreateAuraIconPools(frame)

-- =========================================================
-- Layout / resize
-- =========================================================

local function ApplyLayout(numDebuffs, numBuffs)
    ExsarUI.ApplyAuraLayout(frame, debuffIcons, buffIcons, numDebuffs, numBuffs, ReAnchor)
end

-- =========================================================
-- Update functions
-- =========================================================

local barCfg = {
    unit = "target",
    healthBar = healthBar, healthText = healthText,
    powerBar = powerBar, powerText = powerText,
}

local function UpdateBars()
    ExsarUI.UpdateInfoBars(barCfg)
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
    ExsarUI.ScanAndLayoutAuras("target", debuffIcons, buffIcons, ApplyLayout)
end

-- =========================================================
-- OnUpdate: smooth bar polling (every 0.1 s)
-- =========================================================

ExsarUI.CreatePoller(frame, 0.1, function()
    if UnitExists("target") then UpdateBars() end
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
