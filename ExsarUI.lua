-- ExsarUI.lua
-- Shared UI construction helpers for widget modules.
-- Depends on WoW API and ExsarLogic. Loaded after ExsarLogic.lua, before modules.

local ADDON_NAME = "ExsarAddon"

ExsarUI = {}

-- =========================================================
-- DB initialization helper
-- =========================================================

--- Create a lazy-init DB accessor for a module's SavedVariables namespace.
-- Usage: local myDB = ExsarUI.MakeDB("myModule")
-- Then:  myDB().scale  -- reads ExsarAddonDB.myModule.scale
function ExsarUI.MakeDB(namespace)
    return function()
        ExsarAddonDB[namespace] = ExsarAddonDB[namespace] or {}
        return ExsarAddonDB[namespace]
    end
end

-- =========================================================
-- Frame construction helpers
-- =========================================================

--- Set up standard movable widget frame behavior.
-- Adds background, drag handlers, and position save/restore.
-- @param frame     the frame to set up
-- @param dbFunc    the DB accessor function (e.g. from MakeDB)
-- @param opts      optional table: { bgAlpha = 0.6 }
function ExsarUI.SetupMovableFrame(frame, dbFunc, opts)
    opts = opts or {}
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, opts.bgAlpha or 0.6)

    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        dbFunc().x = x
        dbFunc().y = y
    end)

    return bg
end

--- Restore position, scale, and lock state from saved variables.
-- Call from ADDON_LOADED handler.
-- @param frame     the frame
-- @param dbFunc    the DB accessor
-- @param defaultX  default X offset from CENTER
-- @param defaultY  default Y offset from CENTER
function ExsarUI.RestorePosition(frame, dbFunc, defaultX, defaultY)
    local db = dbFunc()
    if db.x and db.y then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", defaultX or 0, defaultY or 0)
    end
    frame:SetScale(db.scale or 1.0)
    frame:EnableMouse(not db.locked)
end

-- =========================================================
-- TOPLEFT-anchored frame helpers (info widgets)
-- =========================================================

--- Power type colour table shared by info widgets.
ExsarUI.POWER_COLORS = {
    [0] = {0.00, 0.44, 0.87},   -- mana
    [1] = {0.78, 0.25, 0.25},   -- rage
    [2] = {1.00, 0.54, 0.00},   -- focus (hunter pets)
    [3] = {1.00, 0.82, 0.00},   -- energy
    [4] = {0.25, 0.75, 0.25},   -- happiness (hunter pet in TBC)
}

--- Set up a TOPLEFT-anchored movable frame.
-- Returns a state table { x, y, ReAnchor } so modules can call
-- state.ReAnchor() after SetSize to keep the top-left fixed.
-- @param frame      the frame to set up
-- @param dbFunc     DB accessor
-- @param defaultX   default TOPLEFT X offset from UIParent CENTER
-- @param defaultY   default TOPLEFT Y offset from UIParent CENTER
-- @param opts       optional table: { bgAlpha = 0.82 }
-- @return state table with .x, .y, .ReAnchor()
function ExsarUI.SetupTopleftFrame(frame, dbFunc, defaultX, defaultY, opts)
    opts = opts or {}
    local state = { x = defaultX, y = defaultY }
    local dragging = false

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)

    function state.ReAnchor()
        if dragging then return end
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "CENTER", state.x, state.y)
    end

    frame:SetScript("OnDragStart", function(self)
        dragging = true
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        dragging = false
        local left = self:GetLeft()
        local top  = self:GetTop()
        if left and top then
            local s = self:GetScale()
            state.x = left - UIParent:GetWidth()  / (2 * s)
            state.y = top  - UIParent:GetHeight() / (2 * s)
            state.ReAnchor()
            dbFunc().x = state.x
            dbFunc().y = state.y
        end
    end)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, opts.bgAlpha or 0.82)

    return state, bg
end

--- Restore TOPLEFT position from saved variables.
-- @param frame     the frame
-- @param dbFunc    DB accessor
-- @param state     state table from SetupTopleftFrame
function ExsarUI.RestoreTopleftPosition(frame, dbFunc, state)
    local db = dbFunc()
    if db.x and db.y then
        state.x = db.x
        state.y = db.y
    end
    state.ReAnchor()
    frame:SetScale(db.scale or 1.0)
    frame:EnableMouse(not db.locked)
