-- RotationHelper module
-- Shows the current effective weapon speed and suggested rotation.
-- Two lines of text: speed on top (e.g. "1.23s"), rotation below (e.g. "1:1").
--
-- Haste effects. Crossing a rotation threshold is the single most important thing
-- this widget has to say, and a two-character text swap is easy to miss mid-fight.
-- So each faster rotation adds a progressively more intense visual: a MAELSTROM of
-- swirls cascading inward into the widget (ExsarUI.CreateMaelstromEffect — the
-- widget is the black hole, its outline the event horizon) plus a pulse on the
-- rotation text.
--
--   "5:6:1:1"  tier 0  no effect (the baseline rotation)
--   "1:1"      tier 1  slow blue drift
--   "2:3"      tier 2  twice the rate, yellow, heavier text
--   "1:2"      tier 3  full tilt, hot orange, boldest text
--
-- The SHAPE is identical at every tier — same arms, same trail, same spiral, same
-- footprint — and so is OPACITY, near enough (every tier must be plainly legible;
-- see the tier table in ExsarLogic). What escalates is rate, colour, stamp size,
-- glow, pulse rate and the rotation text's own weight. A tier change should read
-- as "the same maelstrom, spun up", never as a different picture.
--
-- Tier lookup and the per-tier parameters are pure (ExsarLogic.RotationHasteTier /
-- MaelstromTierParams), so the escalation is unit-tested and the thresholds stay
-- owned by ExsarLogic.SuggestRotation.
--
-- Settings stored under ExsarAddonDB.rotationHelper.

local ADDON_NAME = "ExsarAddon"

local rDB = ExsarUI.MakeDB("rotationHelper")

-- =========================================================
-- Constants
-- =========================================================

local FRAME_W = 56
local FRAME_H = 34
local PADDING = 4

-- Event horizon of the maelstrom: the widget's half-extents plus a small margin.
-- Swirls spawn outside it and are swallowed as they reach it, so nothing is ever
-- drawn over the text (the effect spans MAELSTROM_REACH times these radii).
local HORIZON_RX = FRAME_W / 2 + 8
local HORIZON_RY = FRAME_H / 2 + 6

local BASE_ROT_COLOR = { 1.00, 0.82, 0.00 }  -- the plain gold used at tier 0
local WHITE          = { 1.00, 1.00, 1.00 }

-- Rotation-text face. Each tier swaps in a heavier/larger one (from the tier
-- params) so the number itself escalates alongside the maelstrom; tier 0 is this
-- baseline. FRIZQT__ has no separate bold cut, so weight comes from the outline
-- flag -- OUTLINE -> THICKOUTLINE is the usable "bolder" axis in WoW.
local ROT_FONT         = "Fonts\\FRIZQT__.TTF"
local BASE_FONT_SIZE   = 13
local BASE_FONT_FLAGS  = "OUTLINE"

local SOFT_DOT = "Interface\\GLUES\\MODELS\\UI_Tauren\\gradientCircle"

-- Tier previewed while the widget is unlocked and the live rotation has no effect
-- of its own, so the swirl's real footprint is visible for positioning.
local PREVIEW_TIER = 1

-- Depth of the effect (index into ExsarLogic.STRATA_ORDER). The maelstrom is a
-- UIParent child, so it has its OWN strata rather than inheriting this widget's --
-- at the default MEDIUM it ends up buried under any neighbouring widget, so it
-- ships at HIGH. Configurable because which widgets sit nearby is per-layout.
local DEFAULT_LAYER = 4   -- "HIGH"

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "RotationHelperFrame", UIParent)
frame:SetSize(FRAME_W, FRAME_H)
local movableBg = ExsarUI.SetupMovableFrame(frame, rDB)
frame:Show()

local placeholderText = ExsarUI.CreatePlaceholder(frame, "Rot")

-- =========================================================
-- Text elements
-- =========================================================

-- Speed text (top line). Deliberately left plain white through every tier — the
-- pulse is on the rotation line, and an unpulsed neighbour keeps it legible.
local speedText = frame:CreateFontString(nil, "OVERLAY")
speedText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
speedText:SetPoint("TOP", frame, "TOP", 0, -PADDING)
speedText:SetTextColor(0.9, 0.9, 0.9, 1)

