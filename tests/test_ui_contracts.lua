-- tests/test_ui_contracts.lua
-- Contract tests for ExsarUI helpers using lightweight stubs.
-- These verify that helpers call the right methods on their arguments
-- without requiring a full WoW API mock.

-- =========================================================
-- Stub helpers
-- =========================================================

--- Create a stub function that records calls.
local function spy()
    local calls = {}
    local fn = function(...)
        calls[#calls + 1] = { ... }
    end
    return fn, calls
end

--- Create a stub bar (StatusBar-like table).
local function stubBar()
    local bar = {}
    bar.SetMinMaxValues, bar._minmax = spy()
    bar.SetValue, bar._value = spy()
    bar.SetStatusBarColor, bar._color = spy()
    return bar
end

--- Create a stub FontString-like table.
local function stubText()
    local t = {}
    t.SetText, t._text = spy()
    return t
end

--- Create a stub frame that records SetScript calls and allows simulating OnUpdate.
local function stubFrame()
    local f = {}
    local scripts = {}
    f.SetScript = function(self, name, fn)
        scripts[name] = fn
    end
    f._scripts = scripts
    return f
end

-- =========================================================
-- Load ExsarLogic (needed by UpdateInfoBars)
-- =========================================================

package.path = package.path .. ";../?.lua"
local Logic = require("ExsarLogic")

-- Mock WoW globals that ExsarUI helpers call
_G.ExsarLogic = Logic
_G.ExsarAddonDB = {}
_G.ExsarUI = {}
_G.ExsarAddon = { AddSlashCommand = function() end }

-- Mock WoW API functions used by UpdateInfoBars
local mockUnitHealth = {}
_G.UnitHealth = function(unit) return mockUnitHealth[unit] or 0 end
_G.UnitHealthMax = function(unit) return mockUnitHealth[unit .. "_max"] or 0 end
_G.UnitPower = function(unit) return mockUnitHealth[unit .. "_power"] or 0 end
_G.UnitPowerMax = function(unit) return mockUnitHealth[unit .. "_powermax"] or 0 end

-- Copy the real implementations we want to test
-- (We load just the functions, not the full file which needs CreateFrame etc.)

function ExsarUI.UpdateInfoBars(cfg)
    local unit = cfg.unit
    local hp    = UnitHealth(unit)
    local hpMax = UnitHealthMax(unit)
    if hpMax > 0 then
        cfg.healthBar:SetMinMaxValues(0, hpMax)
        cfg.healthBar:SetValue(hp)
        if hp == 0 then
            cfg.healthText:SetText("Dead")
            if cfg.hideLowHp then cfg.hideLowHp() end
        else
            local pct = math.floor(hp / hpMax * 100 + 0.5)
            cfg.healthText:SetText(pct .. "%")
            cfg.healthBar:SetStatusBarColor(ExsarLogic.HealthColorThreshold(pct))
            if cfg.lowHpThreshold and cfg.showLowHp and cfg.hideLowHp then
                if pct <= cfg.lowHpThreshold then
                    cfg.showLowHp()
                else
                    cfg.hideLowHp()
                end
            end
        end
    end

    local pw    = UnitPower(unit)
    local pwMax = UnitPowerMax(unit)
    if pwMax > 0 then
        cfg.powerBar:SetMinMaxValues(0, pwMax)
        cfg.powerBar:SetValue(pw)
        cfg.powerText:SetText(ExsarLogic.FormatNumber(pw) .. " / " .. ExsarLogic.FormatNumber(pwMax))
    else
        cfg.powerBar:SetMinMaxValues(0, 1)
        cfg.powerBar:SetValue(0)
        cfg.powerText:SetText("")
    end
end

function ExsarUI.CreatePoller(frame, interval, callback)
    if not frame then
        frame = stubFrame()
    end
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed >= interval then
            elapsed = 0
            callback()
        end
    end)
    return frame
end

function ExsarUI.AnimateDashes(slots, now, speed, dashCount, tailLen)
    local head = ExsarLogic.MarchingAntHead(now, speed, dashCount)
    for _, s in ipairs(slots) do
        if s.active then
            for j, d in ipairs(s.dashes) do
                d:SetAlpha(ExsarLogic.MarchingAntAlpha(j - 1, head, dashCount, tailLen))
            end
        end
    end
end

