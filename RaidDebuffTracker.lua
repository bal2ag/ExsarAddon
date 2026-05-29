-- RaidDebuffTracker module
-- Combined raid-debuff status panel: a vertical list with one row per tracked
-- debuff important for hunter damage. Each row is either:
--   * PRESENT — icon + name on a draining StatusBar (blue → yellow at 50% → orange
--     at 20% of duration remaining) + a countdown timer, so you can see when a
--     debuff is about to fall off and needs refreshing; or
--   * MISSING — icon + red name on a solid dim-red bar (no timer), so you can
--     still call out what's absent on Discord.
-- A present debuff with no readable timer (permanent, or a client that hides
-- others' durations) shows a full blue bar with no countdown.
--
-- Unlike TargetDebuffTracker (which shows debuffs you cast), this scans ALL
-- debuffs on the target (raid debuffs come from other players), matching by name
-- to catch every rank/source.
--
-- Visibility: a target is always required. By default also requires in combat +
-- in a raid; each of those is independently waivable via the "Show out of combat"
-- / "Show out of raid" config checkboxes (both default off). Each tracked debuff
-- can be toggled off in config (e.g. when the raid lacks the class that provides
-- it). Settings stored under ExsarAddonDB.raidDebuffs.

local ADDON_NAME = "ExsarAddon"

local rDB = ExsarUI.MakeDB("raidDebuffs")

-- =========================================================
-- Tracked debuff definitions  (SCAFFOLDING DEFAULTS — to be finalized)
-- =========================================================
-- Each entry:
--   key       stable id for the per-debuff enable map (never reorder-sensitive)
--   name      display/tooltip name (a category name for grouped entries)
--   iconSpell spell id used only to fetch the icon texture (via GetSpellInfo)
--   auras     list of aura names; the entry counts as PRESENT if ANY is on the
--             target. A GROUPED entry (e.g. "Armor Debuff") lists every aura
--             that satisfies the category, so it is only flagged MISSING when
--             *none* of them are up. A SPECIFIC entry (e.g. "Hunter's Mark")
--             just lists its own name (which also catches all ranks).
local TRACKED_DEBUFFS = {
    -- Grouped category: armor reduction — satisfied by Sunder Armor OR Expose
    -- Armor; flagged missing only when neither is up.
    { key = "armorDebuff", name = "Armor Reduction", iconSpell = 7386, -- Sunder Armor icon
      auras = { "Sunder Armor", "Expose Armor" } },
    -- Warlock curse; armor reduction that stacks on top of Sunder/Expose, hence
    -- its own entry (only one curse per warlock can be up at a time).
    { key = "curseRecklessness", name = "Curse of Recklessness", iconSpell = 704,
      auras = { "Curse of Recklessness" } },
    -- Faerie Fire: tracked for the Improved Faerie Fire +hit (the only source of
    -- it in TBC). Plain and improved FF share the same aura name and spellId, so
    -- we detect FF presence as a proxy — relies on the assigned druid being
    -- specced. Deliberately NOT in the armor group.
    { key = "faerieFire", name = "Improved Faerie Fire", iconSpell = 770,
      auras = { "Faerie Fire", "Faerie Fire (Feral)" } },
    -- Paladin debuff: restores mana to attackers (hunter shot sustain). In-game
    -- name uses the British spelling "Judgement"; matched by name (all ranks).
    { key = "judgementWisdom", name = "Judgement of Wisdom", iconSpell = 20186,
      auras = { "Judgement of Wisdom" } },
    -- Paladin debuff. With Improved Seal of the Crusader it grants +crit to all
    -- attacks against the judged target — a talent bonus invisible from the aura,
    -- so it's caster-matched (see CASTER_MATCHED). British spelling in-game.
    { key = "judgementCrusader", name = "Judgement of the Crusader", iconSpell = 21183,
      auras = { "Judgement of the Crusader" } },
    -- Specific debuff.
    { key = "huntersMark", name = "Hunter's Mark", iconSpell = 1130,
      auras = { "Hunter's Mark" } },
}

-- =========================================================
-- Layout constants  (vertical list: title + [icon] colored-name rows)
-- =========================================================

local ICON_SIZE = 20    -- per-row icon (and bar height)
local ROW_GAP   = 3     -- vertical gap between rows
local TEXT_GAP  = 5     -- icon → bar gap
local TITLE_GAP = 4     -- title → first row gap
local PADDING   = 6
local BAR_INSET = 4     -- name/timer inset from the bar edges
local TIMER_RESERVE = 48 -- extra bar width beyond the widest name (timer + insets)

local TITLE_TEXT  = "Raid debuffs:"
local MISSING_COLOR    = { 1, 0.4, 0.4 }       -- missing name color; per-entry `color` overrides
local PRESENT_COLOR    = { 1, 1, 1 }           -- present name color; per-entry `presentColor` overrides
local MISSING_BAR_COLOR = { 0.5, 0.12, 0.12 }  -- solid dim-red fill for a missing row

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "RaidDebuffFrame", UIParent)
ExsarUI.SetupMovableFrame(frame, rDB)

