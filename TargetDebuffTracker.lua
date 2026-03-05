-- TargetDebuffTracker module
-- Shows icons with a marching-ants yellow border and countdown timer for
-- tracked debuffs currently active on the player's target.
-- Single-column vertical layout; only shows debuffs that are present.
-- Settings stored under ExsarAddonDB.targetDebuffs.

local ADDON_NAME = "ExsarAddon"

local function tDB()
    ExsarAddonDB.targetDebuffs = ExsarAddonDB.targetDebuffs or {}
    return ExsarAddonDB.targetDebuffs
end

-- =========================================================
-- Debuff definitions
-- =========================================================
-- Each entry: { name = "Debuff Name", id = spellId }
-- Detection tries spell ID first, then falls back to name.
-- Set id = nil to match by name only (catches all ranks).

local TRACKED_DEBUFFS = {
    { name = "Hunter's Mark", id = nil },
    { name = "Serpent Sting", id = nil },
}

-- =========================================================
-- Layout constants
-- =========================================================

local ICON_SIZE  = 29
local ICON_GAP   = 4
local PADDING    = 6

-- Marching-ants border
local BORDER_W   = 2     -- border thickness in pixels
local DASH_COUNT = 16    -- total dashes around the perimeter (4 per side)
local DASH_SPEED = 1.5   -- full rotations per second
local TAIL_LEN   = 5     -- dashes in the bright trailing tail

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "TargetDebuffFrame", UIParent)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    tDB().x = x
    tDB().y = y
end)

local frameBg = frame:CreateTexture(nil, "BACKGROUND")
frameBg:SetAllPoints()
frameBg:SetColorTexture(0, 0, 0, 0.6)

local placeholderText = frame:CreateFontString(nil, "OVERLAY")
placeholderText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
placeholderText:SetPoint("CENTER", frame, "CENTER", 0, 0)
placeholderText:SetTextColor(0.55, 0.55, 0.55, 0.9)
placeholderText:SetText("Debuffs")
placeholderText:Hide()

frame:Hide()

local C_locked = false

-- =========================================================
-- Icon slot construction
-- =========================================================

local function BuildDashes(iconFrame)
    local dashes  = {}
    local perSide = DASH_COUNT / 4
    local step    = ICON_SIZE / perSide
    local dashLen = step - 1

    for i = 0, DASH_COUNT - 1 do
        local side   = math.floor(i / perSide)
        local pos    = i % perSide
        local offset = pos * step

        local d = iconFrame:CreateTexture(nil, "OVERLAY")
        d:SetColorTexture(1, 0.85, 0, 1)
        d:SetAlpha(0)

        if side == 0 then      -- top, left → right
            d:SetSize(dashLen, BORDER_W)
            d:SetPoint("TOPLEFT",     iconFrame, "TOPLEFT",     offset, 0)
        elseif side == 1 then  -- right, top → bottom
            d:SetSize(BORDER_W, dashLen)
            d:SetPoint("TOPRIGHT",    iconFrame, "TOPRIGHT",    0, -offset)
        elseif side == 2 then  -- bottom, right → left
            d:SetSize(dashLen, BORDER_W)
            d:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", -offset, 0)
        else                   -- left, bottom → top
            d:SetSize(BORDER_W, dashLen)
            d:SetPoint("BOTTOMLEFT",  iconFrame, "BOTTOMLEFT",  0, offset)
        end

        dashes[i + 1] = d
    end
    return dashes
end

local function MakeSlot()
    local s = {
        active  = false,
        expTime = 0,
        name    = nil,
        id      = nil,
    }

    s.iconFrame = CreateFrame("Frame", nil, frame)
    s.iconFrame:SetSize(ICON_SIZE, ICON_SIZE)

    -- Outer yellow glow (extends ~4 px beyond icon on each side)
    s.glow = s.iconFrame:CreateTexture(nil, "BACKGROUND")
    s.glow:SetPoint("TOPLEFT",     s.iconFrame, "TOPLEFT",     -4,  4)
    s.glow:SetPoint("BOTTOMRIGHT", s.iconFrame, "BOTTOMRIGHT",  4, -4)
    s.glow:SetColorTexture(1, 0.85, 0, 0.22)
    s.glow:Hide()

    -- Spell icon
    s.icon = s.iconFrame:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints()
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Reverse cooldown sweep: grey fills the icon as the debuff expires
    s.sweep = CreateFrame("Cooldown", nil, s.iconFrame, "CooldownFrameTemplate")
    s.sweep:SetAllPoints()
    s.sweep:SetDrawEdge(false)
    if s.sweep.SetHideCountdownNumbers then
        s.sweep:SetHideCountdownNumbers(true)
    end
    if s.sweep.SetReverse then
        s.sweep:SetReverse(true)
    end

    -- Marching-ants border dashes
    s.dashes = BuildDashes(s.iconFrame)

    -- Countdown timer text
    s.text = s.iconFrame:CreateFontString(nil, "OVERLAY")
    s.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    s.text:SetPoint("CENTER", s.iconFrame, "CENTER", 0, 0)
    s.text:SetTextColor(1, 1, 1, 1)
    s.text:SetText("")

    s.iconFrame:Hide()
    return s
end

