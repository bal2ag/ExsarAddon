-- tests/test_logic.lua
-- Unit tests for ExsarLogic pure functions.

package.path = package.path .. ";../?.lua"
local Logic = require("ExsarLogic")

-- Helper: compare floats with tolerance
local function approx(a, b, tol)
    tol = tol or 0.001
    return math.abs(a - b) < tol
end

-- =========================================================
-- FormatCooldown
-- =========================================================

describe("FormatCooldown", function()
    it("formats >= 60s as minutes (rounded up)", function()
        assert.are.equal("1m", Logic.FormatCooldown(60))
        assert.are.equal("2m", Logic.FormatCooldown(61))
        assert.are.equal("5m", Logic.FormatCooldown(300))
        assert.are.equal("2m", Logic.FormatCooldown(119))
        assert.are.equal("2m", Logic.FormatCooldown(120))
    end)

    it("formats 10-59s as whole seconds (rounded up)", function()
        assert.are.equal("10", Logic.FormatCooldown(10))
        assert.are.equal("59", Logic.FormatCooldown(59))
        assert.are.equal("11", Logic.FormatCooldown(10.1))
        assert.are.equal("45", Logic.FormatCooldown(45))
    end)

    it("formats < 10s with one decimal", function()
        assert.are.equal("9.9", Logic.FormatCooldown(9.9))
        assert.are.equal("3.2", Logic.FormatCooldown(3.2))
        assert.are.equal("0.5", Logic.FormatCooldown(0.5))
        assert.are.equal("0.1", Logic.FormatCooldown(0.1))
    end)

    it("handles boundary at exactly 10", function()
        assert.are.equal("10", Logic.FormatCooldown(10))
    end)

    it("handles boundary just under 10", function()
        assert.are.equal("10.0", Logic.FormatCooldown(9.99))
    end)

    it("rounds up correctly at minute boundary", function()
        assert.are.equal("2m", Logic.FormatCooldown(60.1))
        assert.are.equal("2m", Logic.FormatCooldown(60.5))
    end)
end)

-- =========================================================
-- FormatShortTimer
-- =========================================================

describe("FormatShortTimer", function()
    it("formats >= 10s as whole seconds (rounded up)", function()
        assert.are.equal("10", Logic.FormatShortTimer(10))
        assert.are.equal("15", Logic.FormatShortTimer(14.2))
        assert.are.equal("60", Logic.FormatShortTimer(60))
    end)

    it("formats < 10s with one decimal", function()
        assert.are.equal("9.9", Logic.FormatShortTimer(9.9))
        assert.are.equal("3.2", Logic.FormatShortTimer(3.2))
        assert.are.equal("0.5", Logic.FormatShortTimer(0.5))
    end)

    it("handles boundary at exactly 10", function()
        assert.are.equal("10", Logic.FormatShortTimer(10))
    end)

    it("handles very large values (no minute tier)", function()
        assert.are.equal("300", Logic.FormatShortTimer(300))
    end)
end)

-- =========================================================
-- FormatNumber
-- =========================================================

describe("FormatNumber", function()
    it("formats >= 1000 with k suffix", function()
        assert.are.equal("1.0k", Logic.FormatNumber(1000))
        assert.are.equal("1.5k", Logic.FormatNumber(1500))
        assert.are.equal("10.0k", Logic.FormatNumber(10000))
        assert.are.equal("100.0k", Logic.FormatNumber(100000))
    end)

    it("returns plain string for < 1000", function()
        assert.are.equal("999", Logic.FormatNumber(999))
        assert.are.equal("0", Logic.FormatNumber(0))
        assert.are.equal("1", Logic.FormatNumber(1))
        assert.are.equal("500", Logic.FormatNumber(500))
    end)

    it("handles exact boundary", function()
        assert.are.equal("1.0k", Logic.FormatNumber(1000))
        assert.are.equal("999", Logic.FormatNumber(999))
    end)
end)

-- =========================================================
-- HealthColorGradient
-- =========================================================

describe("HealthColorGradient", function()
    it("returns green at 100%", function()
        local r, g, b = Logic.HealthColorGradient(100)
        assert.is_true(approx(r, 0.1))
        assert.is_true(approx(g, 0.9))
        assert.is_true(approx(b, 0.1))
    end)

    it("returns yellow at 50%", function()
        local r, g, b = Logic.HealthColorGradient(50)
        assert.is_true(approx(r, 0.9))
        assert.is_true(approx(g, 0.9))
        assert.is_true(approx(b, 0.1))
    end)

    it("returns red at 0%", function()
        local r, g, b = Logic.HealthColorGradient(0)
        assert.is_true(approx(r, 0.9))
        assert.is_true(approx(g, 0.0))
        assert.is_true(approx(b, 0.1))
    end)

    it("interpolates smoothly at 75%", function()
        local r, g, b = Logic.HealthColorGradient(75)
        assert.is_true(approx(r, 0.55))
        assert.is_true(approx(g, 0.9))
        assert.is_true(approx(b, 0.1))
    end)

    it("interpolates at 25%", function()
        local r, g, b = Logic.HealthColorGradient(25)
        assert.is_true(approx(r, 0.9))
        assert.is_true(approx(g, 0.45))
        assert.is_true(approx(b, 0.1))
    end)

    it("green component is always 0.9 above 50%", function()
        for pct = 51, 100 do
            local _, g = Logic.HealthColorGradient(pct)
            assert.is_true(approx(g, 0.9))
        end
    end)
end)