end

--- Add a reset button for TOPLEFT-anchored frames.
-- @return new y offset
function ExsarUI.AddTopleftResetButton(parent, y, dbFunc, state, name, defaultX, defaultY)
    ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
        state.x = defaultX
        state.y = defaultY
        state.ReAnchor()
        dbFunc().x = nil
        dbFunc().y = nil
        print(ADDON_NAME .. ": " .. name .. " position reset.")
    end)
    return y - 30
end

-- =========================================================
-- Info widget shared layout
-- =========================================================

--- Standard layout constants shared by Target/Player/Pet info widgets.
ExsarUI.INFO_LAYOUT = {
    FRAME_W     = 210,
    PAD         = 7,
    PORT_SIZE   = 44,
    BAR_H       = 15,
    ICON_SIZE   = 18,
    ICON_GAP    = 2,
    MAX_DEBUFFS = 16,
    MAX_BUFFS   = 32,
}

-- Derived constants
local IL = ExsarUI.INFO_LAYOUT
IL.ICONS_PER_ROW = math.floor((IL.FRAME_W - IL.PAD * 2 + IL.ICON_GAP) / (IL.ICON_SIZE + IL.ICON_GAP))
IL.BARS_Y        = -(IL.PAD + IL.PORT_SIZE + 5)
IL.AURAS_Y       = IL.BARS_Y - IL.BAR_H - 3 - IL.BAR_H - 5
IL.PRE_AURA_H    = IL.PAD + IL.PORT_SIZE + 5 + IL.BAR_H + 3 + IL.BAR_H

--- Create debuff and buff icon pools for an info widget.
-- @param parentFrame  the widget frame
-- @return debuffIcons, buffIcons tables
function ExsarUI.CreateAuraIconPools(parentFrame)
    local debuffIcons = {}
    local buffIcons   = {}
    for i = 1, IL.MAX_DEBUFFS do debuffIcons[i] = ExsarUI.CreateAuraIcon(parentFrame, IL.ICON_SIZE, true)  end
    for i = 1, IL.MAX_BUFFS   do buffIcons[i]   = ExsarUI.CreateAuraIcon(parentFrame, IL.ICON_SIZE, false) end
    return debuffIcons, buffIcons
end

--- Position aura icons in rows and resize the info widget frame.
-- @param frame        the widget frame
-- @param debuffIcons  debuff icon pool
-- @param buffIcons    buff icon pool
-- @param numDebuffs   number of active debuffs
-- @param numBuffs     number of active buffs
-- @param reAnchorFn   function to call after resize to keep TOPLEFT fixed
function ExsarUI.ApplyAuraLayout(frame, debuffIcons, buffIcons, numDebuffs, numBuffs, reAnchorFn)
    local debuffRows = numDebuffs > 0 and math.ceil(numDebuffs / IL.ICONS_PER_ROW) or 0
    local buffRows   = numBuffs   > 0 and math.ceil(numBuffs   / IL.ICONS_PER_ROW) or 0

    for i, f in ipairs(debuffIcons) do
        if i <= numDebuffs then
            local col = (i - 1) % IL.ICONS_PER_ROW
            local row = math.floor((i - 1) / IL.ICONS_PER_ROW)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", frame, "TOPLEFT",
                IL.PAD + col * (IL.ICON_SIZE + IL.ICON_GAP),
                IL.AURAS_Y - row * (IL.ICON_SIZE + IL.ICON_GAP))
            f:Show()
        else
            f:Hide()
        end
    end

    local buffStartY = IL.AURAS_Y
    if debuffRows > 0 then
        buffStartY = buffStartY - debuffRows * (IL.ICON_SIZE + IL.ICON_GAP) - (buffRows > 0 and 4 or 0)
    end

    for i, f in ipairs(buffIcons) do
        if i <= numBuffs then
            local col = (i - 1) % IL.ICONS_PER_ROW
            local row = math.floor((i - 1) / IL.ICONS_PER_ROW)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", frame, "TOPLEFT",
                IL.PAD + col * (IL.ICON_SIZE + IL.ICON_GAP),
                buffStartY - row * (IL.ICON_SIZE + IL.ICON_GAP))
            f:Show()
        else
            f:Hide()
        end
    end

    local auraH = 0
    if debuffRows + buffRows > 0 then
        auraH = (debuffRows + buffRows) * (IL.ICON_SIZE + IL.ICON_GAP) - IL.ICON_GAP
        if debuffRows > 0 and buffRows > 0 then auraH = auraH + 4 end
    end

    local totalH = IL.PRE_AURA_H + (auraH > 0 and (5 + auraH) or 0) + IL.PAD
    frame:SetSize(IL.FRAME_W, totalH)
    reAnchorFn()
