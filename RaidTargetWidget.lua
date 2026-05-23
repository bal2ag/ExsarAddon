-- RaidTargetWidget module
-- Shows compact info for all units marked with raid target icons, plus a row of
-- tank-assist buttons. Click an icon row to target that mob; click a tank
-- button to assist that tank (target whatever they are tanking, live).
--
-- Targeting uses the secure "static binding, live token" pattern: each button
-- is a SecureUnitButtonTemplate with type1=target and a `unit` attribute set
-- AHEAD of time (out of combat, via ExsarUI.SecureSetAttribute). The secure
-- engine resolves that token (e.g. "raid3target") live on every click, so the
-- button tracks that unit's current target without needing a combat-time
-- rewrite -- which is forbidden under lockdown. This is why the old approach
-- (deciding the macro inside PreClick and SetAttribute-ing it) could never work
-- in combat; we no longer touch attributes at click time.
--
-- The hard limit remains: a binding cannot be changed in combat. So a mark that
-- is RE-marked onto a different mob mid-combat leaves its icon button frozen on
-- the old GUID; we detect that (ExsarLogic.DetectStaleIcons) and grey the button
-- with a red X so the user falls back to the tank row, which is re-mark-proof
-- because it follows the tank, not the icon.
--
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

local TANK_SIZE      = 30
local TANK_GAP       = 4
local TANKS_PER_ROW  = 3
local SECTION_GAP    = 8
local MAX_TANKS      = 12  -- secure-button pool size for the tank row

local PLACEHOLDER_H = 30

-- Target glow: highlights the entry matching the player's current target
local GLOW_COLOR    = { 1.0, 0.82, 0.25, 0.85 }
local GLOW_SIZE     = 3
local GLOW_PULSE_HZ  = 1.2
local GLOW_PULSE_MIN = 0.45
local GLOW_PULSE_MAX = 1.0

-- Forward declarations so helpers defined early can close over tables created
-- further down the file.
local entries
local tankButtons

-- =========================================================
-- Helpers
-- =========================================================

local HealthColor  = ExsarLogic.HealthColorGradient
local PulseAlpha   = ExsarLogic.PulseAlpha

local RT_ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

local function ShowTanks()
    return rDB().showTanks ~= false  -- default ON
end

local function ManualTankSet()
    return ExsarLogic.ParseNameSet(rDB().manualTanks)
end

-- Find a group-member target token (raidNtarget / partyNtarget) that currently
-- points at the given GUID. Such tokens are resolved live by the secure engine
-- at click time and stay valid in combat, so they make the most robust binding.
-- Returns the token string, or nil when no member is on the mob.
local function ResolveMemberTargetToken(guid)
    if not guid then return nil end
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
    return nil
end

-- Find the nameplate token currently showing the given GUID (fallback binding
-- for mobs nobody is targeting; reliable out of combat, may go stale in combat).
local function ResolveNameplateToken(guid)
    if not guid or not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
    local plates = C_NamePlate.GetNamePlates()
    if not plates then return nil end
    for _, plate in ipairs(plates) do
        local t = plate.namePlateUnitToken
        if not t and UnitTokenFromNamePlate then t = UnitTokenFromNamePlate(plate) end
        if t and UnitExists(t) and UnitGUID(t) == guid then return t end
    end
    return nil
end

-- =========================================================
-- Tank roster
-- =========================================================

-- Gather the current group as roster entries the tank picker understands.
-- `unit` is the assist token (member's target); `playerUnit` is the member
-- unit itself (used for class color / connection). The player is excluded --
-- assisting yourself targets your own target, which is a no-op.
local function GatherRoster()
    local roster = {}
    -- A member is a tank if the group has flagged them Tank role
    -- (UnitGroupRolesAssigned, the primary signal), or as a fallback if they
    -- carry a Main Tank assignment.
    local function isTank(unit, rosterRole)
        if UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) == "TANK" then return true end
        if rosterRole == "MAINTANK" then return true end
        if GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) then return true end
        return false
    end

    if IsInRaid() then
        local n = GetNumGroupMembers()
        for i = 1, n do
            local name, _, _, _, _, _, _, online, _, role = GetRaidRosterInfo(i)
            local unit = "raid" .. i
            if name and not UnitIsUnit(unit, "player") then
                roster[#roster + 1] = {
                    name       = name,
                    role       = isTank(unit, role) and "TANK" or nil,
                    unit       = unit .. "target",
                    playerUnit = unit,
                    online     = online ~= false,
                }
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                roster[#roster + 1] = {
                    name       = UnitName(unit),
                    role       = isTank(unit, nil) and "TANK" or nil,
                    unit       = unit .. "target",
                    playerUnit = unit,
                    online     = UnitIsConnected(unit) ~= false,
                }
            end
        end
    end
    return roster