-- =========================================================
-- HealthColorThreshold
-- =========================================================

describe("HealthColorThreshold", function()
    it("returns green above 50%", function()
        local r, g, b = Logic.HealthColorThreshold(51)
        assert.are.equal(0.20, r)
        assert.are.equal(0.75, g)
        assert.are.equal(0.20, b)
    end)

    it("returns yellow at 50%", function()
        local r, g, b = Logic.HealthColorThreshold(50)
        assert.are.equal(0.90, r)
        assert.are.equal(0.90, g)
        assert.are.equal(0.10, b)
    end)

    it("returns yellow at 21%", function()
        local r, g, b = Logic.HealthColorThreshold(21)
        assert.are.equal(0.90, r)
        assert.are.equal(0.90, g)
        assert.are.equal(0.10, b)
    end)

    it("returns red at 20%", function()
        local r, g, b = Logic.HealthColorThreshold(20)
        assert.are.equal(0.80, r)
        assert.are.equal(0.15, g)
        assert.are.equal(0.15, b)
    end)

    it("returns red at 0%", function()
        local r, g, b = Logic.HealthColorThreshold(0)
        assert.are.equal(0.80, r)
        assert.are.equal(0.15, g)
        assert.are.equal(0.15, b)
    end)

    it("returns green at 100%", function()
        local r, g, b = Logic.HealthColorThreshold(100)
        assert.are.equal(0.20, r)
        assert.are.equal(0.75, g)
        assert.are.equal(0.20, b)
    end)
end)

-- =========================================================
-- LevelColor
-- =========================================================

describe("LevelColor", function()
    local playerLevel = 70

    it("returns purple for skull (-1)", function()
        local r, g, b, a = Logic.LevelColor(-1, playerLevel)
        assert.are.equal(0.80, r)
        assert.are.equal(0.30, g)
        assert.are.equal(0.80, b)
        assert.are.equal(1, a)
    end)

    it("returns red for +5 or more", function()
        local r, g, b = Logic.LevelColor(75, playerLevel)
        assert.are.equal(1.00, r)
        assert.are.equal(0.10, g)
        assert.are.equal(0.10, b)
    end)

    it("returns red for +10", function()
        local r, g, b = Logic.LevelColor(80, playerLevel)
        assert.are.equal(1.00, r)
        assert.are.equal(0.10, g)
    end)

    it("returns orange for +3 to +4", function()
        local r, g, b = Logic.LevelColor(73, playerLevel)
        assert.are.equal(1.00, r)
        assert.are.equal(0.50, g)
        assert.are.equal(0.25, b)

        r, g, b = Logic.LevelColor(74, playerLevel)
        assert.are.equal(1.00, r)
        assert.are.equal(0.50, g)
    end)

    it("returns yellow for -2 to +2", function()
        assert.are.equal(1.00, (Logic.LevelColor(70, playerLevel)))
        assert.are.equal(1.00, (Logic.LevelColor(68, playerLevel)))
        assert.are.equal(1.00, (Logic.LevelColor(72, playerLevel)))
    end)

    it("returns green for -4 to -3", function()
        local r, g, b = Logic.LevelColor(67, playerLevel)
        assert.are.equal(0.25, r)
        assert.are.equal(0.75, g)
        assert.are.equal(0.25, b)

        r, g, b = Logic.LevelColor(66, playerLevel)
        assert.are.equal(0.25, r)
    end)

    it("returns grey for -5 or less", function()
        local r, g, b = Logic.LevelColor(65, playerLevel)
        assert.are.equal(0.55, r)
        assert.are.equal(0.55, g)
        assert.are.equal(0.55, b)

        r, g, b = Logic.LevelColor(1, playerLevel)
        assert.are.equal(0.55, r)
    end)

    it("works with different player levels", function()
        -- Level 60 player vs level 65 target = +5 = red
        local r = Logic.LevelColor(65, 60)
        assert.are.equal(1.00, r)

        -- Level 60 player vs level 60 target = 0 = yellow
        r = Logic.LevelColor(60, 60)
        assert.are.equal(1.00, r)
    end)
end)

-- =========================================================
-- CooldownState
-- =========================================================

