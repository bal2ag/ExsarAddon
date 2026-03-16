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
