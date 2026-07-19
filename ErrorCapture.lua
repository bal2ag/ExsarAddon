-- ErrorCapture module
-- Persistently records Lua errors (message + stack + locals) to SavedVariables
-- so they survive the popup being dismissed AND survive /reload or logout. WoW's
-- default error window (ScriptErrorsFrame) is in-memory only and gives no stack
-- for some errors (notably "script exceeded execution time limit"); this captures
-- debugstack()/debuglocals() at the moment the error propagates, which is our best
-- shot at a traceback for those.
--
-- We install our own handler via seterrorhandler and CHAIN to the previous one, so
-- the normal error popup still appears -- behavior is unchanged, we just also log.
--
-- Retrieval:
--   /exsar errdump    -- open a copy-paste window of captured errors (newest first)
--   /exsar errclear   -- wipe the log
--   /exsar errcapture -- toggle capture on/off
--
-- Settings stored under ExsarAddonDB.errorLog (entries = ring buffer, enabled flag).

local ADDON_NAME = "ExsarAddon"

local errDB = ExsarUI.MakeDB("errorLog")   -- lazy accessor; only CALL from ADDON_LOADED on

local MAX_ENTRIES = 50

-- `mem` holds the entries. Before ADDON_LOADED it is a standalone table (catches
-- load-time errors before the DB is ready); on ADDON_LOADED we merge it into the
-- persisted table and re-point `mem` at that table, so later appends persist.
local mem     = {}
local dbReady = false

local function Trim(t)
    while #t > MAX_ENTRIES do
        table.remove(t, 1)
    end
end

-- =========================================================
-- Capture
-- =========================================================

local function CaptureEnabled()
    if dbReady then
        return errDB().enabled ~= false
    end
    return true   -- capture pre-load errors by default
end

local lastNotify = 0
local function Notify()
    local now = (GetTime and GetTime()) or 0
    if now - lastNotify < 5 then return end
    lastNotify = now
    print("|cffff6060ExsarAddon|r captured an error \226\128\148 type |cffffd100/exsar errdump|r to view it.")
end

local capturing = false   -- reentrancy guard: never let the handler error into itself
local function Record(msg)
    if capturing or not CaptureEnabled() then return end
    capturing = true
    pcall(function()
        local stack = ""
        pcall(function() stack = debugstack(2, 20, 20) or "" end)
        local locals
        pcall(function() locals = debuglocals(2) end)

        local entry = {
            time   = (date and date("%m/%d %H:%M:%S")) or "?",
            up     = (GetTime and GetTime()) or 0,
            msg    = tostring(msg),
            stack  = stack,
            locals = locals,
            zone   = (GetRealZoneText and GetRealZoneText()) or "",
            combat = (InCombatLockdown and InCombatLockdown()) or false,
        }
        mem[#mem + 1] = entry
        Trim(mem)

        -- Only ping chat when the error looks like it came from us, so other
        -- addons' errors get logged silently without spamming the hunter.
        local ours = entry.msg:find("ExsarAddon", 1, true)
            or (stack and stack:find("ExsarAddon", 1, true))
        if ours then Notify() end
    end)
    capturing = false
end

-- Chain to whatever handler was installed before us (the default popup, or another
-- error addon), so the visible error UI is preserved.
local prevHandler = geterrorhandler and geterrorhandler()
local function Handler(msg)
    Record(msg)
    if prevHandler then pcall(prevHandler, msg) end
end
if seterrorhandler then
    seterrorhandler(Handler)
end

-- =========================================================
-- Rendering / dump
-- =========================================================

local function ActiveLog()
    return (dbReady and errDB().entries) or mem
end

local function FormatEntry(i, e)
    local head = string.format(
        "#%d  [%s]  zone=%s  combat=%s  t=%.1f",
        i,
        e.time or "?",
        (e.zone and e.zone ~= "" and e.zone) or "?",
        tostring(e.combat),
        e.up or 0
    )
    local parts = { head, "MSG:   " .. (e.msg or ""), "STACK:", e.stack or "(none)" }
    if e.locals and e.locals ~= "" then
        parts[#parts + 1] = "LOCALS:"
        parts[#parts + 1] = e.locals
    end
    return table.concat(parts, "\n")
end

local function DumpErrors()
    local src = ActiveLog()
    if not src or #src == 0 then
        print(ADDON_NAME .. ": no errors captured.")
        return
    end
    local lines = {}
    for i = #src, 1, -1 do   -- newest first
        lines[#lines + 1] = FormatEntry(i, src[i])
        lines[#lines + 1] = string.rep("-", 60)
    end
    ExsarUI.ShowCopyableText(table.concat(lines, "\n"),
        { title = "ExsarAddon \226\128\148 Captured Errors (newest first)" })
end

local function ClearErrors()
    local src = ActiveLog()
    if src then
        for i = #src, 1, -1 do src[i] = nil end
    end
    print(ADDON_NAME .. ": error log cleared.")
end

-- =========================================================
-- Slash commands
-- =========================================================

ExsarAddon.AddSlashCommand("errdump",  DumpErrors)
ExsarAddon.AddSlashCommand("errclear", ClearErrors)
ExsarAddon.AddSlashCommand("errcapture", function()
    if not dbReady then return end
    local db = errDB()
    local nowOn = db.enabled ~= false
    db.enabled = not nowOn
    print(ADDON_NAME .. ": error capture " .. (db.enabled ~= false and "ON" or "OFF") .. ".")
end)

-- =========================================================
-- DB init: merge pre-load entries into the persisted log
-- =========================================================

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON_NAME then return end
    local db = errDB()
    db.entries = db.entries or {}
    for _, e in ipairs(mem) do
        db.entries[#db.entries + 1] = e
    end
    Trim(db.entries)
    mem = db.entries      -- subsequent appends land straight in SavedVariables
    dbReady = true
    ev:UnregisterEvent("ADDON_LOADED")
end)

-- =========================================================
-- Config
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Error Log",
    icon = "INV_Misc_Note_01",
    BuildConfig = function(parent, y)
        local note = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, y)
        note:SetWidth(360)
        note:SetJustifyH("LEFT")
        note:SetText("Records Lua errors (message + stack + locals) to SavedVariables so "
            .. "they survive the popup being dismissed and survive /reload. "
            .. "Slash: /exsar errdump, /exsar errclear, /exsar errcapture.")
        y = y - 52

        ExsarAddon.CreateCheckbox(parent, "Capture Lua errors", 16, y,
            function() return not dbReady or errDB().enabled ~= false end,
            function(v) if dbReady then errDB().enabled = v end end)
        y = y - 34

        ExsarAddon.CreateButton(parent, "Show error log", 16, y, DumpErrors)
        y = y - 28

        ExsarAddon.CreateButton(parent, "Clear error log", 16, y, ClearErrors)
        y = y - 34

        return y
    end,
})