end

-- =========================================================
-- Click outcome diagnostics (failure-only, persistent log)
-- =========================================================

local RT_ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
local CLICK_LOG_CAP = 20

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

local function SnapshotAllMarks()
    local out = {}
    for i = 1, 8 do
        local e = entries[i]
        if e and e.targetGuid then
            out[#out + 1] = { idx = e.raidIndex, name = e.targetName, guid = e.targetGuid, token = e.boundUnit }
        end
    end
    return out
end

local function FormatClickMiss(dbg, prefix)
    local p = prefix or ""
    local lines = {}
    lines[#lines + 1] = p .. "CLICK MISSED @" .. (dbg.timeStr or "?")
          .. " kind=" .. tostring(dbg.kind)
          .. " grp=" .. tostring(dbg.groupKind) .. "/" .. tostring(dbg.groupSize or 0)
          .. " combat=" .. (dbg.combat and "Y" or "N")
          .. " stale=" .. (dbg.stale and "Y" or "N")
          .. " lag=" .. tostring(dbg.latency or "?") .. "ms"
    lines[#lines + 1] = p .. "  intended: icon=" .. FormatIcon(dbg.intendedIdx)
          .. " name=\"" .. (dbg.intendedName or "?") .. "\""
          .. " guid=" .. ShortGuid(dbg.intendedGuid)
    lines[#lines + 1] = p .. "  binding: unit=" .. tostring(dbg.boundUnit or "<none>")
          .. " liveGuid=" .. ShortGuid(dbg.liveGuid)
    lines[#lines + 1] = p .. "  before: name=\"" .. (dbg.oldName or "none") .. "\""
          .. " guid=" .. ShortGuid(dbg.oldGuid) .. " icon=" .. FormatIcon(dbg.oldIdx)
    lines[#lines + 1] = p .. "  after:  name=\"" .. (dbg.newName or "none") .. "\""
          .. " guid=" .. ShortGuid(dbg.newGuid) .. " icon=" .. FormatIcon(dbg.newIdx)
    if dbg.allMarks and #dbg.allMarks > 0 then
        local parts = {}
        for _, m in ipairs(dbg.allMarks) do
            parts[#parts + 1] = FormatIcon(m.idx) .. "=" .. (m.name or "?")
                  .. "(" .. ShortGuid(m.guid) .. "," .. tostring(m.token or "?") .. ")"
        end
        lines[#lines + 1] = p .. "  marks: " .. table.concat(parts, " | ")
    end
    return lines
end

local function LogClickMiss(dbg)
    local p = "|cffff8800[ExsarRTW]|r "
    for _, line in ipairs(FormatClickMiss(dbg, p)) do print(line) end
end

local function PersistMiss(dbg)
    local db = rDB()
    local log = db.clickMissLog or {}
    log[#log + 1] = dbg
    while #log > CLICK_LOG_CAP do table.remove(log, 1) end
    db.clickMissLog = log
end

local function CheckClickOutcome(dbg)
    if not dbg or not dbg.intendedGuid then return end
    dbg.newGuid = UnitExists("target") and UnitGUID("target") or nil
    dbg.newName = UnitExists("target") and UnitName("target") or nil
    dbg.newIdx  = UnitExists("target") and GetRaidTargetIndex("target") or nil
    if dbg.newGuid == dbg.intendedGuid then return end  -- success
    if not IsDebugEnabled() then return end
    dbg.allMarks = SnapshotAllMarks()
    PersistMiss(dbg)
    LogClickMiss(dbg)
end

-- Shared PreClick: snapshot intent + current target for failure diagnostics.
-- No SetAttribute here -- the binding is already in place.
local function SecurePreClick(self)
    local boundUnit = self:GetAttribute("unit")
    -- For an icon entry the intended GUID is the marked mob; for a tank button
    -- the intent is "whatever the tank is on right now".
    local intendedGuid = self.targetGuid
    if not intendedGuid and boundUnit and UnitExists(boundUnit) then
        intendedGuid = UnitGUID(boundUnit)
    end
    local latency
    pcall(function()
        local _, _, h, w = GetNetStats()
        latency = w or h
    end)
    local groupKind = IsInRaid() and "raid" or (IsInGroup() and "party" or "solo")
    self.lastClickDbg = {
        timeStr      = date("%H:%M:%S"),
        kind         = self.tankButton and "tank" or "icon",
        combat       = InCombatLockdown() and true or false,
        stale        = self.isStale and true or false,
        groupKind    = groupKind,
        groupSize    = GetNumGroupMembers and GetNumGroupMembers() or 0,
        latency      = latency,
        boundUnit    = boundUnit,
        liveGuid     = boundUnit and UnitExists(boundUnit) and UnitGUID(boundUnit) or nil,
        intendedGuid = intendedGuid,
        intendedName = self.targetName or (boundUnit and UnitExists(boundUnit) and UnitName(boundUnit)) or nil,
        intendedIdx  = self.raidIndex,
        oldGuid = UnitExists("target") and UnitGUID("target") or nil,
        oldName = UnitExists("target") and UnitName("target") or nil,
        oldIdx  = UnitExists("target") and GetRaidTargetIndex("target") or nil,
    }
end

local function SecurePostClick(self)
    local dbg = self.lastClickDbg
    self.lastClickDbg = nil
    if not dbg or not dbg.intendedGuid then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function() CheckClickOutcome(dbg) end)
    end
end

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "RaidTargetFrame", UIParent)
frame:SetSize(FRAME_W, 50)
local tlState = ExsarUI.SetupTopleftFrame(frame, rDB, DEFAULT_X, DEFAULT_Y)
local ReAnchor = tlState.ReAnchor
frame:Hide()

local placeholderText = ExsarUI.CreatePlaceholder(frame, "Raid Targets")

-- =========================================================
-- Icon entry pool (max 8, one per possible raid icon)
-- =========================================================

entries = {}

local function CreateEntry(index)
    local btn = CreateFrame("Button", ADDON_NAME .. "RaidTarget" .. index,
                            frame, "SecureUnitButtonTemplate")
    btn:SetSize(FRAME_W - PAD * 2, ENTRY_H)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type1", "target")

    btn:SetScript("PreClick", SecurePreClick)
    btn:SetScript("PostClick", SecurePostClick)

    btn.targetGuid = nil
    btn.targetName = nil
    btn.raidIndex  = nil
    btn.boundUnit  = nil
    btn.isStale    = false

    local hoverBg = btn:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(0.3, 0.3, 0.3, 0.3)
    hoverBg:Hide()

    btn:HookScript("OnEnter", function()
        hoverBg:Show()
        if btn.boundUnit and UnitExists(btn.boundUnit) then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetUnit(btn.boundUnit)
            GameTooltip:Show()
        end
    end)
    btn:HookScript("OnLeave", function()
        hoverBg:Hide()
        GameTooltip:Hide()
    end)

    local portRing = btn:CreateTexture(nil, "BORDER")
    portRing:SetSize(PORT_SIZE + 2, PORT_SIZE + 2)
    portRing:SetPoint("LEFT", btn, "LEFT", 1, 0)
    portRing:SetColorTexture(0.45, 0.45, 0.45, 0.85)

    local portFill = btn:CreateTexture(nil, "BORDER")
    portFill:SetSize(PORT_SIZE, PORT_SIZE)
    portFill:SetPoint("CENTER", portRing, "CENTER", 0, 0)
    portFill:SetColorTexture(0, 0, 0, 1)

    local portrait = btn:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(PORT_SIZE, PORT_SIZE)
    portrait:SetPoint("CENTER", portRing, "CENTER", 0, 0)
    pcall(function() portrait:SetMask("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask") end)

    local raidIcon = btn:CreateTexture(nil, "OVERLAY")
    raidIcon:SetSize(RT_ICON_SIZE, RT_ICON_SIZE)
    raidIcon:SetPoint("TOP", portrait, "TOP", 0, RT_ICON_SIZE * 0.45)

    local nameText = btn:CreateFontString(nil, "OVERLAY")
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    nameText:SetPoint("TOPLEFT", portRing, "TOPRIGHT", 4, -2)
    nameText:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)

    local barBg = btn:CreateTexture(nil, "ARTWORK")
    barBg:SetHeight(BAR_H)
    barBg:SetPoint("TOPLEFT", portRing, "TOPRIGHT", 4, -16)
    barBg:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    barBg:SetColorTexture(0.15, 0.15, 0.15, 0.9)

    local healthBar = CreateFrame("StatusBar", nil, btn)
    healthBar:SetHeight(BAR_H)
    healthBar:SetPoint("TOPLEFT", barBg, "TOPLEFT", 0, 0)
    healthBar:SetPoint("BOTTOMRIGHT", barBg, "BOTTOMRIGHT", 0, 0)
    healthBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    healthBar:SetStatusBarColor(0.1, 0.9, 0.1)
    healthBar:SetMinMaxValues(0, 1)

    local healthText = healthBar:CreateFontString(nil, "OVERLAY")
    healthText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    healthText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)

    -- Stale marker: red X shown when the mark was re-marked in combat and the
    -- (frozen) binding can no longer be trusted.
    local sx1, sx2 = ExsarUI.CreateRedX(btn, 2, 2)
    local staleX = { sx1, sx2 }
    for _, line in ipairs(staleX) do line:Hide() end

    -- Target glow (4 edge textures forming a border)
    local glow = {}
    local gr, gg, gb, ga = unpack(GLOW_COLOR)
    glow[1] = btn:CreateTexture(nil, "BACKGROUND"); glow[1]:SetColorTexture(gr, gg, gb, ga)
    glow[1]:SetPoint("TOPLEFT", btn, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
    glow[1]:SetPoint("TOPRIGHT", btn, "TOPRIGHT", GLOW_SIZE, GLOW_SIZE); glow[1]:SetHeight(GLOW_SIZE)
    glow[2] = btn:CreateTexture(nil, "BACKGROUND"); glow[2]:SetColorTexture(gr, gg, gb, ga)
    glow[2]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -GLOW_SIZE, -GLOW_SIZE)
    glow[2]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE); glow[2]:SetHeight(GLOW_SIZE)
    glow[3] = btn:CreateTexture(nil, "BACKGROUND"); glow[3]:SetColorTexture(gr, gg, gb, ga)
    glow[3]:SetPoint("TOPLEFT", btn, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
    glow[3]:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", -GLOW_SIZE, -GLOW_SIZE); glow[3]:SetWidth(GLOW_SIZE)
    glow[4] = btn:CreateTexture(nil, "BACKGROUND"); glow[4]:SetColorTexture(gr, gg, gb, ga)
    glow[4]:SetPoint("TOPRIGHT", btn, "TOPRIGHT", GLOW_SIZE, GLOW_SIZE)
    glow[4]:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE); glow[4]:SetWidth(GLOW_SIZE)
    for _, tex in ipairs(glow) do tex:Hide() end

    btn.glow       = glow
    btn.glowActive = false
    btn.portrait   = portrait
    btn.raidIcon   = raidIcon
    btn.nameText   = nameText
    btn.healthBar  = healthBar
    btn.healthText = healthText
    btn.staleX     = staleX
    btn:Hide()

    return btn
end

for i = 1, 8 do
    entries[i] = CreateEntry(i)
end

-- =========================================================
-- Tank-assist button pool
-- =========================================================

tankButtons = {}

local function CreateTankButton(index)
    local btn = CreateFrame("Button", ADDON_NAME .. "RaidTankBtn" .. index,
                            frame, "SecureUnitButtonTemplate")
    btn:SetSize(TANK_SIZE, TANK_SIZE)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type1", "target")
    btn.tankButton = true

    btn:SetScript("PreClick", SecurePreClick)
    btn:SetScript("PostClick", SecurePostClick)

    btn.boundUnit = nil
    btn.tankName  = nil

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.85)

    -- Large center icon = the tank's current target's raid mark (so the button
    -- reads as "this is the skull tank"). Blank when their target is unmarked.
    local markIcon = btn:CreateTexture(nil, "ARTWORK")
    markIcon:SetSize(TANK_SIZE - 8, TANK_SIZE - 8)
    markIcon:SetPoint("TOP", btn, "TOP", 0, -1)

    -- Class-colored tank name along the bottom edge.
    local nameText = btn:CreateFontString(nil, "OVERLAY")
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    nameText:SetPoint("BOTTOM", btn, "BOTTOM", 0, 1)
    nameText:SetWidth(TANK_SIZE)
    nameText:SetJustifyH("CENTER")
    nameText:SetWordWrap(false)

    local border = ExsarUI.CreateGlow(btn, 0.5, 0.5, 0.5, 0.9, 1, "BORDER")
    btn.border = border

    btn:HookScript("OnEnter", function()
        if btn.boundUnit and UnitExists(btn.boundUnit) then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:AddLine((btn.tankName or "Tank") .. " is on:")
            GameTooltip:SetUnit(btn.boundUnit)
            GameTooltip:Show()
        elseif btn.tankName then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(btn.tankName)
            GameTooltip:AddLine("(no target)", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    btn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    btn.markIcon = markIcon
    btn.nameText = nameText
    btn:Hide()
    return btn
end

for i = 1, MAX_TANKS do
    tankButtons[i] = CreateTankButton(i)
end

-- =========================================================
-- Unit scanning (unchanged: discover every marked, attackable unit)
-- =========================================================

local function ScanMarkedUnits()
    local found = {}
    local byIndex = {}

    local function Check(unit)
        if not UnitExists(unit) then return end
        if not UnitCanAttack("player", unit) then return end
        local idx = GetRaidTargetIndex(unit)
        if not idx then return end
        local guid = UnitGUID(unit)
        if not guid then return end
        if byIndex[idx] and byIndex[idx] ~= guid then return end
        if not found[guid] then
            byIndex[idx] = guid
            found[guid] = { unit = unit, index = idx, guid = guid, name = UnitName(unit) }
        elseif not found[guid].name then
            found[guid].name = UnitName(unit)
        end
    end

    Check("target")
    Check("focus")
    for i = 1, 4 do Check("party" .. i) end
    for i = 1, 40 do Check("raid" .. i) end
    for i = 1, 4 do
        Check("party" .. i .. "target")
        Check("partypet" .. i)
        Check("partypet" .. i .. "target")
    end
    for i = 1, 40 do Check("raid" .. i .. "target") end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = C_NamePlate.GetNamePlates()
        if plates then
            for _, plate in ipairs(plates) do
                local unit = plate.namePlateUnitToken
                if not unit and UnitTokenFromNamePlate then unit = UnitTokenFromNamePlate(plate) end
                if unit then Check(unit) end
            end
        end
    end
    for i = 1, 5 do Check("boss" .. i) end
    return found
end

-- =========================================================
-- Glow pulse
-- =========================================================

local function SetGlowActive(entry, active)
    entry.glowActive = active
    for _, tex in ipairs(entry.glow) do
        if active then tex:Show() else tex:Hide() end
    end
end

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
-- Binding baseline (for in-combat stale detection)
-- =========================================================

local boundBaseline = {}  -- iconIndex -> guid, captured when bindings last written

-- =========================================================
-- Tank row display
-- =========================================================

-- Returns the number of visible tank buttons (for layout).
local function UpdateTankRow(inCombat)
    if not ShowTanks() then
        if not inCombat then
            for i = 1, MAX_TANKS do tankButtons[i]:Hide() end
        end
        return 0
    end

    local tanks = ExsarLogic.ComputeTankList(GatherRoster(), ManualTankSet())
    local shown = math.min(#tanks, MAX_TANKS)

    for i = 1, MAX_TANKS do
        local btn = tankButtons[i]
        local tank = tanks[i]
        if tank and i <= shown then
            btn.tankName = tank.name
            -- Bind the secure click to assist this tank (live token).
            if btn.boundUnit ~= tank.unit then
                ExsarUI.SecureSetAttribute(btn, "unit", tank.unit)
                btn.boundUnit = tank.unit
            end
            -- Name (class colored)
            local short = tank.name and tank.name:match("^[^%-]+") or tank.name or "?"
            if #short > 6 then short = short:sub(1, 6) end
            local r, g, b = 0.8, 0.8, 0.8
            if tank.playerUnit and UnitExists(tank.playerUnit) then
                local _, classFile = UnitClass(tank.playerUnit)
                local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                if c then r, g, b = c.r, c.g, c.b end
            end
            btn.nameText:SetText(short)
            btn.nameText:SetTextColor(r, g, b)
            -- Mark icon = the tank's current target's raid mark
            local mark = tank.unit and UnitExists(tank.unit) and GetRaidTargetIndex(tank.unit)
            if mark then
                btn.markIcon:SetTexture(RT_ICON_TEXTURE .. mark)
                btn.markIcon:Show()
            else
                btn.markIcon:Hide()
            end
            local offline = not tank.online
            btn.markIcon:SetDesaturated(offline)
            btn.nameText:SetAlpha(offline and 0.4 or 1.0)
            if not inCombat then btn:Show() end
        else
            if not inCombat then btn:Hide() end
        end
    end
    return shown
end

-- =========================================================
-- Display update
-- =========================================================

local function Layout(tankCount, iconCount, inCombat)
    if inCombat then return end  -- repositioning secure buttons is blocked in combat

    local tankRows = math.ceil(tankCount / TANKS_PER_ROW)
    local tankAreaH = tankRows > 0 and (tankRows * TANK_SIZE + (tankRows - 1) * TANK_GAP) or 0

    -- Position tank buttons (3 per row), centered under the left pad.
    for i = 1, tankCount do
        local row = math.floor((i - 1) / TANKS_PER_ROW)
        local col = (i - 1) % TANKS_PER_ROW
        local btn = tankButtons[i]
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                     PAD + col * (TANK_SIZE + TANK_GAP),
                     -(PAD + row * (TANK_SIZE + TANK_GAP)))
    end

    local iconStartY = PAD + (tankAreaH > 0 and (tankAreaH + SECTION_GAP) or 0)
    for i = 1, iconCount do
        local entry = entries[i]
        entry:ClearAllPoints()
        entry:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD,
                       -(iconStartY + (i - 1) * (ENTRY_H + ENTRY_GAP)))
    end

    local iconAreaH = iconCount > 0 and (iconCount * ENTRY_H + (iconCount - 1) * ENTRY_GAP) or 0
    local visible = tankCount + iconCount

    if visible > 0 then
        placeholderText:Hide()
        local totalH = iconStartY + iconAreaH + PAD
        if iconAreaH == 0 then totalH = PAD + tankAreaH + PAD end
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
            frame:Hide()
        end
    end
end

local function UpdateDisplay()
    local found = ScanMarkedUnits()

    local sorted = {}
    for _, info in pairs(found) do sorted[#sorted + 1] = info end
    table.sort(sorted, function(a, b) return a.index > b.index end)

    local inCombat = InCombatLockdown()
    local targetGUID = UnitExists("target") and UnitGUID("target") or nil

    -- Current icon -> guid map, and stale detection vs the frozen baseline.
    local currentByIcon = {}
    for _, info in ipairs(sorted) do currentByIcon[info.index] = info.guid end
    local stale = inCombat and ExsarLogic.DetectStaleIcons(boundBaseline, currentByIcon) or {}

    local count = math.min(#sorted, 8)

    for i = 1, 8 do
        local entry = entries[i]
        local info = sorted[i]
        if info and i <= count then
            local unit = info.unit
            entry.targetGuid = info.guid
            entry.raidIndex  = info.index
            entry.targetName = info.name

            -- Bind the secure click: prefer a member-target token (combat-stable,
            -- live), else the mob's nameplate token. Written out of combat;
            -- deferred (and thus frozen) in combat by SecureSetAttribute.
            local bindUnit = ResolveMemberTargetToken(info.guid)
                          or ResolveNameplateToken(info.guid)
            if bindUnit and entry.boundUnit ~= bindUnit then
                ExsarUI.SecureSetAttribute(entry, "unit", bindUnit)
                entry.boundUnit = bindUnit
            end

            local isStale = stale[info.index] and true or false
            entry.isStale = isStale

            SetPortraitTexture(entry.portrait, unit)
            entry.portrait:SetDesaturated(isStale)
            entry.portrait:SetAlpha(isStale and 0.4 or 1.0)
            for _, line in ipairs(entry.staleX) do
                if isStale then line:Show() else line:Hide() end
            end

            entry.raidIcon:SetTexture(RT_ICON_TEXTURE .. info.index)
            entry.raidIcon:SetAlpha(1.0)
            entry.raidIcon:Show()

            local name = info.name or "?"
            local r, g, b
            if UnitIsEnemy("player", unit) then r, g, b = 0.90, 0.20, 0.20
            elseif UnitIsFriend("player", unit) then r, g, b = 0.30, 0.80, 0.30
            else r, g, b = 0.95, 0.95, 0.15 end
            entry.nameText:SetText(name)
            entry.nameText:SetTextColor(r, g, b)

            local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
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

            SetGlowActive(entry, targetGUID and info.guid == targetGUID and true or false)

            if not inCombat then entry:Show() end
        else
            entry.targetGuid = nil
            entry.raidIndex  = nil
            entry.targetName = nil
            entry.isStale    = false
            SetGlowActive(entry, false)
            for _, line in ipairs(entry.staleX) do line:Hide() end
            if not inCombat then entry:Hide() end
        end
    end

    local tankCount = UpdateTankRow(inCombat)

    -- Refresh the stale baseline only out of combat (when bindings are live).
    if not inCombat then
        boundBaseline = {}
        for idx, guid in pairs(currentByIcon) do boundBaseline[idx] = guid end
    end

    Layout(tankCount, count, inCombat)
end

-- =========================================================
-- Polling + events
-- =========================================================

local pollFrame = ExsarUI.CreatePoller(nil, 0.3, UpdateDisplay)
pollFrame:Hide()

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("RAID_TARGET_UPDATE")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestoreTopleftPosition(self, rDB, tlState)
        C_locked = rDB().locked and true or false
        pollFrame:Show()
        UpdateDisplay()
    elseif event == "PLAYER_REGEN_DISABLED" then
        UpdateDisplay()
    else
        UpdateDisplay()
    end
end)

-- =========================================================
-- Slash sub-commands
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

ExsarAddon.AddSlashCommand("rtdump", function()
    local log = rDB().clickMissLog
    if not log or #log == 0 then
        print(ADDON_NAME .. ": no raid-target click misses logged.")
        return
    end
    local lines = {}
    lines[#lines + 1] = ADDON_NAME .. " — " .. #log .. " raid-target click miss(es)"
    lines[#lines + 1] = string.rep("-", 72)
    for i, dbg in ipairs(log) do
        lines[#lines + 1] = "#" .. i
        for _, line in ipairs(FormatClickMiss(dbg, "")) do lines[#lines + 1] = line end
        lines[#lines + 1] = ""
    end
    ExsarUI.ShowCopyableText(table.concat(lines, "\n"),
        { title = "ExsarAddon — Raid Target Click Misses" })
end)

ExsarAddon.AddSlashCommand("rtclear", function()
    rDB().clickMissLog = nil
    print(ADDON_NAME .. ": raid-target click miss log cleared.")
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

        ExsarAddon.CreateCheckbox(parent, "Show tank-assist row", 16, y,
            function() return ShowTanks() end,
            function(v)
                rDB().showTanks = v and true or false
                UpdateDisplay()
            end)
        y = y - 30

        y = ExsarUI.AddMacroEditBox(parent, y, "Manual tanks (names, if no raid Main Tanks set)",
            function() return rDB().manualTanks or "" end,
            function(v)
                rDB().manualTanks = (v and v:match("%S")) and v or nil
                UpdateDisplay()
            end)

        y = ExsarUI.AddTopleftResetButton(parent, y, rDB, tlState, "Raid target", DEFAULT_X, DEFAULT_Y)

        return y
    end,
})