describe("CooldownState", function()
    it("returns 'cooldown' when duration > 1.6", function()
        assert.are.equal("cooldown", Logic.CooldownState(100, 10))
        assert.are.equal("cooldown", Logic.CooldownState(100, 60))
        assert.are.equal("cooldown", Logic.CooldownState(1, 2))
    end)

    it("returns 'gcd' when duration > 0 but <= 1.6", function()
        assert.are.equal("gcd", Logic.CooldownState(100, 1.5))
        assert.are.equal("gcd", Logic.CooldownState(100, 0.5))
        assert.are.equal("gcd", Logic.CooldownState(100, 0.01))
    end)

    it("returns 'ready' when start is 0", function()
        assert.are.equal("ready", Logic.CooldownState(0, 0))
    end)

    it("returns 'ready' when start is nil", function()
        assert.are.equal("ready", Logic.CooldownState(nil, nil))
    end)

    it("returns 'ready' when duration is nil", function()
        assert.are.equal("ready", Logic.CooldownState(100, nil))
    end)

    it("handles exactly 1.6 as GCD (not cooldown)", function()
        assert.are.equal("gcd", Logic.CooldownState(100, 1.6))
    end)

    it("handles just above 1.6 as cooldown", function()
        assert.are.equal("cooldown", Logic.CooldownState(100, 1.601))
    end)

    it("MIN_COOLDOWN_DURATION is 1.6", function()
        assert.are.equal(1.6, Logic.MIN_COOLDOWN_DURATION)
    end)
end)

-- =========================================================
-- CooldownRemaining
-- =========================================================

describe("CooldownRemaining", function()
    it("calculates remaining time", function()
        assert.are.equal(5, Logic.CooldownRemaining(100, 10, 105))
    end)

    it("returns 0 when expired", function()
        assert.are.equal(0, Logic.CooldownRemaining(100, 10, 111))
    end)

    it("returns 0 when exactly expired", function()
        assert.are.equal(0, Logic.CooldownRemaining(100, 10, 110))
    end)

    it("returns 0 for nil inputs", function()
        assert.are.equal(0, Logic.CooldownRemaining(nil, nil, 100))
    end)

    it("returns full duration at start", function()
        assert.are.equal(10, Logic.CooldownRemaining(100, 10, 100))
    end)

    it("returns partial time mid-cooldown", function()
        assert.is_true(approx(3.5, Logic.CooldownRemaining(100, 10, 106.5)))
    end)

    it("handles start=nil duration=non-nil", function()
        assert.are.equal(0, Logic.CooldownRemaining(nil, 10, 100))
    end)
end)

-- =========================================================
-- CalcStripWidth
-- =========================================================

describe("CalcStripWidth", function()
    local iconSize = 32
    local iconGap = 4
    local groupGap = 10
    local padding = 8

    it("calculates width for a single group of 3 visible icons", function()
        local groups = {
            { {known=true}, {known=true}, {known=true} },
        }
        -- padding + 3*32 + 2*4 + padding = 8 + 96 + 8 + 8 = 120
        assert.are.equal(120, Logic.CalcStripWidth(groups, iconSize, iconGap, groupGap, padding))
    end)

    it("calculates width for two groups", function()
        local groups = {
            { {known=true}, {known=true} },
            { {known=true} },
        }
        -- padding + 2*32 + 1*4 + groupGap + 1*32 + padding = 8 + 64 + 4 + 10 + 32 + 8 = 126
        assert.are.equal(126, Logic.CalcStripWidth(groups, iconSize, iconGap, groupGap, padding))
    end)

    it("skips hidden spells", function()
        local groups = {
            { {known=true}, {known=false}, {known=true} },
        }
        -- padding + 2*32 + 1*4 + padding = 8 + 64 + 4 + 8 = 84
        assert.are.equal(84, Logic.CalcStripWidth(groups, iconSize, iconGap, groupGap, padding))
    end)

    it("skips entirely hidden groups (no gap added)", function()
        local groups = {
            { {known=true} },
            { {known=false}, {known=false} },
            { {known=true} },
        }
        -- padding + 32 + groupGap + 32 + padding = 8 + 32 + 10 + 32 + 8 = 90
        assert.are.equal(90, Logic.CalcStripWidth(groups, iconSize, iconGap, groupGap, padding))
    end)

    it("returns double padding when nothing visible", function()
        local groups = {
            { {known=false} },
        }
        assert.are.equal(16, Logic.CalcStripWidth(groups, iconSize, iconGap, groupGap, padding))
    end)

    it("handles empty groups list", function()
        assert.are.equal(16, Logic.CalcStripWidth({}, iconSize, iconGap, groupGap, padding))
    end)

    it("handles single visible icon", function()
        local groups = { { {known=true} } }
        -- padding + 32 + padding = 8 + 32 + 8 = 48
        assert.are.equal(48, Logic.CalcStripWidth(groups, iconSize, iconGap, groupGap, padding))
    end)
end)

-- =========================================================
-- CalcFlatStripSize
-- =========================================================

describe("CalcFlatStripSize", function()
    it("calculates width for visible icons", function()
        local w, h = Logic.CalcFlatStripSize(3, 29, 4, 6)
        -- 6 + 3*29 + 2*4 + 6 = 6 + 87 + 8 + 6 = 107
        assert.are.equal(107, w)
        assert.are.equal(41, h)  -- 29 + 6*2
    end)

    it("returns double padding when no icons", function()
        local w, h = Logic.CalcFlatStripSize(0, 29, 4, 6)
        assert.are.equal(12, w)
        assert.are.equal(41, h)
    end)

    it("handles single icon", function()
        local w, h = Logic.CalcFlatStripSize(1, 29, 4, 6)
        assert.are.equal(41, w)  -- 6 + 29 + 6
        assert.are.equal(41, h)
    end)

    it("handles large count", function()
        local w, h = Logic.CalcFlatStripSize(10, 29, 4, 6)
        -- 6 + 10*29 + 9*4 + 6 = 6 + 290 + 36 + 6 = 338
        assert.are.equal(338, w)
        assert.are.equal(41, h)  -- height is always iconSize + 2*padding
    end)
end)

