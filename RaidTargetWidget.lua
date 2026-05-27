-- RaidTargetWidget module
-- A tank/assist roster: a vertical list of tracked group members (auto-detected
-- tanks plus any manually named members), one per row. Each row shows the
-- member (class-colored name + portrait), the raid mark on whatever they are
-- currently targeting, that target's name, and the target's health. Click a row
-- to ASSIST that member (target whatever they are on, resolved live).
--
-- Why assist-only (the icon-targeting mechanism was removed): you cannot target
-- an arbitrary marked mob from a secure button in combat. Targeting is a
-- protected action, so in combat the unit must come from a value baked into the
-- button BEFORE combat -- either a literal constant or a token the game's own
-- secure engine re-resolves (e.g. "raid3target"). An addon-computed "whoever is
-- on the square right now" choice is exactly what combat forbids, and WoW has no
-- macro conditional for "the unit wearing raid mark N". The only combat-stable
-- handle is therefore a STABLE referent: a person who reliably stays on their
-- mob (a tank). So the widget assists people, not marks.
--
-- Each button is a SecureUnitButtonTemplate with type1=target and a `unit`
-- attribute (e.g. "raid3target") written AHEAD of time, out of combat, via
-- ExsarUI.SecureSetAttribute (deferred under lockdown). The secure engine
-- resolves that token live on every click, so the button tracks the member's
-- current target with no combat-time rewrite. Roster reshuffles (a member moving
-- between groups, changing their raidN index) are handled by re-resolving each
-- tracked member from the roster by name and rebinding -- out of combat, where
-- SecureSetAttribute is allowed.
--
-- Settings stored under ExsarAddonDB.raidTargets.

local ADDON_NAME = "ExsarAddon"

local rDB = ExsarUI.MakeDB("raidTargets")

local DEFAULT_X, DEFAULT_Y = 350, 175
local C_locked   = false

-- =========================================================
-- Layout constants
-- =========================================================

local FRAME_W      = 200
local PAD          = 5
local ROW_H        = 34
local ROW_GAP      = 2
local PORT_SIZE    = 28
local BAR_H        = 5
local MARK_SIZE    = 14
local MAX_ROWS     = 12   -- secure-button pool size

local PLACEHOLDER_H = 30

-- Highlight the row whose tracked member is on the player's current target
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

local RT_ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

local rows  -- forward decl (button pool)

local function ManualNameSet()
    return ExsarLogic.ParseNameSet(rDB().manualTanks)
end

-- =========================================================
-- Roster
-- =========================================================

-- Gather the current group as roster entries. `unit` is the assist token
-- (member's target, e.g. "raid3target"); `playerUnit` is the member unit itself
-- (used for portrait / class color). The player is excluded -- assisting
-- yourself targets your own target, a no-op.
local function GatherRoster()
    local roster = {}
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
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "RaidTargetFrame", UIParent)
frame:SetSize(FRAME_W, 50)
local tlState = ExsarUI.SetupTopleftFrame(frame, rDB, DEFAULT_X, DEFAULT_Y)
local ReAnchor = tlState.ReAnchor
frame:Hide()

local placeholderText = ExsarUI.CreatePlaceholder(frame, "Tank / Assist")

-- =========================================================
-- Assist row pool
-- =========================================================

rows = {}

local function CreateRow(index)
    local btn = CreateFrame("Button", ADDON_NAME .. "RaidAssistRow" .. index,
                            frame, "SecureUnitButtonTemplate")
    btn:SetSize(FRAME_W - PAD * 2, ROW_H)
    btn:RegisterForClicks("AnyUp", "AnyDown")
    btn:SetAttribute("type1", "target")

    btn.boundUnit   = nil
    btn.memberName  = nil

    local hoverBg = btn:CreateTexture(nil, "BACKGROUND")
    hoverBg:SetAllPoints()
    hoverBg:SetColorTexture(0.3, 0.3, 0.3, 0.3)
    hoverBg:Hide()

    btn:HookScript("OnEnter", function()
        hoverBg:Show()
        if btn.boundUnit and UnitExists(btn.boundUnit) then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:AddLine((btn.memberName or "Member") .. " is on:")
            GameTooltip:SetUnit(btn.boundUnit)
            GameTooltip:Show()
        elseif btn.memberName then
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:AddLine(btn.memberName)
            GameTooltip:AddLine("(no target)", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end
    end)
    btn:HookScript("OnLeave", function()
        hoverBg:Hide()
        GameTooltip:Hide()
    end)

    -- Member portrait (left)
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

    -- Top line: class-colored member name
    local memberText = btn:CreateFontString(nil, "OVERLAY")
    memberText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    memberText:SetPoint("TOPLEFT", portRing, "TOPRIGHT", 4, -1)
    memberText:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    memberText:SetJustifyH("LEFT")
    memberText:SetWordWrap(false)

    -- Second line: target's raid mark + target name
    local markIcon = btn:CreateTexture(nil, "OVERLAY")
    markIcon:SetSize(MARK_SIZE, MARK_SIZE)
    markIcon:SetPoint("TOPLEFT", portRing, "TOPRIGHT", 4, -15)

    local targetText = btn:CreateFontString(nil, "OVERLAY")
    targetText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    targetText:SetPoint("LEFT", markIcon, "RIGHT", 3, 0)
    targetText:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
    targetText:SetJustifyH("LEFT")
    targetText:SetWordWrap(false)

    -- Bottom edge: target health bar (what you would assist onto)
    local barBg = btn:CreateTexture(nil, "ARTWORK")
    barBg:SetHeight(BAR_H)
    barBg:SetPoint("BOTTOMLEFT", portRing, "BOTTOMRIGHT", 4, 0)
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
    btn.memberText = memberText
    btn.markIcon   = markIcon
    btn.targetText = targetText
    btn.healthBar  = healthBar
    btn.barBg      = barBg
    btn.healthText = healthText
    btn:Hide()

    return btn
end

for i = 1, MAX_ROWS do
    rows[i] = CreateRow(i)
end

-- =========================================================
-- Glow pulse
-- =========================================================

local function SetGlowActive(row, active)
    row.glowActive = active
    for _, tex in ipairs(row.glow) do
        if active then tex:Show() else tex:Hide() end
    end
end

local glowAnimFrame = CreateFrame("Frame")
glowAnimFrame:SetScript("OnUpdate", function()
    local now = GetTime()
    local alpha = PulseAlpha(now, GLOW_PULSE_HZ, GLOW_PULSE_MIN, GLOW_PULSE_MAX)
    for i = 1, MAX_ROWS do
        local row = rows[i]
        if row.glowActive then
            for _, tex in ipairs(row.glow) do tex:SetAlpha(alpha) end
        end
    end
end)

-- =========================================================
-- Layout
-- =========================================================

local function Layout(count)
    if InCombatLockdown() then return end  -- moving secure buttons is blocked in combat

    for i = 1, count do
        local row = rows[i]
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(PAD + (i - 1) * (ROW_H + ROW_GAP)))
    end

    if count > 0 then
        placeholderText:Hide()
        local totalH = PAD * 2 + count * ROW_H + (count - 1) * ROW_GAP
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

