-- ActiveEffectsTracker module
-- Shows icons with a marching-ants yellow border and countdown timer for
-- tracked active buffs on the player.  Includes both statically defined
-- effects and dynamically detected trinket on-use buffs.
-- Settings stored under ExsarAddonDB.activeEffects.

local ADDON_NAME = "ExsarAddon"

local aeDB = ExsarUI.MakeDB("activeEffects")

-- =========================================================
-- Static effect definitions
-- =========================================================
-- Each entry: { name = "Buff Name", id = spellId }
-- Detection tries spell ID first, then falls back to name.
-- Set id = nil to match by name only.
--
-- Notes:
--   "Bloodlust"        — Horde Shaman version
--   "Heroism"          — Alliance Draenei Shaman version (ID 32182)
--   "The Beast Within" — hunter buff while Bestial Wrath is active (requires talent)

local STATIC_EFFECTS = {
    { name = "Quick Shots",       id = 6150  },
    { name = "Haste Potion",      id = 26297 },
    { name = "Bloodlust",         id = 2825  },  -- Horde (Shaman)
    { name = "Heroism",           id = 32182 },  -- Alliance (Draenei Shaman)
    { name = "Rapid Fire",        id = 3045  },
    { name = "The Beast Within",  id = 34471 },
    { name = "Drums of Battle",   id = nil   },
}

-- Trinket inventory slots tracked dynamically via GetItemSpell
local TRINKET_SLOTS = { 13, 14 }

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

local frame = CreateFrame("Frame", ADDON_NAME .. "ActiveEffectsFrame", UIParent)
ExsarUI.SetupMovableFrame(frame, aeDB)

local placeholderText = frame:CreateFontString(nil, "OVERLAY")
placeholderText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
placeholderText:SetPoint("CENTER", frame, "CENTER", 0, 0)
placeholderText:SetTextColor(0.55, 0.55, 0.55, 0.9)
placeholderText:SetText("Active Effects")
placeholderText:Hide()

frame:Hide()

-- Cached lock state so ApplyLayout can decide whether to show a placeholder
local C_locked = false

-- =========================================================
-- Icon slot construction
-- =========================================================

local function BuildDashes(iconFrame)
    return ExsarUI.BuildDashes(iconFrame, ICON_SIZE, DASH_COUNT, BORDER_W)
end

local function MakeSlot()
    local s = {
        active  = false,
        expTime = 0,
        name    = nil,   -- buff name to match (static) or from GetItemSpell (dynamic)
        id      = nil,   -- spell ID to match (primary); nil = name-only match
        slotId  = nil,   -- trinket inventory slot (13/14) for dynamic slots; nil for static
    }

    s.iconFrame = CreateFrame("Frame", nil, frame)
    s.iconFrame:SetSize(ICON_SIZE, ICON_SIZE)

    s.glow  = ExsarUI.CreateGlow(s.iconFrame)
    s.icon  = ExsarUI.CreateIcon(s.iconFrame)
    s.sweep = ExsarUI.CreateSweep(s.iconFrame, { reverse = true })

    -- Marching-ants border dashes
    s.dashes = BuildDashes(s.iconFrame)

    -- Countdown timer text
    s.text = s.iconFrame:CreateFontString(nil, "OVERLAY")
    s.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    s.text:SetPoint("CENTER", s.iconFrame, "CENTER", 0, 0)
    s.text:SetTextColor(1, 1, 1, 1)
    s.text:SetText("")

    s.iconFrame:EnableMouse(true)
    s.iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if s.slotId then
            GameTooltip:SetInventoryItem("player", s.slotId)
        elseif s.id then
            GameTooltip:SetSpellByID(s.id)
        elseif s.name then
            local id = select(7, GetSpellInfo(s.name))
            if id then GameTooltip:SetSpellByID(id) end
        end
        GameTooltip:Show()
    end)
    s.iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    s.iconFrame:Hide()
    return s
end

