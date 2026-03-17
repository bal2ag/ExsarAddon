-- ConsumableBuffWidget module
-- Always shows tracked consumable item icons with bag counts (greyed when
-- depleted).  When the corresponding buff is active on the player, adds a
-- marching-ants yellow border, a reverse cooldown sweep, and a countdown
-- timer.  Buff matched by spell ID to avoid false positives on shared names.
-- Settings stored under ExsarAddonDB.consumableBuff.

local ADDON_NAME = "ExsarAddon"

local cbDB = ExsarUI.MakeDB("consumableBuff")

-- =========================================================
-- Item / buff definitions
-- =========================================================
-- buffId: spell ID of the buff applied by this consumable; used for precise
-- matching when buffName is shared across multiple spells (e.g. "Well Fed").

local TRACKED_ITEMS = {
    { name = "Kibler's Bits",                 id = 33874, buffName = "Kibler's Bits",               buffId = 43771, unit = "pet" },
    { name = "Flask of Relentless Assault",   id = 22854, buffName = "Flask of Relentless Assault", buffId = 28520 },
    { name = "Elixir of Major Agility",       id = 22831, buffName = "Major Agility",               buffId = 28497 },
    { name = "Elixir of Demonslaying",        id = 9224,  buffName = "Elixir of Demonslaying",      buffId = 11406 },
    { name = "Elixir of Major Mageblood",     id = 22840, buffName = "Greater Mana Regeneration",   buffId = 28509 },
    { name = "Scroll of Agility V",           id = 27498, buffName = "Agility",                     buffId = 33077 },
    { name = "Adamantite Sharpening Stone",   id = 23529, weaponSlot = "mainhand", buffDuration = 1800 },
    { name = "Grilled Mudfish",               id = 27664, buffName = "Well Fed",                    buffId = 33261 },
    { name = "Spicy Hot Talbuk",             id = 33872, buffName = "Well Fed",                    buffId = 43763 },
}

-- =========================================================
-- Layout constants
-- =========================================================

local ICON_SIZE  = 29
local ICON_GAP   = 4
local PADDING    = 6


local NUM_ITEMS = #TRACKED_ITEMS
local GRID_W = NUM_ITEMS * ICON_SIZE + (NUM_ITEMS - 1) * ICON_GAP + PADDING * 2
local GRID_H = ICON_SIZE + PADDING * 2

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "ConsumableBuffFrame", UIParent)
ExsarUI.SetupMovableFrame(frame, cbDB)

frame:Hide()

-- =========================================================
-- Slot construction
-- =========================================================

-- Request data for items the client may not have cached yet (e.g. never
-- picked up).  ITEM_DATA_LOAD_RESULT fires when each one is ready.
if C_Item and C_Item.RequestLoadItemDataByID then
    for _, item in ipairs(TRACKED_ITEMS) do
        C_Item.RequestLoadItemDataByID(item.id)
    end
end

local slots = {}

