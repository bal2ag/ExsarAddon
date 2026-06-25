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

--- Show a modal-ish window with copyable multi-line text.
-- Singleton: subsequent calls reuse the same frame, just swapping the content.
-- @param text  string  the text to display
-- @param opts  table (optional) { title=string, width=number, height=number }
function ExsarUI.ShowCopyableText(text, opts)
    opts = opts or {}
    local W = opts.width  or 800
    local H = opts.height or 500

    local f = _G["ExsarCopyFrame"]
    if not f then
        f = CreateFrame("Frame", "ExsarCopyFrame", UIParent)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop",  f.StopMovingOrSizing)

        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.92)

        -- thin border
        local top = f:CreateTexture(nil, "BORDER")
        top:SetColorTexture(0.5, 0.5, 0.5, 0.9); top:SetHeight(1)
        top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        local bot = f:CreateTexture(nil, "BORDER")
        bot:SetColorTexture(0.5, 0.5, 0.5, 0.9); bot:SetHeight(1)
        bot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        bot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        local lft = f:CreateTexture(nil, "BORDER")
        lft:SetColorTexture(0.5, 0.5, 0.5, 0.9); lft:SetWidth(1)
        lft:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        lft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        local rgt = f:CreateTexture(nil, "BORDER")
        rgt:SetColorTexture(0.5, 0.5, 0.5, 0.9); rgt:SetWidth(1)
        rgt:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        rgt:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

        local titleFs = f:CreateFontString(nil, "OVERLAY")
        titleFs:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        titleFs:SetPoint("TOP", f, "TOP", 0, -8)
        f.titleFs = titleFs

        local hint = f:CreateFontString(nil, "OVERLAY")
        hint:SetFont("Fonts\\FRIZQT__.TTF", 10)
        hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 8)
        hint:SetText("Ctrl+A select all  \194\183  Ctrl+C copy  \194\183  Esc close")
        hint:SetTextColor(0.6, 0.6, 0.6)

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        if closeBtn then
            closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
            closeBtn:SetScript("OnClick", function() f:Hide() end)
        end

        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     10, -26)
        sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -28, 22)
        f.scrollFrame = sf

        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.editBox = eb
    end

    f:SetSize(W, H)
    f:ClearAllPoints()
    f:SetPoint("CENTER")
    f.titleFs:SetText(opts.title or "")

    local eb = f.editBox
    eb:SetWidth(W - 40)        -- leave room for scrollbar + padding
    eb:SetText(text or "")
    eb:HighlightText()

    f:Show()
    eb:SetFocus()
    return f
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

--- Build two parallel arrows pointing up, centered on a frame.
-- Each arrow is a vertical shaft plus two arrowhead segments (3 lines each,
-- 6 lines total). Useful as a "move / reposition" status cue.
-- @param parentFrame  the frame to draw on (lines are centered on it)
-- @param opts         optional table:
--                       thickness — line width (default 6)
--                       height    — shaft length (default 34)
--                       headLen   — arrowhead segment length (default 12)
--                       spacing   — half the gap between the two arrows (default 12)
--                       color     — {r,g,b,a} (default yellow)
--                       layer     — draw layer (default "OVERLAY")
-- @return lines table (1-indexed, 6 entries)
function ExsarUI.CreateUpArrows(parentFrame, opts)
    opts = opts or {}
    local thickness = opts.thickness or 6
    local height    = opts.height    or 34
    local headLen   = opts.headLen   or 12
    local spacing   = opts.spacing   or 12
    local color     = opts.color     or { 1.0, 0.85, 0.0, 1.0 }
    local layer     = opts.layer     or "OVERLAY"

    local lines = {}
    local half  = height / 2

    for _, cx in ipairs({ -spacing, spacing }) do
        local segments = {
            { cx, -half,   cx,           half           },  -- shaft
            { cx,  half,   cx - headLen, half - headLen  },  -- left arrowhead
            { cx,  half,   cx + headLen, half - headLen  },  -- right arrowhead
        }
        for _, s in ipairs(segments) do
            local line = parentFrame:CreateLine(nil, layer)
            line:SetColorTexture(color[1], color[2], color[3], color[4])
            line:SetThickness(thickness)
            line:SetStartPoint("CENTER", parentFrame, s[1], s[2])
            line:SetEndPoint("CENTER", parentFrame, s[3], s[4])
            lines[#lines + 1] = line
        end
    end

    return lines
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

-- =========================================================
-- Ranged weapon helpers
-- =========================================================

-- Hidden tooltip used to read base weapon speed (unaffected by haste buffs).
local scanTip = CreateFrame("GameTooltip", ADDON_NAME .. "ScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

local RANGED_SLOT = 18  -- inventory slot for ranged weapon

--- Read the base (unhasted) speed of the equipped ranged weapon via tooltip scan.
-- @return number  base weapon speed in seconds, or 0 if no weapon equipped
function ExsarUI.GetBaseRangedSpeed()
    local link = GetInventoryItemLink("player", RANGED_SLOT)
    if not link then return 0 end
    scanTip:ClearLines()
    scanTip:SetHyperlink(link)
    for i = 1, scanTip:NumLines() do
        local right = _G[scanTip:GetName() .. "TextRight" .. i]
        if right then
            local str = right:GetText()
            if str then
                local speed = str:match("Speed%s+(%d+%.?%d*)")
                if speed then
                    return tonumber(speed) or 0
                end
            end
        end
    end
    return 0
end

-- Internal: current one-way network latency in seconds.
local function GetLatency()
    local _, _, homeMs, worldMs = GetNetStats()
    return math.max(
        type(homeMs)  == "number" and homeMs  or 0,
        type(worldMs) == "number" and worldMs or 0
    ) / 1000
end

--- Compute the haste-adjusted Auto Shot clipping window + latency.
-- When standing still, the game auto-casts the wind-up inside the cycle.
-- Starting a new spell (e.g. Steady Shot) during this window delays the auto
-- shot. The window scales with haste because the internal cast is hasted.
-- Used by the CastBar for the standing-still natural aim window.
-- @param hastedSpeed  current hasted weapon speed from UnitRangedDamage("player")
-- @param baseSpeed    base weapon speed from ExsarUI.GetBaseRangedSpeed()
-- @return number  clipping window in seconds
function ExsarUI.GetAutoShotClipWindow(hastedSpeed, baseSpeed)
    local baseAim = 0.5
    if baseSpeed > 0 and hastedSpeed > 0 then
        baseAim = 0.5 * hastedSpeed / baseSpeed
    end
    return baseAim + GetLatency()
end

--- Compute the unhasted Auto Shot wind-up time + latency.
-- After stopping from movement, the game must play the full unhasted 0.5s
-- wind-up before the shot fires. This is NOT reduced by haste.
-- Used by the swing timer reticules ("stop moving by here") and the CastBar
-- for movement-delayed aim bars.
-- @return number  wind-up time in seconds
function ExsarUI.GetAutoShotWindUpTime()
    return 0.5 + GetLatency()
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

--- Add a labelled multi-line macro edit box to a config panel.
-- Used for editable macrotext overrides (e.g. PetManagementWidget). The box is
-- non-secure UI; the caller's setter is responsible for pushing the text onto a
-- secure button out of combat. The box saves on focus loss / Escape, and
-- refreshes from the getter on show so it always reflects the saved value.
-- @param parent   config panel frame
-- @param y        current y offset
-- @param label    text shown above the box
-- @param getter   function() -> string  current text (override or default)
-- @param setter   function(text)        called with the edited text on save
-- @return new y offset
function ExsarUI.AddMacroEditBox(parent, y, label, getter, setter)
    local BOX_W, BOX_H = 360, 44

    local lbl = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
    lbl:SetText(label)

    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(BOX_W, BOX_H)
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y - 16)

    -- 1px frame: a grey rectangle 1px larger than the box, with the black fill
    -- drawn on top so only the outer ring shows.
    local frameBorder = box:CreateTexture(nil, "BACKGROUND")
    frameBorder:SetPoint("TOPLEFT", box, "TOPLEFT", -1, 1)
    frameBorder:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 1, -1)
    frameBorder:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    local bg = box:CreateTexture(nil, "BORDER")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.85)

    local eb = CreateFrame("EditBox", nil, box)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    eb:SetTextColor(1, 1, 1, 1)
    eb:SetPoint("TOPLEFT", box, "TOPLEFT", 5, -4)
    eb:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -5, 4)
    eb:SetText(getter() or "")
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function(self) setter(self:GetText()) end)
    eb:SetScript("OnShow", function(self) self:SetText(getter() or "") end)

    return y - 16 - BOX_H - 10