-- =========================================================
-- CalcVerticalStripSize
-- =========================================================

describe("CalcVerticalStripSize", function()
    it("calculates height for visible icons", function()
        local w, h = Logic.CalcVerticalStripSize(3, 29, 4, 6)
        assert.are.equal(41, w)  -- 29 + 6*2
        -- 6 + 3*29 + 2*4 + 6 = 107
        assert.are.equal(107, h)
    end)

    it("returns double padding height when no icons", function()
        local w, h = Logic.CalcVerticalStripSize(0, 29, 4, 6)
        assert.are.equal(41, w)
        assert.are.equal(12, h)
    end)

    it("handles single icon", function()
        local w, h = Logic.CalcVerticalStripSize(1, 29, 4, 6)
        assert.are.equal(41, w)  -- 29 + 6*2
        assert.are.equal(41, h)  -- 6 + 29 + 6
    end)

    it("is transpose of CalcFlatStripSize", function()
        local fw, fh = Logic.CalcFlatStripSize(4, 29, 4, 6)
        local vw, vh = Logic.CalcVerticalStripSize(4, 29, 4, 6)
        assert.are.equal(fw, vh)  -- flat width == vertical height
        assert.are.equal(fh, vw)  -- flat height == vertical width
    end)
end)

-- =========================================================
-- ReticuleFraction
-- =========================================================

describe("ReticuleFraction", function()
    it("calculates fraction of half-width", function()
        assert.is_true(approx(0.5/2.8, Logic.ReticuleFraction(0.5, 2.8)))
    end)

    it("clamps to 0.98", function()
        assert.are.equal(0.98, Logic.ReticuleFraction(2.0, 1.0))
    end)

    it("returns 0 for zero speed", function()
        assert.are.equal(0, Logic.ReticuleFraction(0.5, 0))
    end)

    it("returns 0 for negative speed", function()
        assert.are.equal(0, Logic.ReticuleFraction(0.5, -1))
    end)

    it("handles typical hunter auto shot values", function()
        -- 2.8 speed bow, 0.6 aim window
        local frac = Logic.ReticuleFraction(0.6, 2.8)
        assert.is_true(approx(0.2143, frac))
    end)
end)

-- =========================================================
-- GridPosition
-- =========================================================

describe("GridPosition", function()
    it("first item is at (0, 0)", function()
        local col, row = Logic.GridPosition(1, 5)
        assert.are.equal(0, col)
        assert.are.equal(0, row)
    end)

    it("wraps to next row", function()
        local col, row = Logic.GridPosition(6, 5)
        assert.are.equal(0, col)
        assert.are.equal(1, row)
    end)

    it("handles middle of row", function()
        local col, row = Logic.GridPosition(3, 5)
        assert.are.equal(2, col)
        assert.are.equal(0, row)
    end)

    it("last item in first row", function()
        local col, row = Logic.GridPosition(5, 5)
        assert.are.equal(4, col)
        assert.are.equal(0, row)
    end)

    it("handles second row", function()
        local col, row = Logic.GridPosition(8, 5)
        assert.are.equal(2, col)
        assert.are.equal(1, row)
    end)

    it("handles 1 icon per row", function()
        local col, row = Logic.GridPosition(3, 1)
        assert.are.equal(0, col)
        assert.are.equal(2, row)
    end)
end)

-- =========================================================
-- IconsPerRow
-- =========================================================

describe("IconsPerRow", function()
    it("calculates icons that fit in a frame", function()
        -- frameWidth=200, padding=6 each side, iconSize=29, iconGap=4
        -- available = 200 - 12 + 4 = 192, each icon = 33, floor(192/33) = 5
        assert.are.equal(5, Logic.IconsPerRow(200, 6, 29, 4))
    end)

    it("returns at least 1", function()
        assert.are.equal(1, Logic.IconsPerRow(10, 6, 29, 4))
    end)

    it("exact fit", function()
        -- 2 icons: 6 + 29 + 4 + 29 + 6 = 74
        assert.are.equal(2, Logic.IconsPerRow(74, 6, 29, 4))
    end)

    it("one pixel short of fitting another icon", function()
        -- 74 fits 2 icons exactly; 73 should still be 2
        -- available = 73 - 12 + 4 = 65, each icon = 33, floor(65/33) = 1
        assert.are.equal(1, Logic.IconsPerRow(73, 6, 29, 4))
    end)

    it("handles zero gap", function()
        -- frameWidth=100, padding=5, iconSize=30, iconGap=0
        -- available = 100 - 10 + 0 = 90, each = 30, floor(90/30) = 3
        assert.are.equal(3, Logic.IconsPerRow(100, 5, 30, 0))
    end)

    it("handles large icons in small frame", function()
        assert.are.equal(1, Logic.IconsPerRow(50, 10, 100, 5))
    end)
end)