-- Persistent title; its visibility is the "widget is active" cue (shown whenever
-- unlocked, or in-combat+in-raid+has-target when locked).
local titleText = frame:CreateFontString(nil, "OVERLAY")
titleText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
titleText:SetTextColor(1, 0.82, 0, 1)
titleText:SetText(TITLE_TEXT)
titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -PADDING)

frame:Hide()

local C_locked = false
local C_inCombat = false

-- =========================================================
-- Per-debuff enable state  (default ON; stored false only when disabled)
-- =========================================================

local function IsDebuffEnabled(key)
    local d = rDB().debuffs
    return not d or d[key] ~= false
end

local function SetDebuffEnabled(key, enabled)
    local db = rDB()
    db.debuffs = db.debuffs or {}
    db.debuffs[key] = enabled
end

local function IsWidgetEnabled()
    return rDB().enabled ~= false
end

-- Visibility relaxers (both default OFF → stored true only when enabled).
local function IsShowOutOfCombat()
    return rDB().showOutOfCombat == true
end

local function IsShowOutOfRaid()
    return rDB().showOutOfRaid == true
end

local function IsAutoDetectEnabled()
    return rDB().autoDetect ~= false
end

-- Caster-matched debuffs. Some debuffs only deliver their hunter-relevant bonus
-- when the caster is talented (the bonus is invisible from the aura itself):
--   * Improved Faerie Fire (druid talent) — +hit on the FF debuff
--   * Improved Seal of the Crusader (paladin talent) — +crit to all attacks
--     against a target judged with Judgement of the Crusader
-- For these, the aura only "counts" when applied by a known specced player.
-- Accepted casters come from a manual pin (captured from target, persisted under
-- guidKey/nameKey) plus auto-detection via talent inspect (in-memory autoGuids,
-- re-detected each session to handle respecs). The union is accepted (see
-- ComputeMissingDebuffs caster matching). Adding another such debuff = one row.
local CASTER_MATCHED = {
    faerieFire = {
        talent  = "Improved Faerie Fire",
        class   = "DRUID",
        guidKey = "ffDruidGuid",  nameKey = "ffDruidName",
        label   = "Improved Faerie Fire druid",
    },
    judgementCrusader = {
        talent  = "Improved Seal of the Crusader",
        class   = "PALADIN",
        guidKey = "jocPaladinGuid",  nameKey = "jocPaladinName",
        label   = "Improved Judgement of the Crusader paladin",
    },
}

-- Classes worth inspecting (union of CASTER_MATCHED classes).
local INSPECT_CLASSES = {}
for _, cfg in pairs(CASTER_MATCHED) do INSPECT_CLASSES[cfg.class] = true end

