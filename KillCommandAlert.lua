-- KillCommandAlert module
-- Shows glowing eagle-wing crescents flanking the player when Kill Command is
-- usable (proc active + not on cooldown).
-- Settings are stored under ExsarAddonDB.killCommandAlert.

local ADDON_NAME = "ExsarAddon"

local function kcDB()
    ExsarAddonDB.killCommandAlert = ExsarAddonDB.killCommandAlert or {}
    return ExsarAddonDB.killCommandAlert
end

-- =========================================================
-- Constants
-- =========================================================

local MIN_COOLDOWN = 1.6    -- durations ≤ this are just the GCD, not a real cooldown

-- Wing feather definitions for the RIGHT wing.
-- Each entry: {sx, sy, ex, ey} — start (inner/root) and end (outer tip),
-- all in pixels relative to the parent frame's CENTER.
-- The left wing mirrors these by negating all X values.
-- Feathers fan from the upper-right to the lower-right, forming a crescent arc.
local FEATHER_DEFS = {
    { sx = 45,  sy = 15,  ex = 80,  ey = 115 },  -- top feather (sweeps upward)
    { sx = 47,  sy = 10,  ex = 113, ey = 88  },
    { sx = 49,  sy = 6,   ex = 133, ey = 58  },
    { sx = 50,  sy = 0,   ex = 143, ey = 20  },  -- widest (horizontal span)
    { sx = 49,  sy = -6,  ex = 137, ey = -22 },
    { sx = 47,  sy = -10, ex = 120, ey = -60 },
    { sx = 45,  sy = -15, ex = 87,  ey = -95 },  -- bottom feather (sweeps downward)
}

local CORE_THICKNESS = 8    -- sharp inner line per feather
local GLOW_THICKNESS = 22   -- wider, softer halo duplicate

-- =========================================================
-- Runtime state
-- =========================================================

local K = {
    active      = false,
    pulseTime   = 0,
    killCmdName = "Kill Command",
}

-- =========================================================
-- Frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "KillCmdAuraFrame", UIParent)
frame:SetSize(300, 300)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    kcDB().x = x
    kcDB().y = y
end)
frame:Hide()

-- =========================================================
-- Wing visuals
-- =========================================================

-- Create all feather lines for one wing.  sign=1 for right wing, sign=-1 for left.
local function BuildWing(sign)
    for _, d in ipairs(FEATHER_DEFS) do
        -- Outer glow line (wide, soft)
        local gl = frame:CreateLine(nil, "ARTWORK")
        gl:SetStartPoint("CENTER", frame, d.sx * sign, d.sy)
        gl:SetEndPoint(  "CENTER", frame, d.ex * sign, d.ey)
        gl:SetThickness(GLOW_THICKNESS)
        gl:SetColorTexture(0.85, 0.10, 0.05, 0.12)

        -- Core line (narrow, bright)
        local cl = frame:CreateLine(nil, "OVERLAY")
        cl:SetStartPoint("CENTER", frame, d.sx * sign, d.sy)
        cl:SetEndPoint(  "CENTER", frame, d.ex * sign, d.ey)
        cl:SetThickness(CORE_THICKNESS)
        cl:SetColorTexture(1, 0.20, 0.15, 0.60)
    end
end

BuildWing( 1)   -- right wing
BuildWing(-1)   -- left wing (mirrored)

-- =========================================================
-- Readiness check
-- =========================================================

local function IsReady()
    -- Require a live, active pet.
    if not UnitExists("pet") or UnitIsDead("pet") then return false end
    -- IsUsableSpell: true when the Kill Command proc is active (crit scored).
    -- GetSpellCooldown: guards against IsUsableSpell returning true while
    -- the 1-minute cooldown is still running after a cast.
    local isUsable = IsUsableSpell(K.killCmdName)
    if not isUsable then return false end
    local _, duration = GetSpellCooldown(K.killCmdName)
    return duration == nil or duration <= MIN_COOLDOWN
end

local function UpdateAura()
    local ready = IsReady() and UnitAffectingCombat("player")
    K.active = ready
    local shouldShow = ready or not kcDB().locked
    if shouldShow then
        if not frame:IsShown() then
            K.pulseTime = 0.25   -- start at the sine peak so it lights up immediately
        end
        frame:Show()
    else
        frame:Hide()
    end
end

-- =========================================================
-- OnUpdate: pulse animation
-- =========================================================
-- Animates the frame alpha so all children pulse together without needing to
-- iterate each line every frame.

frame:SetScript("OnUpdate", function(self, elapsed)
    K.pulseTime = K.pulseTime + elapsed
    -- Sine wave at ~0.8 Hz; alpha oscillates between 0.65 and 1.0
    local pulse = 0.825 + 0.175 * math.sin(K.pulseTime * 2 * math.pi * 0.8)
    frame:SetAlpha(pulse)
end)

-- =========================================================
-- Safety-net poll (catches pet death / missed cooldown events)
-- =========================================================

local pollFrame   = CreateFrame("Frame")
local pollElapsed = 0
pollFrame:SetScript("OnUpdate", function(self, elapsed)
    pollElapsed = pollElapsed + elapsed
    if pollElapsed < 0.5 then return end
    pollElapsed = 0
    UpdateAura()
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("SPELL_UPDATE_USABLE")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
frame:RegisterEvent("UNIT_PET")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        local db = kcDB()
        if db.x and db.y then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        else
            self:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
        end
        self:SetScale(db.scale or 1.0)
        self:EnableMouse(not db.locked)
        if not db.locked then
            K.pulseTime = 0.25
            frame:Show()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        K.killCmdName = GetSpellInfo("Kill Command") or "Kill Command"
        UpdateAura()

    elseif event == "SPELL_UPDATE_USABLE" or event == "SPELL_UPDATE_COOLDOWN" then
        UpdateAura()

    elseif event == "UNIT_PET" then
        if arg1 == "player" then UpdateAura() end

    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        UpdateAura()
    end
end)

-- =========================================================
-- Slash sub-command
-- =========================================================

ExsarAddon.AddSlashCommand("killcmdreset", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    kcDB().x = nil
    kcDB().y = nil
    print(ADDON_NAME .. ": Kill Command alert position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Kill Command Alert",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return kcDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                kcDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return kcDB().locked and true or false end,
            function(v)
                kcDB().locked = v
                frame:EnableMouse(not v)
                UpdateAura()
            end
        )
        y = y - 30

        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
            kcDB().x = nil
            kcDB().y = nil
            print(ADDON_NAME .. ": Kill Command alert position reset.")
        end)
        y = y - 30

        return y
    end,
})