-- =========================================================
-- GridRowCount
-- =========================================================

describe("GridRowCount", function()
    it("calculates rows needed", function()
        assert.are.equal(1, Logic.GridRowCount(3, 5))
        assert.are.equal(2, Logic.GridRowCount(6, 5))
        assert.are.equal(2, Logic.GridRowCount(10, 5))
        assert.are.equal(3, Logic.GridRowCount(11, 5))
    end)

    it("returns 0 for no items", function()
        assert.are.equal(0, Logic.GridRowCount(0, 5))
    end)

    it("handles exact multiple", function()
        assert.are.equal(2, Logic.GridRowCount(10, 5))
    end)

    it("handles single item", function()
        assert.are.equal(1, Logic.GridRowCount(1, 5))
    end)

    it("handles 1 icon per row", function()
        assert.are.equal(4, Logic.GridRowCount(4, 1))
    end)

    it("handles negative count", function()
        assert.are.equal(0, Logic.GridRowCount(-1, 5))
    end)
end)

-- =========================================================
-- PulseAlpha
-- =========================================================

describe("PulseAlpha", function()
    it("returns midpoint at time 0", function()
        local alpha = Logic.PulseAlpha(0, 0.8, 0.65, 1.0)
        assert.is_true(approx(0.825, alpha))
    end)

    it("reaches max at quarter period", function()
        local freq = 0.8
        local t = 1 / (4 * freq)
        local alpha = Logic.PulseAlpha(t, freq, 0.65, 1.0)
        assert.is_true(approx(1.0, alpha))
    end)

    it("reaches min at three-quarter period", function()
        local freq = 0.8
        local t = 3 / (4 * freq)
        local alpha = Logic.PulseAlpha(t, freq, 0.65, 1.0)
        assert.is_true(approx(0.65, alpha))
    end)

    it("stays within bounds", function()
        for i = 0, 100 do
            local t = i * 0.1
            local alpha = Logic.PulseAlpha(t, 0.8, 0.65, 1.0)
            assert.is_true(alpha >= 0.65 - 0.001)
            assert.is_true(alpha <= 1.0 + 0.001)
        end
    end)

    it("works with different min/max ranges", function()
        local alpha = Logic.PulseAlpha(0, 1.0, 0.5, 0.85)
        assert.is_true(approx(0.675, alpha))
    end)
end)

-- =========================================================
-- MarchingAntAlpha
-- =========================================================

describe("MarchingAntAlpha", function()
    it("returns full alpha at head position", function()
        local alpha = Logic.MarchingAntAlpha(5, 5, 16, 5)
        assert.is_true(approx(1.0, alpha))
    end)

    it("returns 0 for dashes outside tail", function()
        local alpha = Logic.MarchingAntAlpha(0, 10, 16, 5)
        assert.are.equal(0, alpha)
    end)

    it("fades within tail", function()
        -- dash 1 behind head: dist=1, tailLen=5
        local alpha = Logic.MarchingAntAlpha(4, 5, 16, 5)
        assert.is_true(approx(1.0 - (1/5)*0.85, alpha))
    end)

    it("wraps around correctly", function()
        -- head at 2, dash at 15, dashCount=16 → dist = (2-15+16) % 16 = 3
        local alpha = Logic.MarchingAntAlpha(15, 2, 16, 5)
        assert.is_true(approx(1.0 - (3/5)*0.85, alpha))
    end)

    it("last dash in tail has minimum alpha", function()
        -- dist = tailLen - 1 (just barely in tail)
        local alpha = Logic.MarchingAntAlpha(1, 5, 16, 5)
        -- dist = 4
        assert.is_true(approx(1.0 - (4/5)*0.85, alpha))
    end)
end)

-- =========================================================
-- MarchingAntHead
-- =========================================================

describe("MarchingAntHead", function()
    it("returns 0 at time 0", function()
        assert.are.equal(0, Logic.MarchingAntHead(0, 1.5, 16))
    end)

    it("wraps at dashCount", function()
        -- speed=1.5, dashCount=16: one full cycle in 1/1.5 seconds
        local head = Logic.MarchingAntHead(1/1.5, 1.5, 16)
        assert.is_true(approx(0, head, 0.01))
    end)

    it("progresses linearly", function()
        local head = Logic.MarchingAntHead(0.5, 1.5, 16)
        -- 0.5 * 1.5 * 16 = 12
        assert.is_true(approx(12, head))
    end)

    it("stays within 0 to dashCount", function()
        for i = 0, 200 do
            local t = i * 0.1
            local head = Logic.MarchingAntHead(t, 1.5, 16)
            assert.is_true(head >= 0)
            assert.is_true(head < 16)
        end
    end)

    it("works with different dash counts", function()
        local head = Logic.MarchingAntHead(1.0, 1.0, 8)
        -- 1.0 * 1.0 * 8 = 8, mod 8 = 0
        assert.is_true(approx(0, head, 0.01))
    end)
end)