end

--- Scan auras on a unit and update aura icon pools.
-- @param unit         unit token ("target", "player", "pet")
-- @param debuffIcons  debuff icon pool
-- @param buffIcons    buff icon pool
-- @param applyFn      function(numDebuffs, numBuffs) to call after scanning
function ExsarUI.ScanAndLayoutAuras(unit, debuffIcons, buffIcons, applyFn)
    local numDebuffs = 0
    for i = 1, IL.MAX_DEBUFFS do
        local name, icon, count, _, duration, expTime = UnitDebuff(unit, i)
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
    for i = 1, IL.MAX_BUFFS do
        local name, icon, count, _, duration, expTime = UnitBuff(unit, i)
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

    applyFn(numDebuffs, numBuffs)
end

--- Create the standard portrait (ring + texture) for an info widget.
-- @param frame  the info widget frame
-- @return portrait texture, portRing texture
function ExsarUI.CreateInfoPortrait(frame)
    local portRing = frame:CreateTexture(nil, "BACKGROUND")
    portRing:SetPoint("TOPLEFT", frame, "TOPLEFT", IL.PAD - 1, -(IL.PAD - 1))
    portRing:SetSize(IL.PORT_SIZE + 2, IL.PORT_SIZE + 2)
    portRing:SetColorTexture(0.45, 0.45, 0.45, 0.9)

    local portrait = frame:CreateTexture(nil, "ARTWORK")
    portrait:SetPoint("TOPLEFT", frame, "TOPLEFT", IL.PAD, -IL.PAD)
    portrait:SetSize(IL.PORT_SIZE, IL.PORT_SIZE)

    return portrait, portRing
end

--- Create the standard name, level, and type text for an info widget.
-- @param frame  the info widget frame
-- @return nameText, levelText, typeText
function ExsarUI.CreateInfoText(frame)
    local nameText = frame:CreateFontString(nil, "OVERLAY")
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    nameText:SetPoint("TOPLEFT",  frame, "TOPLEFT",  IL.PAD + IL.PORT_SIZE + 6, -IL.PAD)
    nameText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -IL.PAD, -IL.PAD)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)

    local levelText = frame:CreateFontString(nil, "OVERLAY")
    levelText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    levelText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)

    local typeText = frame:CreateFontString(nil, "OVERLAY")
    typeText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    typeText:SetPoint("TOPLEFT", levelText, "BOTTOMLEFT", 0, -3)
    typeText:SetTextColor(0.72, 0.72, 0.72, 1)

    return nameText, levelText, typeText
end

--- Create a standard status bar (health or power) for an info widget.
-- @param frame   the info widget frame
-- @param yOffset vertical offset from frame top (negative = down)
-- @return bar, barText
function ExsarUI.CreateInfoBar(frame, yOffset)
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  IL.PAD, yOffset)
    bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -IL.PAD, yOffset)
    bar:SetHeight(IL.BAR_H)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 100)
    bar:SetValue(0)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    local text = bar:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    text:SetTextColor(1, 1, 1, 1)

    return bar, text
end

-- =========================================================
-- Damage border factory (info widgets)
-- =========================================================

