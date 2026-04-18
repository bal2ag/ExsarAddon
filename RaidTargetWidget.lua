-- RaidTargetWidget module
-- Shows compact info for all units marked with raid target icons.
-- Click an entry to target that unit.
-- Discovers marked units by scanning nameplates, party/raid members and targets.
-- Settings stored under ExsarAddonDB.raidTargets.

local ADDON_NAME = "ExsarAddon"

local rDB = ExsarUI.MakeDB("raidTargets")

local DEFAULT_X, DEFAULT_Y = 350, 175
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

-- Target glow: highlights the entry matching the player's current target
local GLOW_COLOR    = { 1.0, 0.82, 0.25, 0.85 }
local GLOW_SIZE     = 3
local GLOW_PULSE_HZ  = 1.2
local GLOW_PULSE_MIN = 0.45
local GLOW_PULSE_MAX = 1.0

-- =========================================================
-- Helpers
-- =========================================================

local HealthColor  = ExsarLogic.HealthColorGradient
local PulseAlpha   = ExsarLogic.PulseAlpha

-- Iterate every unit token we can cheaply query and return the first whose
-- GUID still matches. Re-verifying at click time lets us safely use tokens
-- that are normally considered "unstable" (nameplateN, partyNtarget) --
-- because we confirm the token currently points to the intended mob.
local function FindTokenByGUID(guid)
    if not guid then return nil end

    if UnitExists("target")    and UnitGUID("target")    == guid then return "target"    end
    if UnitExists("focus")     and UnitGUID("focus")     == guid then return "focus"     end
    if UnitExists("mouseover") and UnitGUID("mouseover") == guid then return "mouseover" end

    for i = 1, 5 do
        local t = "boss" .. i
        if UnitExists(t) and UnitGUID(t) == guid then return t end
    end

    if IsInRaid() then
        for i = 1, 40 do
            local t = "raid" .. i .. "target"
            if UnitExists(t) and UnitGUID(t) == guid then return t end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local t = "party" .. i .. "target"
            if UnitExists(t) and UnitGUID(t) == guid then return t end
            local pt = "partypet" .. i .. "target"
            if UnitExists(pt) and UnitGUID(pt) == guid then return pt end
        end
    end
    if UnitExists("pettarget") and UnitGUID("pettarget") == guid then return "pettarget" end

    if C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = C_NamePlate.GetNamePlates()
        if plates then
            for _, plate in ipairs(plates) do
                local t = plate.namePlateUnitToken
                if not t and UnitTokenFromNamePlate then
                    t = UnitTokenFromNamePlate(plate)
                end
                if t and UnitExists(t) and UnitGUID(t) == guid then
                    return t
                end
            end
        end
    end

    return nil
end

-- Find a party/raid member whose current target is the intended mob,
-- for the `/assist` fallback when no direct token resolves the GUID.
local function FindAssistMember(guid, rIdx)
    local prefix, count
    if IsInRaid() then
        prefix, count = "raid", 40
    elseif IsInGroup() then
        prefix, count = "party", 4
    else
        return nil
    end
    for i = 1, count do
        local m  = prefix .. i
        local mt = m .. "target"
        if UnitExists(mt) and UnitGUID(mt) == guid then return m end
    end
    -- GUID on member's target may be nil if they're out of our client range;
    -- fall back to icon match so /assist can still rescue us.
    if rIdx then
        for i = 1, count do
            local m  = prefix .. i
            local mt = m .. "target"
            if UnitExists(mt) and GetRaidTargetIndex(mt) == rIdx then return m end
        end
    end
    return nil
end

-- =========================================================
-- Click outcome diagnostics (failure-only chat logging)
-- =========================================================

local RT_ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

local function IsDebugEnabled()
    local v = rDB().debugClicks
    if v == nil then return true end  -- default ON so failures surface without setup
    return v
end

local function ShortGuid(g)
    if not g then return "nil" end
    return "." .. string.sub(g, -6)
end

local function FormatIcon(i)
    if not i then return "none" end
    return i .. " " .. (RT_ICON_NAMES[i] or "?")
end

