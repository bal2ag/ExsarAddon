-- PlayerInfoWidget module
-- A repositionable widget showing the player's portrait, name, level,
-- class, health, power, buffs, and debuffs.
-- Always visible when enabled. Visibility togglable via config.
-- Settings stored under ExsarAddonDB.playerInfo.

local ADDON_NAME = "ExsarAddon"
local UNIT = "player"

local pDB = ExsarUI.MakeDB("playerInfo")

local DEFAULT_X, DEFAULT_Y = -460, 280
local C_enabled = true

-- =========================================================
-- Layout constants (shared via ExsarUI.INFO_LAYOUT)
-- =========================================================

local IL        = ExsarUI.INFO_LAYOUT
local BAR_H     = IL.BAR_H
local BARS_Y    = IL.BARS_Y

local POWER_COLORS = ExsarUI.POWER_COLORS

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "PlayerInfoFrame", UIParent)
local tlState = ExsarUI.SetupTopleftFrame(frame, pDB, DEFAULT_X, DEFAULT_Y)
local ReAnchor = tlState.ReAnchor
frame:Hide()

-- =========================================================
-- Damage border (pulsating red on recent damage)
-- =========================================================

ExsarUI.CreateDamageBorder(frame, UNIT)

-- =========================================================
-- Portrait, text, bars
-- =========================================================

local portrait = ExsarUI.CreateInfoPortrait(frame)
local nameText, levelText, typeText = ExsarUI.CreateInfoText(frame)
nameText:SetTextColor(1, 1, 1, 1)
levelText:SetTextColor(1, 1, 1, 1)
local healthBar, healthText = ExsarUI.CreateInfoBar(frame, BARS_Y)
healthBar:SetStatusBarColor(0.20, 0.75, 0.20)
healthBar:SetValue(100)
local powerBar, powerText = ExsarUI.CreateInfoBar(frame, BARS_Y - BAR_H - 3)

-- =========================================================
-- Aura icons
-- =========================================================

local debuffIcons, buffIcons = ExsarUI.CreateAuraIconPools(frame)

-- =========================================================
-- Layout / resize
-- =========================================================

local function ApplyLayout(numDebuffs, numBuffs)
    ExsarUI.ApplyAuraLayout(frame, debuffIcons, buffIcons, numDebuffs, numBuffs, ReAnchor)
end

-- =========================================================
-- Low-health danger callout
-- =========================================================

local LOW_HP_THRESHOLD = 30  -- default, overridden from DB on load
local RealShowLowHp, RealHideLowHp = ExsarUI.CreateLowHpWarning(frame)

local C_lowHpActive = false
local C_lowHpSoundTime = 0
local LOW_HP_SOUND_ID  = 8333     -- PVPWarningHorde
local SOUND_COOLDOWN   = 5

local function ShowLowHpWarning()
    RealShowLowHp()
    if not C_lowHpActive then
        C_lowHpActive = true
        if pDB().lowHpSound ~= false then
            local now = GetTime()
            if now - C_lowHpSoundTime >= SOUND_COOLDOWN then
                PlaySound(LOW_HP_SOUND_ID, "Master")
                C_lowHpSoundTime = now
            end
        end
    end
end

local function HideLowHpWarning()
    RealHideLowHp()
    C_lowHpActive = false
end

-- =========================================================
-- Update functions
-- =========================================================

local barCfg = {
    unit = UNIT,
    healthBar = healthBar, healthText = healthText,
    powerBar = powerBar, powerText = powerText,
    showLowHp = ShowLowHpWarning, hideLowHp = HideLowHpWarning,
    lowHpThreshold = LOW_HP_THRESHOLD,
}

local function UpdateBars()
    barCfg.lowHpThreshold = LOW_HP_THRESHOLD
    ExsarUI.UpdateInfoBars(barCfg)
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
    ExsarUI.ScanAndLayoutAuras(UNIT, debuffIcons, buffIcons, ApplyLayout)
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

ExsarUI.CreatePoller(frame, 0.1, function()
    if C_enabled then UpdateBars() end
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
        ExsarUI.RestoreTopleftPosition(self, pDB, tlState)
        C_enabled = pDB().enabled ~= false
        LOW_HP_THRESHOLD = pDB().lowHpThreshold or 30
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
    tlState.x = DEFAULT_X
    tlState.y = DEFAULT_Y
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

        ExsarAddon.CreateCheckbox(parent, "Low HP alert sound", 16, y,
            function() return pDB().lowHpSound ~= false end,
            function(v) pDB().lowHpSound = v end
        )
        y = y - 30

        y = ExsarUI.AddTopleftResetButton(parent, y, pDB, tlState, "Player info", DEFAULT_X, DEFAULT_Y)

        return y
    end,
})
