-- CooldownTracker module
-- Displays a movable widget with spell icons and cooldown timers.
-- Settings are stored under ExsarAddonDB.cooldownTracker.

local ADDON_NAME = "ExsarAddon"

local function cDB()
    ExsarAddonDB.cooldownTracker = ExsarAddonDB.cooldownTracker or {}
    return ExsarAddonDB.cooldownTracker
end

-- =========================================================
-- Spell definitions
-- =========================================================

-- Groups are laid out together; extra space is added between groups.
-- Spells with an `id` are only shown when that spell is in the player's spellbook
-- (used for talent-gated abilities like Bestial Wrath and Readiness).
local SPELL_GROUPS = {
    {
        { name = "Multi-Shot"  },
        { name = "Arcane Shot" },
    },
    {
        { name = "Rapid Fire"     },
        { name = "Bestial Wrath", id = 19574 },
        { name = "Readiness",     id = 23989 },
    },
}

-- Cooldowns at or below this duration are just the GCD, not a real cooldown
local MIN_COOLDOWN_DURATION = 1.6

local ICON_SIZE = 29
local ICON_GAP  = 4
local GROUP_GAP = 14  -- default extra space between groups
local PADDING   = 6

-- Inventory slots for trinkets
local TRINKET_SLOT_1 = 13
local TRINKET_SLOT_2 = 14

-- =========================================================
-- Main frame
-- =========================================================

local totalIcons = 0
for _, group in ipairs(SPELL_GROUPS) do totalIcons = totalIcons + #group end
local initWidth = PADDING * 2
    + totalIcons * ICON_SIZE
    + (totalIcons - 1) * ICON_GAP
    + (#SPELL_GROUPS - 1) * GROUP_GAP

local mainFrame = CreateFrame("Frame", ADDON_NAME .. "CooldownFrame", UIParent)
mainFrame:SetSize(initWidth, ICON_SIZE + PADDING * 2)
mainFrame:SetMovable(true)
mainFrame:EnableMouse(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetClampedToScreen(true)

local bg = mainFrame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.6)

mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    cDB().x = x
    cDB().y = y
end)

-- =========================================================
-- Spell icon frames
-- =========================================================

local spellFrames = {}  -- flat, used by UpdateCooldowns
local spellGroups = {}  -- grouped, used by ApplyLayout

