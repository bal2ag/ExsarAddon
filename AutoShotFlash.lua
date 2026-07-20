-- AutoShotFlash module
-- A radial burst marking the exact instant an Auto Shot leaves the bow.
--
-- The auto shot is the spine of the hunter rotation and every timing decision
-- (weave, Steady, reposition) hangs off knowing when the last one fired. The
-- swing timer and cast bar both PREDICT when it is due, but the shot can land up
-- to half a second after that prediction (the hidden retry timer — see the
-- Hunter timing reference in CLAUDE.md), so a prediction is not a substitute for
-- seeing the shot actually go. This widget is that confirmation, in the
-- peripheral vision, with no reading required.
--
-- Sibling of MeleeHitFlash, and deliberately LOUDER than it: melee connecting is
-- useful feedback, but the auto shot firing is the beat the whole rotation is
-- played against. Where the melee cue is a directional slash off to one side,
-- this is a symmetric radial burst — energy compressing to a bright point and
-- radiating outward in all directions (ExsarUI.CreateRadialBurstEffect /
-- ExsarLogic.RadialBurstAnim), suggesting the shot leaving the weapon. It also
-- runs in a cooler colour than the warm melee slash so the two never read as the
-- same event at a glance.
--
-- Detection is the shared auto-shot tracker's OnAutoShot callback, which fires
-- on the UNIT_SPELLCAST_SUCCEEDED for Auto Shot — the same signal that drives
-- AutoShotMonitor's clip scorecard. The delay argument is ignored here: this cue
-- answers only "did it fire, and when", never "was it clean" (that verdict is
-- AutoShotMonitor's NO CLIP! / CLIP +x pop, which is a separate, readable
-- signal — duplicating it here would make a peripheral cue something you have to
-- stop and interpret).
--
-- Settings stored under ExsarAddonDB.autoShotFlash.

local ADDON_NAME = "ExsarAddon"

local asDB = ExsarUI.MakeDB("autoShotFlash")

local auto = ExsarUI.GetAutoShotTracker()

-- =========================================================
-- Constants + tunable defaults
-- =========================================================

-- Slightly longer than the melee flash (0.30): the burst has to expand through
-- its whole radius to read as a release, and the auto-shot cycle it punctuates
-- is seconds long, so there is no risk of one flash blurring into the next.
local DEF_DURATION = 0.35
local MIN_DURATION, MAX_DURATION = 0.15, 1.50

-- Burst look. Cool white-blue against the melee cue's warm gold, so the two
-- flashes are never confused in peripheral vision. Kept fairly wide and bright:
-- this is the cue the user asked to be the least subtle in the addon.
local BURST_COLOR     = { 0.62, 0.88, 1.00, 1.00 }
local BURST_RADIUS    = 64
local BURST_RAYS      = 26
local BURST_THICKNESS = 7.5
local BURST_SOFTNESS  = 0.75   -- < 1 = tighter, crisper streaks

local BURST_CORE      = 30     -- central compression flare diameter (px)
local BURST_TEXTURE   = "Interface\\Cooldown\\star4"  -- same brush as the slash cues

-- Dark rim strength (0 = off, 1 = full). The bright brush layers are ADD-blended,
-- which can only add light — against a busy combat backdrop of bright additive
-- spell FX there is no headroom, so the effect washes out exactly when it matters.
-- A normal-blended near-black underlay supplies the one contrast the game world
-- never draws, so the shape stays readable over anything. Live-tunable slider.
--
-- Deliberately a LIGHT default: enough to define the stroke's edge against a
-- bright backdrop, not enough to read as a drawn outline (a heavy rim makes the
-- effect look cartoonish rather than energetic). Raise it via the slider if it
-- still washes out in a raid.
local DEF_RIM = 0.22
local MIN_RIM, MAX_RIM = 0.0, 1.0

-- Optional fire sound. Default OFF, same reasoning as the melee hit sound: an
-- auto shot fires every few seconds all fight long. Same custom-file-with-
-- fallback pattern — drop your own Sounds/autoshot.ogg (a NEWLY added sound file
-- needs a full client restart, not just /reload; .wav is unsupported).
local FIRE_SOUND          = "Interface\\AddOns\\ExsarAddon\\Sounds\\autoshot.ogg"
local FIRE_SOUND_FALLBACK = 568519   -- built-in whoosh

-- Placement preview while unlocked: re-fire on a loop so position and size can
-- be judged without needing to be shooting something.
local PREVIEW_GAP = 0.5

local FRAME_W, FRAME_H = 140, 140

-- =========================================================
-- State
-- =========================================================

local S = {
    previewNext = 0,
}

local function Duration()
    local v = asDB().duration
    return type(v) == "number" and v or DEF_DURATION
end

local function Rim()
    local v = asDB().rim
    return type(v) == "number" and v or DEF_RIM
end

local function PlayFireSound()
    local willPlay = PlaySoundFile(FIRE_SOUND, "Master")
    if not willPlay then PlaySoundFile(FIRE_SOUND_FALLBACK, "Master") end
end

-- =========================================================
-- Frame + burst effect
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "AutoShotFlashFrame", UIParent)
frame:SetSize(FRAME_W, FRAME_H)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, -320)
ExsarUI.SetupMovableFrame(frame, asDB)
frame:Hide()

