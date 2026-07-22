-- MeleeHitFlash module
-- A fast slash flash confirming that your melee actually CONNECTED while weaving.
--
-- Melee weaving is over in a fraction of a second, and the only existing
-- confirmation is watching the melee swing timer very closely mid-fight. This
-- widget turns that into a peripheral cue: the instant a melee attack lands, a
-- diagonal slash snaps on and erases itself from the middle outward.
--
-- It is deliberately NOT the Windfury flourish (MeleeWeaveHelper's reward
-- eye-candy). Both use ExsarUI.CreateSlashEffect, but this one runs the "burst"
-- reveal model — snap to full length, erase middle-out, brief tip remnants, fade
-- — at roughly a third of the duration, with a tighter/less diffuse brush and
-- much less pseudo-3D depth. A gameplay cue must resolve before the next
-- decision; a flourish may linger.
--
-- Detection is the shared melee tracker's OnLanded callback, which fires the
-- moment the combat-log damage event arrives (white SWING_DAMAGE or a Raptor
-- Strike SPELL_DAMAGE, filtered to the player). That is the same signal behind
-- MeleeWeaveHelper's "WEAVE HIT!" text, but taken RAW: the text is additionally
-- gated on its own feedback toggle and classified into HIT vs LATE, so it can
-- stay silent on a melee that genuinely landed. This cue answers only "did it
-- connect", so it fires on every landed melee (see the note in CLAUDE.md).
--
-- Settings stored under ExsarAddonDB.meleeHitFlash.

local ADDON_NAME = "ExsarAddon"

local mhDB = ExsarUI.MakeDB("meleeHitFlash")

local melee = ExsarUI.GetMeleeSwingTracker()

-- =========================================================
-- Constants + tunable defaults
-- =========================================================

-- Fast enough that the flash is fully resolved well inside a single weave, so it
-- can never blur into the next one (the melee swing cycle is ~3.6s on a 2H, but
-- Raptor plus a white swing can land close together).
local DEF_DURATION = 0.30
local MIN_DURATION, MAX_DURATION = 0.15, 1.50

-- Slash look. Deliberately crisper and flatter than the Windfury flourish:
-- softness < 1 tightens the glow halo (less diffuse), and the low depth keeps it
-- from arcing dramatically toward the viewer.
local SLASH_COLOR     = { 1.00, 0.97, 0.72, 1.00 }  -- same warm family as Windfury
local SLASH_LENGTH    = 46
local SLASH_THICKNESS = 7.5
local SLASH_SOFTNESS  = 0.55   -- < 1 = tighter, harder-edged stroke
local SLASH_DEPTH     = 0.35   -- much flatter than the flourish's 1.25
local SLASH_TEXTURE   = "Interface\\Cooldown\\star4"  -- matches the Windfury brush

-- Dark rim strength (0 = off, 1 = full). The bright brush layers are ADD-blended,
-- which can only add light — against a busy combat backdrop of bright additive
-- spell FX there is no headroom, so the effect washes out exactly when it matters.
-- A normal-blended near-black underlay supplies the one contrast the game world
-- never draws, so the shape stays readable over anything. Live-tunable slider.
local DEF_RIM = 0.65
local MIN_RIM, MAX_RIM = 0.0, 1.0

-- Optional hit sound. Default OFF: this fires on every landed melee, which is
-- frequent enough to grate. Same custom-file-with-fallback pattern as the
-- Windfury whoosh — drop your own Sounds/meleehit.ogg (a NEWLY added sound file
-- needs a full client restart, not just /reload; .wav is unsupported).
local HIT_SOUND          = "Interface\\AddOns\\ExsarAddon\\Sounds\\meleehit.ogg"
local HIT_SOUND_FALLBACK = 568519   -- built-in Whirlwind whoosh

-- Placement preview while unlocked: re-fire the slash on a loop so its position
-- and size can be judged without needing something to hit.
local PREVIEW_GAP = 0.5

local FRAME_W, FRAME_H = 120, 120

-- =========================================================
-- State
-- =========================================================

local S = {
    previewNext = 0,
}

local function Duration()
    local v = mhDB().duration
    return type(v) == "number" and v or DEF_DURATION
end

local function Rim()
    local v = mhDB().rim
    return type(v) == "number" and v or DEF_RIM
end

local function PlayHitSound()
    local willPlay = PlaySoundFile(HIT_SOUND, "Master")
    if not willPlay then PlaySoundFile(HIT_SOUND_FALLBACK, "Master") end
end

-- =========================================================
-- Frame + slash effect
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "MeleeHitFlashFrame", UIParent)
frame:SetSize(FRAME_W, FRAME_H)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, -260)
ExsarUI.SetupMovableFrame(frame, mhDB)
frame:Hide()

-- Placeholder shown only while unlocked, so the drag target is findable even
-- between preview flashes.
local placeholder = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
placeholder:SetPoint("CENTER", frame, "CENTER", 0, 0)
placeholder:SetText("Melee hit flash")
placeholder:SetAlpha(0.5)
placeholder:Hide()

