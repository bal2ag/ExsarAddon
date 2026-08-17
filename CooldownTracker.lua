-- CooldownTracker module
-- Displays a movable widget with spell icons and cooldown timers.
-- Settings are stored under ExsarAddonDB.cooldownTracker.

local ADDON_NAME = "ExsarAddon"

local cDB = ExsarUI.MakeDB("cooldownTracker")

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

local MIN_COOLDOWN_DURATION = ExsarLogic.MIN_COOLDOWN_DURATION

-- Glow border: bright highlight when ability is ready
local GLOW_COLOR = { 1.0, 0.82, 0.25, 0.85 }
local GLOW_SIZE  = 4  -- pixels outward from icon edge

-- Glow pulse: alpha oscillation to draw the eye
local GLOW_PULSE_HZ  = 1.2
local GLOW_PULSE_MIN = 0.45
local GLOW_PULSE_MAX = 1.0

local function AddGlow(parentFrame)
    local glow = {}
    -- Four edge textures forming a soft rectangular border
    local top = parentFrame:CreateTexture(nil, "ARTWORK")
    top:SetPoint("TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
    top:SetPoint("TOPRIGHT", GLOW_SIZE, GLOW_SIZE)
    top:SetHeight(GLOW_SIZE)
    top:SetColorTexture(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], GLOW_COLOR[4])
    glow[#glow + 1] = top

    local bot = parentFrame:CreateTexture(nil, "ARTWORK")
    bot:SetPoint("BOTTOMLEFT", -GLOW_SIZE, -GLOW_SIZE)
    bot:SetPoint("BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
    bot:SetHeight(GLOW_SIZE)
    bot:SetColorTexture(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], GLOW_COLOR[4])
    glow[#glow + 1] = bot

    local left = parentFrame:CreateTexture(nil, "ARTWORK")
    left:SetPoint("TOPLEFT", -GLOW_SIZE, GLOW_SIZE)
    left:SetPoint("BOTTOMLEFT", -GLOW_SIZE, -GLOW_SIZE)
    left:SetWidth(GLOW_SIZE)
    left:SetColorTexture(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], GLOW_COLOR[4])
    glow[#glow + 1] = left

    local right = parentFrame:CreateTexture(nil, "ARTWORK")
    right:SetPoint("TOPRIGHT", GLOW_SIZE, GLOW_SIZE)
    right:SetPoint("BOTTOMRIGHT", GLOW_SIZE, -GLOW_SIZE)
    right:SetWidth(GLOW_SIZE)
    right:SetColorTexture(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], GLOW_COLOR[4])
    glow[#glow + 1] = right

    for _, tex in ipairs(glow) do tex:Hide() end
    return glow
end

local function SetGlowActive(entry, active)
    entry.glowActive = active
    if active then
        for _, tex in ipairs(entry.glow) do tex:Show() end
    else
        for _, tex in ipairs(entry.glow) do tex:Hide() end
    end
end

local ICON_SIZE = 29
local ICON_GAP  = 4 + GLOW_SIZE * 2  -- extra space so glow borders don't overlap neighbors
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
ExsarUI.SetupMovableFrame(mainFrame, cDB)

-- =========================================================
-- Spell icon frames
-- =========================================================

local spellFrames = {}  -- flat, used by UpdateCooldowns
local spellGroups = {}  -- grouped, used by ApplyLayout

local spellBtnIndex = 0
for g, group in ipairs(SPELL_GROUPS) do
    spellGroups[g] = {}
    for _, spellDef in ipairs(group) do
        spellBtnIndex = spellBtnIndex + 1
        local sf = {
            spellName = spellDef.name,
            spellId   = spellDef.id,
            known     = not spellDef.id,  -- talent-gated spells start hidden
        }

        sf.frame = CreateFrame("Button", ADDON_NAME .. "CDSpell" .. spellBtnIndex, mainFrame, "SecureActionButtonTemplate")
        sf.frame:SetSize(ICON_SIZE, ICON_SIZE)
        sf.frame:SetPoint("LEFT", mainFrame, "LEFT", PADDING, 0)  -- repositioned by ApplyLayout
        sf.frame:RegisterForClicks("AnyUp", "AnyDown")
        sf.frame:SetAttribute("type", "spell")
        sf.frame:SetAttribute("spell", spellDef.name)

        sf.icon = ExsarUI.CreateIcon(sf.frame, "BACKGROUND")

        sf.cooldown = ExsarUI.CreateSweep(sf.frame)

        sf.text = ExsarUI.CreateCountdownText(sf.frame)

        sf.glow = AddGlow(sf.frame)

        sf.frame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            local id = sf.spellId or select(7, GetSpellInfo(sf.spellName))
            if id then GameTooltip:SetSpellByID(id) end
            GameTooltip:Show()
        end)
        sf.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        sf.frame:Hide()  -- shown by ApplyLayout once known status is determined
        spellFrames[#spellFrames + 1] = sf
        spellGroups[g][#spellGroups[g] + 1] = sf
    end
end

-- =========================================================
-- Trinket icon frames
-- =========================================================

-- Reuses the same visual structure as spell frames.
local trinketBtnIndex = 0
local function MakeIconFrame(slotId)
    trinketBtnIndex = trinketBtnIndex + 1
    local f = { known = false, slotId = slotId }

    f.frame = CreateFrame("Button", ADDON_NAME .. "CDTrinket" .. trinketBtnIndex, mainFrame, "SecureActionButtonTemplate")
    f.frame:SetSize(ICON_SIZE, ICON_SIZE)
    f.frame:SetPoint("LEFT", mainFrame, "LEFT", PADDING, 0)
    f.frame:RegisterForClicks("AnyUp", "AnyDown")
    f.frame:SetAttribute("type", "macro")
    f.frame:SetAttribute("macrotext", "/use " .. slotId)

    f.icon = ExsarUI.CreateIcon(f.frame, "BACKGROUND")

    f.cooldown = ExsarUI.CreateSweep(f.frame)

    f.text = ExsarUI.CreateCountdownText(f.frame)

    f.glow = AddGlow(f.frame)

    f.frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if f.slotId then
            GameTooltip:SetInventoryItem("player", f.slotId)
        end
        GameTooltip:Show()
    end)
    f.frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f.frame:Hide()
    return f
end

-- One frame per trinket slot; shown only when the slot has an on-use effect.
local trinketFrames = {
    MakeIconFrame(TRINKET_SLOT_1),  -- slot 13
    MakeIconFrame(TRINKET_SLOT_2),  -- slot 14
}

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
    local pending = false
    for _, tf in ipairs(trinketFrames) do
        local itemId    = GetInventoryItemID("player", tf.slotId)
        local spellName = itemId and itemId > 0 and GetItemSpell(itemId) or nil
        -- GetItemSpell returns nil when the item's data isn't cached (transient
        -- after a taxi / zoning), which is indistinguishable from a passive
        -- trinket unless we probe the cache: GetItemInfo ~= nil means loaded.
        local cached = not (itemId and itemId > 0) or GetItemInfo(itemId) ~= nil
        local state  = ExsarLogic.TrinketScanState(itemId, spellName, cached)

        if state == "pending" then
            -- Data not loaded yet -- keep the current display, request a load,
            -- and re-scan when GET_ITEM_INFO_RECEIVED fires (registered below).
            pending = true
            if C_Item and C_Item.RequestLoadItemDataByID then
                C_Item.RequestLoadItemDataByID(itemId)
            end
        else
            local wasKnown = tf.known
            tf.known = (state == "known")
            if tf.known then
                -- Refresh texture in case the item changed
                local tex = GetInventoryItemTexture("player", tf.slotId)
                if tex then tf.icon:SetTexture(tex) end
            else
                tf.icon:SetTexture(nil)
                tf.icon:SetDesaturated(false)
                tf.icon:SetAlpha(1.0)
                tf.cooldown:SetCooldown(0, 0)
                tf.text:SetText("")
            end
            if tf.known ~= wasKnown then changed = true end
        end
    end
    -- Only listen for item-data arrival while something is actually pending,
    -- so we don't re-scan on every unrelated GET_ITEM_INFO_RECEIVED.
    if pending then
        mainFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    else
        mainFrame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
    end
    if changed then ApplyLayout(cDB().groupGap or GROUP_GAP) end
end

-- =========================================================
-- Cooldown updates
-- =========================================================

local FormatCooldown = ExsarLogic.FormatCooldown

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
                SetGlowActive(sf, false)
            elseif onGCD then
                sf.icon:SetDesaturated(false)
                sf.icon:SetAlpha(1.0)
                sf.cooldown:SetCooldown(start, duration)
                local remaining = (start + duration) - now
                sf.text:SetText(remaining > 0 and FormatCooldown(remaining) or "")
                SetGlowActive(sf, false)
            else
                sf.icon:SetDesaturated(false)
                sf.icon:SetAlpha(1.0)
                sf.cooldown:SetCooldown(0, 0)
                sf.text:SetText("")
                SetGlowActive(sf, InCombatLockdown())
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
                SetGlowActive(tf, false)
            elseif onGCD then
                tf.icon:SetDesaturated(false)
                tf.icon:SetAlpha(1.0)
                tf.cooldown:SetCooldown(start, duration)
                local remaining = (start + duration) - now
                tf.text:SetText(remaining > 0 and FormatCooldown(remaining) or "")
                SetGlowActive(tf, false)
            else
                tf.icon:SetDesaturated(false)
                tf.icon:SetAlpha(1.0)
                tf.cooldown:SetCooldown(0, 0)
                tf.text:SetText("")
                SetGlowActive(tf, InCombatLockdown())
            end
        end
    end
end

local PulseAlpha = ExsarLogic.PulseAlpha

local function UpdateGlowPulse()
    local now = GetTime()
    local alpha = PulseAlpha(now, GLOW_PULSE_HZ, GLOW_PULSE_MIN, GLOW_PULSE_MAX)
    for _, sf in ipairs(spellFrames) do
        if sf.glowActive then
            for _, tex in ipairs(sf.glow) do tex:SetAlpha(alpha) end
        end
    end
    for _, tf in ipairs(trinketFrames) do
        if tf.glowActive then
            for _, tex in ipairs(tf.glow) do tex:SetAlpha(alpha) end
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
    UpdateGlowPulse()
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
        ExsarUI.RestorePosition(self, cDB, 0, -200)
    elseif event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
        -- Spell data available; check known spells, load textures, apply layout.
        -- SPELLS_CHANGED fires on talent changes so Bestial Wrath / Readiness
        -- appear or disappear immediately if the player respeccs.
        UpdateKnownSpells()
        UpdateCooldowns()
        ScanTrinkets()
        UpdateTrinketCooldowns()
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "GET_ITEM_INFO_RECEIVED" then
        -- Equipment change, or a previously-uncached trinket's data just arrived
        -- (GET_ITEM_INFO_RECEIVED, registered by ScanTrinkets only while pending).
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

-- /exsar lock and /exsar unlock are global (Core.lua) and cover this widget
-- along with every other, via its AddLockCheckbox registration.

ExsarUI.AddSlashReset("reset", mainFrame, cDB, "Cooldown tracker", 0, -200)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Cooldown Tracker",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, cDB, mainFrame)

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

        y = ExsarUI.AddLockCheckbox(parent, y, cDB, mainFrame)
        y = ExsarUI.AddResetButton(parent, y, cDB, mainFrame, "Cooldown tracker", 0, -200)

        return y
    end,
})