-- =========================================================
-- Display update
-- =========================================================

local function UpdateDisplay()
    local list = ExsarLogic.ComputeAssistList(GatherRoster(), ManualNameSet())
    local inCombat = InCombatLockdown()
    local targetGUID = UnitExists("target") and UnitGUID("target") or nil
    local count = math.min(#list, MAX_ROWS)

    for i = 1, MAX_ROWS do
        local row = rows[i]
        local m = list[i]
        if m and i <= count then
            row.memberName = m.name

            -- Bind the secure click to assist this member (live token). Written
            -- out of combat; deferred (frozen) in combat by SecureSetAttribute.
            if row.boundUnit ~= m.unit then
                ExsarUI.SecureSetAttribute(row, "unit", m.unit)
                row.boundUnit = m.unit
            end

            -- Member portrait + class-colored name
            local short = m.name and m.name:match("^[^%-]+") or m.name or "?"
            local r, g, b = 0.8, 0.8, 0.8
            if m.playerUnit and UnitExists(m.playerUnit) then
                SetPortraitTexture(row.portrait, m.playerUnit)
                local _, classFile = UnitClass(m.playerUnit)
                local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                if c then r, g, b = c.r, c.g, c.b end
            end
            local offline = not m.online
            row.memberText:SetText(short)
            row.memberText:SetTextColor(r, g, b)
            row.portrait:SetDesaturated(offline)
            row.memberText:SetAlpha(offline and 0.4 or 1.0)

            -- Member's current target: mark, name, health
            local tunit = m.unit
            if tunit and UnitExists(tunit) then
                local mark = GetRaidTargetIndex(tunit)
                if mark then
                    row.markIcon:SetTexture(RT_ICON_TEXTURE .. mark)
                    row.markIcon:Show()
                else
                    row.markIcon:Hide()
                end

                local tname = UnitName(tunit) or "?"
                local tr, tg, tb
                if UnitIsEnemy("player", tunit) then tr, tg, tb = 0.95, 0.35, 0.35
                elseif UnitIsFriend("player", tunit) then tr, tg, tb = 0.45, 0.85, 0.45
                else tr, tg, tb = 0.95, 0.95, 0.35 end
                row.targetText:SetText(tname)
                row.targetText:SetTextColor(tr, tg, tb)

                local hp, hpMax = UnitHealth(tunit), UnitHealthMax(tunit)
                if hpMax > 0 then
                    row.healthBar:SetMinMaxValues(0, hpMax)
                    row.healthBar:SetValue(hp)
                    local pct = math.floor(hp / hpMax * 100 + 0.5)
                    row.healthText:SetText(pct .. "%")
                    row.healthBar:SetStatusBarColor(HealthColor(pct))
                else
                    row.healthBar:SetMinMaxValues(0, 1)
                    row.healthBar:SetValue(0)
                    row.healthText:SetText("")
                end
                row.healthBar:Show(); row.barBg:Show()

                SetGlowActive(row, targetGUID and UnitGUID(tunit) == targetGUID and true or false)
            else
                row.markIcon:Hide()
                row.targetText:SetText("(no target)")
                row.targetText:SetTextColor(0.6, 0.6, 0.6)
                row.healthBar:Hide(); row.barBg:Hide()
                row.healthText:SetText("")
                SetGlowActive(row, false)
            end

            if not inCombat then row:Show() end
        else
            row.memberName = nil
            SetGlowActive(row, false)
            if not inCombat then row:Hide() end
        end
    end

    Layout(count)
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

        y = ExsarUI.AddMacroEditBox(parent, y, "Extra members to track (added to auto tanks) — comma/space/newline separated",
            function() return rDB().manualTanks or "" end,
            function(v)
                rDB().manualTanks = (v and v:match("%S")) and v or nil
                UpdateDisplay()
            end)

        y = ExsarUI.AddTopleftResetButton(parent, y, rDB, tlState, "Raid target", DEFAULT_X, DEFAULT_Y)

        return y
    end,
})