-- The slash lives on its own UIParent-child frame anchored here, so it fires even
-- while this frame is hidden (which is its normal state — the widget has no
-- persistent content of its own). Because that frame is a UIParent child it does
-- NOT inherit this frame's scale, hence getScale feeding the configured scale.
local slash = ExsarUI.CreateSlashEffect(frame, {
    reveal      = "burst",
    thicknessFn = ExsarLogic.SlashBurstThickness,
    duration    = Duration,   -- live: the config slider retunes it without a reload
    color       = SLASH_COLOR,
    length      = SLASH_LENGTH,
    thickness   = SLASH_THICKNESS,
    softness    = SLASH_SOFTNESS,
    depth       = SLASH_DEPTH,
    dotTexture  = SLASH_TEXTURE,
    rim         = DEF_RIM,   -- live via slash:SetRim below
    getScale    = function() return mhDB().scale or 1 end,
})

-- =========================================================
-- Group context gating
-- =========================================================

local function GetGroupContext()
    if IsInRaid() then return "raid" end
    if IsInGroup() then return "party" end
    return "solo"
end

local function ContextEnabled()
    local db = mhDB()
    return ExsarLogic.AggroAlertEnabled(
        GetGroupContext(),
        db.enableSolo ~= false,
        db.enableParty ~= false,
        db.enableRaid ~= false
    )
end

-- =========================================================
-- Trigger
-- =========================================================

local function FireFlash(withSound)
    slash:SetRim(Rim())   -- resolved per fire, so the slider applies without a reload
    slash:Trigger()
    if withSound and mhDB().hitSound == true then PlayHitSound() end
end

-- Fired by the shared melee tracker the instant a melee attack CONNECTS (white
-- swing or Raptor Strike). Misses/dodges/parries do not reach here — the tracker
-- advances swing TIMING on those but only fires OnLanded on real damage, which is
-- exactly the "did it actually hit" question this widget answers.
local function OnMeleeLanded()
    if mhDB().enabled == false then return end
    if not ContextEnabled() then return end
    if not UnitAffectingCombat("player") then return end
    FireFlash(true)
end
melee:OnLanded(OnMeleeLanded)

-- =========================================================
-- Display / preview loop
-- =========================================================

local function UpdateDisplay()
    local unlocked = not mhDB().locked
    placeholder:SetShown(unlocked)
    if unlocked then frame:Show() else frame:Hide() end
end

frame:SetScript("OnUpdate", function()
    -- While unlocked, loop the slash (silently) so placement and size can be
    -- previewed without waiting on a real hit.
    if mhDB().locked then return end
    if mhDB().enabled == false then return end
    local now = GetTime()
    if now >= S.previewNext then
        S.previewNext = now + Duration() + PREVIEW_GAP
        FireFlash(false)
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, mhDB, 0, -260)
        UpdateDisplay()
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateDisplay()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarUI.AddSlashReset("hitflashreset", frame, mhDB, "Melee hit flash", 0, -260)

ExsarAddon.AddSlashCommand("hitflashtest", function()
    FireFlash(true)
    print(ADDON_NAME .. ": melee hit flash fired.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Melee Hit Flash",
    icon = "Ability_Warrior_Cleave",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateCheckbox(parent, "Enable melee hit flash", 16, y,
            function() return mhDB().enabled ~= false end,
            function(v) mhDB().enabled = v; UpdateDisplay() end
        )
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Enable in solo", 16, y,
            function() return mhDB().enableSolo ~= false end,
            function(v) mhDB().enableSolo = v end
        )
        y = y - 30
        ExsarAddon.CreateCheckbox(parent, "Enable in party", 16, y,
            function() return mhDB().enableParty ~= false end,
            function(v) mhDB().enableParty = v end
        )
        y = y - 30
        ExsarAddon.CreateCheckbox(parent, "Enable in raid", 16, y,
            function() return mhDB().enableRaid ~= false end,
            function(v) mhDB().enableRaid = v end
        )
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Play a sound on each melee hit", 16, y,
            function() return mhDB().hitSound == true end,
            function(v) mhDB().hitSound = v end
        )
        y = y - 34

        local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
        note:SetWidth(360)
        note:SetJustifyH("LEFT")
        note:SetText("Fires the instant a melee attack connects (white swing or "
            .. "Raptor Strike) — misses do not flash. Unlock the widget to loop a "
            .. "silent preview while you position and size it.\n"
            .. "  /exsar hitflashtest  — fire the flash now")
        y = y - 60

        ExsarAddon.CreateSlider(parent, "Flash duration (s)", 16, y,
            MIN_DURATION, MAX_DURATION, 0.05,
            function() return Duration() end,
            function(v) mhDB().duration = math.floor(v * 20 + 0.5) / 20 end
        )
        y = y - 55

        ExsarAddon.CreateSlider(parent, "Dark rim (contrast)", 16, y,
            MIN_RIM, MAX_RIM, 0.05,
            function() return Rim() end,
            function(v) mhDB().rim = math.floor(v * 20 + 0.5) / 20 end
        )
        y = y - 55

        y = ExsarUI.AddScaleSlider(parent, y, mhDB, frame)
        y = ExsarUI.AddLockCheckbox(parent, y, mhDB, frame, function()
            UpdateDisplay()
        end)
        y = ExsarUI.AddResetButton(parent, y, mhDB, frame, "Melee hit flash", 0, -260)
        return y
    end,
})