for g, group in ipairs(SPELL_GROUPS) do
    spellGroups[g] = {}
    for _, spellDef in ipairs(group) do
        local sf = {
            spellName = spellDef.name,
            spellId   = spellDef.id,
            known     = not spellDef.id,  -- talent-gated spells start hidden
        }

        sf.frame = CreateFrame("Frame", nil, mainFrame)
        sf.frame:SetSize(ICON_SIZE, ICON_SIZE)
        sf.frame:SetPoint("LEFT", mainFrame, "LEFT", PADDING, 0)  -- repositioned by ApplyLayout

        sf.icon = sf.frame:CreateTexture(nil, "BACKGROUND")
        sf.icon:SetAllPoints()
        sf.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- trim the default icon border

        sf.cooldown = CreateFrame("Cooldown", nil, sf.frame, "CooldownFrameTemplate")
        sf.cooldown:SetAllPoints()
        sf.cooldown:SetDrawEdge(false)
        if sf.cooldown.SetHideCountdownNumbers then
            sf.cooldown:SetHideCountdownNumbers(true)
        end

        sf.text = sf.frame:CreateFontString(nil, "OVERLAY")
        sf.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        sf.text:SetPoint("CENTER", sf.frame, "CENTER", 0, 0)
        sf.text:SetText("")

        sf.frame:Hide()  -- shown by ApplyLayout once known status is determined
        spellFrames[#spellFrames + 1] = sf
        spellGroups[g][#spellGroups[g] + 1] = sf
    end
end

-- =========================================================
-- Trinket icon frames
-- =========================================================

-- Reuses the same visual structure as spell frames.
local function MakeIconFrame()
    local f = { known = false }

    f.frame = CreateFrame("Frame", nil, mainFrame)
    f.frame:SetSize(ICON_SIZE, ICON_SIZE)
    f.frame:SetPoint("LEFT", mainFrame, "LEFT", PADDING, 0)

    f.icon = f.frame:CreateTexture(nil, "BACKGROUND")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    f.cooldown = CreateFrame("Cooldown", nil, f.frame, "CooldownFrameTemplate")
    f.cooldown:SetAllPoints()
    f.cooldown:SetDrawEdge(false)
    if f.cooldown.SetHideCountdownNumbers then
        f.cooldown:SetHideCountdownNumbers(true)
    end

    f.text = f.frame:CreateFontString(nil, "OVERLAY")
    f.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    f.text:SetPoint("CENTER", f.frame, "CENTER", 0, 0)
    f.text:SetText("")

    f.frame:Hide()
    return f
end

-- One frame per trinket slot; shown only when the slot has an on-use effect.
local trinketFrames = {
    MakeIconFrame(),  -- slot 13
    MakeIconFrame(),  -- slot 14
}
trinketFrames[1].slotId = TRINKET_SLOT_1
trinketFrames[2].slotId = TRINKET_SLOT_2

-- =========================================================
-- Layout
-- =========================================================

local function ApplyLayout(gap)
    local x = PADDING
    local anyPlaced = false

    -- Trinket group: shown first (left side) when any trinket has an on-use effect
    local trinketVisible = {}
    for _, tf in ipairs(trinketFrames) do
        if tf.known then trinketVisible[#trinketVisible + 1] = tf
        else tf.frame:Hide() end
    end
    if #trinketVisible > 0 then
        for _, tf in ipairs(trinketVisible) do
            tf.frame:ClearAllPoints()
            tf.frame:SetPoint("LEFT", mainFrame, "LEFT", x, 0)
            tf.frame:Show()
            x = x + ICON_SIZE + ICON_GAP
            anyPlaced = true
        end
    end

    for _, group in ipairs(spellGroups) do
        local visible = {}
        for _, sf in ipairs(group) do
            if sf.known then
                visible[#visible + 1] = sf
            else
                sf.frame:Hide()
            end
        end

        if #visible > 0 then
            if anyPlaced then
                x = x + gap  -- extra separator before this group
            end
            for _, sf in ipairs(visible) do
                sf.frame:ClearAllPoints()
                sf.frame:SetPoint("LEFT", mainFrame, "LEFT", x, 0)
                sf.frame:Show()
                x = x + ICON_SIZE + ICON_GAP
                anyPlaced = true
            end
        end
    end

    local newWidth = anyPlaced and (x - ICON_GAP + PADDING) or (PADDING * 2)
    mainFrame:SetSize(newWidth, ICON_SIZE + PADDING * 2)
end

-- Checks which spells are in the player's spellbook, loads any missing icon
-- textures, then re-runs the layout. Called on login and whenever spells change.
local function UpdateKnownSpells()
    for _, sf in ipairs(spellFrames) do
        if sf.spellId then
            if _G.IsSpellKnown then
                sf.known = _G.IsSpellKnown(sf.spellId)
            else
                sf.known = GetSpellInfo(sf.spellName) ~= nil
            end
        else
            sf.known = true
        end

        if sf.known and not sf.icon:GetTexture() then
            local _, _, iconTexture = GetSpellInfo(sf.spellName)
            if iconTexture then
                sf.icon:SetTexture(iconTexture)
            end
        end
    end

    ApplyLayout(cDB().groupGap or GROUP_GAP)
end

-- Checks each trinket slot for an equipped item with a USE effect.
-- Loads the icon texture and updates the layout.  Called on login,
-- world entry, and whenever equipment changes.
local function ScanTrinkets()
    local changed = false
    for _, tf in ipairs(trinketFrames) do
        local itemId   = GetInventoryItemID("player", tf.slotId)
        local wasKnown = tf.known
        tf.known = false
        if itemId and itemId > 0 then
            local spellName = GetItemSpell(itemId)
            if spellName then
                tf.known = true
                -- Refresh texture in case the item changed
                local tex = GetInventoryItemTexture("player", tf.slotId)
                if tex then tf.icon:SetTexture(tex) end
            end
        end
        if not tf.known then
            tf.icon:SetTexture(nil)
            tf.icon:SetDesaturated(false)
            tf.icon:SetAlpha(1.0)
            tf.cooldown:SetCooldown(0, 0)
            tf.text:SetText("")
        end
        if tf.known ~= wasKnown then changed = true end
    end
    if changed then ApplyLayout(cDB().groupGap or GROUP_GAP) end
end

-- =========================================================
-- Cooldown updates
-- =========================================================

local function FormatCooldown(remaining)
    if remaining >= 60 then
        return string.format("%dm", math.floor(remaining / 60))
    elseif remaining >= 10 then
        return string.format("%d", math.ceil(remaining))
    else
        return string.format("%.1f", remaining)
    end
end

local function UpdateCooldowns()
    local now = GetTime()
    for _, sf in ipairs(spellFrames) do
        if sf.known then
            local start, duration = GetSpellCooldown(sf.spellName)
            local onCooldown = start and start > 0 and duration and duration > MIN_COOLDOWN_DURATION
            local onGCD      = not onCooldown and start and start > 0 and duration and duration > 0

            if onCooldown then
                sf.icon:SetDesaturated(true)
                sf.icon:SetAlpha(0.4)
                sf.cooldown:SetCooldown(start, duration)
                local remaining = (start + duration) - now
                sf.text:SetText(remaining > 0 and FormatCooldown(remaining) or "")
            elseif onGCD then
                sf.icon:SetDesaturated(false)
                sf.icon:SetAlpha(1.0)
                sf.cooldown:SetCooldown(start, duration)
                local remaining = (start + duration) - now
                sf.text:SetText(remaining > 0 and FormatCooldown(remaining) or "")
            else
                sf.icon:SetDesaturated(false)
                sf.icon:SetAlpha(1.0)
                sf.cooldown:SetCooldown(0, 0)
                sf.text:SetText("")
            end
        end
    end
end

local function UpdateTrinketCooldowns()
    local now = GetTime()
    for _, tf in ipairs(trinketFrames) do
        if tf.known then
            local start, duration = GetInventoryItemCooldown("player", tf.slotId)
            local onCD  = start and start > 0 and duration and duration > MIN_COOLDOWN_DURATION
            local onGCD = not onCD and start and start > 0 and duration and duration > 0
            if onCD then
                tf.icon:SetDesaturated(true)
                tf.icon:SetAlpha(0.4)
                tf.cooldown:SetCooldown(start, duration)
                local remaining = (start + duration) - now
                tf.text:SetText(remaining > 0 and FormatCooldown(remaining) or "")
            elseif onGCD then
                tf.icon:SetDesaturated(false)
                tf.icon:SetAlpha(1.0)
                tf.cooldown:SetCooldown(start, duration)
                local remaining = (start + duration) - now
                tf.text:SetText(remaining > 0 and FormatCooldown(remaining) or "")
            else
                tf.icon:SetDesaturated(false)
                tf.icon:SetAlpha(1.0)
                tf.cooldown:SetCooldown(0, 0)
                tf.text:SetText("")
            end
        end
    end
end

local updateElapsed = 0
mainFrame:SetScript("OnUpdate", function(self, elapsed)
    updateElapsed = updateElapsed + elapsed
    if updateElapsed >= 0.1 then
        updateElapsed = 0
        UpdateCooldowns()
        UpdateTrinketCooldowns()
    end
end)

-- =========================================================
-- Events
-- =========================================================

mainFrame:RegisterEvent("ADDON_LOADED")
mainFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
mainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mainFrame:RegisterEvent("SPELLS_CHANGED")
mainFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

mainFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        local db = cDB()
        if db.x and db.y then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        else
            self:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
        end
        mainFrame:SetScale(db.scale or 1.0)
        mainFrame:EnableMouse(not db.locked)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
        -- Spell data available; check known spells, load textures, apply layout.
        -- SPELLS_CHANGED fires on talent changes so Bestial Wrath / Readiness
        -- appear or disappear immediately if the player respeccs.
        UpdateKnownSpells()
        UpdateCooldowns()
        ScanTrinkets()
        UpdateTrinketCooldowns()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        ScanTrinkets()
        UpdateTrinketCooldowns()
    else
        UpdateCooldowns()
        UpdateTrinketCooldowns()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("lock", function()
    cDB().locked = true
    mainFrame:EnableMouse(false)
    print(ADDON_NAME .. ": Cooldown tracker locked.")
end)

ExsarAddon.AddSlashCommand("unlock", function()
    cDB().locked = false
    mainFrame:EnableMouse(true)
    print(ADDON_NAME .. ": Cooldown tracker unlocked.")
end)

ExsarAddon.AddSlashCommand("reset", function()
    mainFrame:ClearAllPoints()
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    cDB().x = nil
    cDB().y = nil
    print(ADDON_NAME .. ": Cooldown tracker position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Cooldown Tracker",
    BuildConfig = function(parent, y)
        -- Scale slider
        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return cDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                cDB().scale = rounded
                mainFrame:SetScale(rounded)
            end
        )
        y = y - 55

        -- Group spacing slider
        ExsarAddon.CreateSlider(parent, "Group Spacing", 16, y, 0, 40, 1,
            function() return cDB().groupGap or GROUP_GAP end,
            function(v)
                local gap = math.floor(v + 0.5)
                cDB().groupGap = gap
                ApplyLayout(gap)
            end
        )
        y = y - 55

        -- Lock checkbox
        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return cDB().locked and true or false end,
            function(v)
                cDB().locked = v
                mainFrame:EnableMouse(not v)
            end
        )
        y = y - 30

        -- Reset position button
        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
            cDB().x = nil
            cDB().y = nil
            print(ADDON_NAME .. ": Cooldown tracker position reset.")
        end)
        y = y - 30

        return y
    end,
})