--- Create a pulsating red damage border system for an info widget frame.
-- Listens for COMBAT_LOG_EVENT_UNFILTERED and flashes on incoming damage.
-- @param frame  the info widget frame
-- @param unit   unit token ("player", "pet", etc.)
-- @return ShowDamageBorder, HideDamageBorder functions
function ExsarUI.CreateDamageBorder(frame, unit)
    local DAMAGE_BORDER_W     = 3
    local DAMAGE_GLOW_W       = 8
    local DAMAGE_FADE_TIME    = 3.0
    local DAMAGE_PULSE_FREQ   = 1.5
    local DAMAGE_PULSE_MIN    = 0.35
    local DAMAGE_PULSE_MAX    = 0.90

    local dmgGlow   = {}
    local dmgBorder = {}

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
        local pulse = ExsarLogic.PulseAlpha(GetTime(), DAMAGE_PULSE_FREQ, DAMAGE_PULSE_MIN, DAMAGE_PULSE_MAX)
        for _, t in ipairs(dmgBorder) do t:SetAlpha(pulse) end
        for _, t in ipairs(dmgGlow)   do t:SetAlpha(pulse * 0.45) end
        dmgOverlayFrame:SetAlpha(pulse * 0.25)
    end)

    local dmgCombatFrame = CreateFrame("Frame")
    dmgCombatFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    dmgCombatFrame:SetScript("OnEvent", function()
        local _, subEvent, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()
        if destGUID ~= UnitGUID(unit) then return end
        if subEvent == "SWING_DAMAGE"
            or subEvent == "SPELL_DAMAGE"
            or subEvent == "SPELL_PERIODIC_DAMAGE"
            or subEvent == "RANGE_DAMAGE"
            or subEvent == "DAMAGE_SHIELD"
            or subEvent == "ENVIRONMENTAL_DAMAGE" then
            ShowDamageBorder()
        end
    end)

    return ShowDamageBorder, HideDamageBorder
end

-- =========================================================
-- Low-HP warning factory (info widgets)
-- =========================================================

--- Create a low-HP burst warning effect for an info widget frame.
-- Radiating lines + pulsating "!" marker, driven by caller via Show/Hide.
-- @param frame  the info widget frame
-- @return ShowLowHpWarning, HideLowHpWarning functions
function ExsarUI.CreateLowHpWarning(frame)
    local LOW_HP_PULSE_FREQ  = 2.0
    local LOW_HP_PULSE_MIN   = 0.3
    local LOW_HP_PULSE_MAX   = 0.9

    local burstFrame = CreateFrame("Frame", nil, frame)
    burstFrame:SetAllPoints()
    burstFrame:SetFrameLevel(frame:GetFrameLevel() + 12)
    burstFrame:Hide()

    local burstLines = {}
    local BURST_DEFS = {
        { "T", 0.10, 22 }, { "T", 0.25, 28 }, { "T", 0.40, 25 }, { "T", 0.50, 32 },
        { "T", 0.60, 25 }, { "T", 0.75, 28 }, { "T", 0.90, 22 },
        { "B", 0.10, 22 }, { "B", 0.25, 28 }, { "B", 0.40, 25 }, { "B", 0.50, 32 },
        { "B", 0.60, 25 }, { "B", 0.75, 28 }, { "B", 0.90, 22 },
        { "L", 0.15, 22 }, { "L", 0.40, 26 }, { "L", 0.60, 26 }, { "L", 0.85, 22 },
        { "R", 0.15, 22 }, { "R", 0.40, 26 }, { "R", 0.60, 26 }, { "R", 0.85, 22 },
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

    local bangText = burstFrame:CreateFontString(nil, "OVERLAY")
    bangText:SetFont("Fonts\\FRIZQT__.TTF", 80, "OUTLINE, THICKOUTLINE")
    bangText:SetPoint("CENTER", frame, "CENTER", 0, 0)
    bangText:SetTextColor(1.0, 0.20, 0.15, 1)
    bangText:SetText("!")

    local function UpdateBurstPositions()
        local fw = frame:GetWidth()
        local fh = frame:GetHeight()
        if not fw or fw < 1 then fw = IL.FRAME_W end
        if not fh or fh < 1 then fh = IL.PRE_AURA_H + IL.PAD end
        local hw, hh = fw / 2, fh / 2
        for _, b in ipairs(burstLines) do
            local bx, by
            if b.edge == "T" then
                bx = -hw + b.pos * fw; by = hh
            elseif b.edge == "B" then
                bx = -hw + b.pos * fw; by = -hh
            elseif b.edge == "L" then
                bx = -hw; by = -hh + b.pos * fh
            else
                bx = hw; by = -hh + b.pos * fh
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
        local pulse = ExsarLogic.PulseAlpha(GetTime(), LOW_HP_PULSE_FREQ, LOW_HP_PULSE_MIN, LOW_HP_PULSE_MAX)
        burstFrame:SetAlpha(pulse)
    end)

    return ShowLowHpWarning, HideLowHpWarning