local autoGuids = {}  -- [key] = { [guid] = true }   auto-detected specced casters
local autoNames = {}  -- [guid] = name               for config labels
for key in pairs(CASTER_MATCHED) do autoGuids[key] = {} end

local function RequiredCasterFor(key)
    local cfg = CASTER_MATCHED[key]
    if not cfg then return nil end
    local set
    local manual = rDB()[cfg.guidKey]
    if manual then set = { [manual] = true } end
    for guid in pairs(autoGuids[key]) do
        set = set or {}
        set[guid] = true
    end
    return set  -- nil when nobody is designated → any caster counts
end

-- =========================================================
-- Icon slot construction
-- =========================================================

local function MakeSlot(debuff)
    local s = { def = debuff }

    -- Row container holds the icon (left) + a status bar (right of icon) that
    -- carries the name (left-overlaid) and the countdown timer (right-overlaid).
    s.row = CreateFrame("Frame", nil, frame)
    s.row:SetHeight(ICON_SIZE)

    local holder = CreateFrame("Frame", nil, s.row)
    holder:SetSize(ICON_SIZE, ICON_SIZE)
    holder:SetPoint("TOPLEFT", s.row, "TOPLEFT", 0, 0)
    s.icon = ExsarUI.CreateIcon(holder)

    -- Draining timer bar. Present → colored fill that drains as the debuff
    -- expires; missing → solid dim-red fill. Width is set per layout pass.
    s.bar = CreateFrame("StatusBar", nil, s.row)
    s.bar:SetPoint("TOPLEFT", holder, "TOPRIGHT", TEXT_GAP, 0)
    s.bar:SetHeight(ICON_SIZE)
    s.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    s.bar:SetMinMaxValues(0, 1)
    s.bar:SetValue(1)

    local bg = s.bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    s.name = s.bar:CreateFontString(nil, "OVERLAY")
    s.name:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    s.name:SetPoint("LEFT", s.bar, "LEFT", BAR_INSET, 0)
    local c = debuff.color or MISSING_COLOR
    s.name:SetTextColor(c[1], c[2], c[3], 1)
    s.name:SetText(debuff.name)

    s.timer = s.bar:CreateFontString(nil, "OVERLAY")
    s.timer:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    s.timer:SetPoint("RIGHT", s.bar, "RIGHT", -BAR_INSET, 0)
    s.timer:SetTextColor(1, 1, 1, 1)

    s.row:Hide()
    return s
end

