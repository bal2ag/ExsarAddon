-- tests/test_maelstrom.lua
-- Contract tests for ExsarUI.CreateMaelstromEffect.
--
-- Unlike tests/test_ui_contracts.lua (which re-declares small helpers), this
-- loads the REAL ExsarUI.lua behind a recording CreateFrame stub, so the renderer
-- under test cannot drift away from a copy. ExsarUI.lua is pure function
-- definitions at load time, which is what makes that possible.
--
-- The geometry itself lives in ExsarLogic (MaelstromPoint / MaelstromTrailProfile
-- / MaelstromTierParams) and is tested there; what is checked here is the
-- renderer's own contract: how many stamps it allocates, that it shows exactly
-- the ones the current tier asks for, that it stops when params go away, and that
-- it can come back afterwards.

package.path = package.path .. ";./?.lua;../?.lua"
local Logic = require("ExsarLogic")

local function approx(a, b, tol)
    return math.abs(a - b) < (tol or 0.001)
end

-- =========================================================
-- Recording stubs
-- =========================================================

local NOOP_FALLBACK  -- forward declaration (defined with the frame stub below)

local function stubTexture(layer)
    local t = setmetatable({
        layer = layer, shown = false, w = 0, h = 0,
        x = 0, y = 0, color = {}, texture = nil,
    }, NOOP_FALLBACK)
    function t:SetTexture(p)     self.texture = p end
    function t:SetBlendMode()    end
    function t:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    function t:SetSize(w, h)     self.w, self.h = w, h end
    function t:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
    function t:Show()            self.shown = true end
    function t:Hide()            self.shown = false end
    return t
end

-- Anything the renderer does not exercise (and the handful of frames ExsarUI.lua
-- builds at load time) falls through to a no-op, so this stub only has to model
-- the calls the test actually asserts on.
NOOP_FALLBACK = { __index = function() return function() end end }

