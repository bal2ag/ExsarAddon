-- RaidTargetWidget module
-- Shows compact info for all units marked with raid target icons.
-- Click an entry to target that unit.
-- Discovers marked units by scanning nameplates, party/raid members and targets.
-- Settings stored under ExsarAddonDB.raidTargets.

local ADDON_NAME = "ExsarAddon"

local rDB = ExsarUI.MakeDB("raidTargets")

local anchorX, anchorY = 350, 175
local C_dragging = false
local C_locked   = false

-- =========================================================
-- Layout constants
-- =========================================================

local FRAME_W      = 180
local PAD          = 5
local ENTRY_H      = 34
local ENTRY_GAP    = 2
local PORT_SIZE    = 28
local BAR_H        = 6
local RT_ICON_SIZE = 16   -- raid target icon overlay

-- =========================================================
-- Helpers
-- =========================================================

local HealthColor = ExsarLogic.HealthColorGradient

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "RaidTargetFrame", UIParent)
frame:SetSize(FRAME_W, 50)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:Hide()

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
        rDB().x = anchorX
        rDB().y = anchorY
    end
end)

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0.05, 0.05, 0.05, 0.82)

-- Placeholder shown when unlocked and no marked targets exist
local placeholderText = frame:CreateFontString(nil, "OVERLAY")
placeholderText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
placeholderText:SetPoint("CENTER", frame, "CENTER", 0, 0)
placeholderText:SetTextColor(0.55, 0.55, 0.55, 0.9)
placeholderText:SetText("Raid Targets")
placeholderText:Hide()

local PLACEHOLDER_H = 30

-- =========================================================
-- Entry pool (max 8, one per possible raid icon)
-- =========================================================

local entries = {}

local function CreateEntry(index)
    local btn = CreateFrame("Button", ADDON_NAME .. "RaidTarget" .. index,
                            frame, "SecureActionButtonTemplate")
    btn:SetSize(FRAME_W - PAD * 2, ENTRY_H)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type", "macro")

    -- Hover highlight
    local hoverBg = btn:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(0.3, 0.3, 0.3, 0.3)
    hoverBg:Hide()

    btn:HookScript("OnEnter", function()
        hoverBg:Show()
        if btn.unitToken and UnitExists(btn.unitToken) then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetUnit(btn.unitToken)
            GameTooltip:Show()
        end
    end)
    btn:HookScript("OnLeave", function()
        hoverBg:Hide()
        GameTooltip:Hide()
    end)

    -- Portrait ring (1px grey)
    local portRing = btn:CreateTexture(nil, "BORDER")
    portRing:SetSize(PORT_SIZE + 2, PORT_SIZE + 2)
    portRing:SetPoint("LEFT", btn, "LEFT", 1, 0)
    portRing:SetColorTexture(0.45, 0.45, 0.45, 0.85)

    -- Portrait black fill
    local portFill = btn:CreateTexture(nil, "BORDER")
    portFill:SetSize(PORT_SIZE, PORT_SIZE)
    portFill:SetPoint("CENTER", portRing, "CENTER", 0, 0)
    portFill:SetColorTexture(0, 0, 0, 1)

    -- Portrait texture
    local portrait = btn:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(PORT_SIZE, PORT_SIZE)
    portrait:SetPoint("CENTER", portRing, "CENTER", 0, 0)
    pcall(function()
        portrait:SetMask("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    end)

    -- Raid target icon (top-center of portrait, overlapping edge)
    local raidIcon = btn:CreateTexture(nil, "OVERLAY")
    raidIcon:SetSize(RT_ICON_SIZE, RT_ICON_SIZE)
    raidIcon:SetPoint("TOP", portrait, "TOP", 0, RT_ICON_SIZE * 0.45)

    -- Name text (right of portrait)
    local nameText = btn:CreateFontString(nil, "OVERLAY")
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    nameText:SetPoint("TOPLEFT", portRing, "TOPRIGHT", 4, -2)
    nameText:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)

    -- Health bar background
    local barBg = btn:CreateTexture(nil, "ARTWORK")
    barBg:SetHeight(BAR_H)
    barBg:SetPoint("TOPLEFT", portRing, "TOPRIGHT", 4, -16)
    barBg:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    barBg:SetColorTexture(0.15, 0.15, 0.15, 0.9)

    -- Health bar
    local healthBar = CreateFrame("StatusBar", nil, btn)
    healthBar:SetHeight(BAR_H)
    healthBar:SetPoint("TOPLEFT", barBg, "TOPLEFT", 0, 0)
    healthBar:SetPoint("BOTTOMRIGHT", barBg, "BOTTOMRIGHT", 0, 0)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetStatusBarColor(0.1, 0.9, 0.1)
    healthBar:SetMinMaxValues(0, 1)

    -- Health percentage text
    local healthText = healthBar:CreateFontString(nil, "OVERLAY")
    healthText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    healthText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)

    btn.portrait   = portrait
    btn.raidIcon   = raidIcon
    btn.nameText   = nameText
    btn.healthBar  = healthBar
    btn.healthText = healthText
    btn.unitToken  = nil
    btn:Hide()

    return btn