-- =========================================================
-- CalcAnchorOffset
-- =========================================================

describe("CalcAnchorOffset", function()
    it("returns center offset for centered frame", function()
        -- Frame at center of 1920x1080 screen, scale 1.0
        local ax, ay = Logic.CalcAnchorOffset(960 - 50, 540 + 50, 1.0, 1920, 1080)
        -- anchorX = (960-50) - 1920/(2*1) = 910 - 960 = -50
        -- anchorY = (540+50) - 1080/(2*1) = 590 - 540 = 50
        assert.is_true(approx(-50, ax))
        assert.is_true(approx(50, ay))
    end)

    it("accounts for scale", function()
        local ax, ay = Logic.CalcAnchorOffset(100, 500, 2.0, 1920, 1080)
        -- anchorX = 100 - 1920/4 = 100 - 480 = -380
        -- anchorY = 500 - 1080/4 = 500 - 270 = 230
        assert.is_true(approx(-380, ax))
        assert.is_true(approx(230, ay))
    end)

    it("returns 0,0 when frame is at exact center offset", function()
        local ax, ay = Logic.CalcAnchorOffset(960, 540, 1.0, 1920, 1080)
        assert.is_true(approx(0, ax))
        assert.is_true(approx(0, ay))
    end)

    it("handles top-left corner", function()
        local ax, ay = Logic.CalcAnchorOffset(0, 1080, 1.0, 1920, 1080)
        -- anchorX = 0 - 960 = -960
        -- anchorY = 1080 - 540 = 540
        assert.is_true(approx(-960, ax))
        assert.is_true(approx(540, ay))
    end)

    it("handles fractional scale", function()
        local ax, ay = Logic.CalcAnchorOffset(200, 800, 0.5, 1920, 1080)
        -- anchorX = 200 - 1920/(2*0.5) = 200 - 1920 = -1720
        -- anchorY = 800 - 1080/(2*0.5) = 800 - 1080 = -280
        assert.is_true(approx(-1720, ax))
        assert.is_true(approx(-280, ay))
    end)
end)

-- =========================================================
-- RoundScale
-- =========================================================

describe("RoundScale", function()
    it("rounds to nearest 0.05", function()
        assert.is_true(approx(1.0, Logic.RoundScale(1.0)))
        assert.is_true(approx(1.05, Logic.RoundScale(1.06)))
        assert.is_true(approx(1.05, Logic.RoundScale(1.07)))
        assert.is_true(approx(1.10, Logic.RoundScale(1.08)))
        assert.is_true(approx(0.50, Logic.RoundScale(0.5)))
        assert.is_true(approx(2.00, Logic.RoundScale(2.0)))
    end)

    it("rounds 0.52 to 0.50", function()
        assert.is_true(approx(0.50, Logic.RoundScale(0.52)))
    end)

    it("rounds 0.53 to 0.55", function()
        assert.is_true(approx(0.55, Logic.RoundScale(0.53)))
    end)

    it("rounds 1.425 to 1.45", function()
        assert.is_true(approx(1.45, Logic.RoundScale(1.425)))
    end)
end)

-- =========================================================
-- AggroAlertEnabled
-- =========================================================

describe("AggroAlertEnabled", function()
    it("returns true for solo when solo enabled", function()
        assert.is_true(Logic.AggroAlertEnabled("solo", true, false, false))
    end)

    it("returns false for solo when solo disabled", function()
        assert.is_false(Logic.AggroAlertEnabled("solo", false, true, true))
    end)

    it("returns true for party when party enabled", function()
        assert.is_true(Logic.AggroAlertEnabled("party", false, true, false))
    end)

    it("returns false for party when party disabled", function()
        assert.is_false(Logic.AggroAlertEnabled("party", true, false, true))
    end)

    it("returns true for raid when raid enabled", function()
        assert.is_true(Logic.AggroAlertEnabled("raid", false, false, true))
    end)

    it("returns false for raid when raid disabled", function()
        assert.is_false(Logic.AggroAlertEnabled("raid", true, true, false))
    end)

    it("returns false for unknown context", function()
        assert.is_false(Logic.AggroAlertEnabled("battleground", true, true, true))
    end)

    it("treats nil as false", function()
        assert.is_false(Logic.AggroAlertEnabled("solo", nil, true, true))
    end)

    it("all enabled returns true for all contexts", function()
        assert.is_true(Logic.AggroAlertEnabled("solo", true, true, true))
        assert.is_true(Logic.AggroAlertEnabled("party", true, true, true))
        assert.is_true(Logic.AggroAlertEnabled("raid", true, true, true))
    end)
end)

-- =========================================================
-- SelectBestRank
-- =========================================================