end

-- =========================================================
-- Aura icon factory (info widgets)
-- =========================================================

--- Create a single aura icon frame with ring, icon, cooldown sweep, and stack text.
-- Used by Target/Player/Pet info widgets.
-- @param parentFrame  the parent frame
-- @param iconSize     size of the icon (square)
-- @param isDebuff     true → red ring, false → grey ring
-- @return frame with .icon, .cooldown, .stackText fields
function ExsarUI.CreateAuraIcon(parentFrame, iconSize, isDebuff)
    local f = CreateFrame("Frame", nil, parentFrame)
    f:SetSize(iconSize, iconSize)

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

-- =========================================================
-- Placeholder text (shown when widget is unlocked and empty)
-- =========================================================

function ExsarUI.CreatePlaceholder(frame, text, fontSize)
    local ph = frame:CreateFontString(nil, "OVERLAY")
    ph:SetFont("Fonts\\FRIZQT__.TTF", fontSize or 11, "OUTLINE")
    ph:SetPoint("CENTER", frame, "CENTER", 0, 0)
    ph:SetTextColor(0.55, 0.55, 0.55, 0.9)
    ph:SetText(text)
    ph:Hide()
    return ph
end

-- =========================================================
-- Icon construction helpers
-- =========================================================

--- Create a standard icon texture inside a frame, with texcoord trim.
function ExsarUI.CreateIcon(parentFrame, layer)
    local icon = parentFrame:CreateTexture(nil, layer or "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return icon
end

--- Create a standard cooldown sweep overlay.
-- @param parentFrame  the parent frame
-- @param opts         optional table: { reverse = false, hideNumbers = true }
function ExsarUI.CreateSweep(parentFrame, opts)
    opts = opts or {}
    local sweep = CreateFrame("Cooldown", nil, parentFrame, "CooldownFrameTemplate")
    sweep:SetAllPoints()
    sweep:SetDrawEdge(false)
    if sweep.SetHideCountdownNumbers then
        sweep:SetHideCountdownNumbers(opts.hideNumbers ~= false)
    end
    if opts.reverse and sweep.SetReverse then
        sweep:SetReverse(true)
    end
    return sweep
end

--- Create a countdown text overlay on an icon.
function ExsarUI.CreateCountdownText(parentFrame, fontSize, yOffset)
    local text = parentFrame:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", fontSize or 11, "OUTLINE")
    text:SetPoint("CENTER", parentFrame, "CENTER", 0, yOffset or 0)
    text:SetTextColor(1, 1, 1, 1)
    return text
end

--- Create a glow background behind an icon (solid color rectangle extending beyond the icon).
-- Also used for thin border rings (size=1) and warning glows (red color, BORDER layer).
-- @param parentFrame  the icon frame
-- @param r, g, b, a   glow color (defaults to gold)
-- @param size          pixels to extend beyond the icon edge (default 4)
-- @param layer         draw layer (default "BACKGROUND")
function ExsarUI.CreateGlow(parentFrame, r, g, b, a, size, layer)
    size = size or 4
    local glow = parentFrame:CreateTexture(nil, layer or "BACKGROUND")
    glow:SetPoint("TOPLEFT",     parentFrame, "TOPLEFT",     -size,  size)
    glow:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT",  size, -size)
    glow:SetColorTexture(r or 1, g or 0.85, b or 0, a or 0.22)
    glow:Hide()
    return glow
end

--- Create a Red X overlay (two diagonal red lines) indicating an inactive/missing state.
-- @param parentFrame  the frame to overlay
-- @param inset        pixels to inset from corners (default 4)
-- @param thickness    line thickness (default 3)
-- @return line1, line2
function ExsarUI.CreateRedX(parentFrame, inset, thickness)
    inset = inset or 4
    thickness = thickness or 3
    local line1 = parentFrame:CreateLine(nil, "OVERLAY")
    line1:SetColorTexture(0.9, 0.15, 0.15, 1)
    line1:SetThickness(thickness)
    line1:SetStartPoint("TOPLEFT",     parentFrame,  inset, -inset)
    line1:SetEndPoint("BOTTOMRIGHT",   parentFrame, -inset,  inset)

    local line2 = parentFrame:CreateLine(nil, "OVERLAY")
    line2:SetColorTexture(0.9, 0.15, 0.15, 1)
    line2:SetThickness(thickness)
    line2:SetStartPoint("TOPRIGHT",    parentFrame, -inset, -inset)
    line2:SetEndPoint("BOTTOMLEFT",    parentFrame,  inset,  inset)

    return line1, line2
end

-- =========================================================
-- Marching ants border construction
-- =========================================================

--- Build marching-ants dash textures around an icon frame.
-- @param iconFrame   the frame to border
-- @param iconSize    size of the icon (square)
-- @param dashCount   total number of dashes (must be divisible by 4)
-- @param borderW     width of the dash line in pixels
-- @return dashes table (1-indexed)
function ExsarUI.BuildDashes(iconFrame, iconSize, dashCount, borderW)
    local dashes  = {}
    local perSide = dashCount / 4
    local step    = iconSize / perSide
    local dashLen = step - 1

    for i = 0, dashCount - 1 do
        local side   = math.floor(i / perSide)
        local pos    = i % perSide
        local offset = pos * step

        local d = iconFrame:CreateTexture(nil, "OVERLAY")
        d:SetColorTexture(1, 0.85, 0, 1)
        d:SetAlpha(0)

        if side == 0 then      -- top, left → right
            d:SetSize(dashLen, borderW)
            d:SetPoint("TOPLEFT",     iconFrame, "TOPLEFT",     offset, 0)
        elseif side == 1 then  -- right, top → bottom
            d:SetSize(borderW, dashLen)
            d:SetPoint("TOPRIGHT",    iconFrame, "TOPRIGHT",    0, -offset)
        elseif side == 2 then  -- bottom, right → left
            d:SetSize(dashLen, borderW)
            d:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -offset, 0)
        else                   -- left, bottom → top
            d:SetSize(borderW, dashLen)
            d:SetPoint("BOTTOMLEFT",  iconFrame, "BOTTOMLEFT",  0, offset)
        end

        dashes[i + 1] = d
    end
    return dashes
