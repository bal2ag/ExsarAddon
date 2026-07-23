-- WindfuryHitFlash module
-- A flash celebrating that a Windfury Totem extra-attack landed on your melee.
--
-- Windfury Totem (from a grouped enhancement shaman) grants a single extra melee
-- attack on a proc — a burst of free damage that a weaving hunter wants to SEE
-- land. This is the reward cue for it.
--
-- It is a close sibling of MeleeHitFlash, deliberately: the base element is the
-- same ExsarUI.CreateSlashEffect "burst" slash (snap to full length, erase from
-- the middle outward, brief remnants, fade). Two things set it apart so a Windfury
-- proc never reads as an ordinary melee-hit flash:
--   1. the slash is MIRRORED horizontally (flipX) — upper-left→lower-right ("\")
--      where the melee-hit flash runs lower-left→upper-right ("/");
--   2. a WHIRLWIND / tornado flourish (ExsarUI.CreateWhirlwindEffect) is layered
--      on top — a rotating funnel that snaps in and erases middle-out on the same
--      timing as the slash, so the two resolve together as one event.
--
-- Detection is the shared melee tracker's OnWindfury callback (the same single
-- combat-log parse behind the melee/auto trackers; ExsarLogic.IsWindfuryProc
-- matches the SPELL_EXTRA_ATTACKS subevent by name, so all ranks/sources count).
-- Windfury Totem grants ONE extra attack per proc, so one proc = one flash (no
-- de-dupe needed; only the shaman's own Windfury Weapon procs two attacks).
--
-- Settings stored under ExsarAddonDB.windfuryHitFlash.

local ADDON_NAME = "ExsarAddon"

local wfDB = ExsarUI.MakeDB("windfuryHitFlash")

local melee = ExsarUI.GetMeleeSwingTracker()

-- =========================================================
-- Constants + tunable defaults
-- =========================================================

-- A reward flourish rather than a split-second gameplay cue, so it can linger a
-- little longer than the melee-hit flash (0.30). Still resolves well inside a
-- weave so procs never blur together.
local DEF_DURATION = 0.55
local MIN_DURATION, MAX_DURATION = 0.15, 2.00

-- Slash look. Same warm-gold burst blade as MeleeHitFlash (so it reads as "a
-- melee thing"), just mirrored via flipX below.
local SLASH_COLOR     = { 1.00, 0.97, 0.72, 1.00 }
local SLASH_LENGTH    = 48
local SLASH_THICKNESS = 7.5
local SLASH_SOFTNESS  = 0.55   -- < 1 = tighter, harder-edged stroke
local SLASH_DEPTH     = 0.35
local SLASH_TEXTURE   = "Interface\\Cooldown\\star4"

-- Whirlwind flourish look. A cooler, airier tint than the gold slash so it layers
-- visibly on top instead of merging into it — this is the piece that says
-- "Windfury", not "melee".
local WHIRL_COLOR     = { 0.72, 0.90, 1.00, 1.00 }  -- pale blue-white
local WHIRL_RADIUS    = 34    -- px half-width of the funnel mouth
local WHIRL_HEIGHT    = 100   -- px top-to-bottom
local WHIRL_TURNS     = 2.5
local WHIRL_SPIN      = 1.2    -- extra revolutions over the lifetime
local WHIRL_THICKNESS = 7
local WHIRL_SOFTNESS  = 0.7
local WHIRL_TEXTURE   = "Interface\\Cooldown\\star4"

-- Optional whoosh. Default ON: unlike the melee-hit flash (fires on every swing),
-- Windfury procs are the rewarding, less-frequent moment. Custom bundled sound
-- with a built-in fallback — drop your own Sounds/windfury.ogg (a NEWLY added
-- sound file needs a full client restart, not just /reload; .wav is unsupported).
local WF_SOUND          = "Interface\\AddOns\\ExsarAddon\\Sounds\\windfury.ogg"
local WF_SOUND_FALLBACK = 568519   -- built-in Whirlwind whoosh

-- Placement preview while unlocked: re-fire on a loop so position and size can be
-- judged without needing a real proc.
local PREVIEW_GAP = 0.6

local FRAME_W, FRAME_H = 130, 130

-- =========================================================
-- State
-- =========================================================

local S = {
    previewNext = 0,
}

local function Duration()
    local v = wfDB().duration
    return type(v) == "number" and v or DEF_DURATION
end

local function PlayWindfurySound()
    local willPlay = PlaySoundFile(WF_SOUND, "Master")
    if not willPlay then PlaySoundFile(WF_SOUND_FALLBACK, "Master") end
end

-- =========================================================
-- Frame + effects
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "WindfuryHitFlashFrame", UIParent)
frame:SetSize(FRAME_W, FRAME_H)
frame:SetPoint("CENTER", UIParent, "CENTER", 0, -300)
ExsarUI.SetupMovableFrame(frame, wfDB)
frame:Hide()

-- Placeholder shown only while unlocked, so the drag target stays findable in the
-- gaps between preview flashes.
local placeholder = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
placeholder:SetPoint("CENTER", frame, "CENTER", 0, 0)
placeholder:SetText("Windfury hit flash")
placeholder:SetAlpha(0.5)
placeholder:Hide()

-- Both effects live on their own UIParent-child frames anchored here, so they
-- fire even while this frame is hidden (its normal state). Both take the live
-- Duration so a single slider retunes them together, and both share the config
-- scale.
local slash = ExsarUI.CreateSlashEffect(frame, {
    reveal      = "burst",
    thicknessFn = ExsarLogic.SlashBurstThickness,
    flipX       = true,   -- mirror of the melee-hit slash: upper-left → lower-right
    duration    = Duration,
    color       = SLASH_COLOR,
    length      = SLASH_LENGTH,
    thickness   = SLASH_THICKNESS,
    softness    = SLASH_SOFTNESS,
    depth       = SLASH_DEPTH,
    dotTexture  = SLASH_TEXTURE,
    getScale    = function() return wfDB().scale or 1 end,
})

local whirl = ExsarUI.CreateWhirlwindEffect(frame, {
    duration   = Duration,
    color      = WHIRL_COLOR,
    radius     = WHIRL_RADIUS,
    height     = WHIRL_HEIGHT,
    turns      = WHIRL_TURNS,
    spin       = WHIRL_SPIN,
    thickness  = WHIRL_THICKNESS,
    softness   = WHIRL_SOFTNESS,
    dotTexture = WHIRL_TEXTURE,
    getScale   = function() return wfDB().scale or 1 end,
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
    local db = wfDB()
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
    slash:Trigger()
    whirl:Trigger()
    if withSound and wfDB().sound ~= false then PlayWindfurySound() end
end

-- Fired by the shared melee tracker on a Windfury extra-attack proc. Gated on the
-- widget being enabled + solo/party/raid context + in combat. One proc = one
-- flash (Windfury Totem grants a single extra attack).
local function OnWindfuryProc()
    if wfDB().enabled == false then return end
    if not ContextEnabled() then return end
    if not UnitAffectingCombat("player") then return end
    FireFlash(true)
end
melee:OnWindfury(OnWindfuryProc)

-- =========================================================
-- Display / preview loop
-- =========================================================

local function UpdateDisplay()
    local unlocked = not wfDB().locked
    placeholder:SetShown(unlocked)
    if unlocked then frame:Show() else frame:Hide() end
end

frame:SetScript("OnUpdate", function()
    -- While unlocked, loop the flash (silently) so placement and size can be
    -- previewed without waiting on a real proc.
    if wfDB().locked then return end
    if wfDB().enabled == false then return end
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
        ExsarUI.RestorePosition(self, wfDB, 0, -300)
        UpdateDisplay()
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateDisplay()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarUI.AddSlashReset("wfflashreset", frame, wfDB, "Windfury hit flash", 0, -300)

ExsarAddon.AddSlashCommand("wfflashtest", function()
    FireFlash(true)
    print(ADDON_NAME .. ": Windfury hit flash fired.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Windfury Hit Flash",
    icon = "Spell_Nature_Windfury",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateCheckbox(parent, "Enable Windfury hit flash", 16, y,
            function() return wfDB().enabled ~= false end,
            function(v) wfDB().enabled = v; UpdateDisplay() end
        )
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Enable in solo", 16, y,
            function() return wfDB().enableSolo ~= false end,
            function(v) wfDB().enableSolo = v end
        )
        y = y - 30
        ExsarAddon.CreateCheckbox(parent, "Enable in party", 16, y,
            function() return wfDB().enableParty ~= false end,
            function(v) wfDB().enableParty = v end
        )
        y = y - 30
        ExsarAddon.CreateCheckbox(parent, "Enable in raid", 16, y,
            function() return wfDB().enableRaid ~= false end,
            function(v) wfDB().enableRaid = v end
        )
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Play a whoosh on each Windfury proc", 16, y,
            function() return wfDB().sound ~= false end,
            function(v) wfDB().sound = v end
        )
        y = y - 34

        local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
        note:SetWidth(360)
        note:SetJustifyH("LEFT")
        note:SetText("Fires when a Windfury Totem extra-attack lands on your melee "
            .. "(needs a grouped shaman). A mirrored slash plus a whirlwind flourish. "
            .. "Unlock the widget to loop a silent preview while you position it.\n"
            .. "  /exsar wfflashtest  — fire the flash now")
        y = y - 60

        ExsarAddon.CreateSlider(parent, "Flash duration (s)", 16, y,
            MIN_DURATION, MAX_DURATION, 0.05,
            function() return Duration() end,
            function(v) wfDB().duration = math.floor(v * 20 + 0.5) / 20 end
        )
        y = y - 55

        y = ExsarUI.AddScaleSlider(parent, y, wfDB, frame)
        y = ExsarUI.AddLockCheckbox(parent, y, wfDB, frame, function()
            UpdateDisplay()
        end)
        y = ExsarUI.AddResetButton(parent, y, wfDB, frame, "Windfury hit flash", 0, -300)
        return y
    end,
})
