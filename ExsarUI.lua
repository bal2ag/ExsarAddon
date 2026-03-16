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
-- @param parentFrame  the icon frame
-- @param r, g, b, a   glow color (defaults to gold)
-- @param size          pixels to extend beyond the icon edge (default 4)
function ExsarUI.CreateGlow(parentFrame, r, g, b, a, size)
    size = size or 4
    local glow = parentFrame:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("TOPLEFT",     parentFrame, "TOPLEFT",     -size,  size)
    glow:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT",  size, -size)
    glow:SetColorTexture(r or 1, g or 0.85, b or 0, a or 0.22)
    glow:Hide()
    return glow
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