end

--- Animate marching-ants dashes for a list of slots.
-- Each slot must have: .active (bool), .dashes (table from BuildDashes).
-- @param slots      list of slot tables
-- @param now        current time (GetTime())
-- @param speed      animation speed
-- @param dashCount  total dash count
-- @param tailLen    bright tail length
function ExsarUI.AnimateDashes(slots, now, speed, dashCount, tailLen)
    local head = ExsarLogic.MarchingAntHead(now, speed, dashCount)
    for _, s in ipairs(slots) do
        if s.active then
            for j, d in ipairs(s.dashes) do
                d:SetAlpha(ExsarLogic.MarchingAntAlpha(j - 1, head, dashCount, tailLen))
            end
        end
    end
end

-- =========================================================
-- Config panel helpers
-- =========================================================

--- Add a standard scale slider to a config panel.
-- @param parent   config panel frame
-- @param y        current y offset
-- @param dbFunc   DB accessor
-- @param frame    the widget frame to scale
-- @return new y offset
function ExsarUI.AddScaleSlider(parent, y, dbFunc, frame)
    ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
        function() return dbFunc().scale or 1.0 end,
        function(v)
            local rounded = ExsarLogic.RoundScale(v)
            dbFunc().scale = rounded
            frame:SetScale(rounded)
        end
    )
    return y - 55
end