-- Rotation text (bottom line, larger/bolder). The haste pulse is applied to THIS
-- string and nothing else — an earlier version put an additive glow blob and a
-- THICKOUTLINE halo copy behind it, and both read as a distracting coloured smear
-- sitting behind the number rather than as the text itself glowing. Pulse the
-- glyphs, don't light up the space around them.
local rotText = frame:CreateFontString(nil, "OVERLAY")
rotText:SetFont(ROT_FONT, BASE_FONT_SIZE, BASE_FONT_FLAGS)
rotText:SetPoint("TOP", speedText, "BOTTOM", 0, -1)
rotText:SetTextColor(BASE_ROT_COLOR[1], BASE_ROT_COLOR[2], BASE_ROT_COLOR[3], 1)

-- =========================================================
-- State
-- =========================================================

local S = {
    speed    = 0,
    lastRot  = "",
    locked   = false,
    tier     = 0,     -- live tier from the current rotation
    override = nil,   -- /exsar rotfx forced tier (0..3), nil = auto
    active   = false, -- a readable ranged speed, i.e. the widget has content
}

-- =========================================================
-- Effect settings
-- =========================================================

local function EffectsEnabled()  return rDB().effects   ~= false end
local function TextPulseEnabled() return rDB().textPulse ~= false end

local function NumSetting(key, default)
    local v = rDB()[key]
    return (type(v) == "number" and v > 0) and v or default
end

--- The tier the effect should render at right now.
-- A /exsar rotfx override wins outright (that is the whole point of the debug
-- command). Otherwise an unlocked widget always previews something so the swirl
-- can be positioned, and a locked one shows only what the live rotation earns.
local function ActiveTier()
    if not EffectsEnabled() then return 0 end
    if S.override then return S.override end
    if not rDB().locked then
        return S.tier > 0 and S.tier or PREVIEW_TIER
    end
    if not S.active then return 0 end
    return S.tier
end

-- Params are read every frame by both the ring and the text pulse, so memoize on
-- the inputs: the table is rebuilt only when the tier or a slider actually moves,
-- never once per frame.
local function Params()
    local tier = ActiveTier()
    local im   = NumSetting("fxIntensity", 1)
    local sm   = NumSetting("fxSpeed", 1)
    if tier ~= S.pTier or im ~= S.pIm or sm ~= S.pSm then
        S.pTier, S.pIm, S.pSm = tier, im, sm
        S.params = ExsarLogic.MaelstromTierParams(tier, im, sm)
    end
    return S.params
end