local function stubFrame()
    local f = setmetatable({ textures = {}, scripts = {}, points = {} }, NOOP_FALLBACK)
    function f:CreateTexture(_, layer)
        local t = stubTexture(layer)
        self.textures[#self.textures + 1] = t
        return t
    end
    function f:SetSize(w, h)     self.w, self.h = w, h end
    function f:SetFrameStrata(s) self.strata = s; self.level = nil end  -- WoW resets the level
    function f:SetFrameLevel(n)  self.level = n end
    function f:SetPoint(...)     self.points[#self.points + 1] = { ... } end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    function f:Show()            self.shown = true end
    function f:Hide()            self.shown = false end
    function f:IsShown()         return self.shown end
    return f
end

-- Load the real ExsarUI behind the stub. Capture a local handle: later test files
-- reassign the _G.ExsarUI global to their own stub tables.
_G.ExsarLogic   = Logic
_G.ExsarAddonDB = _G.ExsarAddonDB or {}
_G.UIParent     = _G.UIParent   or {}
_G.WorldFrame   = _G.WorldFrame or {}
_G.ExsarAddon   = _G.ExsarAddon
    or setmetatable({}, { __index = function() return function() end end })

local realCreateFrame = _G.CreateFrame
_G.CreateFrame = function() return stubFrame() end
dofile("ExsarUI.lua")
_G.CreateFrame = realCreateFrame
local UI = _G.ExsarUI

-- =========================================================
-- Harness
-- =========================================================

--- Build a maelstrom over a fresh stub frame.
-- @return effect, frame, tick(elapsed), stamps
local function makeEffect(opts)
    opts = opts or {}
    local frame
    local prevCreate = _G.CreateFrame
    _G.CreateFrame = function()
        frame = stubFrame()
        return frame
    end
    local effect = UI.CreateMaelstromEffect({}, opts)
    _G.CreateFrame = prevCreate

    local function tick(elapsed)
        frame.scripts.OnUpdate(frame, elapsed)
    end

    -- Only count the stamps that are currently visible.
    local function shown()
        local n = 0
        for _, t in ipairs(frame.textures) do
            if t.shown then n = n + 1 end
        end
        return n
    end

    return effect, frame, tick, shown
end

local LAYERS = 2  -- soft halo + bright core
local STAMPS = Logic.MAELSTROM_ARMS * Logic.MAELSTROM_TRAIL

-- =========================================================
-- Tests
-- =========================================================

describe("CreateMaelstromEffect", function()
    it("allocates the full stamp budget up front, all hidden", function()
        local _, frame, _, shown = makeEffect()
        assert.are.equal(STAMPS * LAYERS, #frame.textures)
        assert.are.equal(0, shown())
    end)

    it("draws nothing while getParams returns nil", function()
        local _, _, tick, shown = makeEffect({ getParams = function() return nil end })
        tick(0.1)
        tick(0.1)
        assert.are.equal(0, shown())
    end)

    it("has the same silhouette at every tier", function()
        -- The core design rule. Driving each tier by 0.25/infallPerSec puts them
        -- all at the identical flow position, so the stamp SET and their radii
        -- must match exactly; only the slow `spin` drift differs between tiers,
        -- which is a rate channel and rotates the whole pattern rigidly, so the
        -- comparison is made on rotation-invariant radii over a circular horizon.
        local R = 40
        local function shapeAt(tier)
            local p = Logic.MaelstromTierParams(tier)
            local _, frame, tick = makeEffect({
                getParams = function() return p end,
                radiusX = R, radiusY = R,
            })
            tick(0.25 / p.infallPerSec)
            local radii = {}
            for i, t in ipairs(frame.textures) do
                radii[i] = t.shown and (math.sqrt(t.x * t.x + t.y * t.y) / R) or false
            end
            return radii
        end
        local a, b, c = shapeAt(1), shapeAt(2), shapeAt(3)
        local visible = 0
        for i = 1, #a do
            if a[i] == false then
                assert.are.equal(false, b[i], "stamp " .. i .. " visibility differs by tier")
                assert.are.equal(false, c[i], "stamp " .. i .. " visibility differs by tier")
            else
                visible = visible + 1
                assert.is_true(approx(a[i], b[i]), "stamp " .. i .. " radius differs by tier")
                assert.is_true(approx(a[i], c[i]), "stamp " .. i .. " radius differs by tier")
            end
        end
        assert.is_true(visible > 0)
    end)

    it("makes a higher tier brighter, fatter and glowier at the same position", function()
        local function peak(tier)
            local p = Logic.MaelstromTierParams(tier)
            local _, frame, tick = makeEffect({ getParams = function() return p end })
            tick(0.25 / p.infallPerSec)
            local w, a = 0, 0
            for _, t in ipairs(frame.textures) do
                if t.shown then
                    if t.w > w then w = t.w end
                    if (t.color[4] or 0) > a then a = t.color[4] end
                end
            end
            return w, a
        end
        local w1, a1 = peak(1)
        local w3, a3 = peak(3)
        assert.is_true(w3 > w1)   -- size + glow halo
        assert.is_true(a3 > a1)   -- opacity
    end)

    it("never draws inside the event horizon", function()
        -- The anchored widget must stay completely clear.
        local p = Logic.MaelstromTierParams(3)
        local RX, RY, scale = 36, 23, 1.5
        local _, frame, tick = makeEffect({
            getParams = function() return p end,
            radiusX = RX, radiusY = RY,
            getScale = function() return scale end,
        })
        local outerSeen = false
        for step = 1, 12 do
            tick(0.2 * step)
            for _, t in ipairs(frame.textures) do
                if t.shown then
                    -- Normalize back onto the unit circle: the horizon is r = 1.
                    local nx, ny = t.x / (RX * scale), t.y / (RY * scale)
                    local r = math.sqrt(nx * nx + ny * ny)
                    assert.is_true(r >= 1 - 1e-6, "stamp fell inside the horizon")
                    assert.is_true(r <= p.reach + 1e-6, "stamp spawned beyond the rim")
                    if r > p.reach * 0.8 then outerSeen = true end
                end
            end
        end
        assert.is_true(outerSeen)  -- material really does reach out to the rim
    end)

    it("cascades: a swirl head falls inward as the flow advances", function()
        -- Circular horizon so pixel distance IS the radius (on an ellipse the
        -- rotation that accompanies the fall would confound the measurement).
        local p = Logic.MaelstromTierParams(2)
        local R = 40
        local _, frame, tick = makeEffect({
            getParams = function() return p end,
            radiusX = R, radiusY = R,
        })
        local function headRadius()
            local t = frame.textures[1]   -- halo layer, swirl 1, head stamp
            return math.sqrt(t.x * t.x + t.y * t.y) / R
        end

        tick(0.05 / p.infallPerSec)       -- flow = 0.05, freshly spawned
        local prev = headRadius()
        assert.is_true(prev > 1.5)        -- still out near the rim
        for _ = 1, 8 do
            tick(0.1 / p.infallPerSec)
            local r = headRadius()
            assert.is_true(r < prev, "the swirl head must keep falling inward")
            prev = r
        end
        assert.is_true(prev < 1.2)        -- and end up hard against the horizon
    end)

    it("hides every stamp when params go away, and redraws when they return", function()
        local params = Logic.MaelstromTierParams(2)
        local _, _, tick, shown = makeEffect({ getParams = function() return params end })
        tick(1)
        assert.is_true(shown() > 0)

        params = nil
        tick(1)
        assert.are.equal(0, shown())

        -- The frame is never hidden (a hidden frame gets no OnUpdate in WoW), so
        -- the effect must be able to come back on its own.
        params = Logic.MaelstromTierParams(2)
        tick(1)
        assert.is_true(shown() > 0)
    end)

    it("scales stamp size and geometry with the widget scale", function()
        local p = Logic.MaelstromTierParams(2)
        local function biggest(scale)
            local _, frame, tick = makeEffect({
                getParams = function() return p end,
                getScale = function() return scale end,
            })
            tick(10)
            local m, far = 0, 0
            for _, t in ipairs(frame.textures) do
                if t.shown then
                    if t.w > m then m = t.w end
                    local d = math.sqrt(t.x * t.x + t.y * t.y)
                    if d > far then far = d end
                end
            end
            return m, far
        end
        local w1, d1 = biggest(1)
        local w2, d2 = biggest(2)
        assert.is_true(w2 > w1)
        assert.is_true(d2 > d1)
    end)

    it("throttles rendering but keeps the swirl on wall-clock time", function()
        local p = Logic.MaelstromTierParams(2)
        local effect, _, tick, shown = makeEffect({
            getParams = function() return p end,
            fps = 10,   -- render at most every 0.1s
        })

        tick(0.01)
        assert.are.equal(0, shown())          -- below the interval: no draw yet
        assert.is_true(effect.flow > 0)       -- but the cascade already advanced

        local flowAfterFirst = effect.flow
        tick(0.2)
        assert.is_true(shown() > 0)           -- past the interval: drawn
        assert.is_true(effect.flow > flowAfterFirst)
    end)

    it("advances the cascade proportionally to the tier's infall rate", function()
        local function flowAfter(tier)
            local effect, _, tick = makeEffect({
                getParams = function() return Logic.MaelstromTierParams(tier) end,
            })
            tick(0.5)
            return effect.flow
        end
        assert.is_true(flowAfter(3) > flowAfter(1))
    end)

    it("wraps the flow and spin phases instead of growing without bound", function()
        local effect, _, tick = makeEffect({
            getParams = function() return Logic.MaelstromTierParams(3) end,
        })
        for _ = 1, 200 do tick(0.1) end
        assert.is_true(effect.flow >= 0 and effect.flow < 1)
        assert.is_true(effect.spin >= 0 and effect.spin < 2 * math.pi)
    end)

    it("repoints every allocated stamp on SetTexture", function()
        local effect, frame = makeEffect({ dotTexture = "First\\Path" })
        for _, t in ipairs(frame.textures) do
            assert.are.equal("First\\Path", t.texture)
        end
        assert.are.equal("Second\\Path", effect:SetTexture("Second\\Path"))
        for _, t in ipairs(frame.textures) do
            assert.are.equal("Second\\Path", t.texture)
        end
        assert.are.equal("Second\\Path", effect.dotTexture)
    end)

    it("clamps per-stamp alpha to 1 when the intensity slider overdrives", function()
        local p = Logic.MaelstromTierParams(3, 2.0)
        assert.is_true(p.alpha > 1)   -- the params really do overdrive
        local _, frame, tick = makeEffect({ getParams = function() return p end })
        tick(10)
        local sawSaturated = false
        for _, t in ipairs(frame.textures) do
            if t.shown then
                assert.is_true(t.color[4] <= 1, "per-stamp alpha must be clamped")
                if approx(1, t.color[4]) then sawSaturated = true end
            end
        end
        assert.is_true(sawSaturated)  -- and it really is being driven to the cap
    end)

    it("defaults to a strata above ordinary widgets", function()
        -- It is a UIParent child, so it does not inherit the anchor's strata --
        -- at MEDIUM or below a neighbouring widget would simply cover it.
        local _, frame = makeEffect()
        assert.are.equal("HIGH", frame.strata)
        assert.is_true(frame.level > 0)
    end)

    it("re-applies the frame level after a strata change", function()
        -- SetFrameStrata resets the level in WoW; forgetting to re-apply silently
        -- drops the effect behind same-strata frames.
        local effect, frame = makeEffect({ frameLevel = 77 })
        assert.are.equal(77, frame.level)
        assert.are.equal("DIALOG", effect:SetStrata("DIALOG"))
        assert.are.equal("DIALOG", frame.strata)
        assert.are.equal(77, frame.level)
        assert.are.equal("DIALOG", effect.strata)
    end)

    it("makes SetStrata a no-op when the strata is unchanged", function()
        local effect, frame = makeEffect({ strata = "MEDIUM" })
        frame.level = "untouched"
        assert.are.equal("MEDIUM", effect:SetStrata("MEDIUM"))
        assert.are.equal("untouched", frame.level)
        assert.are.equal("MEDIUM", effect:SetStrata(nil))
    end)

    it("accepts every strata the config scale can produce", function()
        local effect, frame = makeEffect()
        for i = 1, #Logic.STRATA_ORDER do
            local name = Logic.StrataForLevel(i)
            effect:SetStrata(name)
            assert.are.equal(name, frame.strata)
        end
    end)

    it("tints every visible stamp with the tier colour", function()
        local p = Logic.MaelstromTierParams(3)
        local _, frame, tick = makeEffect({ getParams = function() return p end })
        tick(10)
        for _, t in ipairs(frame.textures) do
            if t.shown then
                assert.are.equal(p.color[1], t.color[1])
                assert.are.equal(p.color[2], t.color[2])
                assert.are.equal(p.color[3], t.color[3])
                assert.is_true(t.color[4] > 0)
            end
        end
    end)
end)