end

-- =========================================================
-- Keybinding bridge
-- =========================================================

--- Bridge Blizzard named bindings to secure button clicks for a widget's slots.
-- For each slot i in 1..count it reads the key bound to "<bindingPrefix>"..i
-- (assigned in Blizzard's Key Bindings UI, which gives native conflict warnings
-- and syncs across computers) and:
--   (a) installs a secure override binding so pressing that key clicks
--       "<buttonPrefix>"..i — the override path is what lets the item be used
--       even in combat, and
--   (b) calls onSlotKey(i, key) so the caller can update an on-icon hotkey label.
-- SetOverrideBindingClick / ClearOverrideBindings are protected and cannot run
-- in combat lockdown, so the override step is skipped while in combat and
-- re-applied on PLAYER_REGEN_ENABLED. The onSlotKey callback always runs (label
-- updates are not protected), so labels stay current even mid-combat.
-- An internal watcher frame re-applies on UPDATE_BINDINGS / PLAYER_ENTERING_WORLD
-- / PLAYER_REGEN_ENABLED, so callers only need to call this once after their
-- secure buttons exist.
-- @param opts table:
--   owner          frame used as the override-binding owner (its overrides are
--                  cleared and rebuilt on each pass)
--   bindingPrefix  e.g. "EXSAR_USE_ITEM"
--   buttonPrefix   e.g. "ExsarAddonItemBtn"
--   count          number of slots
--   onSlotKey      optional function(index, key) — key is the first bound key or nil
--   deps           optional injected WoW funcs for testing: GetBindingKey,
--                  SetOverrideBindingClick, ClearOverrideBindings, InCombatLockdown
-- @return apply  the single-pass function (also returned for direct/manual calls)
function ExsarUI.SetupKeybindBridge(opts)
    local owner         = opts.owner
    local bindingPrefix = opts.bindingPrefix
    local buttonPrefix  = opts.buttonPrefix
    local count         = opts.count
    local onSlotKey     = opts.onSlotKey
    local deps          = opts.deps or {}
    local getBindingKey           = deps.GetBindingKey           or GetBindingKey
    local setOverrideBindingClick = deps.SetOverrideBindingClick or SetOverrideBindingClick
    local clearOverrideBindings   = deps.ClearOverrideBindings   or ClearOverrideBindings
    local inCombatLockdown        = deps.InCombatLockdown        or InCombatLockdown

    local function apply()
        local combat = inCombatLockdown()
        if not combat then
            clearOverrideBindings(owner)
        end
        for i = 1, count do
            local key1, key2 = getBindingKey(bindingPrefix .. i)
            if onSlotKey then onSlotKey(i, key1) end
            if not combat then
                local btn = buttonPrefix .. i
                if key1 then setOverrideBindingClick(owner, true, key1, btn) end
                if key2 then setOverrideBindingClick(owner, true, key2, btn) end
            end
        end
    end

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("UPDATE_BINDINGS")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:SetScript("OnEvent", apply)
    apply()
    return apply
end

--- Combat-deferred secure attribute setter.
-- `SetAttribute` on a protected (secure) frame is blocked during combat
-- lockdown, but the binding for a click-to-target button often needs to change
-- as marks/targets move. This mirrors the classic SecureActionQueue pattern:
-- out of combat the attribute is written immediately; in combat the write is
-- stashed (deduplicated by frame+key, so only the latest value per key is kept)
-- and flushed on PLAYER_REGEN_ENABLED. The secure engine still resolves
-- *live* tokens (e.g. "raid3target") at click time, so a static binding set
-- this way tracks that unit's current target without further writes.
local secureAttrQueue = {}
local secureAttrWatcher
function ExsarUI.SecureSetAttribute(frame, key, value)
    if not frame then return end
    if not InCombatLockdown() then
        frame:SetAttribute(key, value)
        return
    end
    if not secureAttrWatcher then
        secureAttrWatcher = CreateFrame("Frame")
        secureAttrWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        secureAttrWatcher:SetScript("OnEvent", function()
            for _, q in pairs(secureAttrQueue) do
                q.frame:SetAttribute(q.key, q.value)
            end
            secureAttrQueue = {}
        end)
    end
    local id = (frame:GetName() or tostring(frame)) .. "#" .. key
    secureAttrQueue[id] = { frame = frame, key = key, value = value }
end