-- All slots: static effects first, then dynamic trinket slots
local slots = {}
for _, effect in ipairs(STATIC_EFFECTS) do
    local s = MakeSlot()
    s.name = effect.name
    s.id   = effect.id
    slots[#slots + 1] = s
end
for _, slotId in ipairs(TRINKET_SLOTS) do
    local s = MakeSlot()
    s.slotId = slotId   -- id and name populated by ScanTrinkets()
    slots[#slots + 1] = s
end

-- =========================================================
-- Layout
-- =========================================================

local function ApplyLayout()
    local x       = PADDING
    local anyShown = false

    for _, s in ipairs(slots) do
        if s.active then
            s.iconFrame:ClearAllPoints()
            s.iconFrame:SetPoint("LEFT", frame, "LEFT", x, 0)
            s.iconFrame:Show()
            x = x + ICON_SIZE + ICON_GAP
            anyShown = true
        else
            s.iconFrame:Hide()
        end
    end

    if anyShown then
        frame:SetSize(x - ICON_GAP + PADDING, ICON_SIZE + PADDING * 2)
        placeholderText:Hide()
        frame:Show()
    elseif not C_locked then
        -- Unlocked with no active buffs: show a placeholder so the widget
        -- can be repositioned without needing a buff to be active.
        frame:SetSize(100, ICON_SIZE + PADDING * 2)
        placeholderText:Show()
        frame:Show()
    else
        placeholderText:Hide()
        frame:Hide()
    end
end

-- =========================================================
-- Trinket scanning
-- =========================================================

local function ScanTrinkets()
    for _, s in ipairs(slots) do
        if s.slotId then
            local itemId = GetInventoryItemID("player", s.slotId)
            if itemId and itemId > 0 then
                local spellName, spellId = GetItemSpell(itemId)
                s.name = spellName   -- nil if item has no use effect
                s.id   = spellId
            else
                s.name = nil
                s.id   = nil
            end
        end
    end
end

-- =========================================================
-- Buff scanning
-- =========================================================

-- Scan all current player buffs once per tick, building lookup tables
-- by spell ID and name.  Each slot is matched ID-first then name.
local lastTimeStrs = {}

local function UpdateBuffs()
    local now = GetTime()

    local byId   = {}
    local byName = {}
    for i = 1, 40 do
        local bName, bIcon, _, _, bDuration, bExpTime, _, _, _, bSpellId = UnitBuff("player", i)
        if not bName then break end
        if bSpellId and bSpellId > 0 then
            byId[bSpellId] = { icon = bIcon, expTime = bExpTime or 0, duration = bDuration or 0 }
        end
        if not byName[bName] then
            byName[bName] = { icon = bIcon, expTime = bExpTime or 0, duration = bDuration or 0 }
        end
    end

    local layoutChanged = false

    for i, s in ipairs(slots) do
        -- Skip dynamic trinket slots with no use effect
        if s.slotId and not s.id and not s.name then
            if s.active then
                s.active = false
                s.icon:SetTexture(nil)
                s.sweep:SetCooldown(0, 0)
                s.glow:Hide()
                s.text:SetText("")
                lastTimeStrs[i] = ""
                layoutChanged = true
            end
        else
            local match
            if s.id   then match = byId[s.id]     end
            if not match and s.name then match = byName[s.name] end

            local wasActive = s.active

            if match then
                s.active  = true
                s.expTime = match.expTime
                s.icon:SetTexture(match.icon)
                s.glow:Show()

                -- Reverse sweep: grows grey over the icon as the buff runs out.
                -- buffStart = expirationTime - totalDuration; SetReverse makes
                -- elapsed time show as filled grey rather than remaining time.
                if match.expTime > 0 and match.duration and match.duration > 0 then
                    s.sweep:SetCooldown(match.expTime - match.duration, match.duration)
                else
                    s.sweep:SetCooldown(0, 0)
                end

                local remaining = s.expTime > 0 and math.max(0, s.expTime - now) or nil
                local newStr
                if not remaining then
                    newStr = ""
                else
                    newStr = ExsarLogic.FormatCooldown(remaining)
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
    end

    if layoutChanged then ApplyLayout() end
end

-- =========================================================
-- Marching-ants animation (runs every frame via animTicker)
-- =========================================================

local function AnimateDashes()
    ExsarUI.AnimateDashes(slots, GetTime(), DASH_SPEED, DASH_COUNT, TAIL_LEN)
end

-- Dedicated always-on frame for smooth dash animation.  The main frame
-- may be hidden (no active buffs + locked), so we can't rely on its OnUpdate.
local animTicker = CreateFrame("Frame")
animTicker:Show()
animTicker:SetScript("OnUpdate", function() AnimateDashes() end)

-- =========================================================
-- OnUpdate: buff state + timer text (every 0.1 s)
-- =========================================================

local scanElapsed = 0
frame:SetScript("OnUpdate", function(self, elapsed)
    scanElapsed = scanElapsed + elapsed
    if scanElapsed >= 0.1 then
        scanElapsed = 0
        UpdateBuffs()
    end
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, aeDB, 0, -160)
        C_locked = aeDB().locked and true or false
        ApplyLayout()

    elseif event == "PLAYER_ENTERING_WORLD" then
        ScanTrinkets()
        UpdateBuffs()

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then UpdateBuffs() end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        ScanTrinkets()
        UpdateBuffs()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("effectsreset", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
    aeDB().x = nil
    aeDB().y = nil
    print(ADDON_NAME .. ": Active effects tracker position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Active Effects Tracker",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, aeDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, aeDB, frame, function(v)
            C_locked = v
            ApplyLayout()
        end)

        y = ExsarUI.AddResetButton(parent, y, aeDB, frame, "Active effects", 0, -160)

        return y
    end,
})