for i, item in ipairs(TRACKED_ITEMS) do
    local s = {
        itemId      = item.id,
        itemName    = item.name,
        buffName    = item.buffName,
        buffId      = item.buffId,
        unit        = item.unit or "player",
        weaponSlot  = item.weaponSlot,
        buffDuration = item.buffDuration,
        count       = -1,
        known       = false,
        buffActive  = false,
        lastTimeStr = "",
    }

    s.iconFrame = CreateFrame("Button", ADDON_NAME .. "ConsumableBtn" .. i, frame,
                              "SecureActionButtonTemplate")
    s.iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
    -- Both AnyUp and AnyDown required for TBC Classic Anniversary.
    s.iconFrame:RegisterForClicks("AnyUp", "AnyDown")
    s.iconFrame:SetAttribute("type", "item")
    s.iconFrame:SetAttribute("item", item.name)
    s.iconFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(s.itemId)
        GameTooltip:Show()
    end)
    s.iconFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    s.iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT",
        PADDING + (i - 1) * (ICON_SIZE + ICON_GAP), -PADDING)

    -- Glow: extends 4 px beyond icon on each side; only the outer ring is
    -- visible because slotBg (fully opaque, created after) covers the center.
    s.glow = s.iconFrame:CreateTexture(nil, "BACKGROUND")
    s.glow:SetPoint("TOPLEFT",     s.iconFrame, "TOPLEFT",     -4,  4)
    s.glow:SetPoint("BOTTOMRIGHT", s.iconFrame, "BOTTOMRIGHT",  4, -4)
    s.glow:SetColorTexture(1, 0.85, 0, 0.70)
    s.glow:Hide()

    -- Fully opaque slot background; covers glow center, keeps icon readable.
    local slotBg = s.iconFrame:CreateTexture(nil, "BACKGROUND")
    slotBg:SetAllPoints()
    slotBg:SetColorTexture(0, 0, 0, 1.0)

    -- Item icon
    s.icon = ExsarUI.CreateIcon(s.iconFrame)

    local iconTex = select(10, GetItemInfo(item.id))
    if iconTex then s.icon:SetTexture(iconTex) end

    -- Reverse cooldown sweep: grey fills the icon as the buff expires.
    s.sweep = ExsarUI.CreateSweep(s.iconFrame, { reverse = true })

    -- Countdown timer text (center of icon; only shown when buff is active)
    s.timeText = ExsarUI.CreateCountdownText(s.iconFrame)

    -- Stack count (bottom-right corner)
    s.countText = s.iconFrame:CreateFontString(nil, "OVERLAY")
    s.countText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    s.countText:SetPoint("BOTTOMRIGHT", s.iconFrame, "BOTTOMRIGHT", 1, 1)
    s.countText:SetTextColor(1, 1, 0.8, 1)
    s.countText:SetText("")

    s.iconFrame:Show()
    slots[#slots + 1] = s
end

-- =========================================================
-- Layout
-- =========================================================

local function ApplyLayout()
    frame:SetSize(GRID_W, GRID_H)
    frame:Show()
end

-- =========================================================
-- Bag scanning
-- =========================================================

local function ScanBags()
    for _, s in ipairs(slots) do
        local count = GetItemCount(s.itemId)
        s.known = count > 0

        if count ~= s.count then
            s.count = count
            s.countText:SetText(count == 0 and "0" or tostring(count))
        end

        if not s.icon:GetTexture() then
            local tex = select(10, GetItemInfo(s.itemId))
            if tex then s.icon:SetTexture(tex) end
        end

        s.icon:SetDesaturated(not s.known)
        s.icon:SetAlpha(s.known and 1.0 or 0.35)
    end
end

-- =========================================================
-- Buff scanning
-- =========================================================

local function UpdateBuffs()
    local now = GetTime()

    local activeById = {}
    for i = 1, 40 do
        local bName, _, _, _, bDuration, bExpTime, _, _, _, bSpellId = UnitBuff("player", i)
        if not bName then break end
        if bSpellId then
            activeById[bSpellId] = { duration = bDuration or 0, expTime = bExpTime or 0 }
        end
    end

    local petActiveById = {}
    if UnitExists("pet") then
        for i = 1, 40 do
            local bName, _, _, _, bDuration, bExpTime, _, _, _, bSpellId = UnitBuff("pet", i)
            if not bName then break end
            if bSpellId then
                petActiveById[bSpellId] = { duration = bDuration or 0, expTime = bExpTime or 0 }
            end
        end
    end

    -- Weapon enchant info (temporary sharpening/weightstones etc.)
    local hasMainEnchant, mainExpMs = GetWeaponEnchantInfo()

    for _, s in ipairs(slots) do
        local match
        if s.weaponSlot == "mainhand" then
            if hasMainEnchant and mainExpMs and mainExpMs > 0 then
                local remaining = mainExpMs / 1000
                local duration = s.buffDuration or remaining
                -- Cache start time so SetCooldown receives stable values
                -- and the sweep animation doesn't reset every poll cycle.
                if not s.enchantStart then
                    s.enchantStart = now + remaining - duration
                end
                local expTime = s.enchantStart + duration
                match = { duration = duration, expTime = expTime }
            else
                s.enchantStart = nil
            end
        elseif s.unit == "pet" then
            match = petActiveById[s.buffId]
        else
            match = activeById[s.buffId]
        end

        if match and match.duration > 0 then
            s.buffActive = true
            s.glow:Show()
            s.sweep:SetCooldown(match.expTime - match.duration, match.duration)

            local remaining = math.max(0, match.expTime - now)
            local newStr = ExsarLogic.FormatCooldown(remaining)
            if newStr ~= s.lastTimeStr then
                s.lastTimeStr = newStr
                s.timeText:SetText(newStr)
            end
        else
            s.buffActive  = false
            s.glow:Hide()
            s.sweep:SetCooldown(0, 0)
            if s.lastTimeStr ~= "" then
                s.lastTimeStr = ""
                s.timeText:SetText("")
            end
        end
    end
end

-- =========================================================
-- OnUpdate: buff timer text (every 0.1 s)
-- =========================================================

ExsarUI.CreatePoller(frame, 0.1, UpdateBuffs)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("UNIT_INVENTORY_CHANGED")
frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
frame:RegisterEvent("UNIT_PET")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, cbDB, 200, -160)
        ApplyLayout()

    elseif event == "PLAYER_ENTERING_WORLD" then
        ScanBags()
        UpdateBuffs()

    elseif event == "PLAYER_ALIVE" then
        ScanBags()
        UpdateBuffs()

    elseif event == "BAG_UPDATE" then
        ScanBags()

    elseif event == "UNIT_AURA" then
        if arg1 == "player" or arg1 == "pet" then UpdateBuffs() end

    elseif event == "UNIT_PET" then
        UpdateBuffs()

    elseif event == "UNIT_INVENTORY_CHANGED" then
        UpdateBuffs()

    elseif event == "ITEM_DATA_LOAD_RESULT" then
        ScanBags()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarUI.AddSlashReset("consumablebuffreset", frame, cbDB, "Consumable buff widget", 200, -160)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Consumable Buffs",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, cbDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, cbDB, frame)

        y = ExsarUI.AddResetButton(parent, y, cbDB, frame, "Consumable buffs", 200, -160)

        return y
    end,
})