describe("SelectBestRank", function()
    local ranks = {
        { id = 5, name = "Rank V",   buffId = 55 },
        { id = 4, name = "Rank IV",  buffId = 44 },
        { id = 3, name = "Rank III", buffId = 33 },
        { id = 2, name = "Rank II",  buffId = 22 },
        { id = 1, name = "Rank I",   buffId = 11 },
    }

    it("returns highest rank when all have stock", function()
        local result = Logic.SelectBestRank(ranks, function() return 5 end)
        assert.are.equal(5, result.id)
    end)

    it("returns highest rank with stock when top rank is empty", function()
        local counts = { [5] = 0, [4] = 0, [3] = 3, [2] = 1, [1] = 2 }
        local result = Logic.SelectBestRank(ranks, function(id) return counts[id] or 0 end)
        assert.are.equal(3, result.id)
    end)

    it("returns lowest rank when only lowest has stock", function()
        local counts = { [5] = 0, [4] = 0, [3] = 0, [2] = 0, [1] = 1 }
        local result = Logic.SelectBestRank(ranks, function(id) return counts[id] or 0 end)
        assert.are.equal(1, result.id)
    end)

    it("falls back to highest rank when nothing in stock", function()
        local result = Logic.SelectBestRank(ranks, function() return 0 end)
        assert.are.equal(5, result.id)
    end)

    it("returns the full rank entry table", function()
        local counts = { [5] = 0, [4] = 2, [3] = 0, [2] = 0, [1] = 0 }
        local result = Logic.SelectBestRank(ranks, function(id) return counts[id] or 0 end)
        assert.are.equal(4, result.id)
        assert.are.equal("Rank IV", result.name)
        assert.are.equal(44, result.buffId)
    end)

    it("skips zero-count ranks even if later ranks have stock", function()
        local counts = { [5] = 0, [4] = 3, [3] = 0, [2] = 5, [1] = 0 }
        local result = Logic.SelectBestRank(ranks, function(id) return counts[id] or 0 end)
        assert.are.equal(4, result.id)
    end)

    it("works with a single rank", function()
        local single = { { id = 10, name = "Only", buffId = 99 } }
        local result = Logic.SelectBestRank(single, function() return 0 end)
        assert.are.equal(10, result.id)
    end)

    it("works with a single rank that has stock", function()
        local single = { { id = 10, name = "Only", buffId = 99 } }
        local result = Logic.SelectBestRank(single, function() return 3 end)
        assert.are.equal(10, result.id)
    end)
end)

-- =========================================================
-- SuggestRotation
-- =========================================================

describe("SuggestRotation", function()
    it("suggests 5:6:1:1 for very slow speeds", function()
        assert.are.equal("5:6:1:1", Logic.SuggestRotation(2.0))
        assert.are.equal("5:6:1:1", Logic.SuggestRotation(1.84))
        assert.are.equal("5:6:1:1", Logic.SuggestRotation(3.0))
    end)

    it("suggests 5:6:1:1 at the 1.83 boundary", function()
        assert.are.equal("5:6:1:1", Logic.SuggestRotation(1.83))
    end)

    it("suggests 1:1 for mid-range speeds", function()
        assert.are.equal("1:1", Logic.SuggestRotation(1.5))
        assert.are.equal("1:1", Logic.SuggestRotation(1.3))
    end)

    it("suggests 1:1 at the 1.22 boundary", function()
        assert.are.equal("1:1", Logic.SuggestRotation(1.22))
    end)

    it("suggests 2:3 between 0.83 and 1.22", function()
        assert.are.equal("2:3", Logic.SuggestRotation(1.0))
        assert.are.equal("2:3", Logic.SuggestRotation(0.9))
        assert.are.equal("2:3", Logic.SuggestRotation(1.21))
    end)

    it("suggests 1:2 at 0.83 and below", function()
        assert.are.equal("1:2", Logic.SuggestRotation(0.83))
        assert.are.equal("1:2", Logic.SuggestRotation(0.7))
        assert.are.equal("1:2", Logic.SuggestRotation(0.5))
    end)
end)

-- =========================================================
-- Pet happiness model
-- =========================================================

