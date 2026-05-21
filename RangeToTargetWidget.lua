-- RangeToTargetWidget module
-- Shows an estimated distance bracket to the current target (e.g. "5-8 yd")
-- plus a weaving zone label (MELEE / WEAVE / FAR).
--
-- WoW exposes no exact distance, so distance is bracketed by probing a set of
-- harm range checks with known thresholds: a melee spell (Wing Clip, 5 yd) plus
-- a ladder of items with fixed ranges. IsSpellInRange works in combat; item
-- checks against an enemy target work in combat too (re-permitted by Blizzard in
-- Dec 2023) and degrade gracefully — any checker returning nil (invalid item ID
-- or restricted) is simply skipped, narrowing the bracket only as far as the
-- usable checkers allow.
--
-- Settings stored under ExsarAddonDB.rangeToTarget.

local ADDON_NAME = "ExsarAddon"

local rtDB = ExsarUI.MakeDB("rangeToTarget")

-- =========================================================
-- Range checkers (ascending by range)
-- =========================================================
-- spell entries use IsSpellInRange; item entries use IsItemInRange. Only harm
-- checks with NO minimum range are valid here — a spell with a dead-zone
-- minimum (e.g. Auto Shot) would report out-of-range when too close and corrupt
-- the lower bound. Item IDs come from the LibRangeCheck harm-item tables; ones
-- not present in the TBC client return nil and are skipped at runtime.

local CHECKERS = {
    { range = 5,  spell = "Wing Clip" },          -- melee
    { range = 8,  item  = 34368 },                -- Attuned Crystal Cores
    { range = 10, item  = 32321 },                -- Sparrowhawk Net
    { range = 15, item  = 33069 },                -- Sturdy Rope
    { range = 20, item  = 10645 },                -- Gnomish Death Ray
    { range = 25, item  = 24268 },                -- Netherweave Net
    { range = 30, item  = 7734  },                -- Six Demon Bag
    { range = 35, item  = 18904 },                -- Zorbin's Ultra-Shrinker
}

-- =========================================================
-- Zone colors
-- =========================================================

local ZONE_COLOR = {
    melee   = { 1.00, 0.55, 0.10 },   -- orange: too close
    weave   = { 0.20, 0.90, 0.30 },   -- green: sweet spot
    inrange = { 0.55, 0.70, 1.00 },   -- blue: within shooting range
    far     = { 0.90, 0.25, 0.25 },   -- red: out of shooting range
    ["?"]   = { 0.70, 0.70, 0.70 },   -- grey: indeterminate
}

local ZONE_LABEL = {
    melee   = "MELEE",
    weave   = "WEAVE",
    inrange = "IN RANGE",
    far     = "FAR",
    ["?"]   = "",
}

-- =========================================================
-- Frame
-- =========================================================

local FRAME_W = 64
local FRAME_H = 34
local PADDING = 4

local frame = CreateFrame("Frame", ADDON_NAME .. "RangeToTargetFrame", UIParent)
frame:SetSize(FRAME_W, FRAME_H)
local movableBg = ExsarUI.SetupMovableFrame(frame, rtDB)
frame:Show()

local placeholderText = ExsarUI.CreatePlaceholder(frame, "Range")

-- Range bracket (top line)
local rangeText = frame:CreateFontString(nil, "OVERLAY")
rangeText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
rangeText:SetPoint("TOP", frame, "TOP", 0, -PADDING)
rangeText:SetTextColor(1, 1, 1, 1)

-- Zone label (bottom line, colored by zone)
local zoneText = frame:CreateFontString(nil, "OVERLAY")
zoneText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
zoneText:SetPoint("TOP", rangeText, "BOTTOM", 0, -1)

-- =========================================================
-- Update
-- =========================================================

local results = {}  -- reused each poll to avoid garbage

local function HaveAttackableTarget()
    return UnitExists("target") and not UnitIsDead("target")
        and UnitCanAttack("player", "target")
end

local function UpdateDisplay()
    local locked = rtDB().locked

    if not HaveAttackableTarget() then
        rangeText:Hide()
        zoneText:Hide()
        if locked then
            frame:Hide()
        else
            frame:Show()
            movableBg:Show()
            placeholderText:Show()
        end
        return
    end

    placeholderText:Hide()
    movableBg:Hide()
    frame:Show()

    for i, checker in ipairs(CHECKERS) do
        local inRange
        if checker.spell then
            inRange = IsSpellInRange(checker.spell, "target")
        else
            inRange = IsItemInRange(checker.item, "target")
        end
        -- IsSpellInRange returns 1/0/nil; IsItemInRange returns boolean/nil.
        if inRange == 1 or inRange == true then
            results[i] = true
        elseif inRange == 0 or inRange == false then
            results[i] = false
        else
            results[i] = nil
        end
    end

    local minR, maxR = ExsarLogic.ComputeRangeBracket(CHECKERS, results)
    local zone = ExsarLogic.RangeZone(minR, maxR)

    rangeText:SetText(ExsarLogic.FormatRangeBracket(minR, maxR))
    rangeText:Show()

    local c = ZONE_COLOR[zone]
    zoneText:SetText(ZONE_LABEL[zone])
    zoneText:SetTextColor(c[1], c[2], c[3], 1)
    zoneText:Show()
end

-- =========================================================
-- Polling (range checks have no event; poll at 0.1s)
-- =========================================================

local pollElapsed = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    pollElapsed = pollElapsed + elapsed
    if pollElapsed < 0.1 then return end
    pollElapsed = 0
    UpdateDisplay()
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, rtDB, 0, -200)
        UpdateDisplay()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_TARGET_CHANGED" then
        UpdateDisplay()
    end
end)

-- =========================================================
-- Slash sub-command
-- =========================================================

ExsarUI.AddSlashReset("rangereset", frame, rtDB, "Range to target", 0, -200)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Range to Target",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, rtDB, frame)
        y = ExsarUI.AddLockCheckbox(parent, y, rtDB, frame, function()
            UpdateDisplay()
        end)
        y = ExsarUI.AddResetButton(parent, y, rtDB, frame, "Range to target", 0, -200)
        return y
    end,
})