local slots = {}
for _, debuff in ipairs(TRACKED_DEBUFFS) do
    slots[#slots + 1] = MakeSlot(debuff)
end

-- =========================================================
-- Icon texture resolution (deferred until spell data is available)
-- =========================================================

local function ResolveIcons()
    for _, s in ipairs(slots) do
        if not s.iconResolved and s.def.iconSpell then
            local icon = select(3, GetSpellInfo(s.def.iconSpell))
            if icon then
                s.icon:SetTexture(icon)
                s.iconResolved = true
            end
        end
    end
end

-- =========================================================
-- Layout
-- =========================================================

local lastTimeStrs = {}  -- [slotIndex] = last timer string (avoid SetText churn)

-- Lay out the title + one row per ENABLED tracked debuff (vertical), present or
-- missing. Only called when the widget is active, so the title is always shown.
-- `status` is the ordered ExsarLogic.ComputeDebuffStatus result; `timing` maps
-- aura name → { duration, expTime } for present debuffs; `now` is GetTime().
local function ApplyLayout(status, timing, now)
    for _, s in ipairs(slots) do s.row:Hide() end

    -- Uniform bar width across rows = widest enabled name + room for the timer.
    local maxNameW = 0
    for _, st in ipairs(status) do
        maxNameW = math.max(maxNameW, slots[st.def._slotIndex].name:GetStringWidth())
    end
    local barW = maxNameW + TIMER_RESERVE

    local maxRowW = titleText:GetStringWidth()
    local yOffset = PADDING + titleText:GetStringHeight() + TITLE_GAP

    for _, st in ipairs(status) do
        local idx = st.def._slotIndex
        local s = slots[idx]
        s.row:ClearAllPoints()
        s.row:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -yOffset)
        s.bar:SetWidth(barW)
        local rowW = ICON_SIZE + TEXT_GAP + barW
        s.row:SetWidth(rowW)
        maxRowW = math.max(maxRowW, rowW)

        if st.satisfied then
            local t = timing and timing[st.aura]
            local dur = (t and t.duration) or 0
            local exp = (t and t.expTime) or 0
            local remaining = exp > 0 and math.max(0, exp - now) or 0
            if dur > 0 and exp > 0 then
                s.bar:SetMinMaxValues(0, dur)
                s.bar:SetValue(remaining)
                s.bar:SetStatusBarColor(ExsarLogic.DebuffBarColor(remaining, dur))
                local str = ExsarLogic.FormatCooldown(remaining)
                if str ~= lastTimeStrs[idx] then
                    lastTimeStrs[idx] = str
                    s.timer:SetText(str)
                end
            else
                -- present but no readable timer (permanent / API hid it)
                s.bar:SetMinMaxValues(0, 1)
                s.bar:SetValue(1)
                s.bar:SetStatusBarColor(ExsarLogic.DebuffBarColor(1, 0))
                s.timer:SetText("")
                lastTimeStrs[idx] = nil
            end
            local c = st.def.presentColor or PRESENT_COLOR
            s.name:SetTextColor(c[1], c[2], c[3], 1)
        else
            -- missing: solid dim-red bar, red name, no timer
            s.bar:SetMinMaxValues(0, 1)
            s.bar:SetValue(1)
            s.bar:SetStatusBarColor(MISSING_BAR_COLOR[1], MISSING_BAR_COLOR[2], MISSING_BAR_COLOR[3])
            s.timer:SetText("")
            lastTimeStrs[idx] = nil
            local c = st.def.color or MISSING_COLOR
            s.name:SetTextColor(c[1], c[2], c[3], 1)
        end

        s.row:Show()
        yOffset = yOffset + ICON_SIZE + ROW_GAP
    end

    -- Trim the trailing row gap (none added when the list is empty).
    if #status > 0 then yOffset = yOffset - ROW_GAP end

    frame:SetSize(maxRowW + PADDING * 2, yOffset + PADDING)
    frame:Show()
end

-- =========================================================
-- Scan / update
-- =========================================================

local function UpdateMissing()
    local unlocked = not C_locked
    local hasTarget = UnitExists("target") and true or false

    local show = ExsarLogic.RaidDebuffsShouldShow({
        enabled         = IsWidgetEnabled(),
        inCombat        = C_inCombat,
        inRaid          = IsInRaid(),
        hasTarget       = hasTarget,
        showOutOfCombat = IsShowOutOfCombat(),
        showOutOfRaid   = IsShowOutOfRaid(),
        unlocked        = unlocked,
    })

    if not show then
        frame:Hide()
        return
    end

    -- Build the aura→caster map of debuffs on the target (any caster) plus a
    -- parallel aura→timing map (duration + expiration) for the draining bars.
    -- Returns 5/6/7 of UnitDebuff are duration / expirationTime / caster token;
    -- resolve the caster to a GUID so entries with a required caster (Faerie
    -- Fire) can be matched. A nil token (caster out of range / unreported)
    -- stores `true` = present-but-unknown. While unlocked we skip the scan
    -- entirely (present stays empty) so EVERY enabled debuff lists as missing —
    -- a deterministic positioning preview independent of the current target.
    local present, timing = {}, {}
    if hasTarget and not unlocked then
        for i = 1, 40 do
            local bName, _, _, _, bDuration, bExp, bCaster = UnitDebuff("target", i)
            if not bName then break end
            local guid = bCaster and UnitGUID(bCaster) or nil
            present[bName] = guid or true
            if not timing[bName] then
                timing[bName] = { duration = bDuration or 0, expTime = bExp or 0 }
            end
        end
    end

    -- Tag each entry with its slot index for the layout step.
    for idx, def in ipairs(TRACKED_DEBUFFS) do def._slotIndex = idx end

    local status = ExsarLogic.ComputeDebuffStatus(
        TRACKED_DEBUFFS, IsDebuffEnabled, present, RequiredCasterFor)

    ApplyLayout(status, timing, GetTime())