end

for i = 1, 8 do
    entries[i] = CreateEntry(i)
end

-- =========================================================
-- Unit scanning
-- =========================================================

local function ScanMarkedUnits()
    local found = {}   -- guid -> {unit, index}

    local function Check(unit)
        if not UnitExists(unit) then return end
        local idx = GetRaidTargetIndex(unit)
        if not idx then return end
        local guid = UnitGUID(unit)
        if not guid then return end
        -- Prefer the first token we find per guid
        if not found[guid] then
            found[guid] = { unit = unit, index = idx, guid = guid }
        end
    end

    -- Player's target and focus
    Check("target")
    Check("focus")

    -- Party members + their targets + their pets
    for i = 1, 4 do
        Check("party" .. i)
        Check("party" .. i .. "target")
        Check("partypet" .. i)
        Check("partypet" .. i .. "target")
    end

    -- Raid members + their targets
    for i = 1, 40 do
        Check("raid" .. i)
        Check("raid" .. i .. "target")
    end

    -- Nameplates (visible units nearby — works even when nobody targets them)
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = C_NamePlate.GetNamePlates()
        if plates then
            for _, plate in ipairs(plates) do
                -- Try multiple property names for TBC Classic Anniversary compat
                local unit = plate.namePlateUnitToken
                if not unit and UnitTokenFromNamePlate then
                    unit = UnitTokenFromNamePlate(plate)
                end
                if unit then
                    Check(unit)
                end
            end
        end
    end

    -- Boss frames
    for i = 1, 5 do
        Check("boss" .. i)
    end

    return found
end

-- =========================================================
-- Find a party/raid member whose target matches this GUID
-- Returns e.g. "party2" or "raid5" for use with /assist
-- =========================================================

local function FindAssistToken(guid)
    -- Check party members first (more common, smaller loop)
    for i = 1, 4 do
        local token = "party" .. i .. "target"
        if UnitExists(token) and UnitGUID(token) == guid then
            return "party" .. i
        end
    end
    -- Check raid members
    for i = 1, 40 do
        local token = "raid" .. i .. "target"
        if UnitExists(token) and UnitGUID(token) == guid then
            return "raid" .. i
        end
    end
    return nil
end

-- =========================================================
-- Display update
-- =========================================================

local activeCount = 0

