-- AggroAlert module
-- Shows pulsating red text when an enemy mob is targeting the player.
-- Configurable for solo, party, and raid contexts.
-- Settings stored under ExsarAddonDB.aggroAlert.

local ADDON_NAME = "ExsarAddon"

local aDB = ExsarUI.MakeDB("aggroAlert")

-- =========================================================
-- Constants
-- =========================================================

local POLL_INTERVAL    = 0.2
local PULSE_HZ         = 1.5
local PULSE_LO         = 0.7
local PULSE_HI         = 1.0
local MAX_MOBS         = 5
local LINE_HEIGHT      = 22
local LINE_GAP         = 2
local FRAME_PAD        = 8
local FRAME_W          = 350
local SOUND_ID         = 8959   -- RAID_WARNING
local SOUND_COOLDOWN   = 3      -- seconds between sound plays

-- =========================================================
-- State
-- =========================================================

local S = {
    active        = false,
    pulseTime     = 0,
    nameplates    = {},  -- set of unit tokens from nameplate events
    lastSoundTime = 0,   -- GetTime() of last sound play
}

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "AggroAlertFrame", UIParent)
frame:SetSize(FRAME_W, LINE_HEIGHT + FRAME_PAD * 2)
ExsarUI.SetupMovableFrame(frame, aDB, { bgAlpha = 0 })
frame:Hide()

-- =========================================================
-- Visuals — text lines
-- =========================================================

local textLines = {}
for i = 1, MAX_MOBS do
    local t = frame:CreateFontString(nil, "OVERLAY")
    t:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE, THICKOUTLINE")
    t:SetJustifyH("CENTER")
    t:SetTextColor(1, 0.3, 0.3, 1)
    if i == 1 then
        t:SetPoint("TOP", frame, "TOP", 0, -FRAME_PAD)
    else
        t:SetPoint("TOP", textLines[i - 1], "BOTTOM", 0, -LINE_GAP)
    end
    t:SetPoint("LEFT", frame, "LEFT", FRAME_PAD, 0)
    t:SetPoint("RIGHT", frame, "RIGHT", -FRAME_PAD, 0)
    t:Hide()
    textLines[i] = t
end

-- Placeholder shown when unlocked and no aggro is active
local placeholder = frame:CreateFontString(nil, "OVERLAY")
placeholder:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE, THICKOUTLINE")
placeholder:SetJustifyH("CENTER")
placeholder:SetTextColor(1, 0.3, 0.3, 0.5)
placeholder:SetPoint("TOP", frame, "TOP", 0, -FRAME_PAD)
placeholder:SetPoint("LEFT", frame, "LEFT", FRAME_PAD, 0)
placeholder:SetPoint("RIGHT", frame, "RIGHT", -FRAME_PAD, 0)
placeholder:SetText("You have aggro on <mob>!")
placeholder:Hide()

-- =========================================================
-- Pulsating glow border
-- =========================================================

local GLOW_SIZE = 6   -- how far the glow extends beyond the frame edge

