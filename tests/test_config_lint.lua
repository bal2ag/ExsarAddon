-- tests/test_config_lint.lua
-- Source-lint guard for config-panel BuildConfig code.
--
-- BuildConfig functions run inside the WoW client (they call CreateFrame via
-- ExsarAddon.CreateSlider/Checkbox/Button), so they are never exercised by the
-- rest of the suite. This lint catches the one mistake that has actually bitten
-- us: mixing up the two config-helper conventions.
--
--   * ExsarAddon.CreateSlider / CreateCheckbox / CreateButton  -> return a FRAME.
--     Call them bare, then advance y yourself:  Create...(); y = y - 30
--   * ExsarUI.AddScaleSlider / AddLockCheckbox / AddResetButton -> return the
--     new y offset:  y = ExsarUI.AddLockCheckbox(...)
--
-- Writing `y = ExsarAddon.CreateCheckbox(...)` assigns a Frame to y; the next
-- `y = y - 30` then throws "arithmetic on a table value", which aborts the whole
-- options-panel build loop and breaks config for every module after it.

-- Frame-returning helpers whose result must never be assigned to the layout y.
local FRAME_HELPERS = { "CreateSlider", "CreateCheckbox", "CreateButton" }

--- Read the list of addon Lua files from the .toc (authoritative load list).
local function tocLuaFiles()
    local files = {}
    local f = assert(io.open("ExsarAddon.toc", "r"),
        "could not open ExsarAddon.toc (run busted from the repo root)")
    for line in f:lines() do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" and trimmed:sub(1, 1) ~= "#" and trimmed:match("%.lua$") then
            files[#files + 1] = trimmed
        end
    end
    f:close()
    return files
end

--- Scan one file for `y = ExsarAddon.<FrameHelper>(` assignments.
-- @return array of "line N: <text>" offenders
local function scanFile(path)
    local offenders = {}
    local f = io.open(path, "r")
    if not f then return offenders end
    local n = 0
    for line in f:lines() do
        n = n + 1
        for _, helper in ipairs(FRAME_HELPERS) do
            -- match e.g.  y = ExsarAddon.CreateCheckbox(
            if line:match("y%s*=%s*ExsarAddon%.%s*" .. helper .. "%s*%(") then
                offenders[#offenders + 1] = string.format("line %d: %s", n,
                    line:gsub("^%s+", ""))
            end
        end
    end
    f:close()
    return offenders
end

describe("config helper conventions", function()
    it("never assigns a frame-returning helper's result to the layout y", function()
        local problems = {}
        for _, path in ipairs(tocLuaFiles()) do
            for _, offender in ipairs(scanFile(path)) do
                problems[#problems + 1] = path .. ":" .. offender
            end
        end
        assert.are.equal(0, #problems,
            "ExsarAddon.CreateSlider/Checkbox/Button return a FRAME, not a y offset. "
            .. "Call them bare and advance y separately (or use the ExsarUI.Add* "
            .. "helpers, which return y). Offenders:\n  "
            .. table.concat(problems, "\n  "))
    end)
end)
