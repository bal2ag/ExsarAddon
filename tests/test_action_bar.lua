-- tests/test_action_bar.lua
-- Contract tests for the ExsarUI.CreateActionBar features the cooldown trackers
-- are built on: `hideWhenNoUse` trinket slots, the `readyPulse` ready state, and
-- `hideEmptyBar`.
--
-- Like tests/test_maelstrom.lua (and unlike tests/test_ui_contracts.lua, which
-- re-declares copies), this loads the REAL ExsarUI.lua behind stubbed WoW
-- globals, so the engine under test cannot drift away from a copy. The stubs are
-- mutable module-level tables the tests drive: set the equipped trinket, the
-- cooldown a spell reports, or the combat flag, then pump the bar's Refresh and
-- assert on the slot state the engine derived.

package.path = package.path .. ";./?.lua;../?.lua"
local Logic = require("ExsarLogic")

-- =========================================================
-- Mutable world state the tests drive
-- =========================================================

local W = {}

local function resetWorld()
    W.inCombat      = false
    W.time          = 1000
    W.trinketItem   = { [13] = nil, [14] = nil }  -- slot -> item id
    W.itemSpell     = {}   -- item id -> on-use spell name (nil = passive/proc)
    W.itemCached    = {}   -- item id -> bool
    W.trinketCd     = {}   -- slot -> { start, duration }
    W.spellCd       = {}   -- spell name -> { start, duration }
    W.knownSpells   = {}   -- spell name -> bool
    W.loadRequests  = {}
end
resetWorld()

-- =========================================================
-- Recording stubs
-- =========================================================

local NOOP_FALLBACK
NOOP_FALLBACK = { __index = function() return function() end end }

local function stubTexture(layer)
    local t = setmetatable({ layer = layer, shown = false }, NOOP_FALLBACK)
    function t:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
    function t:SetTexture(p)  self.texture = p end
    function t:GetTexture()   return self.texture end
    function t:SetAlpha(a)    self.alpha = a end
    function t:Show()         self.shown = true end
    function t:Hide()         self.shown = false end
    function t:SetShown(v)    self.shown = v and true or false end
    function t:IsShown()      return self.shown end
    return t
end

local function stubFontString()
    local fs = setmetatable({}, NOOP_FALLBACK)
    function fs:SetText(v) self.text = v end
    function fs:GetText()  return self.text end
    function fs:Show()     self.shown = true end
    function fs:Hide()     self.shown = false end
    function fs:IsShown()  return self.shown end
    return fs
end