-- =========================================================
-- Maelstrom ring
-- =========================================================
-- Lives on its own UIParent-child frame anchored here (so it is unaffected by the
-- widget's own scale — hence getScale) and reads Params() live, so config sliders
-- and /exsar rotfx apply on the next frame with no reload.

local maelstrom = ExsarUI.CreateMaelstromEffect(frame, {
    getParams  = Params,
    getScale   = function() return rDB().scale or 1 end,
    radiusX    = HORIZON_RX,
    radiusY    = HORIZON_RY,
    dotTexture = SOFT_DOT,
})

local function LayerIndex()
    return select(2, ExsarLogic.StrataForLevel(NumSetting("fxLayer", DEFAULT_LAYER)))
end

-- Push the saved depth onto the effect. Cannot run at construction (the DB is not
-- readable until ADDON_LOADED), so it is applied from there and from the slider.
local function ApplyLayer()
    maelstrom:SetStrata((ExsarLogic.StrataForLevel(NumSetting("fxLayer", DEFAULT_LAYER))))
end

-- =========================================================
-- Text pulse
-- =========================================================

-- Tracks whether the pulse has actually touched the text, so the every-frame
-- "nothing to pulse" path costs one boolean test instead of a redundant write.
-- The construction-time colour above already IS the cleared state, so starting at
-- false is correct.
local textEffectOn = false

-- SetFont is comparatively expensive and re-lays out the string, so only call it
-- when the face actually changes (a tier flip), never on the per-frame pulse.
local curFontSize, curFontFlags = BASE_FONT_SIZE, BASE_FONT_FLAGS
local function ApplyFont(size, flags)
    if size == curFontSize and flags == curFontFlags then return end
    curFontSize, curFontFlags = size, flags
    rotText:SetFont(ROT_FONT, size, flags)
end

local function ClearTextEffect()
    if not textEffectOn then return end
    rotText:SetTextColor(BASE_ROT_COLOR[1], BASE_ROT_COLOR[2], BASE_ROT_COLOR[3], 1)
    ApplyFont(BASE_FONT_SIZE, BASE_FONT_FLAGS)
    textEffectOn = false
end

-- Drive the rotation text's emphasis from the same tier params as the maelstrom,
-- so the two escalate together. Everything happens on the glyphs themselves --
-- nothing is drawn behind them (see the note at rotText):
--   * WEIGHT / SIZE step up per tier (OUTLINE -> THICKOUTLINE, 14 -> 15 -> 17pt),
--     a static emphasis that reads even at a glance mid-cast;
--   * COLOUR pulses from the tier colour toward white at each crest -- a colour
--     pulse survives a busy background far better than alpha alone -- with a light
--     alpha dip underneath it for the breathing.
local function UpdateTextEffect()
    local p = Params()
    if not p or not TextPulseEnabled() or not rotText:IsShown() then
        ClearTextEffect()
        return
    end

    ApplyFont(p.fontSize, p.fontFlags)

    local a = ExsarLogic.PulseAlpha(GetTime(), p.pulseFreq, p.pulseMin, 1)
    local span = 1 - p.pulseMin
    local t = span > 0 and ((a - p.pulseMin) / span) or 1

    local r, g, b = ExsarLogic.LerpColor(p.color, WHITE, t * 0.75)
    rotText:SetTextColor(r, g, b, 0.80 + 0.20 * t)

    textEffectOn = true
end

-- =========================================================
-- Update
-- =========================================================

local function UpdateDisplay()
    local speed = select(1, UnitRangedDamage("player"))
    S.speed = (type(speed) == "number" and speed > 0) and speed or 0

    if S.speed <= 0 then
        S.active = false
        S.tier = 0
        -- Clear the cached rotation too: without this, a weapon re-equip landing
        -- on the SAME rotation would skip the refresh below and strand tier 0.
        S.lastRot = ""
        speedText:Hide()
        rotText:Hide()
        ClearTextEffect()
        if not S.locked then
            placeholderText:Show()
            movableBg:Show()
            frame:Show()
        else
            frame:Hide()
        end
        return
    end

    S.active = true
    placeholderText:Hide()
    movableBg:Hide()
    frame:Show()

    speedText:SetText(string.format("%.2fs", S.speed))
    speedText:Show()

    -- The 1s poll re-runs this constantly, so only touch the string when the
    -- rotation actually changes.
    local rot = ExsarLogic.SuggestRotation(S.speed)
    if rot ~= S.lastRot then
        S.lastRot = rot
        S.tier = ExsarLogic.RotationHasteTier(rot)
        rotText:SetText(rot)
    end
    rotText:Show()
end

-- =========================================================
-- Polling fallback: UnitRangedDamage can lag behind events
-- (e.g. Rapid Fire fading reports stale speed on UNIT_AURA).
-- Poll every 1s as a cheap safety net.
--
-- The text pulse rides the same OnUpdate but runs every frame (three colour
-- writes, negligible) so it breathes smoothly rather than stepping at 1 Hz.
-- =========================================================

local pollElapsed = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    UpdateTextEffect()
    pollElapsed = pollElapsed + elapsed
    if pollElapsed < 1 then return end
    pollElapsed = 0
    UpdateDisplay()
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("UNIT_ATTACK_SPEED")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("BAG_UPDATE")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, rDB, 0, -250)
        S.locked = rDB().locked and true or false
        ApplyLayer()
        UpdateDisplay()

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateDisplay()

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then
            UpdateDisplay()
        end

    elseif event == "UNIT_ATTACK_SPEED" then
        if arg1 == "player" then
            UpdateDisplay()
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "BAG_UPDATE" then
        UpdateDisplay()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarUI.AddSlashReset("rotreset", frame, rDB, "Rotation helper", 0, -250)