local glowTextures = {}
-- Top
glowTextures[1] = frame:CreateTexture(nil, "BACKGROUND")
glowTextures[1]:SetColorTexture(1.0, 0.10, 0.05, 0.6)
glowTextures[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
glowTextures[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", GLOW_SIZE, GLOW_SIZE)
glowTextures[1]:SetHeight(GLOW_SIZE)
-- Bottom
glowTextures[2] = frame:CreateTexture(nil, "BACKGROUND")
glowTextures[2]:SetColorTexture(1.0, 0.10, 0.05, 0.6)
glowTextures[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -GLOW_SIZE, -GLOW_SIZE)
glowTextures[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
glowTextures[2]:SetHeight(GLOW_SIZE)
-- Left
glowTextures[3] = frame:CreateTexture(nil, "BACKGROUND")
glowTextures[3]:SetColorTexture(1.0, 0.10, 0.05, 0.6)
glowTextures[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
glowTextures[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -GLOW_SIZE, -GLOW_SIZE)
glowTextures[3]:SetWidth(GLOW_SIZE)
-- Right
glowTextures[4] = frame:CreateTexture(nil, "BACKGROUND")
glowTextures[4]:SetColorTexture(1.0, 0.10, 0.05, 0.6)
glowTextures[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", GLOW_SIZE, GLOW_SIZE)
glowTextures[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
glowTextures[4]:SetWidth(GLOW_SIZE)

for _, tex in ipairs(glowTextures) do tex:Hide() end

local function ShowGlow()
    for _, tex in ipairs(glowTextures) do tex:Show() end
end

local function HideGlow()
    for _, tex in ipairs(glowTextures) do tex:Hide() end
end

-- =========================================================
-- Group context
-- =========================================================

local function GetGroupContext()
    if IsInRaid() then return "raid" end
    if IsInGroup() then return "party" end
    return "solo"
end

-- =========================================================
-- Aggro scanning — nameplates + party/raid target-of-target
-- =========================================================

local function ScanAggro()
    local seen = {}   -- guid -> true (dedup)
    local mobs = {}

    -- Check if a unit is an enemy mob targeting the player.
    -- Returns immediately once MAX_MOBS is reached.
    local function Check(unit)
        if #mobs >= MAX_MOBS then return end
        if not UnitExists(unit) then return end
        if not UnitIsEnemy(unit, "player") then return end
        if UnitIsDead(unit) then return end
        local target = unit .. "target"
        if not UnitExists(target) then return end
        if not UnitIsUnit(target, "player") then return end
        local guid = UnitGUID(unit)
        if not guid or seen[guid] then return end
        local name = UnitName(unit)
        if not name then return end
        seen[guid] = true
        mobs[#mobs + 1] = name
    end

    -- Player's target (does targettarget point at me?)
    Check("target")

    -- Player's pet target
    Check("pettarget")

    -- Party members' targets
    for i = 1, 4 do
        Check("party" .. i .. "target")
        Check("partypet" .. i .. "target")
    end

    -- Raid members' targets
    for i = 1, 40 do
        Check("raid" .. i .. "target")
    end

    -- Boss frames
    for i = 1, 5 do
        Check("boss" .. i)
    end

    -- Nameplates (catches mobs not targeted by any group member)
    for unit in pairs(S.nameplates) do
        Check(unit)
    end

    return mobs
end

-- =========================================================
-- Update display
-- =========================================================

local function UpdateDisplay()
    if aDB().disabled then
        frame:Hide()
        return
    end

    local mobs = {}
    local db = aDB()
    if ExsarLogic.AggroAlertEnabled(
        GetGroupContext(),
        db.enableSolo ~= false,
        db.enableParty ~= false,
        db.enableRaid ~= false
    ) then
        mobs = ScanAggro()
    end

    local wasActive = S.active
    S.active = #mobs > 0

    -- Play sound on aggro gain (with cooldown)
    if S.active and not wasActive then
        local now = GetTime()
        if now - S.lastSoundTime >= SOUND_COOLDOWN then
            PlaySound(SOUND_ID, "Master")
            S.lastSoundTime = now
        end
    end

    -- Update text lines
    for i = 1, MAX_MOBS do
        if i <= #mobs then
            textLines[i]:SetText("You have aggro on " .. mobs[i] .. "!")
            textLines[i]:Show()
        else
            textLines[i]:Hide()
        end
    end

    -- Show placeholder when unlocked with no aggro
    if #mobs == 0 and not aDB().locked then
        placeholder:Show()
    else
        placeholder:Hide()
    end

    -- Resize frame to fit visible lines
    if #mobs > 0 then
        frame:SetHeight(FRAME_PAD * 2 + #mobs * LINE_HEIGHT + (#mobs - 1) * LINE_GAP)
    else
        frame:SetHeight(FRAME_PAD * 2 + LINE_HEIGHT)
    end

    -- Show/hide glow border (active aggro or unlocked placeholder)
    if S.active or not aDB().locked then
        ShowGlow()
    else
        HideGlow()
    end

    local shouldShow = S.active or not aDB().locked
    if shouldShow then
        if not frame:IsShown() then
            S.pulseTime = 0.25
        end
        frame:Show()
    else
        frame:Hide()
    end
end

-- =========================================================
-- Pulse animation
-- =========================================================

frame:SetScript("OnUpdate", function(self, elapsed)
    S.pulseTime = S.pulseTime + elapsed
    frame:SetAlpha(ExsarLogic.PulseAlpha(S.pulseTime, PULSE_HZ, PULSE_LO, PULSE_HI))
end)

-- =========================================================
-- Polling for target changes
-- =========================================================

ExsarUI.CreatePoller(nil, POLL_INTERVAL, UpdateDisplay)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, aDB, 0, -200)
        if not aDB().locked then
            S.pulseTime = 0.25
            frame:Show()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        S.nameplates = {}
        UpdateDisplay()

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        S.nameplates[arg1] = true
        UpdateDisplay()

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        S.nameplates[arg1] = nil
        UpdateDisplay()

    elseif event == "UNIT_THREAT_SITUATION_UPDATE" then
        if arg1 == "player" then
            UpdateDisplay()
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        UpdateDisplay()
    end
end)

-- =========================================================
-- Slash sub-command
-- =========================================================

ExsarUI.AddSlashReset("aggroreset", frame, aDB, "Aggro alert", 0, -200)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Aggro Alert",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateCheckbox(parent, "Enable in solo", 16, y,
            function() return aDB().enableSolo ~= false end,
            function(v) aDB().enableSolo = v; UpdateDisplay() end
        )
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Enable in party", 16, y,
            function() return aDB().enableParty ~= false end,
            function(v) aDB().enableParty = v; UpdateDisplay() end
        )
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Enable in raid", 16, y,
            function() return aDB().enableRaid ~= false end,
            function(v) aDB().enableRaid = v; UpdateDisplay() end
        )
        y = y - 30

        y = ExsarUI.AddScaleSlider(parent, y, aDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, aDB, frame)

        y = ExsarUI.AddResetButton(parent, y, aDB, frame, "Aggro alert", 0, -200)

        return y
    end,
})