local function LogClickMiss(dbg)
    local p = "|cffff8800[ExsarRTW]|r "
    print(p .. "CLICK MISSED (tier=" .. tostring(dbg.tier) .. ")")
    print(p .. "  intended: icon=" .. FormatIcon(dbg.intendedIdx)
          .. " name=\"" .. (dbg.intendedName or "?") .. "\""
          .. " guid=" .. ShortGuid(dbg.intendedGuid))
    local r = ""
    if dbg.token     then r = r .. " token=" .. dbg.token end
    if dbg.assist    then r = r .. " assist=" .. dbg.assist end
    if dbg.macrotext then r = r .. " macro=\"" .. dbg.macrotext .. "\"" end
    if r ~= "" then print(p .. "  resolver:" .. r) end
    print(p .. "  before: name=\"" .. (dbg.oldName or "none") .. "\""
          .. " guid=" .. ShortGuid(dbg.oldGuid)
          .. " icon=" .. FormatIcon(dbg.oldIdx))
    print(p .. "  after:  name=\"" .. (dbg.newName or "none") .. "\""
          .. " guid=" .. ShortGuid(dbg.newGuid)
          .. " icon=" .. FormatIcon(dbg.newIdx))
end

local function CheckClickOutcome(dbg)
    if not dbg or not dbg.intendedGuid then return end
    dbg.newGuid = UnitExists("target") and UnitGUID("target") or nil
    dbg.newName = UnitExists("target") and UnitName("target") or nil
    dbg.newIdx  = UnitExists("target") and GetRaidTargetIndex("target") or nil
    if dbg.newGuid == dbg.intendedGuid then return end  -- success, nothing to log
    if not IsDebugEnabled() then return end
    LogClickMiss(dbg)
end

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "RaidTargetFrame", UIParent)
frame:SetSize(FRAME_W, 50)
local tlState = ExsarUI.SetupTopleftFrame(frame, rDB, DEFAULT_X, DEFAULT_Y)
local ReAnchor = tlState.ReAnchor
frame:Hide()