local function TierLabel(tier)
    if tier == 1 then return "1 (1:1, slow blue)" end
    if tier == 2 then return "2 (2:3, faster yellow)" end
    if tier == 3 then return "3 (1:2, full-tilt orange)" end
    return "0 (5:6:1:1, no effect)"
end

-- Force a haste tier so the effect can be judged without gearing/buffing into it.
-- The override outranks everything (including a locked widget), which is what
-- makes it useful for tuning; "auto" hands control back to the live rotation.
ExsarAddon.AddSlashCommand("rotfx", function(arg)
    arg = arg and arg:match("^%s*(%S*)") or ""

    if arg == "auto" or arg == "off" or arg == "clear" then
        S.override = nil
        print(ADDON_NAME .. ": rotation effect back to AUTO — live tier "
            .. TierLabel(S.tier) .. ".")
        return
    end

    local n = tonumber(arg)
    if n and n >= 0 and n <= 3 then
        S.override = math.floor(n)
        print(ADDON_NAME .. ": rotation effect forced to tier " .. TierLabel(S.override)
            .. ". Use '/exsar rotfx auto' to release it.")
        return
    end

    print(ADDON_NAME .. ": rotation effect — live tier " .. TierLabel(S.tier)
        .. (S.override and (", FORCED to " .. TierLabel(S.override)) or ", not forced")
        .. ". Effects are " .. (EffectsEnabled() and "on" or "off")
        .. ", drawn at layer " .. LayerIndex() .. " (" .. maelstrom.strata .. ").")
    print("  /exsar rotfx 0|1|2|3   — force a tier    /exsar rotfx auto — release")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Rotation Helper",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateCheckbox(parent, "Haste effects (swirling maelstrom)", 16, y,
            function() return EffectsEnabled() end,
            function(v) rDB().effects = v end
        )
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Emphasize the rotation text", 16, y,
            function() return TextPulseEnabled() end,
            function(v) rDB().textPulse = v; if not v then ClearTextEffect() end end
        )
        y = y - 34

        local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
        note:SetWidth(360)
        note:SetJustifyH("LEFT")
        note:SetText("Swirls cascade inward into the widget, escalating with haste: "
            .. "1:1 = slow blue, 2:3 = faster yellow, 1:2 = full-tilt orange. The "
            .. "rotation text takes the same colour and grows bolder each step. "
            .. "The swirl shape and brightness stay constant \226\128\148 what "
            .. "escalates is rate, colour, size and glow. 5:6:1:1 shows nothing.\n"
            .. "  /exsar rotfx 0|1|2|3  — force a tier to preview it\n"
            .. "  /exsar rotfx auto     — back to the live rotation")
        y = y - 76

        ExsarAddon.CreateSlider(parent, "Effect intensity", 16, y, 0.2, 2.0, 0.05,
            function() return NumSetting("fxIntensity", 1) end,
            function(v) rDB().fxIntensity = math.floor(v * 20 + 0.5) / 20 end
        )
        y = y - 55

        ExsarAddon.CreateSlider(parent, "Effect speed", 16, y, 0.2, 3.0, 0.05,
            function() return NumSetting("fxSpeed", 1) end,
            function(v) rDB().fxSpeed = math.floor(v * 20 + 0.5) / 20 end
        )
        y = y - 55

        -- Depth. The effect is its own UIParent-child frame, so it does not
        -- inherit this widget's strata; raise this if a neighbouring widget is
        -- covering the swirls.
        ExsarAddon.CreateSlider(parent, "Effect layer (1 = behind UI, 5 = in front)",
            16, y, 1, 5, 1,
            function() return LayerIndex() end,
            function(v) rDB().fxLayer = math.floor(v + 0.5); ApplyLayer() end
        )
        y = y - 55

        y = ExsarUI.AddScaleSlider(parent, y, rDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, rDB, frame, function(v)
            S.locked = v
            UpdateDisplay()
        end)

        y = ExsarUI.AddResetButton(parent, y, rDB, frame, "Rotation helper", 0, -250)

        return y
    end,
})
