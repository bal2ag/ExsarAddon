-- ConsumableBuffWidget module
-- Always shows tracked consumable item icons with bag counts (greyed when
-- depleted).  When the corresponding buff is active on the player, adds a
-- marching-ants yellow border, a reverse cooldown sweep, and a countdown
-- timer.  Buff matched by spell ID to avoid false positives on shared names.
-- Settings stored under ExsarAddonDB.consumableBuff.

local ADDON_NAME = "ExsarAddon"

local function cbDB()
    ExsarAddonDB.consumableBuff = ExsarAddonDB.consumableBuff or {}
    return ExsarAddonDB.consumableBuff
end

-- =========================================================
-- Item / buff definitions
-- =========================================================
-- buffId: spell ID of the buff applied by this consumable; used for precise
-- matching when buffName is shared across multiple spells (e.g. "Well Fed").

local TRACKED_ITEMS = {
    { name = "Flask of Relentless Assault",   id = 22854, buffName = "Flask of Relentless Assault", buffId = 28520 },
    { name = "Elixir of Major Agility",       id = 22831, buffName = "Major Agility",               buffId = 28497 },
    { name = "Elixir of Demonslaying",        id = 9224,  buffName = "Elixir of Demonslaying",      buffId = 11406 },
    { name = "Elixir of Major Mageblood",     id = 22840, buffName = "Greater Mana Regeneration",   buffId = 28509 },
    { name = "Scroll of Agility V",           id = 27498, buffName = "Agility",                     buffId = 33077 },
    { name = "Adamantite Sharpening Stone",   id = 23529, buffName = "Sharpen Blade",               buffId = 29453 },
    { name = "Grilled Mudfish",               id = 27664, buffName = "Well Fed",                    buffId = 33261 },
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
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetClampedToScreen(true)
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local _, _, _, x, y = self:GetPoint()
    cbDB().x = x
    cbDB().y = y
end)

local frameBg = frame:CreateTexture(nil, "BACKGROUND")
frameBg:SetAllPoints()
frameBg:SetColorTexture(0, 0, 0, 0.6)

frame:Hide()

local C_locked = false

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
    s.icon = s.iconFrame:CreateTexture(nil, "ARTWORK")
    s.icon:SetAllPoints()
    s.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local iconTex = select(10, GetItemInfo(item.id))
    if iconTex then s.icon:SetTexture(iconTex) end

    -- Reverse cooldown sweep: grey fills the icon as the buff expires.
    s.sweep = CreateFrame("Cooldown", nil, s.iconFrame, "CooldownFrameTemplate")
    s.sweep:SetAllPoints()
    s.sweep:SetDrawEdge(false)
    if s.sweep.SetHideCountdownNumbers then
        s.sweep:SetHideCountdownNumbers(true)
    end
    if s.sweep.SetReverse then
        s.sweep:SetReverse(true)
    end

    -- Countdown timer text (center of icon; only shown when buff is active)
    s.timeText = s.iconFrame:CreateFontString(nil, "OVERLAY")
    s.timeText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    s.timeText:SetPoint("CENTER", s.iconFrame, "CENTER", 0, 0)
    s.timeText:SetTextColor(1, 1, 1, 1)
    s.timeText:SetText("")

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

    for _, s in ipairs(slots) do
        local match = activeById[s.buffId]

        if match and match.duration > 0 then
            s.buffActive = true
            s.glow:Show()
            s.sweep:SetCooldown(match.expTime - match.duration, match.duration)

            local remaining = math.max(0, match.expTime - now)
            local newStr
            if remaining >= 60 then
                newStr = string.format("%dm", math.floor(remaining / 60))
            elseif remaining >= 10 then
                newStr = string.format("%d", math.ceil(remaining))
            else
                newStr = string.format("%.1f", remaining)
            end
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
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        local db = cbDB()
        if db.x and db.y then
            self:ClearAllPoints()
            self:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        else
            self:SetPoint("CENTER", UIParent, "CENTER", 200, -160)
        end
        self:SetScale(db.scale or 1.0)
        self:EnableMouse(not db.locked)
        C_locked = db.locked and true or false
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
        if arg1 == "player" then UpdateBuffs() end

    elseif event == "ITEM_DATA_LOAD_RESULT" then
        ScanBags()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarAddon.AddSlashCommand("consumablebuffreset", function()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 200, -160)
    cbDB().x = nil
    cbDB().y = nil
    print(ADDON_NAME .. ": Consumable buff widget position reset.")
end)

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Consumable Buffs",
    BuildConfig = function(parent, y)
        ExsarAddon.CreateSlider(parent, "Widget Scale", 16, y, 0.5, 3.0, 0.05,
            function() return cbDB().scale or 1.0 end,
            function(v)
                local rounded = math.floor(v * 20 + 0.5) / 20
                cbDB().scale = rounded
                frame:SetScale(rounded)
            end
        )
        y = y - 55

        ExsarAddon.CreateCheckbox(parent, "Lock widget position", 16, y,
            function() return cbDB().locked and true or false end,
            function(v)
                cbDB().locked = v
                C_locked = v
                frame:EnableMouse(not v)
            end
        )
        y = y - 30

        ExsarAddon.CreateButton(parent, "Reset Position", 16, y, function()
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 200, -160)
            cbDB().x = nil
            cbDB().y = nil
            print(ADDON_NAME .. ": Consumable buff widget position reset.")
        end)
        y = y - 30

        return y
    end,
})