function ExsarUI.CreateUpArrows(parentFrame, opts)
    opts = opts or {}
    local thickness = opts.thickness or 6
    local height    = opts.height    or 34
    local headLen   = opts.headLen   or 12
    local spacing   = opts.spacing   or 12
    local color     = opts.color     or { 1.0, 0.85, 0.0, 1.0 }
    local layer     = opts.layer     or "OVERLAY"

    local lines = {}
    local half  = height / 2

    for _, cx in ipairs({ -spacing, spacing }) do
        local segments = {
            { cx, -half,   cx,           half           },  -- shaft
            { cx,  half,   cx - headLen, half - headLen  },  -- left arrowhead
            { cx,  half,   cx + headLen, half - headLen  },  -- right arrowhead
        }
        for _, s in ipairs(segments) do
            local line = parentFrame:CreateLine(nil, layer)
            line:SetColorTexture(color[1], color[2], color[3], color[4])
            line:SetThickness(thickness)
            line:SetStartPoint("CENTER", parentFrame, s[1], s[2])
            line:SetEndPoint("CENTER", parentFrame, s[3], s[4])
            lines[#lines + 1] = line
        end
    end

    return lines
end

-- =========================================================
-- UpdateInfoBars
-- =========================================================

describe("UpdateInfoBars", function()
    before_each(function()
        mockUnitHealth = {}
    end)

    it("sets health bar values and percentage text", function()
        mockUnitHealth["player"] = 750
        mockUnitHealth["player_max"] = 1000

        local hBar = stubBar()
        local hText = stubText()
        local pBar = stubBar()
        local pText = stubText()

        ExsarUI.UpdateInfoBars({
            unit = "player",
            healthBar = hBar, healthText = hText,
            powerBar = pBar, powerText = pText,
        })

        -- Health bar should be set to 0-1000 range with value 750
        assert.are.same({ hBar, 0, 1000 }, hBar._minmax[1])
        assert.are.same({ hBar, 750 }, hBar._value[1])
        -- 750/1000 = 75%
        assert.are.same({ hText, "75%" }, hText._text[1])
        -- Color should be green (>50%)
        assert.are.same({ hBar, 0.20, 0.75, 0.20 }, hBar._color[1])
    end)

    it("shows 'Dead' when hp is 0", function()
        mockUnitHealth["player"] = 0
        mockUnitHealth["player_max"] = 1000

        local hBar = stubBar()
        local hText = stubText()
        local pBar = stubBar()
        local pText = stubText()

        ExsarUI.UpdateInfoBars({
            unit = "player",
            healthBar = hBar, healthText = hText,
            powerBar = pBar, powerText = pText,
        })

        assert.are.same({ hText, "Dead" }, hText._text[1])
        -- No color change when dead
        assert.are.equal(0, #hBar._color)
    end)

    it("calls hideLowHp when dead", function()
        mockUnitHealth["player"] = 0
        mockUnitHealth["player_max"] = 1000

        local hideCalled = false
        ExsarUI.UpdateInfoBars({
            unit = "player",
            healthBar = stubBar(), healthText = stubText(),
            powerBar = stubBar(), powerText = stubText(),
            hideLowHp = function() hideCalled = true end,
            showLowHp = function() end,
            lowHpThreshold = 30,
        })

        assert.is_true(hideCalled)
    end)

    it("calls showLowHp when below threshold", function()
        mockUnitHealth["player"] = 200
        mockUnitHealth["player_max"] = 1000

        local showCalled = false
        local hideCalled = false
        ExsarUI.UpdateInfoBars({
            unit = "player",
            healthBar = stubBar(), healthText = stubText(),
            powerBar = stubBar(), powerText = stubText(),
            showLowHp = function() showCalled = true end,
            hideLowHp = function() hideCalled = true end,
            lowHpThreshold = 30,
        })

        assert.is_true(showCalled)
        assert.is_false(hideCalled)
    end)

    it("calls hideLowHp when above threshold", function()
        mockUnitHealth["player"] = 800
        mockUnitHealth["player_max"] = 1000

        local showCalled = false
        local hideCalled = false
        ExsarUI.UpdateInfoBars({
            unit = "player",
            healthBar = stubBar(), healthText = stubText(),
            powerBar = stubBar(), powerText = stubText(),
            showLowHp = function() showCalled = true end,
            hideLowHp = function() hideCalled = true end,
            lowHpThreshold = 30,
        })

        assert.is_false(showCalled)
        assert.is_true(hideCalled)
    end)

    it("skips low hp warning when no threshold configured", function()
        mockUnitHealth["player"] = 100
        mockUnitHealth["player_max"] = 1000

        local anyCalled = false
        ExsarUI.UpdateInfoBars({
            unit = "player",
            healthBar = stubBar(), healthText = stubText(),
            powerBar = stubBar(), powerText = stubText(),
            showLowHp = function() anyCalled = true end,
            hideLowHp = function() anyCalled = true end,
        })

        assert.is_false(anyCalled)
    end)

    it("formats power text with FormatNumber", function()
        mockUnitHealth["player_power"] = 2500
        mockUnitHealth["player_powermax"] = 5000

        local pBar = stubBar()
        local pText = stubText()

        ExsarUI.UpdateInfoBars({
            unit = "player",
            healthBar = stubBar(), healthText = stubText(),
            powerBar = pBar, powerText = pText,
        })

        assert.are.same({ pBar, 0, 5000 }, pBar._minmax[1])
        assert.are.same({ pBar, 2500 }, pBar._value[1])
        assert.are.same({ pText, "2.5k / 5.0k" }, pText._text[1])
    end)

    it("clears power bar when max power is 0", function()
        mockUnitHealth["player_power"] = 0
        mockUnitHealth["player_powermax"] = 0

        local pBar = stubBar()
        local pText = stubText()

        ExsarUI.UpdateInfoBars({
            unit = "player",
            healthBar = stubBar(), healthText = stubText(),
            powerBar = pBar, powerText = pText,
        })

        assert.are.same({ pBar, 0, 1 }, pBar._minmax[1])
        assert.are.same({ pBar, 0 }, pBar._value[1])
        assert.are.same({ pText, "" }, pText._text[1])
    end)

    it("uses correct unit token", function()
        mockUnitHealth["pet"] = 300
        mockUnitHealth["pet_max"] = 500
        mockUnitHealth["pet_power"] = 100
        mockUnitHealth["pet_powermax"] = 200

        local hText = stubText()
        local pText = stubText()

        ExsarUI.UpdateInfoBars({
            unit = "pet",
            healthBar = stubBar(), healthText = hText,
            powerBar = stubBar(), powerText = pText,
        })

        -- 300/500 = 60%
        assert.are.same({ hText, "60%" }, hText._text[1])
        assert.are.same({ pText, "100 / 200" }, pText._text[1])
    end)

    it("uses yellow color at 50%", function()
        mockUnitHealth["player"] = 500
        mockUnitHealth["player_max"] = 1000

        local hBar = stubBar()
        ExsarUI.UpdateInfoBars({
            unit = "player",
            healthBar = hBar, healthText = stubText(),
            powerBar = stubBar(), powerText = stubText(),
        })

        assert.are.same({ hBar, 0.90, 0.90, 0.10 }, hBar._color[1])
    end)

    it("uses red color at 15%", function()
        mockUnitHealth["player"] = 150
        mockUnitHealth["player_max"] = 1000

        local hBar = stubBar()
        ExsarUI.UpdateInfoBars({
            unit = "player",
            healthBar = hBar, healthText = stubText(),
            powerBar = stubBar(), powerText = stubText(),
        })

        assert.are.same({ hBar, 0.80, 0.15, 0.15 }, hBar._color[1])
    end)
end)

-- =========================================================
-- CreatePoller
-- =========================================================

describe("CreatePoller", function()
    it("creates a frame when nil is passed", function()
        local called = 0
        local f = ExsarUI.CreatePoller(nil, 0.1, function() called = called + 1 end)
        assert.is_table(f)
        assert.is_function(f._scripts["OnUpdate"])
    end)

    it("sets OnUpdate on provided frame", function()
        local f = stubFrame()
        local result = ExsarUI.CreatePoller(f, 0.1, function() end)
        assert.are.equal(f, result)
        assert.is_function(f._scripts["OnUpdate"])
    end)

    it("does not fire callback before interval", function()
        local f = stubFrame()
        local called = 0
        ExsarUI.CreatePoller(f, 0.1, function() called = called + 1 end)

        -- Simulate 0.05s elapsed — should not fire
        f._scripts["OnUpdate"](f, 0.05)
        assert.are.equal(0, called)
    end)

    it("fires callback at interval", function()
        local f = stubFrame()
        local called = 0
        ExsarUI.CreatePoller(f, 0.1, function() called = called + 1 end)

        -- Simulate 0.1s elapsed — should fire once
        f._scripts["OnUpdate"](f, 0.1)
        assert.are.equal(1, called)
    end)

    it("accumulates elapsed time across frames", function()
        local f = stubFrame()
        local called = 0
        ExsarUI.CreatePoller(f, 0.1, function() called = called + 1 end)

        f._scripts["OnUpdate"](f, 0.04)
        assert.are.equal(0, called)
        f._scripts["OnUpdate"](f, 0.04)
        assert.are.equal(0, called)
        f._scripts["OnUpdate"](f, 0.04)
        assert.are.equal(1, called)
    end)

    it("resets elapsed after firing", function()
        local f = stubFrame()
        local called = 0
        ExsarUI.CreatePoller(f, 0.1, function() called = called + 1 end)

        f._scripts["OnUpdate"](f, 0.1)
        assert.are.equal(1, called)
        -- Next 0.05 should not fire
        f._scripts["OnUpdate"](f, 0.05)
        assert.are.equal(1, called)
        -- But 0.05 more should fire
        f._scripts["OnUpdate"](f, 0.05)
        assert.are.equal(2, called)
    end)

    it("works with 0.5s interval", function()
        local f = stubFrame()
        local called = 0
        ExsarUI.CreatePoller(f, 0.5, function() called = called + 1 end)

        for _ = 1, 4 do
            f._scripts["OnUpdate"](f, 0.1)
        end
        assert.are.equal(0, called)
        f._scripts["OnUpdate"](f, 0.1)
        assert.are.equal(1, called)
    end)
end)

-- =========================================================
-- AnimateDashes
-- =========================================================

describe("AnimateDashes", function()
    local function stubDash()
        local d = {}
        d.SetAlpha, d._alpha = spy()
        return d
    end

    it("sets alpha on active slot dashes", function()
        local d1, d2, d3 = stubDash(), stubDash(), stubDash()
        local slots = {
            { active = true, dashes = { d1, d2, d3 } },
        }

        ExsarUI.AnimateDashes(slots, 0, 1.5, 3, 2)

        -- All 3 dashes should have SetAlpha called once
        assert.are.equal(1, #d1._alpha)
        assert.are.equal(1, #d2._alpha)
        assert.are.equal(1, #d3._alpha)
    end)

    it("skips inactive slots", function()
        local d1 = stubDash()
        local slots = {
            { active = false, dashes = { d1 } },
        }

        ExsarUI.AnimateDashes(slots, 0, 1.5, 3, 2)

        assert.are.equal(0, #d1._alpha)
    end)

    it("head dash gets full alpha", function()
        -- At time=0, head position is 0, so dash index 0 (first dash) is at head
        local d1, d2 = stubDash(), stubDash()
        local slots = {
            { active = true, dashes = { d1, d2 } },
        }

        ExsarUI.AnimateDashes(slots, 0, 1.5, 2, 1)

        -- d1 is dash index 0, head is at 0, dist=0, in tail → alpha ~1.0
        local alpha1 = d1._alpha[1][2]
        assert.is_true(alpha1 > 0.9)
    end)

    it("dashes outside tail get 0 alpha", function()
        local dashes = {}
        for _ = 1, 8 do
            dashes[#dashes + 1] = stubDash()
        end
        local slots = {
            { active = true, dashes = dashes },
        }

        ExsarUI.AnimateDashes(slots, 0, 1.5, 8, 2)

        -- Dashes far from head should have alpha = 0
        -- Head is at 0, tail length 2
        -- dash 0 (index 1): dist=0, in tail
        -- dash 7 (index 8): dist=1, in tail
        -- dashes 1-6 (indices 2-7): dist=7,6,5,4,3,2, all >= tail, so alpha=0
        for i = 2, 7 do
            local alpha = dashes[i]._alpha[1][2]
            assert.are.equal(0, alpha)
        end
    end)

    it("handles multiple active slots", function()
        local d1, d2 = stubDash(), stubDash()
        local slots = {
            { active = true, dashes = { d1 } },
            { active = true, dashes = { d2 } },
        }

        ExsarUI.AnimateDashes(slots, 0, 1.5, 1, 1)

        assert.are.equal(1, #d1._alpha)
        assert.are.equal(1, #d2._alpha)
    end)
end)

-- =========================================================
-- CreateUpArrows
-- =========================================================

describe("CreateUpArrows", function()
    local function stubLine()
        local l = {}
        l.SetColorTexture, l._color = spy()
        l.SetThickness, l._thickness = spy()
        l.SetStartPoint, l._start = spy()
        l.SetEndPoint, l._end = spy()
        return l
    end

    local function stubLineFrame()
        local f = {}
        local lines = {}
        f.CreateLine = function()
            local l = stubLine()
            lines[#lines + 1] = l
            return l
        end
        f._lines = lines
        return f
    end

    it("creates six lines (two 3-segment arrows)", function()
        local f = stubLineFrame()
        local arrows = ExsarUI.CreateUpArrows(f)
        assert.are.equal(6, #f._lines)
        assert.are.equal(6, #arrows)
    end)

    it("sets thickness and color on every line", function()
        local f = stubLineFrame()
        ExsarUI.CreateUpArrows(f, { thickness = 7, color = { 1, 0.85, 0, 1 } })
        for _, l in ipairs(f._lines) do
            assert.are.equal(1, #l._thickness)
            assert.are.equal(7, l._thickness[1][2])
            assert.are.same({ l, 1, 0.85, 0, 1 }, l._color[1])
        end
    end)

    it("anchors each line with a start and end point", function()
        local f = stubLineFrame()
        ExsarUI.CreateUpArrows(f)
        for _, l in ipairs(f._lines) do
            assert.are.equal(1, #l._start)
            assert.are.equal(1, #l._end)
        end
    end)

    it("arrowhead segments converge on the shaft tip", function()
        local f = stubLineFrame()
        ExsarUI.CreateUpArrows(f, { height = 34, headLen = 12, spacing = 12 })
        -- First arrow: lines 1 (shaft), 2 (left head), 3 (right head)
        local shaft, headL, headR = f._lines[1], f._lines[2], f._lines[3]
        -- spy records { self, anchor, frame, x, y }; compare the x/y coords
        local shaftEnd  = shaft._end[1]
        local headLStrt = headL._start[1]
        local headRStrt = headR._start[1]
        -- shaft end point and both arrowhead start points are the same tip
        assert.are.equal(shaftEnd[4], headLStrt[4])
        assert.are.equal(shaftEnd[5], headLStrt[5])
        assert.are.equal(shaftEnd[4], headRStrt[4])
        assert.are.equal(shaftEnd[5], headRStrt[5])
        -- the tip y is +half (17) — pointing up
        assert.are.equal(17, shaftEnd[5])
    end)
end)

-- =========================================================
-- SetupKeybindBridge
-- =========================================================
-- Copy of the real implementation (the full ExsarUI.lua can't be loaded under
-- busted because it calls CreateFrame at file scope). A stub CreateFrame records
-- the internal watcher frame so we can simulate binding-refresh events.

local lastWatcher
_G.CreateFrame = function()
    local f = {}
    f._events = {}
    f.RegisterEvent = function(self, e) self._events[e] = true end
    f.SetScript = function(self, name, fn) self["_script_" .. name] = fn end
    lastWatcher = f
    return f
end

function ExsarUI.SetupKeybindBridge(opts)
    local owner         = opts.owner
    local bindingPrefix = opts.bindingPrefix
    local buttonPrefix  = opts.buttonPrefix
    local count         = opts.count
    local onSlotKey     = opts.onSlotKey
    local deps          = opts.deps or {}
    local getBindingKey           = deps.GetBindingKey           or GetBindingKey
    local setOverrideBindingClick = deps.SetOverrideBindingClick or SetOverrideBindingClick
    local clearOverrideBindings   = deps.ClearOverrideBindings   or ClearOverrideBindings
    local inCombatLockdown        = deps.InCombatLockdown        or InCombatLockdown

    local function apply()
        local combat = inCombatLockdown()
        if not combat then
            clearOverrideBindings(owner)
        end
        for i = 1, count do
            local key1, key2 = getBindingKey(bindingPrefix .. i)
            if onSlotKey then onSlotKey(i, key1) end
            if not combat then
                local btn = buttonPrefix .. i
                if key1 then setOverrideBindingClick(owner, true, key1, btn) end
                if key2 then setOverrideBindingClick(owner, true, key2, btn) end
            end
        end
    end

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("UPDATE_BINDINGS")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:SetScript("OnEvent", apply)
    apply()
    return apply
end

describe("SetupKeybindBridge", function()
    -- Build a deps table whose WoW funcs are spies, with a configurable
    -- key map and combat state.
    local function makeDeps(keyMap, inCombat)
        local d = {}
        d.GetBindingKey = function(name)
            local k = keyMap[name]
            if type(k) == "table" then return k[1], k[2] end
            return k
        end
        d.SetOverrideBindingClick, d._override = spy()
        d.ClearOverrideBindings, d._clear     = spy()
        d.InCombatLockdown = function() return inCombat and true or false end
        return d
    end

    it("bridges each bound key to its matching button when out of combat", function()
        local deps = makeDeps({ EXSAR_USE_ITEM1 = "SHIFT-1", EXSAR_USE_ITEM3 = "F" }, false)
        ExsarUI.SetupKeybindBridge({
            owner = "OWNER", bindingPrefix = "EXSAR_USE_ITEM",
            buttonPrefix = "Btn", count = 3, deps = deps,
        })
        -- Two keys bound → two override calls, with priority=true.
        assert.are.equal(2, #deps._override)
        assert.are.same({ "OWNER", true, "SHIFT-1", "Btn1" }, deps._override[1])
        assert.are.same({ "OWNER", true, "F", "Btn3" }, deps._override[2])
        -- Overrides cleared once per apply pass.
        assert.are.equal(1, #deps._clear)
    end)

    it("binds both primary and secondary keys for a slot", function()
        local deps = makeDeps({ EXSAR_USE_ITEM1 = { "A", "B" } }, false)
        ExsarUI.SetupKeybindBridge({
            owner = "O", bindingPrefix = "EXSAR_USE_ITEM",
            buttonPrefix = "Btn", count = 1, deps = deps,
        })
        assert.are.equal(2, #deps._override)
        assert.are.same({ "O", true, "A", "Btn1" }, deps._override[1])
        assert.are.same({ "O", true, "B", "Btn1" }, deps._override[2])
    end)

    it("calls onSlotKey for every slot with the resolved key (nil when unbound)", function()
        local deps = makeDeps({ EXSAR_USE_ITEM2 = "C" }, false)
        local seen = {}
        ExsarUI.SetupKeybindBridge({
            owner = "O", bindingPrefix = "EXSAR_USE_ITEM",
            buttonPrefix = "Btn", count = 3, deps = deps,
            onSlotKey = function(i, key) seen[i] = key or false end,
        })
        assert.are.equal(false, seen[1])
        assert.are.equal("C", seen[2])
        assert.are.equal(false, seen[3])
    end)

    it("skips override binding in combat but still drives labels", function()
        local deps = makeDeps({ EXSAR_USE_ITEM1 = "SHIFT-1" }, true)
        local seen = {}
        ExsarUI.SetupKeybindBridge({
            owner = "O", bindingPrefix = "EXSAR_USE_ITEM",
            buttonPrefix = "Btn", count = 1, deps = deps,
            onSlotKey = function(i, key) seen[i] = key end,
        })
        -- Protected calls skipped under combat lockdown.
        assert.are.equal(0, #deps._override)
        assert.are.equal(0, #deps._clear)
        -- Label callback still ran.
        assert.are.equal("SHIFT-1", seen[1])
    end)

    it("re-applies when a binding-refresh event fires", function()
        local deps = makeDeps({ EXSAR_USE_ITEM1 = "SHIFT-1" }, false)
        ExsarUI.SetupKeybindBridge({
            owner = "O", bindingPrefix = "EXSAR_USE_ITEM",
            buttonPrefix = "Btn", count = 1, deps = deps,
        })
        assert.are.equal(1, #deps._override)
        -- The internal watcher registered the refresh events...
        assert.is_true(lastWatcher._events["UPDATE_BINDINGS"])
        assert.is_true(lastWatcher._events["PLAYER_REGEN_ENABLED"])
        -- ...and firing OnEvent runs another apply pass.
        lastWatcher._script_OnEvent()
        assert.are.equal(2, #deps._override)
    end)
end)