local function UpdateDisplay()
    local found = ScanMarkedUnits()

    -- Build sorted array by raid icon index (1=star .. 8=skull)
    local sorted = {}
    for _, info in pairs(found) do
        sorted[#sorted + 1] = info
    end
    table.sort(sorted, function(a, b) return a.index > b.index end)

    local count = #sorted
    local inCombat = InCombatLockdown()

    for i = 1, 8 do
        local entry = entries[i]
        local info = sorted[i]

        if info then
            local unit = info.unit

            -- Store token for tooltip
            entry.unitToken = unit

            -- Find an assist-able token for reliable targeting
            local assistToken = FindAssistToken(info.guid)
            local canTarget = assistToken ~= nil

            -- Update secure attribute (only out of combat)
            if not inCombat then
                if canTarget then
                    entry:SetAttribute("macrotext", "/assist " .. assistToken)
                else
                    entry:SetAttribute("macrotext", "")
                end
            end

            -- Portrait
            SetPortraitTexture(entry.portrait, unit)
            if canTarget then
                entry.portrait:SetDesaturated(false)
                entry.portrait:SetAlpha(1.0)
            else
                entry.portrait:SetDesaturated(true)
                entry.portrait:SetAlpha(0.6)
            end

            -- Raid icon texture
            entry.raidIcon:SetTexture(
                "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. info.index)
            entry.raidIcon:Show()

            -- Name (colored by reaction)
            local name = UnitName(unit) or "?"
            local r, g, b = 0.9, 0.9, 0.9
            if UnitIsEnemy("player", unit) then
                r, g, b = 0.90, 0.20, 0.20
            elseif UnitIsFriend("player", unit) then
                r, g, b = 0.30, 0.80, 0.30
            else
                r, g, b = 0.95, 0.95, 0.15
            end
            entry.nameText:SetText(name)
            if canTarget then
                entry.nameText:SetTextColor(r, g, b)
            else
                entry.nameText:SetTextColor(r * 0.5, g * 0.5, b * 0.5)
            end

            -- Health
            local hp    = UnitHealth(unit)
            local hpMax = UnitHealthMax(unit)
            if hpMax > 0 then
                entry.healthBar:SetMinMaxValues(0, hpMax)
                entry.healthBar:SetValue(hp)
                local pct = math.floor(hp / hpMax * 100 + 0.5)
                entry.healthText:SetText(pct .. "%")
                entry.healthBar:SetStatusBarColor(HealthColor(pct))
            else
                entry.healthBar:SetMinMaxValues(0, 1)
                entry.healthBar:SetValue(1)
                entry.healthText:SetText("")
            end

            -- Position within frame
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", frame, "TOPLEFT",
                           PAD, -(PAD + (i - 1) * (ENTRY_H + ENTRY_GAP)))

            if not inCombat then
                entry:Show()
            end
        else
            entry.unitToken = nil
            if not inCombat then
                entry:Hide()
            end
        end
    end

    activeCount = count

    -- Resize and show/hide frame
    if count > 0 then
        placeholderText:Hide()
        local totalH = PAD * 2 + count * ENTRY_H + math.max(0, count - 1) * ENTRY_GAP
        frame:SetSize(FRAME_W, totalH)
        ReAnchor()
        frame:Show()
    else
        if not C_locked then
            frame:SetSize(FRAME_W, PLACEHOLDER_H)
            ReAnchor()
            placeholderText:Show()
            frame:Show()
        else
            placeholderText:Hide()
            if not inCombat then
                frame:Hide()
            end
        end
    end
end

-- =========================================================
-- Health-only fast update (no rescan)
-- =========================================================

local function UpdateHealth()
    for i = 1, activeCount do
        local entry = entries[i]
        local unit = entry.unitToken
        if unit and UnitExists(unit) then
            local hp    = UnitHealth(unit)
            local hpMax = UnitHealthMax(unit)
            if hpMax > 0 then
                entry.healthBar:SetMinMaxValues(0, hpMax)
                entry.healthBar:SetValue(hp)
                local pct = math.floor(hp / hpMax * 100 + 0.5)
                entry.healthText:SetText(pct .. "%")
                entry.healthBar:SetStatusBarColor(HealthColor(pct))
            end
        end
    end
end

-- =========================================================
-- Polling
-- =========================================================

local pollFrame = CreateFrame("Frame")
local scanElapsed = 0
local SCAN_INTERVAL = 0.3

pollFrame:SetScript("OnUpdate", function(self, elapsed)
    scanElapsed = scanElapsed + elapsed
    if scanElapsed >= SCAN_INTERVAL then
        scanElapsed = 0
        UpdateDisplay()
    end
end)
pollFrame:Hide()

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        local db = rDB()
        anchorX = db.x or 350
        anchorY = db.y or 175
        self:SetScale(db.scale or 1.0)
        C_locked = db.locked and true or false
        self:EnableMouse(not C_locked)
        ReAnchor()
        pollFrame:Show()
        UpdateDisplay()

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateDisplay()

    elseif event == "PLAYER_REGEN_ENABLED" then
        UpdateDisplay()
    end
end)

-- =========================================================
-- Slash sub-command
-- =========================================================

ExsarAddon.AddSlashCommand("rtreset", function()
    anchorX = 350
    anchorY = 175
    ReAnchor()
    rDB().x = nil
    rDB().y = nil
    print(ADDON_NAME .. ": Raid target widget position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Raid Target Widget",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return rDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                rDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return C_locked end,
            function(v)
                rDB().locked = v
                C_locked = v
                frame:EnableMouse(not v)
                UpdateDisplay()
            end
        )
        y = y - 30

        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            anchorX = 350
            anchorY = 175
            ReAnchor()
            rDB().x = nil
            rDB().y = nil
            print(ADDON_NAME .. ": Raid target widget position reset.")
        end)
        y = y - 30

        return y
    end,
})