describe("ReconcileHappinessTier", function()
    local TIER_MIN = { [1] = 0,   [2] = 350, [3] = 700  }
    local TIER_MAX = { [1] = 349, [2] = 699, [3] = 1050 }

    it("preserves exact arithmetic when feed-carried estimate is already in the new tier (UP)", function()
        -- Pet at 695 (tier 2), fed +8 → 703, API flips to tier 3.
        -- Prior bug: snapped to TIER_MIN[3]=700, erasing +3 real points.
        local est, anchored = Logic.ReconcileHappinessTier(703, 3, false, TIER_MIN, TIER_MAX)
        assert.are.equal(703, est)
        assert.is_false(anchored)
    end)

    it("preserves anchored=true when estimate is already in the new tier", function()
        local est, anchored = Logic.ReconcileHappinessTier(703, 3, true, TIER_MIN, TIER_MAX)
        assert.are.equal(703, est)
        assert.is_true(anchored)
    end)

    it("snaps to tier floor and anchors when estimate is below the new tier (UP flip outpaced arithmetic)", function()
        local est, anchored = Logic.ReconcileHappinessTier(680, 3, false, TIER_MIN, TIER_MAX)
        assert.are.equal(700, est)
        assert.is_true(anchored)
    end)

    it("snaps to tier ceiling and anchors when estimate is above the new tier (DOWN flip)", function()
        -- Our decay lagged reality — API says tier 2 but we thought 710.
        local est, anchored = Logic.ReconcileHappinessTier(710, 2, false, TIER_MIN, TIER_MAX)
        assert.are.equal(699, est)
        assert.is_true(anchored)
    end)

    it("preserves estimate when decay already predicted the DOWN flip", function()
        -- Our arithmetic had us at 695 (already within tier 2) when API confirms tier 2.
        local est, anchored = Logic.ReconcileHappinessTier(695, 2, false, TIER_MIN, TIER_MAX)
        assert.are.equal(695, est)
        assert.is_false(anchored)
    end)

    it("clamps above-range estimate to tier ceiling", function()
        local est, anchored = Logic.ReconcileHappinessTier(1200, 3, false, TIER_MIN, TIER_MAX)
        assert.are.equal(1050, est)
        assert.is_true(anchored)
    end)

    it("is a no-op when estimate sits exactly on the floor boundary", function()
        local est, anchored = Logic.ReconcileHappinessTier(700, 3, true, TIER_MIN, TIER_MAX)
        assert.are.equal(700, est)
        assert.is_true(anchored)
    end)

    it("is a no-op when estimate sits exactly on the ceiling boundary", function()
        local est, anchored = Logic.ReconcileHappinessTier(699, 2, false, TIER_MIN, TIER_MAX)
        assert.are.equal(699, est)
        assert.is_false(anchored)
    end)
end)

describe("ApplyHappinessDecay", function()
    local TIER_MIN = { [1] = 0, [2] = 350, [3] = 700 }
    local MAX = 1050
    local DECAY = 50 / 6  -- ~8.33 pts/min

    it("subtracts decay across elapsed seconds", function()
        local newEst = Logic.ApplyHappinessDecay(800, 60, DECAY, 3, TIER_MIN, MAX)
        assert.is_true(approx(800 - DECAY, newEst, 0.01))
    end)

    it("clamps at the API tier floor so estimate never drifts below it", function()
        -- Prior bug: from 700 at tier 3, decay → ~691.67 → ptsAboveTier negative → 0.0s forever.
        local newEst = Logic.ApplyHappinessDecay(700, 60, DECAY, 3, TIER_MIN, MAX)
        assert.are.equal(700, newEst)
    end)

    it("stays clamped at floor across many decay ticks while API tier holds", function()
        local est = 701
        for _ = 1, 20 do
            est = Logic.ApplyHappinessDecay(est, 10, DECAY, 3, TIER_MIN, MAX)
        end
        assert.are.equal(700, est)
    end)

    it("allows estimate to drift freely above the floor", function()
        local newEst = Logic.ApplyHappinessDecay(1050, 60, DECAY, 3, TIER_MIN, MAX)
        assert.is_true(approx(1050 - DECAY, newEst, 0.01))
    end)

    it("uses 0 as floor when API tier is unknown", function()
        local newEst = Logic.ApplyHappinessDecay(5, 600, DECAY, 0, TIER_MIN, MAX)
        assert.are.equal(0, newEst)
    end)

    it("clamps above max if somehow over", function()
        local newEst = Logic.ApplyHappinessDecay(2000, 0, DECAY, 3, TIER_MIN, MAX)
        assert.are.equal(1050, newEst)
    end)

    it("handles zero elapsed as a no-op", function()
        local newEst = Logic.ApplyHappinessDecay(900, 0, DECAY, 3, TIER_MIN, MAX)
        assert.are.equal(900, newEst)
    end)

    it("treats negative elapsed as zero", function()
        local newEst = Logic.ApplyHappinessDecay(900, -5, DECAY, 3, TIER_MIN, MAX)
        assert.are.equal(900, newEst)
    end)

    it("tier-2 floor clamps at 350, not 700", function()
        local newEst = Logic.ApplyHappinessDecay(350, 60, DECAY, 2, TIER_MIN, MAX)
        assert.are.equal(350, newEst)
    end)

    it("returns clamped=true when decay would cross the floor", function()
        local _, clamped = Logic.ApplyHappinessDecay(700.5, 60, DECAY, 3, TIER_MIN, MAX)
        assert.is_true(clamped)
    end)

    it("returns clamped=false when decay stays above the floor", function()
        local _, clamped = Logic.ApplyHappinessDecay(900, 60, DECAY, 3, TIER_MIN, MAX)
        assert.is_false(clamped)
    end)

    it("returns clamped=false when elapsed is zero even if already at floor", function()
        -- A no-op tick shouldn't count as a clamp event.
        local _, clamped = Logic.ApplyHappinessDecay(700, 0, DECAY, 3, TIER_MIN, MAX)
        assert.is_false(clamped)
    end)

    it("returns clamped=true on every active tick while pinned at floor", function()
        local _, clamped = Logic.ApplyHappinessDecay(700, 1, DECAY, 3, TIER_MIN, MAX)
        assert.is_true(clamped)
    end)
end)