-- Placeholder shown only while unlocked, so the drag target stays findable in
-- the gaps between preview bursts.
local placeholder = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
placeholder:SetPoint("CENTER", frame, "CENTER", 0, 0)
placeholder:SetText("Auto shot flash")
placeholder:SetAlpha(0.5)
placeholder:Hide()

-- The burst lives on its own UIParent-child frame anchored here, so it fires even
-- while this frame is hidden (its normal state — the widget has no persistent
-- content). Because that frame is a UIParent child it does NOT inherit this
-- frame's scale, hence getScale feeding it the configured scale.
local burst = ExsarUI.CreateRadialBurstEffect(frame, {
    duration   = Duration,   -- live: the config slider retunes it without a reload
    color      = BURST_COLOR,
    radius     = BURST_RADIUS,
    rays       = BURST_RAYS,
    thickness  = BURST_THICKNESS,
    softness   = BURST_SOFTNESS,
    coreSize   = BURST_CORE,
    dotTexture = BURST_TEXTURE,
    rim        = DEF_RIM,   -- live via burst:SetRim below
    getScale   = function() return asDB().scale or 1 end,
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
    local db = asDB()
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
    burst:SetRim(Rim())   -- resolved per fire, so the slider applies without a reload
    burst:Trigger()
    if withSound and asDB().fireSound == true then PlayFireSound() end
end

-- Fired by the shared auto-shot tracker the instant an Auto Shot lands. The
-- second argument (how late the shot was) is deliberately unused — see the file
-- header.
--
-- Note there is no in-combat gate here (unlike MeleeHitFlash): the pull's first
-- auto shot is what PUTS you in combat, so it fires just before
-- PLAYER_REGEN_DISABLED and a combat check would swallow the one shot whose
-- timing matters most. An auto shot firing is itself proof of a combat action,
-- so the gate would add nothing anyway.
local function OnAutoShotFired()
    if asDB().enabled == false then return end
    if not ContextEnabled() then return end
    FireFlash(true)
end
auto:OnAutoShot(OnAutoShotFired)

-- =========================================================
-- Display / preview loop
-- =========================================================

local function UpdateDisplay()
    local unlocked = not asDB().locked
    placeholder:SetShown(unlocked)
    if unlocked then frame:Show() else frame:Hide() end
end

frame:SetScript("OnUpdate", function()
    -- While unlocked, loop the burst (silently) so placement and size can be
    -- previewed without waiting on a real shot.
    if asDB().locked then return end
    if asDB().enabled == false then return end
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
        ExsarUI.RestorePosition(self, asDB, 0, -320)
        UpdateDisplay()
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateDisplay()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarUI.AddSlashReset("shotflashreset", frame, asDB, "Auto shot flash", 0, -320)

ExsarAddon.AddSlashCommand("shotflashtest", function()
    FireFlash(true)
    print(ADDON_NAME .. ": auto shot flash fired.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Auto Shot Flash",
    icon = 75,   -- Auto Shot (spellID, so the icon path can't be mistyped)
    BuildConfig = function(parent, y)
        ExsarAddon.CreateCheckbox(parent, "Enable auto shot flash", 16, y,
            function() return asDB().enabled ~= false end,
            function(v) asDB().enabled = v; UpdateDisplay() end
        )
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Enable in solo", 16, y,
            function() return asDB().enableSolo ~= false end,
            function(v) asDB().enableSolo = v end
        )
        y = y - 30
        ExsarAddon.CreateCheckbox(parent, "Enable in party", 16, y,
            function() return asDB().enableParty ~= false end,
            function(v) asDB().enableParty = v end
        )
        y = y - 30
        ExsarAddon.CreateCheckbox(parent, "Enable in raid", 16, y,
            function() return asDB().enableRaid ~= false end,
            function(v) asDB().enableRaid = v end
        )
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Play a sound on each auto shot", 16, y,
            function() return asDB().fireSound == true end,
            function(v) asDB().fireSound = v end
        )
        y = y - 34

        local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
        note:SetWidth(360)
        note:SetJustifyH("LEFT")
        note:SetText("Bursts the instant an auto shot actually fires — which can be "
            .. "up to half a second after the swing timer says it is due. Unlock the "
            .. "widget to loop a silent preview while you position and size it.\n"
            .. "  /exsar shotflashtest  — fire the burst now")
        y = y - 68

        ExsarAddon.CreateSlider(parent, "Burst duration (s)", 16, y,
            MIN_DURATION, MAX_DURATION, 0.05,
            function() return Duration() end,
            function(v) asDB().duration = math.floor(v * 20 + 0.5) / 20 end
        )
        y = y - 55

        ExsarAddon.CreateSlider(parent, "Dark rim (contrast)", 16, y,
            MIN_RIM, MAX_RIM, 0.05,
            function() return Rim() end,
            function(v) asDB().rim = math.floor(v * 20 + 0.5) / 20 end
        )
        y = y - 55

        y = ExsarUI.AddScaleSlider(parent, y, asDB, frame)
        y = ExsarUI.AddLockCheckbox(parent, y, asDB, frame, function()
            UpdateDisplay()
        end)
        y = ExsarUI.AddResetButton(parent, y, asDB, frame, "Auto shot flash", 0, -320)
        return y
    end,
})