-- Placeholder shown when unlocked and no marked targets exist
local placeholderText = ExsarUI.CreatePlaceholder(frame, "Raid Targets")

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
    btn:SetAttribute("macrotext", "/targetexact nil")

    -- PreClick: pick the best targeting strategy at click time, using the
    -- intended mob's GUID as the ground truth.
    -- Tier 1: find ANY unit token whose UnitGUID() currently equals our stored
    --         GUID -- handles nameplateN, partyNtarget, etc. safely because
    --         we re-verify at click time. Uses secure type=target.
    -- Tier 2: /assist a group member whose current target matches our GUID
    --         (or, if GUIDs aren't resolvable locally, our raid icon).
    -- Tier 3: /targetexact Name -- last resort; may hit wrong same-name mob.
    btn:SetScript("PreClick", function(self)
        local guid = self.targetGuid
        local name = self.targetName
        local rIdx = self.raidIndex

        self:SetAttribute("type", "macro")
        self:SetAttribute("unit", nil)
        self:SetAttribute("macrotext", "/targetexact nil")

        local dbg = {
            intendedGuid = guid,
            intendedName = name,
            intendedIdx  = rIdx,
            oldGuid = UnitExists("target") and UnitGUID("target") or nil,
            oldName = UnitExists("target") and UnitName("target") or nil,
            oldIdx  = UnitExists("target") and GetRaidTargetIndex("target") or nil,
        }

        if not guid then
            dbg.tier = "no-guid"
            self.lastClickDbg = dbg
            return
        end

        local token = FindTokenByGUID(guid)
        if token then
            self:SetAttribute("type", "target")
            self:SetAttribute("unit", token)
            dbg.tier  = 1
            dbg.token = token
            self.lastClickDbg = dbg
            return
        end

        local member = FindAssistMember(guid, rIdx)
        if member then
            local macro = "/assist [@" .. member .. "]"
            self:SetAttribute("macrotext", macro)
            dbg.tier      = 2
            dbg.assist    = member
            dbg.macrotext = macro
            self.lastClickDbg = dbg
            return
        end

        if name then
            local macro = "/targetexact " .. name
            self:SetAttribute("macrotext", macro)
            dbg.tier      = 3
            dbg.macrotext = macro
        else
            dbg.tier = "none"
        end
        self.lastClickDbg = dbg
    end)

    -- PostClick: schedule an outcome check so we log when a click failed to
    -- swap the player's target to the intended mob.
    btn:SetScript("PostClick", function(self)
        local dbg = self.lastClickDbg
        self.lastClickDbg = nil
        if not dbg or not dbg.intendedGuid then return end
        if C_Timer and C_Timer.After then
            C_Timer.After(0.25, function() CheckClickOutcome(dbg) end)
        end
    end)

    -- Targeting data (updated by UpdateDisplay, read by PreClick)
    btn.targetGuid  = nil
    btn.targetName  = nil
    btn.raidIndex   = nil

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

    -- Target glow (4 edge textures forming a border)
    local glow = {}
    local gr, gg, gb, ga = unpack(GLOW_COLOR)
    -- top
    glow[1] = btn:CreateTexture(nil, "BACKGROUND")
    glow[1]:SetColorTexture(gr, gg, gb, ga)
    glow[1]:SetPoint("TOPLEFT", btn, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
    glow[1]:SetPoint("TOPRIGHT", btn, "TOPRIGHT", GLOW_SIZE, GLOW_SIZE)
    glow[1]:SetHeight(GLOW_SIZE)
    -- bottom
    glow[2] = btn:CreateTexture(nil, "BACKGROUND")
    glow[2]:SetColorTexture(gr, gg, gb, ga)
    glow[2]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -GLOW_SIZE, -GLOW_SIZE)
    glow[2]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
    glow[2]:SetHeight(GLOW_SIZE)
    -- left
    glow[3] = btn:CreateTexture(nil, "BACKGROUND")
    glow[3]:SetColorTexture(gr, gg, gb, ga)
    glow[3]:SetPoint("TOPLEFT", btn, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
    glow[3]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -GLOW_SIZE, -GLOW_SIZE)
    glow[3]:SetWidth(GLOW_SIZE)
    -- right
    glow[4] = btn:CreateTexture(nil, "BACKGROUND")
    glow[4]:SetColorTexture(gr, gg, gb, ga)
    glow[4]:SetPoint("TOPRIGHT", btn, "TOPRIGHT", GLOW_SIZE, GLOW_SIZE)
    glow[4]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
    glow[4]:SetWidth(GLOW_SIZE)
    for _, tex in ipairs(glow) do tex:Hide() end

    btn.glow       = glow
    btn.glowActive = false
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
    local found = {}      -- guid -> {unit, index, guid, name}
    local byIndex = {}    -- index -> guid (one entry per raid icon)

    local function Check(unit)
        if not UnitExists(unit) then return end
        if not UnitCanAttack("player", unit) then return end
        local idx = GetRaidTargetIndex(unit)
        if not idx then return end
        local guid = UnitGUID(unit)
        if not guid then return end

        -- Deduplicate: one GUID per icon index
        if byIndex[idx] and byIndex[idx] ~= guid then return end

        if not found[guid] then
            byIndex[idx] = guid
            found[guid] = {
                unit  = unit,
                index = idx,
                guid  = guid,
                name  = UnitName(unit),
            }
        elseif not found[guid].name then
            found[guid].name = UnitName(unit)
        end
    end

    -- Player's target and focus (stable, highest priority)
    Check("target")
    Check("focus")

    -- Party/raid members (stable tokens)
    for i = 1, 4 do
        Check("party" .. i)
    end
    for i = 1, 40 do
        Check("raid" .. i)
    end

    -- Party/raid member targets (not stable, but useful for discovery)
    for i = 1, 4 do
        Check("party" .. i .. "target")
        Check("partypet" .. i)
        Check("partypet" .. i .. "target")
    end
    for i = 1, 40 do
        Check("raid" .. i .. "target")
    end

    -- Nameplates (not stable, but discover units nobody is targeting)
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = C_NamePlate.GetNamePlates()
        if plates then
            for _, plate in ipairs(plates) do
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
-- Glow helpers
-- =========================================================

local function SetGlowActive(entry, active)
    entry.glowActive = active
    if active then
        for _, tex in ipairs(entry.glow) do tex:Show() end
    else
        for _, tex in ipairs(entry.glow) do tex:Hide() end
    end
end

-- Per-frame animation for smooth glow pulsing
local glowAnimFrame = CreateFrame("Frame")
glowAnimFrame:SetScript("OnUpdate", function()
    local now = GetTime()
    local alpha = PulseAlpha(now, GLOW_PULSE_HZ, GLOW_PULSE_MIN, GLOW_PULSE_MAX)
    for i = 1, 8 do
        local entry = entries[i]
        if entry.glowActive then
            for _, tex in ipairs(entry.glow) do tex:SetAlpha(alpha) end
        end
    end
end)

-- =========================================================
-- Display update
-- =========================================================

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
    local targetGUID = UnitExists("target") and UnitGUID("target") or nil

    local staleEntries = {}

    for i = 1, 8 do
        local entry = entries[i]
        local info = sorted[i]

        if info then
            local unit = info.unit

            -- Store token for tooltip
            entry.unitToken = unit

            -- Store targeting data for PreClick handler
            entry.targetGuid  = info.guid
            entry.raidIndex   = info.index
            entry.targetName  = info.name
            entry.stale       = false

            -- Portrait
            SetPortraitTexture(entry.portrait, unit)
            entry.portrait:SetDesaturated(false)
            entry.portrait:SetAlpha(1.0)

            -- Raid icon texture
            entry.raidIcon:SetTexture(
                "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. info.index)
            entry.raidIcon:SetAlpha(1.0)
            entry.raidIcon:Show()

            -- Name (colored by reaction)
            local name = info.name or "?"
            local r, g, b
            if UnitIsEnemy("player", unit) then
                r, g, b = 0.90, 0.20, 0.20
            elseif UnitIsFriend("player", unit) then
                r, g, b = 0.30, 0.80, 0.30
            else
                r, g, b = 0.95, 0.95, 0.15
            end
            entry.nameText:SetText(name)
            entry.nameText:SetTextColor(r, g, b)

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

            -- Target glow: highlight if this is the player's current target
            local isTarget = targetGUID and info.guid == targetGUID
            SetGlowActive(entry, isTarget)

            -- Position within frame (active entries first)
            entry:ClearAllPoints()
            entry:SetPoint("TOPLEFT", frame, "TOPLEFT",
                           PAD, -(PAD + (i - 1) * (ENTRY_H + ENTRY_GAP)))

            if not inCombat then
                entry:Show()
            end
        else
            entry.unitToken    = nil
            entry.targetGuid   = nil
            entry.raidIndex    = nil
            entry.targetName   = nil
            entry.stale        = true
            SetGlowActive(entry, false)
            if not inCombat then
                entry:Hide()
            else
                -- Can't hide secure buttons in combat; collect for bottom placement
                staleEntries[#staleEntries + 1] = entry
                entry.portrait:SetDesaturated(true)
                entry.portrait:SetAlpha(0.35)
                entry.nameText:SetTextColor(0.5, 0.5, 0.5)
                entry.healthBar:SetStatusBarColor(0.3, 0.3, 0.3)
                entry.healthText:SetText("")
                entry.raidIcon:SetAlpha(0.35)
            end
        end
    end

    -- Reposition stale entries below all active entries
    for s = 1, #staleEntries do
        local entry = staleEntries[s]
        local row = count + s - 1
        entry:ClearAllPoints()
        entry:SetPoint("TOPLEFT", frame, "TOPLEFT",
                       PAD, -(PAD + row * (ENTRY_H + ENTRY_GAP)))
    end

    -- Resize and show/hide frame (include stale entries in height during combat)
    local visibleCount = count + #staleEntries
    if visibleCount > 0 then
        placeholderText:Hide()
        local totalH = PAD * 2 + visibleCount * ENTRY_H
                       + math.max(0, visibleCount - 1) * ENTRY_GAP
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

-- =========================================================
-- Polling
-- =========================================================

local pollFrame = ExsarUI.CreatePoller(nil, 0.3, UpdateDisplay)
pollFrame:Hide()

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestoreTopleftPosition(self, rDB, tlState)
        C_locked = rDB().locked and true or false
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
    tlState.x = DEFAULT_X
    tlState.y = DEFAULT_Y
    ReAnchor()
    rDB().x = nil
    rDB().y = nil
    print(ADDON_NAME .. ": Raid target widget position reset.")
end)

ExsarAddon.AddSlashCommand("rtdebug", function()
    local nowOn = not IsDebugEnabled()
    rDB().debugClicks = nowOn
    print(ADDON_NAME .. ": Raid target click debug logging " .. (nowOn and "ON" or "OFF"))
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Raid Target Widget",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, rDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, rDB, frame, function(v)
            C_locked = v
            UpdateDisplay()
        end)

        y = ExsarUI.AddTopleftResetButton(parent, y, rDB, tlState, "Raid target", DEFAULT_X, DEFAULT_Y)

        return y
    end,
})