end

-- =========================================================
-- Auto-detect talented casters (Improved Faerie Fire / Improved Seal of the
-- Crusader) via talent inspect
-- =========================================================
-- We can't read talents off a debuff, so we inspect raid members of the relevant
-- classes: when one comes back specced, cache their GUID for that key. We only
-- need to catch a player ONCE — the cached GUID then matches their debuff
-- anywhere. A config callback refreshes the panel labels on detection.
--
-- NOTE on the "unknown unit / out of range" spam (why this is gated the way it
-- is): `NotifyInspect` errors loudly when the unit is out of inspect range, and
-- the error path never fires `INSPECT_READY`, so a naive retry loop hammers the
-- same far-away raider. `CanInspect` does NOT check range. The fix is to gate on
-- `CheckInteractDistance(unit, 1)` (real ~28yd inspect range) and a per-GUID
-- backoff, so we only ever inspect someone actually in range and never spam.
local OnAutoDetect  -- forward declaration; set by BuildConfig

local inspectWanted = {}   -- [guid] = unit   raid members not yet inspected
local inspectPending = nil -- guid currently being inspected
local inspectSentAt  = 0   -- GetTime() when the pending request was sent
local inspectBackoff = {}  -- [guid] = GetTime() of last attempt (range/error skip)
local INSPECT_BACKOFF = 10 -- seconds before retrying a given GUID