local function stubFrame()
    local f = setmetatable({
        textures = {}, scripts = {}, attrs = {}, events = {}, shown = false,
    }, NOOP_FALLBACK)
    function f:CreateTexture(_, layer)
        local t = stubTexture(layer)
        self.textures[#self.textures + 1] = t
        return t
    end
    function f:CreateFontString() return stubFontString() end
    function f:SetSize(w, h)      self.w, self.h = w, h end
    function f:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
    function f:ClearAllPoints()   self.x, self.y = nil, nil end
    function f:SetScript(n, fn)   self.scripts[n] = fn end
    function f:RegisterEvent(e)   self.events[e] = true end
    function f:SetAttribute(k, v) self.attrs[k] = v end
    function f:GetAttribute(k)    return self.attrs[k] end
    function f:Show()             self.shown = true end
    function f:Hide()             self.shown = false end
    function f:SetShown(v)        self.shown = v and true or false end
    function f:IsShown()          return self.shown end
    return f
end

-- ---------- WoW API surface CreateActionBar touches ----------
_G.ExsarLogic   = Logic
_G.ExsarAddonDB = {}
_G.UIParent     = _G.UIParent   or {}
_G.WorldFrame   = _G.WorldFrame or {}
_G.ExsarAddon   = setmetatable({}, { __index = function() return function() end end })

_G.GetTime           = function() return W.time end
_G.InCombatLockdown  = function() return W.inCombat end
_G.GetRealZoneText   = function() return "Nowhere" end
_G.UnitExists        = function() return false end
_G.UnitIsDead        = function() return false end
_G.UnitBuff          = function() return nil end
_G.UnitDebuff        = function() return nil end
_G.GetItemCount      = function() return 0 end
_G.IsUsableSpell     = function() return true, false end
_G.IsSpellInRange    = function() return nil end
_G.GetSpellLink      = function() return nil end
_G.GetSpellTexture   = function(n) return "tex:" .. tostring(n) end
_G.GetSpellInfo      = function(n) return W.knownSpells[n] and n or nil end
_G.IsSpellKnown      = function() return true end
_G.GetItemInfo       = function(id) return W.itemCached[id] and ("item" .. id) or nil end
_G.GetItemInfoInstant = function() return nil end
_G.GetItemSpell      = function(id) return W.itemSpell[id] end
_G.GetInventoryItemID      = function(_, slot) return W.trinketItem[slot] end
_G.GetInventoryItemTexture = function(_, slot)
    local id = W.trinketItem[slot]
    return id and ("trinkettex:" .. id) or nil
end
_G.GetInventoryItemCooldown = function(_, slot)
    local cd = W.trinketCd[slot]
    if not cd then return 0, 0 end
    return cd[1], cd[2]
end
_G.GetSpellCooldown = function(name)
    local cd = W.spellCd[name]
    if not cd then return 0, 0 end
    return cd[1], cd[2]
end
_G.C_Item = { RequestLoadItemDataByID = function(id)
    W.loadRequests[#W.loadRequests + 1] = id
end }
_G.C_Container = {
    GetContainerNumSlots     = function() return 0 end,
    GetContainerItemID       = function() return nil end,
    GetContainerItemCooldown = function() return 0, 0 end,
}

local realCreateFrame = _G.CreateFrame
_G.CreateFrame = function() return stubFrame() end
dofile("ExsarUI.lua")
_G.CreateFrame = realCreateFrame
-- Capture a local handle: later test files reassign the _G.ExsarUI global.
local UI = _G.ExsarUI

-- Rebuild a bar from scratch so each test starts on clean slot state.
local barSeq = 0
local function makeBar(opts)
    barSeq = barSeq + 1
    _G.CreateFrame = function() return stubFrame() end
    local bar = UI.CreateActionBar({
        name         = "testBar" .. barSeq,
        frameName    = "TestBarFrame" .. barSeq,
        buttonPrefix = "TestBarBtn" .. barSeq .. "_",
        placeholder  = "Test Bar",
        layout       = "horizontal",
        actions      = opts.actions,
        moduleName   = "Test Bar",
        readyPulse   = opts.readyPulse,
        hideEmptyBar = opts.hideEmptyBar,
        dimOnCooldown = true,
    })
    _G.CreateFrame = realCreateFrame
    return bar
end

local TRINKET_ACTIONS = {
    { key = "t13", name = "Top",    trinketSlot = 13, hideWhenNoUse = true },
    { key = "t14", name = "Bottom", trinketSlot = 14, hideWhenNoUse = true },
}

-- ResolveTrinkets is throttled to once a second; advance past it between pumps.
local function pump(bar)
    W.time = W.time + 2
    bar.Refresh()
    bar.ApplyLayout()
end

-- =========================================================
-- hideWhenNoUse
-- =========================================================

describe("CreateActionBar hideWhenNoUse", function()
    before_each(resetWorld)

    it("shows a trinket slot whose equipped item has an on-use effect", function()
        W.trinketItem[13] = 111
        W.itemSpell[111]  = "Some Use Effect"
        W.itemCached[111] = true
        local bar = makeBar({ actions = TRINKET_ACTIONS })
        pump(bar)
        assert.is_falsy(bar.slots[1].hidden)
        assert.is_true(bar.slots[1].btn:IsShown())
    end)

    it("hides a slot whose equipped trinket is a passive/proc trinket", function()
        W.trinketItem[13] = 111       -- cached, but GetItemSpell returns nil
        W.itemCached[111] = true
        local bar = makeBar({ actions = TRINKET_ACTIONS })
        pump(bar)
        assert.is_true(bar.slots[1].hidden)
        assert.is_false(bar.slots[1].btn:IsShown())
    end)

    it("hides a slot with an empty trinket socket", function()
        local bar = makeBar({ actions = TRINKET_ACTIONS })
        pump(bar)
        assert.is_true(bar.slots[1].hidden)
        assert.is_true(bar.slots[2].hidden)
    end)

    it("leaves state alone and requests a load while item data is uncached", function()
        W.trinketItem[13] = 111
        W.itemSpell[111]  = "Some Use Effect"
        W.itemCached[111] = true
        local bar = makeBar({ actions = TRINKET_ACTIONS })
        pump(bar)
        assert.is_falsy(bar.slots[1].hidden)

        -- Data goes uncached (zoning / taxi): "pending", NOT a hide.
        W.itemSpell[111]  = nil
        W.itemCached[111] = false
        W.loadRequests    = {}
        pump(bar)
        assert.is_falsy(bar.slots[1].hidden)
        assert.are.equal(111, W.loadRequests[1])
    end)

    it("packs the remaining slot to the front when the first one hides", function()
        W.trinketItem[14] = 222
        W.itemSpell[222]  = "Some Use Effect"
        W.itemCached[222] = true
        local bar = makeBar({ actions = TRINKET_ACTIONS })
        pump(bar)
        assert.is_true(bar.slots[1].hidden)
        assert.is_false(bar.slots[2].hidden)
        -- Slot 2 took the leading position rather than leaving a hole.
        assert.are.equal(6, bar.slots[2].btn.x)  -- AB_PADDING
    end)

    it("reflows when a trinket is swapped for one with an on-use effect", function()
        local bar = makeBar({ actions = TRINKET_ACTIONS })
        pump(bar)
        assert.is_true(bar.slots[1].hidden)

        W.trinketItem[13] = 111
        W.itemSpell[111]  = "Some Use Effect"
        W.itemCached[111] = true
        pump(bar)
        assert.is_falsy(bar.slots[1].hidden)
    end)

    it("leaves slots without hideWhenNoUse always visible", function()
        local bar = makeBar({ actions = {
            { key = "t13", name = "Top", trinketSlot = 13 },
        } })
        pump(bar)  -- nothing equipped at all
        assert.is_falsy(bar.slots[1].hidden)
    end)
end)

-- =========================================================
-- readyPulse
-- =========================================================

describe("CreateActionBar readyPulse", function()
    before_each(function()
        resetWorld()
        W.knownSpells["Multi-Shot"] = true
    end)

    local SPELL_ACTIONS = {
        { key = "ms", name = "Multi-Shot", spells = { { name = "Multi-Shot" } } },
    }

    it("creates a ready glow on macro/spell slots only when enabled", function()
        local off = makeBar({ actions = SPELL_ACTIONS })
        assert.is_nil(off.slots[1].readyGlow)
        local on = makeBar({ actions = SPELL_ACTIONS, readyPulse = true })
        assert.is_not_nil(on.slots[1].readyGlow)
    end)

    it("is not ready out of combat, even with every cooldown up", function()
        local bar = makeBar({ actions = SPELL_ACTIONS, readyPulse = true })
        W.inCombat = false
        pump(bar)
        assert.is_false(bar.slots[1].ready)
    end)

    it("is ready in combat with no cooldown running", function()
        local bar = makeBar({ actions = SPELL_ACTIONS, readyPulse = true })
        W.inCombat = true
        pump(bar)
        assert.is_true(bar.slots[1].ready)
    end)

    it("is not ready while a real cooldown runs", function()
        local bar = makeBar({ actions = SPELL_ACTIONS, readyPulse = true })
        W.inCombat = true
        W.spellCd["Multi-Shot"] = { W.time, 10 }
        pump(bar)
        assert.is_false(bar.slots[1].ready)
    end)

    it("is not ready during the GCD, so the glow can't strobe on every global", function()
        local bar = makeBar({ actions = SPELL_ACTIONS, readyPulse = true })
        W.inCombat = true
        -- A live GCD: the slot's own spell reports it, and so does the engine's
        -- shared Wing Clip probe (which is what gates the GCD swirl). Start is
        -- offset by the pump's clock advance so it is still running when read.
        W.spellCd["Multi-Shot"] = { W.time + 2, 1.5 }  -- "gcd", not a real CD
        W.spellCd["Wing Clip"]  = { W.time + 2, 1.5 }
        pump(bar)
        assert.is_false(bar.slots[1].ready)
    end)

    it("is ready again once the GCD has passed", function()
        local bar = makeBar({ actions = SPELL_ACTIONS, readyPulse = true })
        W.inCombat = true
        W.spellCd["Multi-Shot"] = { W.time + 2, 1.5 }
        W.spellCd["Wing Clip"]  = { W.time + 2, 1.5 }
        pump(bar)
        assert.is_false(bar.slots[1].ready)

        W.spellCd["Multi-Shot"] = nil
        W.spellCd["Wing Clip"]  = nil
        pump(bar)
        assert.is_true(bar.slots[1].ready)
    end)

    it("tracks a trinket slot's own cooldown", function()
        W.trinketItem[13] = 111
        W.itemSpell[111]  = "Some Use Effect"
        W.itemCached[111] = true
        local bar = makeBar({ actions = TRINKET_ACTIONS, readyPulse = true })
        W.inCombat = true
        pump(bar)
        assert.is_true(bar.slots[1].ready)

        W.trinketCd[13] = { W.time, 120 }
        pump(bar)
        assert.is_false(bar.slots[1].ready)
    end)

    it("widens the icon gap so neighbouring glows don't touch", function()
        W.knownSpells["Arcane Shot"] = true
        local actions = {
            { key = "ms", name = "Multi-Shot",  spells = { { name = "Multi-Shot"  } } },
            { key = "as", name = "Arcane Shot", spells = { { name = "Arcane Shot" } } },
        }
        local plain = makeBar({ actions = actions })
        pump(plain)
        local pulsing = makeBar({ actions = actions, readyPulse = true })
        pump(pulsing)
        assert.is_true(pulsing.slots[2].btn.x > plain.slots[2].btn.x)
    end)
end)

-- =========================================================
-- hideEmptyBar
-- =========================================================

describe("CreateActionBar hideEmptyBar", function()
    before_each(resetWorld)

    it("hides the frame when every slot is hidden and the widget is locked", function()
        local bar = makeBar({ actions = TRINKET_ACTIONS, hideEmptyBar = true })
        bar.dbFunc().locked = true
        pump(bar)
        assert.is_false(bar.frame:IsShown())
    end)

    it("still shows an empty bar while unlocked, so it can be positioned", function()
        local bar = makeBar({ actions = TRINKET_ACTIONS, hideEmptyBar = true })
        bar.dbFunc().locked = false
        pump(bar)
        assert.is_true(bar.frame:IsShown())
    end)

    it("shows the frame again once a usable trinket is equipped", function()
        local bar = makeBar({ actions = TRINKET_ACTIONS, hideEmptyBar = true })
        bar.dbFunc().locked = true
        pump(bar)
        assert.is_false(bar.frame:IsShown())

        W.trinketItem[13] = 111
        W.itemSpell[111]  = "Some Use Effect"
        W.itemCached[111] = true
        pump(bar)
        assert.is_true(bar.frame:IsShown())
    end)

    it("keeps an empty locked bar shown without the opt", function()
        local bar = makeBar({ actions = TRINKET_ACTIONS })
        bar.dbFunc().locked = true
        pump(bar)
        assert.is_true(bar.frame:IsShown())
    end)
end)