local slots = {}
for _, debuff in ipairs(TRACKED_DEBUFFS) do
    local s = MakeSlot()
    s.name = debuff.name
    s.id   = debuff.id
    slots[#slots + 1] = s
end

-- =========================================================
-- Layout
-- =========================================================

local function ApplyLayout()
    local yOffset  = PADDING
    local anyShown = false

    for _, s in ipairs(slots) do
        if s.active then
            s.iconFrame:ClearAllPoints()
            s.iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -yOffset)
            s.iconFrame:Show()
            yOffset = yOffset + ICON_SIZE + ICON_GAP
            anyShown = true
        else
            s.iconFrame:Hide()
        end
    end

    if anyShown then
        frame:SetSize(ICON_SIZE + PADDING * 2, yOffset - ICON_GAP + PADDING)
        placeholderText:Hide()
        frame:Show()
    elseif not C_locked then
        frame:SetSize(ICON_SIZE + PADDING * 2, 40)
        placeholderText:Show()
        frame:Show()
    else
        placeholderText:Hide()
        frame:Hide()
    end
end

-- =========================================================
-- Debuff scanning
-- =========================================================

local lastTimeStrs = {}

local function UpdateDebuffs()
    local now = GetTime()

    -- Build lookup tables from the target's current debuffs
    local byId   = {}
    local byName = {}
    if UnitExists("target") then
        for i = 1, 40 do
            local bName, bIcon, _, _, bDuration, bExpTime, _, _, _, bSpellId =
                UnitDebuff("target", i)
            if not bName then break end
            if bSpellId and bSpellId > 0 then
                byId[bSpellId] = { icon = bIcon, expTime = bExpTime or 0, duration = bDuration or 0 }
            end
            if not byName[bName] then
                byName[bName] = { icon = bIcon, expTime = bExpTime or 0, duration = bDuration or 0 }
            end
        end
    end

    local layoutChanged = false

    for i, s in ipairs(slots) do
        local match
        if s.id   then match = byId[s.id]     end
        if not match and s.name then match = byName[s.name] end

        local wasActive = s.active

        if match then
            s.active  = true
            s.expTime = match.expTime
            s.icon:SetTexture(match.icon)
            s.glow:Show()

            if match.expTime > 0 and match.duration and match.duration > 0 then
                s.sweep:SetCooldown(match.expTime - match.duration, match.duration)
            else
                s.sweep:SetCooldown(0, 0)
            end

            local remaining = s.expTime > 0 and math.max(0, s.expTime - now) or nil
            local newStr
            if not remaining then
                newStr = ""
            elseif remaining >= 60 then
                newStr = string.format("%dm", math.floor(remaining / 60))
            elseif remaining >= 10 then
                newStr = string.format("%d", math.ceil(remaining))
            else
                newStr = string.format("%.1f", remaining)
            end
            if newStr ~= lastTimeStrs[i] then
                lastTimeStrs[i] = newStr
                s.text:SetText(newStr)
            end
        else
            s.active = false
            s.icon:SetTexture(nil)
            s.sweep:SetCooldown(0, 0)
            s.glow:Hide()
            s.text:SetText("")
            lastTimeStrs[i] = ""
        end

        if s.active ~= wasActive then layoutChanged = true end
    end

    if layoutChanged then ApplyLayout() end
end

-- =========================================================
-- Marching-ants animation (runs every frame via animTicker)
-- =========================================================

local function AnimateDashes()
    local head = (GetTime() * DASH_SPEED * DASH_COUNT) % DASH_COUNT
    for _, s in ipairs(slots) do
        if s.active then
            for j, d in ipairs(s.dashes) do
                local dist = (head - (j - 1) + DASH_COUNT) % DASH_COUNT
                if dist < TAIL_LEN then
                    d:SetAlpha(1.0 - (dist / TAIL_LEN) * 0.85)
                else
                    d:SetAlpha(0)
                end
            end
        end
    end
end

-- Dedicated always-on frame for smooth dash animation.
local animTicker = CreateFrame("Frame")
animTicker:Show()
animTicker:SetScript("OnUpdate", function() AnimateDashes() end)

-- =========================================================
-- OnUpdate: debuff state + timer text (every 0.1 s)
-- =========================================================

local scanElapsed = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    scanElapsed = scanElapsed + elapsed
    if scanElapsed >= 0.1 then
        scanElapsed = 0
        UpdateDebuffs()
    end
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        local db = tDB()
        if db.x and db.y then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        else
            self:SetPoint("CENTER", UIParent, "CENTER", -300, 100)
        end
        self:SetScale(db.scale or 1.0)
        self:EnableMouse(not db.locked)
        C_locked = db.locked and true or false
        ApplyLayout()

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateDebuffs()

    elseif event == "UNIT_AURA" then
        if arg1 == "target" then UpdateDebuffs() end

    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateDebuffs()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("debuffsreset", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", -300, 100)
    tDB().x = nil
    tDB().y = nil
    print(ADDON_NAME .. ": Target debuff tracker position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Target Debuff Tracker",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return tDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                tDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return tDB().locked and true or false end,
            function(v)
                tDB().locked = v
                C_locked = v
                frame:EnableMouse(not v)
                ApplyLayout()
            end
        )
        y = y - 30

        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", -300, 100)
            tDB().x = nil
            tDB().y = nil
            print(ADDON_NAME .. ": Target debuff tracker position reset.")
        end)
        y = y - 30

        return y
    end,
})