-- Read the inspected unit's talents into a pure { name, rank } list.
local function ReadInspectTalents()
    local list = {}
    local numTabs = GetNumTalentTabs(true) or 0
    for t = 1, numTabs do
        local numTalents = GetNumTalents(t, true) or 0
        for i = 1, numTalents do
            local name, _, _, _, rank = GetTalentInfo(t, i, true)
            if name then list[#list + 1] = { name = name, rank = rank or 0 } end
        end
    end
    return list
end

-- Has this GUID already been confirmed specced for any caster-matched key?
local function AlreadyDetected(guid)
    for key in pairs(CASTER_MATCHED) do
        if autoGuids[key][guid] then return true end
    end
    return false
end

-- Refresh the set of raid members (of inspectable classes) we still want to check.
local function RefreshInspectQueue()
    if not IsAutoDetectEnabled() or not IsInRaid() then
        for k in pairs(inspectWanted) do inspectWanted[k] = nil end
        return
    end
    local present = {}
    for i = 1, 40 do
        local unit = "raid" .. i
        if UnitExists(unit) then
            local _, class = UnitClass(unit)
            local guid = UnitGUID(unit)
            if class and INSPECT_CLASSES[class] and guid then
                present[guid] = true
                if not AlreadyDetected(guid) then
                    inspectWanted[guid] = unit
                end
            end
        end
    end
    -- Drop anyone no longer in the raid.
    for guid in pairs(inspectWanted) do
        if not present[guid] then inspectWanted[guid] = nil end
    end
end

-- Kick off the next inspect if one isn't already in flight. Only inspects units
-- actually within inspect range (CheckInteractDistance), never the whole roster —
-- this is what prevents the out-of-range error spam.
local function ProcessInspectQueue()
    if not IsAutoDetectEnabled() then return end
    if InCombatLockdown() then return end  -- avoid inspect churn mid-fight
    -- Don't fight Blizzard's own inspect window for the single inspect channel.
    if InspectFrame and InspectFrame:IsShown() then return end
    -- Clear a stale pending request that never got an INSPECT_READY.
    if inspectPending and GetTime() - inspectSentAt > 3 then
        inspectPending = nil
    end
    if inspectPending then return end
    local now = GetTime()
    for guid, unit in pairs(inspectWanted) do
        -- Re-verify the token still maps to this GUID, is reachable, IN RANGE,
        -- and not in backoff from a recent attempt.
        if UnitGUID(unit) == guid
           and CanInspect(unit)
           and CheckInteractDistance(unit, 1)   -- 1 = inspect range (~28yd)
           and (not inspectBackoff[guid] or now - inspectBackoff[guid] > INSPECT_BACKOFF) then
            inspectPending = guid
            inspectSentAt  = now
            inspectBackoff[guid] = now
            NotifyInspect(unit)
            return
        end
    end
end

-- Handle inspect data arriving for `guid` (may be ours or a manual UI inspect).
local function OnInspectReady(guid)
    if guid == inspectPending then inspectPending = nil end
    local unit = inspectWanted[guid]
    if not unit then return end          -- not a member we're tracking
    if UnitGUID(unit) ~= guid then return end

    local _, class = UnitClass(unit)
    local talents = ReadInspectTalents()
    local detected = false
    -- One inspect reads all talents; check every key matching this unit's class.
    for key, cfg in pairs(CASTER_MATCHED) do
        if cfg.class == class and ExsarLogic.FindTalentRank(talents, cfg.talent) > 0 then
            autoGuids[key][guid] = true
            autoNames[guid] = UnitName(unit) or "?"
            detected = true
        end
    end
    if detected then
        UpdateMissing()
        if OnAutoDetect then OnAutoDetect() end
    end
    inspectWanted[guid] = nil            -- resolved either way
    inspectBackoff[guid] = nil
    ClearInspectPlayer(guid)
end

-- Slow ticker drives the inspect queue (range/throttle aware).
ExsarUI.CreatePoller(CreateFrame("Frame"), 2.0, ProcessInspectQueue)

-- =========================================================
-- Polling + events
-- =========================================================

ExsarUI.CreatePoller(frame, 0.2, UpdateMissing)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("INSPECT_READY")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, rDB, -300, 160)
        C_locked = rDB().locked and true or false
        ResolveIcons()
        UpdateMissing()

    elseif event == "PLAYER_ENTERING_WORLD" then
        C_inCombat = InCombatLockdown() and true or false
        ResolveIcons()
        RefreshInspectQueue()
        UpdateMissing()

    elseif event == "INSPECT_READY" then
        OnInspectReady(arg1)

    elseif event == "PLAYER_REGEN_DISABLED" then
        C_inCombat = true
        UpdateMissing()

    elseif event == "PLAYER_REGEN_ENABLED" then
        C_inCombat = false
        UpdateMissing()

    elseif event == "SPELLS_CHANGED" then
        ResolveIcons()

    elseif event == "UNIT_AURA" then
        if arg1 == "target" then UpdateMissing() end

    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateMissing()

    elseif event == "GROUP_ROSTER_UPDATE" then
        RefreshInspectQueue()
        UpdateMissing()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarUI.AddSlashReset("raiddebuffsreset", frame, rDB, "Raid debuff tracker", -300, 160)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Raid Debuff Tracker",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateCheckbox(parent, "Enable widget", 16, y,
            function() return IsWidgetEnabled() end,
            function(v)
                rDB().enabled = v
                UpdateMissing()
            end)
        y = y - 30

        -- Visibility relaxers (a target is always required). Both default off,
        -- so the default gating stays combat + raid + target.
        ExsarAddon.CreateCheckbox(parent, "Show out of combat", 16, y,
            function() return IsShowOutOfCombat() end,
            function(v)
                rDB().showOutOfCombat = v
                UpdateMissing()
            end)
        y = y - 30

        ExsarAddon.CreateCheckbox(parent, "Show out of raid", 16, y,
            function() return IsShowOutOfRaid() end,
            function(v)
                rDB().showOutOfRaid = v
                UpdateMissing()
            end)
        y = y - 30

        y = ExsarUI.AddScaleSlider(parent, y, rDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, rDB, frame, function(v)
            C_locked = v
            UpdateMissing()
        end)

        -- Per-debuff toggles (disable the ones the raid can't provide).
        local heading = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        heading:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
        heading:SetText("Tracked debuffs")
        y = y - 24

        for _, def in ipairs(TRACKED_DEBUFFS) do
            local key = def.key
            ExsarAddon.CreateCheckbox(parent, def.name, 24, y,
                function() return IsDebuffEnabled(key) end,
                function(v)
                    SetDebuffEnabled(key, v)
                    UpdateMissing()
                end)
            y = y - 28
        end

        -- Caster-matched debuffs: one section each (Improved Faerie Fire druid,
        -- Improved Seal of the Crusader paladin, ...). Auto-detected from raid via
        -- talent inspect; the user can also manually pin the known caster (the
        -- talent bonus is unreadable from the aura, so the debuff only counts when
        -- applied by a designated/specced player). Rendered in tracked-list order.
        y = y - 8
        ExsarAddon.CreateCheckbox(parent, "Auto-detect talented casters (inspect)", 16, y,
            function() return IsAutoDetectEnabled() end,
            function(v)
                rDB().autoDetect = v
                if v then RefreshInspectQueue() end
            end)
        y = y - 28

        local refreshers = {}
        for _, def in ipairs(TRACKED_DEBUFFS) do
            local cfg = CASTER_MATCHED[def.key]
            if cfg then
                local key = def.key
                y = y - 8
                local hdg = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                hdg:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
                hdg:SetText(cfg.label)
                y = y - 22

                local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                lbl:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, y)
                lbl:SetWidth(340)
                lbl:SetJustifyH("LEFT")
                local function Refresh()
                    local parts = {}
                    local manual = rDB()[cfg.nameKey]
                    if manual and manual ~= "" then
                        parts[#parts + 1] = "|cff40ff40" .. manual .. "|r (pinned)"
                    end
                    for guid in pairs(autoGuids[key]) do
                        parts[#parts + 1] = "|cff40c0ff" .. (autoNames[guid] or "?") .. "|r (auto)"
                    end
                    if #parts > 0 then
                        lbl:SetText("Accepting: " .. table.concat(parts, ", "))
                    else
                        lbl:SetText("|cff999999none yet (any caster counts; auto-detecting...)|r")
                    end
                end
                refreshers[#refreshers + 1] = Refresh
                lbl:SetScript("OnShow", Refresh)
                Refresh()
                y = y - 22

                ExsarAddon.CreateButton(parent, "Set from target", 24, y, function()
                    if UnitExists("target") and UnitIsPlayer("target") then
                        rDB()[cfg.guidKey] = UnitGUID("target")
                        rDB()[cfg.nameKey] = UnitName("target")
                        Refresh()
                        UpdateMissing()
                        local _, class = UnitClass("target")
                        local warn = (class ~= cfg.class) and " |cffff4040(not a " .. cfg.class .. "!)|r" or ""
                        print(ADDON_NAME .. ": " .. cfg.label .. " set to " .. (rDB()[cfg.nameKey] or "?") .. warn)
                    else
                        print(ADDON_NAME .. ": target a player first.")
                    end
                end)
                ExsarAddon.CreateButton(parent, "Clear", 174, y, function()
                    rDB()[cfg.guidKey] = nil
                    rDB()[cfg.nameKey] = nil
                    Refresh()
                    UpdateMissing()
                end)
                y = y - 30
            end
        end
        -- Refresh every section's label when auto-detection updates.
        OnAutoDetect = function()
            for _, fn in ipairs(refreshers) do fn() end
        end

        y = ExsarUI.AddResetButton(parent, y, rDB, frame, "Raid debuffs", -300, 160)

        return y
    end,
})