--- Add a standard lock checkbox to a config panel.
-- @param parent   config panel frame
-- @param y        current y offset
-- @param dbFunc   DB accessor
-- @param frame    the widget frame to lock/unlock
-- @param onLock   optional callback(v) called after lock state changes
-- @return new y offset
function ExsarUI.AddLockCheckbox(parent, y, dbFunc, frame, onLock)
    ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
        function() return dbFunc().locked and true or false end,
        function(v)
            dbFunc().locked = v
            frame:EnableMouse(not v)
            if onLock then onLock(v) end
        end
    )
    return y - 30
end

--- Add a standard reset-position button to a config panel.
-- @param parent     config panel frame
-- @param y          current y offset
-- @param dbFunc     DB accessor
-- @param frame      the widget frame
-- @param name       display name for the print message
-- @param defaultX   default X offset
-- @param defaultY   default Y offset
-- @return new y offset
--- Update health and power bars for an info widget.
-- @param cfg table with keys:
--   unit        — unit token ("player", "pet", "target")
--   healthBar   — StatusBar frame
--   healthText  — FontString
--   powerBar    — StatusBar frame
--   powerText   — FontString
--   showLowHp   — function(void) or nil  (called when hp% <= threshold)
--   hideLowHp   — function(void) or nil  (called otherwise)
--   lowHpThreshold — number or nil (percent, e.g. 30)
function ExsarUI.UpdateInfoBars(cfg)
    local unit = cfg.unit
    local hp    = UnitHealth(unit)
    local hpMax = UnitHealthMax(unit)
    if hpMax > 0 then
        cfg.healthBar:SetMinMaxValues(0, hpMax)
        cfg.healthBar:SetValue(hp)
        if hp == 0 then
            cfg.healthText:SetText("Dead")
            if cfg.hideLowHp then cfg.hideLowHp() end
        else
            local pct = math.floor(hp / hpMax * 100 + 0.5)
            cfg.healthText:SetText(pct .. "%")
            cfg.healthBar:SetStatusBarColor(ExsarLogic.HealthColorThreshold(pct))
            if cfg.lowHpThreshold and cfg.showLowHp and cfg.hideLowHp then
                if pct <= cfg.lowHpThreshold then
                    cfg.showLowHp()
                else
                    cfg.hideLowHp()
                end
            end
        end
    end

    local pw    = UnitPower(unit)
    local pwMax = UnitPowerMax(unit)
    if pwMax > 0 then
        cfg.powerBar:SetMinMaxValues(0, pwMax)
        cfg.powerBar:SetValue(pw)
        cfg.powerText:SetText(ExsarLogic.FormatNumber(pw) .. " / " .. ExsarLogic.FormatNumber(pwMax))
    else
        cfg.powerBar:SetMinMaxValues(0, 1)
        cfg.powerBar:SetValue(0)
        cfg.powerText:SetText("")
    end
end

--- Register a standard slash reset command for a CENTER-anchored widget.
-- @param cmd       slash sub-command name (e.g. "castbarreset")
-- @param frame     the widget frame
-- @param dbFunc    DB accessor function
-- @param name      display name for the print message
-- @param defaultX  default X offset from center
-- @param defaultY  default Y offset from center
--- Create a polling OnUpdate that fires a callback at a fixed interval.
-- @param frame     the frame to attach OnUpdate to (or nil to create a new hidden frame)
-- @param interval  seconds between updates (e.g. 0.1 or 0.5)
-- @param callback  function to call each interval
-- @return the frame (useful if nil was passed to create a new one)
function ExsarUI.CreatePoller(frame, interval, callback)
    if not frame then
        frame = CreateFrame("Frame")
    end
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= interval then
            elapsed = 0
            callback()
        end
    end)
    return frame
end

function ExsarUI.AddSlashReset(cmd, frame, dbFunc, name, defaultX, defaultY)
    ExsarAddon.AddSlashCommand(cmd, function()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", defaultX or 0, defaultY or 0)
        dbFunc().x = nil
        dbFunc().y = nil
        print(ADDON_NAME .. ": " .. name .. " position reset.")
    end)
end

function ExsarUI.AddResetButton(parent, y, dbFunc, frame, name, defaultX, defaultY)
    ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", defaultX or 0, defaultY or 0)
        dbFunc().x = nil
        dbFunc().y = nil
        print(ADDON_NAME .. ": " .. name .. " position reset.")
    end)
    return y - 30
end