-- =========================================================
-- Bindable icon action bar engine
-- =========================================================
-- Shared engine behind the keybindable mini action bars (UsableItemsWidget,
-- PetManagementWidget, and future themed bars). It owns the common chassis -- a
-- movable frame, secure SecureActionButtonTemplate slots, layout, cooldown
-- sweep / count / hotkey-label rendering, the keybind bridge, slash reset,
-- config rows and module registration -- while each slot's behavior is
-- described by a declarative action spec, with optional resolver-callback
-- escape hatches for the genuinely bespoke cases.
--
-- Pure selection logic lives in ExsarLogic (SelectBestRank, SelectFirstInStock,
-- CooldownState, PetActionEnabled, PetStateKey); only mechanism lives here.
--
-- A slot has a kind: "item" (UsableItems behavior -- tracks bag stock, dims
-- when out of stock or on cooldown, optional rank/alternate swapping, gold
-- border ring) or "macro"/"spell" (PetManagement behavior -- always present,
-- greyed by a pet-state/`requires` predicate, drives a GCD/item/debuff sweep).
-- Kind is `action.type` or inferred (macro field -> "macro", spell -> "spell",
-- else "item").
--
-- Action spec (declarative defaults):
--   key, name        stable id / display label (binding row + tooltip)
--   type             "item" | "macro" | "spell" (optional; inferred otherwise)
--   macro / spell    secure payload for macro/spell kinds
--   spells           talent-gated spell list (names or { name, id }, preference
--                    order): macro kind that /casts each (first known fires);
--                    icon + CD follow the first KNOWN spell; the slot HIDES when
--                    none are known (e.g. Bestial Wrath sub Readiness; Intimidation
--                    only when BM). Known via IsSpellKnown(id), name-lookup fallback.
--   id, name         item id + name for item kind (name doubles as the label)
--   icon/iconItem/iconSpell  static icon source (path / item / spell), retried
--   dynamicIcon      pet-state map { alive=, dead=, missing= } of icon specs
--   ranks            highest-first interchangeable item ids (SelectBestRank)
--   alternates       first-in-stock substitutes ({id,name,zones=}) for item kind
--   hideWhenEmpty / groupFallback   grid reflow (item kind, grid layout)
--   countItem        bag-count item (true = "the active item"); useCharges/
--                    countCharges sum charges across stacks
--   cooldownItem     item whose CD drives the sweep (macro kind)
--   cooldownSpell    spell name whose CD drives the sweep (GetSpellCooldown;
--                    macro/spell kind, e.g. a trap's cooldown)
--   cooldownDebuff   player debuff name driving the CD (e.g. Tinnitus)
--   cooldownTrinket  equipped inventory slot (13/14) whose CD feeds the sweep,
--                    WITHOUT taking over icon/macro (unlike trinketSlot) -- for a
--                    macro that fires a trinket + a spell (show "both ready")
--   trinketSlot      equipped inventory slot (13/14): macro kind that defaults
--                    to "/use <slot>", with icon from GetInventoryItemTexture
--                    and CD from GetInventoryItemCooldown (for a cooldowns bar)
--   gcd              show the GCD sweep (macro kind)
--   requires         pet-state grey-out token (PetActionEnabled)
--   tooltipSpell     override for the hover tooltip's spell. By default a
--                    macro/spell slot shows the tooltip of its associated spell
--                    (the resolved `spells` entry, else `spell`, else `iconSpell`)
--                    -- UNLESS it has a hand-written `macro` that is not a single
--                    /cast (ExsarLogic.IsSimpleCastMacro), in which case it shows
--                    its macro text. Set this to a spell name to force that spell,
--                    or to `false` to force the macro-text tooltip.
--   activeBuff       player buff name; glows the border only while it is up
--                    (action kind + opts.border; e.g. the active aspect)
--   borderColor      {r,g,b,a} static border color override (per-slot opt-in
--                    creates the border ring even when opts.border is unset,
--                    e.g. a single warning slot on an otherwise borderless bar)
--   bindingLabel     override for the Key Bindings UI row label
--   rangeSpell       (with opts.rangeCheck) spell name governing the out-of-range
--                    red shade. Auto-resolved for spell/`spells` slots; macro/item
--                    slots must set it explicitly, or `false` to suppress.
--   rangeUnit        (with opts.rangeCheck) unit token whose range to check for
--                    the shade. Default "target" (harm spells, and friendly-
--                    target spells like Misdirection). Set "pet" for pet-targeted
--                    abilities (Mend/Feed Pet). IsSpellInRange returns nil for the
--                    wrong unit type, so the shade self-selects per spell.
--   manaSpell        (with opts.manaCheck) spell name whose mana cost governs the
--                    out-of-mana blue shade. Auto-resolved for spell/`spells`
--                    slots; macro/item slots opt in explicitly, or `false` to
--                    suppress. Independent of rangeSpell (a slot's range spell and
--                    its mana-cost spell can differ -- the Auto Shot macro range-
--                    checks Auto Shot, which costs no mana).
-- Escape hooks (called on the poll tick; consume returns):
--   resolveActive(s)        -> { id, name, icon } current item (item kind)
--   getCooldown(s)          -> start, duration, isRealCD
--   getCount(s)             -> number
--   resolveIcon(s, petState)-> texture
--   isEnabled(s, petState)  -> bool
--   isActive(s, petState)   -> bool (drives the border; overrides activeBuff)
--   resolveBorderColor(s, petState) -> {r,g,b,a} | nil   per-tick dynamic
--                    border show + recolor; nil hides it. Overrides isActive /
--                    activeBuff / borderColor (lets one slot flip between
--                    multiple states, e.g. Devilsaur Prep yellow vs red).
--   resolveMacro(s, petState) -> macrotext string   stage-dependent macrotext
--                    (e.g. Devilsaur Prep: equip vs use+swap). Engine queues
--                    SecureSetAttribute when the text changes (combat-deferred).
--   tooltip(s, GameTooltip) -> custom tooltip
--
-- opts: name (DB namespace), frameName, buttonPrefix, placeholder, actions,
--   layout ("horizontal"|"vertical"|"grid"), gridCols, border (gold 1px ring
--   active indicator) / activeAnts (marching-ants active indicator),
--   dimOnCooldown (dim macro/spell slots while a real CD runs),
--   rangeCheck (red out-of-range shade over slots whose ability is out of range
--   of its target -- hostile, friendly, or pet; see rangeSpell / rangeUnit),
--   manaCheck (blue out-of-mana shade over slots whose spell is unusable for
--   lack of mana; see manaSpell. Takes precedence over the range shade),
--   moduleName,
--   configName, defaultX, defaultY, slashReset, bindingPrefix, bindingCount,
--   bindingHeaderGlobal, bindingHeaderText, extraEvents, pollInterval.
-- Returns a handle { frame, slots, Refresh, ApplyLayout, dbFunc }.

local AB_ICON_SIZE = 29
local AB_ICON_GAP  = 4
local AB_PADDING   = 6
local AB_GCD_PROBE = "Wing Clip"  -- no CD of its own -> GetSpellCooldown = GCD only

-- Marching-ants active indicator (opts.activeAnts) -- standard params.
local AB_DASH_BORDER_W = 2
local AB_DASH_COUNT    = 16
local AB_DASH_SPEED    = 1.5
local AB_DASH_TAIL     = 5

-- Resolve an icon spec (string path, { spell=name }, or { item=id|name }) to a
-- texture, or nil if not yet resolvable (e.g. uncached item).
local function AB_ResolveIconSpec(spec)
    if type(spec) == "string" then return spec end
    if type(spec) == "table" then
        if spec.spell then return GetSpellTexture(spec.spell) end
        if spec.item  then return select(10, GetItemInfo(spec.item)) end
    end
    return nil
end

-- start,duration for a named player debuff currently active (else nil,nil).
local function AB_DebuffCooldown(debuffName)
    for i = 1, 40 do
        local name, _, _, _, duration, expTime = UnitDebuff("player", i)
        if not name then break end
        if name == debuffName and duration and duration > 0 then
            return expTime - duration, duration
        end
    end
    return nil, nil
end

-- True if the player currently has a buff with the given name (any rank).
-- Used by the action bar engine (activeBuff) and by swing-cycle tracking
-- (Feign Death end detection in RangedSwingTimer / CastBar).
function ExsarUI.PlayerHasBuff(buffName)
    for i = 1, 40 do
        local name = UnitBuff("player", i)
        if not name then break end
        if name == buffName then return true end
    end
    return false
end
local AB_PlayerHasBuff = ExsarUI.PlayerHasBuff

-- Show a spell's tooltip (by name or id) on GameTooltip via its hyperlink.
-- Returns true if a tooltip was shown (false if the spell can't be linked, e.g.
-- not known), so the caller can fall back to macro text.
local function AB_ShowSpellTooltip(spell)
    if not spell then return false end
    local link = GetSpellLink(spell)
    if not link then return false end
    GameTooltip:SetHyperlink(link)
    return true
end

-- Build "/cast <name>" macrotext for a spells list. The first known spell
-- fires; an unknown /cast line silently no-ops, so spec substitutes work
-- automatically (e.g. Bestial Wrath for BM, Readiness for Survival).
local function AB_SpellsMacro(spells)
    local lines = {}
    for _, e in ipairs(spells) do
        lines[#lines + 1] = "/cast " .. (type(e) == "table" and e.name or e)
    end
    return table.concat(lines, "\n")
end

-- Resolve the first known spell in a list to its name, or nil if none known
-- (the slot is then talent-irrelevant and hidden). Prefers IsSpellKnown(id),
-- authoritative for talent spells; falls back to a name lookup when an entry
-- carries no id (or on clients without IsSpellKnown). Entry = name string or
-- { name = , id = }.
local function AB_FirstKnownSpell(spells)
    local isKnown = _G.IsSpellKnown
    for _, e in ipairs(spells) do
        local name = type(e) == "table" and e.name or e
        local id   = type(e) == "table" and e.id or nil
        local known
        if id and isKnown then known = isKnown(id) and true or false
        else known = GetSpellInfo(name) ~= nil end
        if known then return name end
    end
    return nil
end

-- start,duration for an item's cooldown, read from whichever bag slot holds it
-- (TBC has no GetItemCooldown; GetContainerItemCooldown also reflects shared
-- category cooldowns). Returns nil,nil if the item isn't in bags.
local function AB_ItemCooldown(itemId)
    if not itemId then return nil, nil end
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if C_Container.GetContainerItemID(bag, slot) == itemId then
                return C_Container.GetContainerItemCooldown(bag, slot)
            end
        end
    end
    return nil, nil
end

function ExsarUI.CreateActionBar(opts)
    local dbFunc         = ExsarUI.MakeDB(opts.name)
    local actions        = opts.actions
    local layout         = opts.layout or "horizontal"
    local buttonPrefix   = opts.buttonPrefix
    local defaultX       = opts.defaultX or 0
    local defaultY       = opts.defaultY or 0
    local FormatCooldown = ExsarLogic.FormatCooldown
    local MIN_CD         = ExsarLogic.MIN_COOLDOWN_DURATION

    local frame = CreateFrame("Frame", opts.frameName, UIParent)
    ExsarUI.SetupMovableFrame(frame, dbFunc)
    local placeholderText = ExsarUI.CreatePlaceholder(frame, opts.placeholder or "Bar")
    frame:Hide()

    -- Fixed grid width = widest column + 1 (or explicit opts.gridCols).
    local gridCols = opts.gridCols
    if layout == "grid" and not gridCols then
        gridCols = 1
        for _, a in ipairs(actions) do
            if a.col and (a.col + 1) > gridCols then gridCols = a.col + 1 end
        end
    end

    -- ---------- slot construction ----------
    local slots = {}
    for i, action in ipairs(actions) do
        local kind = action.type
        if not kind then
            if action.macro or action.trinketSlot or action.spells
               or action.resolveMacro then kind = "macro"
            elseif action.spell then kind = "spell"
            else kind = "item" end
        end

        local s = {
            action = action, kind = kind,
            col = action.col, row = action.row,
            count = -1, known = false,
        }

        local btn = CreateFrame("Button", buttonPrefix .. i, frame,
                                "SecureActionButtonTemplate")
        btn:SetSize(AB_ICON_SIZE, AB_ICON_SIZE)
        btn:RegisterForClicks("AnyUp", "AnyDown")  -- both required on Anniversary
        s.btn = btn

        -- Initial secure attributes (we are out of combat at file load). A
        -- trinketSlot with no explicit macro defaults to "/use <slot>".
        if kind == "macro" then
            s.macrotext = action.macro
                or (action.trinketSlot and ("/use " .. action.trinketSlot))
                or (action.spells and AB_SpellsMacro(action.spells))
            btn:SetAttribute("type", "macro")
            btn:SetAttribute("macrotext", s.macrotext)
        elseif kind == "spell" then
            btn:SetAttribute("type", "spell")
            btn:SetAttribute("spell", action.spell)
        else  -- item
            s.itemId   = action.id
            s.itemName = action.name
            btn:SetAttribute("type", "item")
            btn:SetAttribute("item",
                action.hideWhenEmpty and ("item:" .. (action.id or 0)) or action.name)
            if C_Item and C_Item.RequestLoadItemDataByID then
                for _, alt in ipairs(action.alternates or {}) do
                    C_Item.RequestLoadItemDataByID(alt.id)
                end
                for _, rk in ipairs(action.ranks or {}) do
                    C_Item.RequestLoadItemDataByID(rk.id)
                end
            end
        end

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if action.tooltip then
                action.tooltip(s, GameTooltip)
            elseif action.trinketSlot then
                GameTooltip:SetInventoryItem("player", action.trinketSlot)
            elseif s.kind == "item" then
                GameTooltip:SetItemByID(s.itemId)
            else
                -- Macro/spell slots: show the associated spell's tooltip when
                -- there is one (the resolved spells entry, a spell-kind spell, or
                -- the icon spell). A hand-written macro that is NOT just a single
                -- /cast (extra /use, /startattack, /targetenemy, ...) shows its
                -- macro text instead. tooltipSpell overrides either way: a name
                -- forces that spell, `false` forces the macro-text tooltip.
                local spell
                if action.tooltipSpell ~= nil then
                    spell = action.tooltipSpell
                elseif action.macro and not ExsarLogic.IsSimpleCastMacro(action.macro) then
                    spell = nil
                else
                    spell = s.activeSpell or action.spell or action.iconSpell
                end
                if not (spell and AB_ShowSpellTooltip(spell)) then
                    GameTooltip:SetText(action.name, 1, 1, 1)
                    if s.macrotext then
                        GameTooltip:AddLine(s.macrotext, 0.7, 0.7, 0.7, true)
                    end
                end
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Optional gold 1px border ring (created before slotBg so only the
        -- outer ring shows once the opaque backing covers the center).
        -- Created for the whole bar (opts.border) OR per-slot when the action
        -- declares a static `borderColor` / dynamic `resolveBorderColor` (e.g.
        -- the Devilsaur Prep slot's yellow/red warning).
        if opts.border or action.borderColor or action.resolveBorderColor then
            local c = action.borderColor
            local r, g, b, a = 1, 0.82, 0.25, 0.85
            if c then r, g, b, a = c[1] or r, c[2] or g, c[3] or b, c[4] or a end
            s.border = ExsarUI.CreateGlow(btn, r, g, b, a, 1)
        end
        local slotBg = btn:CreateTexture(nil, "BACKGROUND")
        slotBg:SetAllPoints()
        slotBg:SetColorTexture(0, 0, 0, 1.0)

        s.icon = ExsarUI.CreateIcon(btn)
        if action.icon then
            s.icon:SetTexture(action.icon)
        elseif kind == "item" then
            -- Item data may not be cached on a cold start; show the question-mark
            -- placeholder and mark unresolved so ResolveStaticIcons retries it on
            -- GET_ITEM_INFO_RECEIVED (probing the texture won't work -- the
            -- placeholder counts as a texture and would block the retry forever).
            local tex = select(10, GetItemInfo(s.itemId))
            s.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
            s.iconResolved = tex ~= nil
        else
            s.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        s.cooldown = ExsarUI.CreateSweep(btn)
        s.cooldown:EnableMouse(false)
        s.timeText = ExsarUI.CreateCountdownText(btn)

        -- Marching-ants active indicator (alternative to the glow border).
        if opts.activeAnts then
            s.dashes = ExsarUI.BuildDashes(btn, AB_ICON_SIZE, AB_DASH_COUNT, AB_DASH_BORDER_W)
        end

        s.keyText = btn:CreateFontString(nil, "OVERLAY")
        s.keyText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        s.keyText:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 1, -1)
        s.keyText:SetJustifyH("RIGHT")
        s.keyText:SetTextColor(0.9, 0.9, 0.9, 1)
        s.keyText:SetText("")

        s.countText = btn:CreateFontString(nil, "OVERLAY")
        s.countText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        s.countText:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 1, 1)
        s.countText:SetTextColor(1, 1, 0.8, 1)
        s.countText:SetText("")

        -- Out-of-range red shade (opts.rangeCheck): a translucent red wash over
        -- the whole icon when the slot's ability is out of range on an
        -- attackable target. OVERLAY sub-level -1 keeps it above the icon but
        -- below the hotkey/count text.
        if opts.rangeCheck then
            s.rangeShade = btn:CreateTexture(nil, "OVERLAY")
            s.rangeShade:SetAllPoints()
            s.rangeShade:SetColorTexture(1, 0, 0, 0.35)
            s.rangeShade:SetDrawLayer("OVERLAY", -1)
            s.rangeShade:Hide()
        end

        -- Out-of-mana blue shade (opts.manaCheck): a translucent blue wash, same
        -- placement as the range shade, shown when the slot's spell is unusable
        -- specifically for lack of mana/power. Takes precedence over the range
        -- shade (only one of the two is ever shown).
        if opts.manaCheck then
            s.manaShade = btn:CreateTexture(nil, "OVERLAY")
            s.manaShade:SetAllPoints()
            s.manaShade:SetColorTexture(0.1, 0.4, 1, 0.4)
            s.manaShade:SetDrawLayer("OVERLAY", -1)
            s.manaShade:Hide()
        end

        btn:Hide()  -- ApplyLayout shows/positions
        slots[i] = s
    end

    -- ---------- layout (protected: out of combat only) ----------
    local function ApplyLayout()
        if InCombatLockdown() then return end
        local n = #slots
        if n == 0 then
            placeholderText:Show()
            frame:SetSize(AB_ICON_SIZE + AB_PADDING * 2, AB_ICON_SIZE + AB_PADDING * 2)
            frame:Show()
            return
        end
        placeholderText:Hide()

        if layout == "horizontal" or layout == "vertical" then
            -- Single row/column; hidden slots (e.g. talent-irrelevant `spells`)
            -- are skipped and the remaining slots pack together.
            local vis = 0
            for _, s in ipairs(slots) do
                if s.hidden then
                    s.btn:Hide()
                else
                    s.btn:ClearAllPoints()
                    if layout == "horizontal" then
                        s.btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                            AB_PADDING + vis * (AB_ICON_SIZE + AB_ICON_GAP), -AB_PADDING)
                    else
                        s.btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                            AB_PADDING, -(AB_PADDING + vis * (AB_ICON_SIZE + AB_ICON_GAP)))
                    end
                    s.btn:Show()
                    vis = vis + 1
                end
            end
            if vis == 0 then placeholderText:Show(); vis = 1 end
            local long  = AB_PADDING * 2 + vis * AB_ICON_SIZE + (vis - 1) * AB_ICON_GAP
            local short = AB_ICON_SIZE + AB_PADDING * 2
            frame:SetSize(layout == "horizontal" and long or short,
                          layout == "horizontal" and short or long)

        else  -- grid, with hideWhenEmpty / groupFallback dynamic-row reflow
            local groupHasAny = {}
            for _, s in ipairs(slots) do
                if s.action.hideWhenEmpty and s.known then
                    groupHasAny[s.col .. "," .. s.row] = true
                end
            end
            local dynRow = {}
            local maxRow = 0
            for _, s in ipairs(slots) do
                if s.row and s.row > maxRow then maxRow = s.row end
            end
            for _, s in ipairs(slots) do
                local a = s.action
                if a.hideWhenEmpty and not s.known then
                    local key = s.col .. "," .. s.row
                    if a.groupFallback and not groupHasAny[key] then
                        s.btn:ClearAllPoints()
                        s.btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                            AB_PADDING + s.col * (AB_ICON_SIZE + AB_ICON_GAP),
                            -(AB_PADDING + s.row * (AB_ICON_SIZE + AB_ICON_GAP)))
                        s.btn:Show()
                    else
                        s.btn:Hide()
                    end
                else
                    local row = s.row
                    if a.hideWhenEmpty then
                        local key = s.col .. "," .. s.row
                        row = dynRow[key] or s.row
                        dynRow[key] = row + 1
                    end
                    if row > maxRow then maxRow = row end
                    s.btn:ClearAllPoints()
                    s.btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
                        AB_PADDING + s.col * (AB_ICON_SIZE + AB_ICON_GAP),
                        -(AB_PADDING + row * (AB_ICON_SIZE + AB_ICON_GAP)))
                    s.btn:Show()
                end
            end
            local rows = maxRow + 1
            local gw = gridCols * AB_ICON_SIZE + (gridCols - 1) * AB_ICON_GAP + AB_PADDING * 2
            frame:SetSize(gw, rows * AB_ICON_SIZE + (rows - 1) * AB_ICON_GAP + AB_PADDING * 2)
        end
        frame:Show()
    end

    -- ---------- static icon resolution (retried until item/spell data cached) ----------
    local function ResolveStaticIcons()
        for _, s in ipairs(slots) do
            local a = s.action
            if not s.iconResolved and (a.iconItem or a.iconSpell) then
                local tex = a.iconItem and select(10, GetItemInfo(a.iconItem))
                    or (a.iconSpell and GetSpellTexture(a.iconSpell))
                if tex then s.icon:SetTexture(tex); s.iconResolved = true end
            end
            if s.kind == "item" and not s.iconResolved then
                local tex = select(10, GetItemInfo(s.itemId))
                if tex then s.icon:SetTexture(tex); s.iconResolved = true end
            end
        end
    end

    -- ---------- talent-gated spell resolution (spells list) ----------
    -- For each `spells` slot, pick the first known spell (its icon/cooldown
    -- follow it) and hide the slot when none are known (talent-irrelevant).
    -- Spec is stable mid-session, but this is cheap and self-correcting as the
    -- spellbook loads; a hidden-state change reflows (out of combat).
    local function ResolveSpells()
        local needLayout = false
        for _, s in ipairs(slots) do
            if s.action.spells then
                local active = AB_FirstKnownSpell(s.action.spells)
                local hidden = active == nil
                if hidden ~= (s.hidden == true) then needLayout = true end
                s.hidden, s.activeSpell = hidden, active
            end
        end
        if needLayout then ApplyLayout() end
    end

    -- ---------- active-item swap (rank/alternate, protected: out of combat) ----------
    local function ResolveActiveAll()
        if InCombatLockdown() then return end
        local zone = GetRealZoneText()
        for _, s in ipairs(slots) do
            if s.kind == "item" then
                local a = s.action
                local chosen
                if a.resolveActive then
                    chosen = a.resolveActive(s)
                elseif a.ranks then
                    chosen = ExsarLogic.SelectBestRank(a.ranks, GetItemCount)
                elseif a.alternates then
                    chosen = ExsarLogic.SelectFirstInStock(
                        { id = a.id, name = a.name }, a.alternates, zone, GetItemCount)
                end
                if chosen and chosen.id ~= s.itemId then
                    s.itemId, s.itemName = chosen.id, chosen.name
                    s.btn:SetAttribute("item",
                        a.hideWhenEmpty and ("item:" .. chosen.id) or chosen.name)
                    local tex = chosen.icon or select(10, GetItemInfo(chosen.id))
                    s.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
                    s.iconResolved = tex ~= nil  -- retry via ResolveStaticIcons if cold
                    s.count = -1  -- force countText refresh
                end
            end
        end
    end

    -- ---------- re-apply protected secure attributes (on PLAYER_REGEN_ENABLED) ----------
    local function ApplyAttributes()
        if InCombatLockdown() then return end
        for _, s in ipairs(slots) do
            if s.kind == "macro" then
                s.btn:SetAttribute("macrotext", s.macrotext)
            elseif s.kind == "spell" then
                s.btn:SetAttribute("spell", s.action.spell)
            else
                s.btn:SetAttribute("item",
                    s.action.hideWhenEmpty and ("item:" .. (s.itemId or 0)) or s.itemName)
            end
        end
    end

    -- ---------- bag counts + in-stock state ----------
    local function ScanCounts()
        local needLayout = false
        for _, s in ipairs(slots) do
            local a = s.action
            local nval
            if a.getCount then
                nval = a.getCount(s) or 0
            else
                local countItem
                if a.countItem == true then countItem = s.itemId
                elseif a.countItem ~= nil then countItem = a.countItem
                elseif s.kind == "item" then countItem = s.itemId end
                if countItem then
                    local charges = a.countCharges or a.useCharges
                    nval = GetItemCount(countItem, false, charges and true or false)
                end
            end
            if nval ~= nil then
                local wasKnown = s.known
                if s.kind == "item" then s.known = nval > 0 end
                if a.hideWhenEmpty and wasKnown ~= s.known then needLayout = true end
                if nval ~= s.count then
                    s.count = nval
                    s.countText:SetText(tostring(nval))
                end
            end
        end
        if needLayout then ApplyLayout() end
    end

    -- Apply the active-state border to a slot: a dynamic resolveBorderColor
    -- override (returns {r,g,b,a} or nil to hide -- used for the Devilsaur Prep
    -- yellow/red warning) takes precedence over the default s.active gate,
    -- which lights the static gold ring.
    local function AB_ApplyBorder(s, petState)
        if not s.border then return end
        local a = s.action
        if a.resolveBorderColor then
            local rgba = a.resolveBorderColor(s, petState)
            if rgba then
                s.border:SetColorTexture(rgba[1] or 1, rgba[2] or 1,
                                         rgba[3] or 1, rgba[4] or 0.85)
                s.border:Show()
            else
                s.border:Hide()
            end
        else
            s.border:SetShown(s.active and true or false)
        end
    end

    -- Resolve the spell whose range governs a slot's out-of-range shade.
    -- Spell/`spells` slots auto-use their cast spell; macro/item slots opt in
    -- via an explicit `rangeSpell` string (or `rangeSpell = false` to suppress).
    local function AB_RangeSpell(s)
        local a = s.action
        if a.rangeSpell ~= nil then return a.rangeSpell or nil end
        if s.kind == "item" then return nil end
        return s.activeSpell or a.spell
    end

    -- Resolve the spell whose mana cost governs a slot's out-of-mana shade.
    -- Same shape as AB_RangeSpell but independent (the range spell and the
    -- mana-cost spell can differ -- e.g. the Auto Shot macro range-checks Auto
    -- Shot, which is free). Macro/item slots opt in via an explicit `manaSpell`
    -- string (or `manaSpell = false` to suppress).
    local function AB_ManaSpell(s)
        local a = s.action
        if a.manaSpell ~= nil then return a.manaSpell or nil end
        if s.kind == "item" then return nil end
        return s.activeSpell or a.spell
    end

    -- ---------- per-slot visuals (icons / cooldown / grey-out / border) ----------
    local function UpdateVisuals()
        local now = GetTime()
        local exists = UnitExists("pet")
        local petState = {
            exists = exists and true or false,
            alive  = (exists and not UnitIsDead("pet")) and true or false,
        }
        local stateKey = ExsarLogic.PetStateKey(petState)

        local gcdStart, gcdDuration = GetSpellCooldown(AB_GCD_PROBE)
        local gcdActive = gcdStart and gcdStart > 0 and gcdDuration and gcdDuration > 0

        for _, s in ipairs(slots) do
            local a = s.action

            -- Dynamic / hook icon (e.g. all-in-one pet button, or the trinket
            -- currently equipped in a tracked inventory slot).
            if a.resolveIcon then
                local tex = a.resolveIcon(s, petState)
                if tex then s.icon:SetTexture(tex) end
            elseif a.dynamicIcon then
                local tex = AB_ResolveIconSpec(a.dynamicIcon[stateKey])
                if tex then s.icon:SetTexture(tex) end
            elseif a.trinketSlot then
                local tex = GetInventoryItemTexture("player", a.trinketSlot)
                if tex then s.icon:SetTexture(tex) end
            elseif a.spells and s.activeSpell then
                local tex = GetSpellTexture(s.activeSpell)
                if tex then s.icon:SetTexture(tex) end
            end

            if s.kind == "item" then
                -- Out of stock with no debuff CD: greyed, no cooldown.
                if not s.known and not a.cooldownDebuff then
                    s.icon:SetDesaturated(true)
                    s.icon:SetAlpha(0.35)
                    s.cooldown:SetCooldown(0, 0)
                    s.timeText:SetText("")
                    s.active = false
                else
                    local start, duration
                    if a.cooldownDebuff then
                        start, duration = AB_DebuffCooldown(a.cooldownDebuff)
                    else
                        start, duration = AB_ItemCooldown(s.itemId)
                    end
                    local onCD = start and start > 0 and duration and duration > MIN_CD
                    if onCD then
                        s.icon:SetDesaturated(true)
                        s.icon:SetAlpha(0.4)
                        s.cooldown:SetCooldown(start, duration)
                        local remaining = (start + duration) - now
                        s.timeText:SetText(remaining > 0 and FormatCooldown(remaining) or "")
                    else
                        s.icon:SetDesaturated(not s.known)
                        s.icon:SetAlpha(s.known and 1.0 or 0.35)
                        s.cooldown:SetCooldown(0, 0)
                        s.timeText:SetText("")
                    end
                    s.active = s.known and true or false
                end
                AB_ApplyBorder(s, petState)

            else  -- macro / spell: greyed by a predicate, sweep from item/debuff/GCD
                local start, duration, isRealCD
                if a.getCooldown then
                    start, duration, isRealCD = a.getCooldown(s)
                else
                    if a.cooldownItem then
                        if not s.cooldownItemId then
                            s.cooldownItemId = select(1, GetItemInfoInstant(a.cooldownItem))
                        end
                        local st, dur = AB_ItemCooldown(s.cooldownItemId)
                        if ExsarLogic.CooldownState(st, dur) == "cooldown" then
                            start, duration, isRealCD = st, dur, true
                        end
                    end
                    if a.cooldownSpell then
                        local st, dur = GetSpellCooldown(a.cooldownSpell)
                        if ExsarLogic.CooldownState(st, dur) == "cooldown"
                           and (not start or (st + dur) > (start + duration)) then
                            start, duration, isRealCD = st, dur, true
                        end
                    end
                    if a.trinketSlot then
                        local st, dur = GetInventoryItemCooldown("player", a.trinketSlot)
                        if ExsarLogic.CooldownState(st, dur) == "cooldown"
                           and (not start or (st + dur) > (start + duration)) then
                            start, duration, isRealCD = st, dur, true
                        end
                    end
                    if a.cooldownTrinket then
                        local st, dur = GetInventoryItemCooldown("player", a.cooldownTrinket)
                        if ExsarLogic.CooldownState(st, dur) == "cooldown"
                           and (not start or (st + dur) > (start + duration)) then
                            start, duration, isRealCD = st, dur, true
                        end
                    end
                    if a.spells and s.activeSpell then
                        local st, dur = GetSpellCooldown(s.activeSpell)
                        if ExsarLogic.CooldownState(st, dur) == "cooldown"
                           and (not start or (st + dur) > (start + duration)) then
                            start, duration, isRealCD = st, dur, true
                        end
                    end
                    if a.cooldownDebuff then
                        local st, dur = AB_DebuffCooldown(a.cooldownDebuff)
                        if st and dur and dur > MIN_CD
                           and (not start or (st + dur) > (start + duration)) then
                            start, duration, isRealCD = st, dur, true
                        end
                    end
                    if a.gcd and gcdActive
                       and (not start or (gcdStart + gcdDuration) > (start + duration)) then
                        start, duration, isRealCD = gcdStart, gcdDuration, false
                    end
                end

                if start then
                    s.cooldown:SetCooldown(start, duration)
                    if isRealCD then
                        local remaining = (start + duration) - now
                        s.timeText:SetText(remaining > 0 and FormatCooldown(remaining) or "")
                    else
                        s.timeText:SetText("")  -- brief GCD: sweep only, no number
                    end
                else
                    s.cooldown:SetCooldown(0, 0)
                    s.timeText:SetText("")
                end

                local enabled
                if a.isEnabled then
                    enabled = a.isEnabled(s, petState) and true or false
                else
                    enabled = ExsarLogic.PetActionEnabled(a.requires, petState)
                end
                -- Grey-out priority: requirement-disabled > on-cooldown dim
                -- (opts.dimOnCooldown, real CDs only — not the brief GCD) > full.
                if not enabled then
                    s.icon:SetDesaturated(true)
                    s.icon:SetAlpha(0.35)
                elseif opts.dimOnCooldown and isRealCD then
                    s.icon:SetDesaturated(true)
                    s.icon:SetAlpha(0.4)
                else
                    s.icon:SetDesaturated(false)
                    s.icon:SetAlpha(1.0)
                end
                -- Active indicator: highlight the slot only when it defines an
                -- "active" predicate -- a player buff is up (activeBuff, e.g. the
                -- current aspect) or isActive(s) returns true (e.g. the equipped
                -- weapon). Slots with no predicate never highlight. Drives both
                -- the glow border and the marching-ants (s.active).
                local active
                if a.isActive then active = a.isActive(s, petState) and true or false
                elseif a.activeBuff then active = AB_PlayerHasBuff(a.activeBuff)
                else active = false end
                s.active = active
                AB_ApplyBorder(s, petState)

                -- Stage-dependent macrotext (e.g. Devilsaur Prep: equip vs
                -- use+swap depending on whether the Tooth is in slot 13 yet).
                -- Setting macrotext is protected, so combat-defer via
                -- ExsarUI.SecureSetAttribute. Only writes when the text
                -- changes so we don't flood the queue.
                if a.resolveMacro then
                    local text = a.resolveMacro(s, petState)
                    if text and text ~= s.macrotext then
                        s.macrotext = text
                        ExsarUI.SecureSetAttribute(s.btn, "macrotext", text)
                    end
                end
            end

            -- Out-of-mana blue shade (item slots have no mana spell so they
            -- never shade). Computed first because it takes PRECEDENCE over the
            -- range shade: when a slot is both out of range and out of mana, the
            -- blue (mana) wash is the more actionable signal, so it wins.
            local manaShow = false
            if s.manaShade then
                local spell = AB_ManaSpell(s)
                if spell then
                    local _, noMana = IsUsableSpell(spell)
                    manaShow = ExsarLogic.ShouldShowManaShade(noMana)
                end
                s.manaShade:SetShown(manaShow)
            end

            -- Out-of-range red shade (applies to both kinds; item slots have no
            -- range spell so they never shade). The range UNIT is per-slot:
            -- "target" by default (harm spells, and friendly-target spells like
            -- Misdirection), or `rangeUnit` (e.g. "pet" for Mend/Feed Pet).
            -- IsSpellInRange returns nil when the spell can't act on that unit,
            -- so a harm spell against a friendly target (or vice versa) never
            -- shades -- no attackable-only gate needed here. Suppressed while the
            -- mana shade is up (mana precedence).
            if s.rangeShade then
                local show = false
                local spell = AB_RangeSpell(s)
                if spell and not manaShow then
                    local unit = s.action.rangeUnit or "target"
                    local valid = UnitExists(unit) and not UnitIsDead(unit)
                    show = ExsarLogic.ShouldShowRangeShade(
                        IsSpellInRange(spell, unit), valid and true or false)
                end
                s.rangeShade:SetShown(show)
            end
        end
    end

    local function Refresh()
        ResolveStaticIcons()
        ResolveSpells()
        ResolveActiveAll()
        ScanCounts()
        UpdateVisuals()
    end

    ExsarUI.CreatePoller(frame, opts.pollInterval or 0.1, Refresh)

    -- Marching-ants active indicator: smooth per-frame animation on a dedicated
    -- always-on ticker (each slot's s.active is refreshed by the poll/UNIT_AURA;
    -- inactive slots get their dashes zeroed since the button stays shown).
    if opts.activeAnts then
        local antTicker = CreateFrame("Frame")
        antTicker:SetScript("OnUpdate", function()
            ExsarUI.AnimateDashes(slots, GetTime(), AB_DASH_SPEED, AB_DASH_COUNT, AB_DASH_TAIL)
            for _, s in ipairs(slots) do
                if not s.active then
                    for _, d in ipairs(s.dashes) do d:SetAlpha(0) end
                end
            end
        end)
    end

    -- ---------- events ----------
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:RegisterEvent("SPELLS_CHANGED")
    frame:RegisterEvent("BAG_UPDATE")
    frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
    frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    frame:RegisterEvent("UNIT_PET")
    frame:RegisterEvent("UNIT_AURA")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    for _, ev in ipairs(opts.extraEvents or {}) do frame:RegisterEvent(ev) end

    frame:SetScript("OnEvent", function(self, event, arg1)
        if event == "ADDON_LOADED" then
            if arg1 ~= ADDON_NAME then return end
            ExsarUI.RestorePosition(self, dbFunc, defaultX, defaultY)
            ApplyAttributes()
            ApplyLayout()
            Refresh()
        elseif event == "PLAYER_ENTERING_WORLD" then
            ApplyLayout()
            Refresh()
        elseif event == "PLAYER_REGEN_ENABLED" then
            ApplyAttributes()
            ResolveActiveAll()
            ApplyLayout()
            Refresh()
        elseif event == "UNIT_PET" or event == "UNIT_AURA" then
            if arg1 == "player" then Refresh() end
        else
            Refresh()
        end
    end)

    -- ---------- keybindings ----------
    if opts.bindingHeaderGlobal and opts.bindingHeaderText then
        _G[opts.bindingHeaderGlobal] = opts.bindingHeaderText
    end
    if opts.bindingPrefix then
        local bindingCount = opts.bindingCount or #actions
        for i = 1, bindingCount do
            local a = actions[i]
            _G["BINDING_NAME_" .. opts.bindingPrefix .. i] =
                (a and (a.bindingLabel or a.name))
                or ((opts.placeholder or "Bar") .. " Action " .. i)
        end

        ExsarUI.SetupKeybindBridge({
            owner         = frame,
            bindingPrefix = opts.bindingPrefix,
            buttonPrefix  = buttonPrefix,
            count         = #slots,
            onSlotKey     = function(index, key)
                local s = slots[index]
                if s then s.keyText:SetText(ExsarLogic.AbbreviateBindingKey(key) or "") end
            end,
        })
    end

    -- ---------- slash reset + config + module registration ----------
    if opts.slashReset then
        ExsarUI.AddSlashReset(opts.slashReset, frame, dbFunc,
            opts.configName or opts.moduleName or opts.name, defaultX, defaultY)
    end

    ExsarAddon.RegisterModule({
        name = opts.moduleName or opts.name,
        BuildConfig = function(parent, y)
            y = ExsarUI.AddScaleSlider(parent, y, dbFunc, frame)
            y = ExsarUI.AddLockCheckbox(parent, y, dbFunc, frame, function() ApplyLayout() end)
            y = ExsarUI.AddResetButton(parent, y, dbFunc, frame,
                opts.configName or opts.moduleName or opts.name, defaultX, defaultY)
            return y
        end,
    })

    return { frame = frame, slots = slots, Refresh = Refresh,
             ApplyLayout = ApplyLayout, dbFunc = dbFunc }
end
