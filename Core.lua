local ADDON_NAME = "ExsarAddon"

ExsarAddon = {}

local registeredModules = {}
local slashHandlers     = {}
local OPT_ID            = 0

-- =========================================================
-- Module registration API
-- =========================================================

-- Register a feature module. `module` must be a table with:
--   name        (string)
--   BuildConfig (function(parent, y) -> endY)
function ExsarAddon.RegisterModule(module)
    registeredModules[#registeredModules + 1] = module
end

-- Register a sub-command for /exsar.
function ExsarAddon.AddSlashCommand(cmd, fn)
    slashHandlers[cmd] = fn
end

-- =========================================================
-- Config widget helpers (available to all modules)
-- =========================================================

function ExsarAddon.CreateSlider(parent, label, x, y, minV, maxV, step, getter, setter)
    OPT_ID = OPT_ID + 1
    local s = CreateFrame("Slider", ADDON_NAME .. "OptSl" .. OPT_ID, parent, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s:SetWidth(200)
    s:SetHeight(17)

    -- TBC Classic Anniversary quirk: slider track may be invisible; draw our own
    pcall(function() s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal") end)
    local thumb = s.GetThumbTexture and s:GetThumbTexture()
    if thumb and thumb.SetSize then thumb:SetSize(16, 16) end
    local trackBg = s:CreateTexture(nil, "BACKGROUND")
    trackBg:SetColorTexture(0, 0, 0, 1)
    trackBg:SetPoint("LEFT",  s, "LEFT",  5, 0)
    trackBg:SetPoint("RIGHT", s, "RIGHT", -5, 0)
    trackBg:SetHeight(8)
    local tplBg = _G[s:GetName() .. "Background"]
    if tplBg then tplBg:Hide() end

    local sText = _G[s:GetName() .. "Text"]
    local sLow  = _G[s:GetName() .. "Low"]
    local sHigh = _G[s:GetName() .. "High"]
    if sLow  then sLow:SetText(tostring(minV)) end
    if sHigh then sHigh:SetText(tostring(maxV)) end

    local function updateLabel(v)
        if sText then
            local display
            if step >= 1 then
                display = tostring(math.floor(v + 0.5))
            else
                display = string.format("%." .. math.max(0, math.ceil(-math.log10(step))) .. "f", v)
            end
            sText:SetText(label .. ": " .. display)
        end
    end

    s._ignore = true
    s:SetValue(getter())
    updateLabel(getter())
    s._ignore = false

    s:SetScript("OnShow", function(self)
        self._ignore = true
        self:SetValue(getter())
        updateLabel(getter())
        self._ignore = false
    end)
    s:SetScript("OnValueChanged", function(self, v)
        updateLabel(v)
        if self._ignore then return end
        setter(v)
    end)

    return s
end

function ExsarAddon.CreateCheckbox(parent, label, x, y, getter, setter)
    OPT_ID = OPT_ID + 1
    local cb = CreateFrame("CheckButton", ADDON_NAME .. "OptCB" .. OPT_ID, parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local cbText = cb.Text or _G[cb:GetName() .. "Text"]
    if cbText then cbText:SetText(label) end
    cb:SetScript("OnShow", function(self) self:SetChecked(getter()) end)
    cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
    cb:SetChecked(getter())
    return cb
end

function ExsarAddon.CreateButton(parent, label, x, y, onClick)
    OPT_ID = OPT_ID + 1
    local btn = CreateFrame("Button", ADDON_NAME .. "OptBtn" .. OPT_ID, parent, "UIPanelButtonTemplate")
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    btn:SetSize(140, 22)
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- =========================================================
-- Options panel (Interface -> AddOns -> ExsarAddon)
-- =========================================================

local OPTIONS_CATEGORY
local ToggleConfig  -- forward declaration

local Options = CreateFrame("Frame", ADDON_NAME .. "Options", UIParent)
Options.name = ADDON_NAME

local function BuildOptions()
    if Options._built then return end
    Options._built = true

    table.sort(registeredModules, function(a, b) return a.name < b.name end)

    local SIDEBAR_W = 155

    -- Sidebar: dark background strip on the left
    local sidebarBg = Options:CreateTexture(nil, "BACKGROUND")
    sidebarBg:SetColorTexture(0, 0, 0, 0.25)
    sidebarBg:SetPoint("TOPLEFT",    Options, "TOPLEFT",    0, 0)
    sidebarBg:SetPoint("BOTTOMLEFT", Options, "BOTTOMLEFT", 0, 0)
    sidebarBg:SetWidth(SIDEBAR_W)

    -- Vertical divider between sidebar and content
    local divider = Options:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT",    Options, "TOPLEFT",    SIDEBAR_W, 0)
    divider:SetPoint("BOTTOMLEFT", Options, "BOTTOMLEFT", SIDEBAR_W, 0)

    local navButtons    = {}
    local contentPanels = {}

    local function SelectModule(idx)
        for i = 1, #contentPanels do
            contentPanels[i]:SetShown(i == idx)
        end
        for i, btn in ipairs(navButtons) do
            if i == idx then
                btn:LockHighlight()
            else
                btn:UnlockHighlight()
            end
        end
    end

    -- Sidebar navigation buttons, one per module
    local navY = -10
    for i, module in ipairs(registeredModules) do
        local btn = CreateFrame("Button", ADDON_NAME .. "NavBtn" .. i, Options,
                                "UIPanelButtonTemplate")
        btn:SetPoint("TOPLEFT", Options, "TOPLEFT", 6, navY)
        btn:SetWidth(SIDEBAR_W - 12)
        btn:SetHeight(24)
        btn:SetText(module.name)
        local idx = i
        btn:SetScript("OnClick", function() SelectModule(idx) end)
        navButtons[i] = btn
        navY = navY - 28
    end

    -- Content panels: one per module, shown/hidden on nav selection
    for i, module in ipairs(registeredModules) do
        local panel = CreateFrame("Frame", nil, Options)
        panel:SetPoint("TOPLEFT",     Options, "TOPLEFT",     SIDEBAR_W + 10, 0)
        panel:SetPoint("BOTTOMRIGHT", Options, "BOTTOMRIGHT",             0,  0)

        local y = -16

        local header = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, y)
        header:SetText(module.name)
        y = y - 24

        local line = panel:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.4, 0.4, 0.4, 0.6)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT",  panel, "TOPLEFT",  16, y)
        line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, y)
        y = y - 14

        local ok, err = pcall(module.BuildConfig, panel, y)
        if not ok then
            print(ADDON_NAME .. ": config build failed for '" .. tostring(module.name) .. "': " .. tostring(err))
        end

        panel:Hide()
        contentPanels[i] = panel
    end

    SelectModule(1)
end

Options:SetScript("OnShow", BuildOptions)

ToggleConfig = function()
    if Settings and Settings.OpenToCategory then
        local id = OPTIONS_CATEGORY and (OPTIONS_CATEGORY.ID or (OPTIONS_CATEGORY.GetID and OPTIONS_CATEGORY:GetID()))
        Settings.OpenToCategory(id or Options.name)
        return
    end
    if InterfaceOptionsFrame_OpenToCategory then
        -- Calling twice is a long-standing quirk in the old Interface Options UI
        InterfaceOptionsFrame_OpenToCategory(Options)
        InterfaceOptionsFrame_OpenToCategory(Options)
        return
    end
    if InterfaceOptionsFrame and InterfaceOptionsFrame.Show then
        InterfaceOptionsFrame:Show()
    end
end

pcall(function()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        OPTIONS_CATEGORY = Settings.RegisterCanvasLayoutCategory(Options, Options.name)
        Settings.RegisterAddOnCategory(OPTIONS_CATEGORY)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(Options)
    end
end)

-- =========================================================
-- DB initialization
-- =========================================================

local coreFrame = CreateFrame("Frame")
coreFrame:RegisterEvent("ADDON_LOADED")
coreFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarAddonDB = ExsarAddonDB or {}
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- =========================================================
-- Slash commands
-- =========================================================

-- Temporary debug helper: /exsar debugframe
-- Inspects TargetFrame regions and shows results in a copyable popup.
-- Remove once the elite dragon texture info is captured.
local function DebugTargetFrameRegions()
    local lines = {}

    local function ScanRegions(parent, prefix)
        for i, r in ipairs({parent:GetRegions()}) do
            if r:GetObjectType() == "Texture" then
                local s1,s2,_,_,_,_,s7,s8 = r:GetTexCoord()
                local w, h = r:GetSize()
                local px, py
                local numPoints = r.GetNumPoints and r:GetNumPoints() or 0
                if numPoints > 0 then
                    local _, _, _, ox, oy = r:GetPoint(1)
                    px, py = ox, oy
                end
                lines[#lines + 1] = string.format(
                    "%s%d %s %s %.0fx%.0f tc(%.2f,%.2f,%.2f,%.2f) off(%s,%s)",
                    prefix, i,
                    r:IsShown() and "SHOWN" or "hidden",
                    tostring(r:GetTexture()),
                    w, h,
                    s1, s2, s7, s8,
                    tostring(px), tostring(py)
                )
            end
        end
        for i, c in ipairs({parent:GetChildren()}) do
            lines[#lines + 1] = string.format("%schild%d %s %s",
                prefix, i,
                c:GetName() or "(anon)",
                c:IsShown() and "SHOWN" or "hidden")
            ScanRegions(c, prefix .. "  ")
        end
    end

    ScanRegions(TargetFrame, "")

    ExsarUI.ShowCopyableText(table.concat(lines, "\n"),
        { title = "ExsarAddon — TargetFrame regions", width = 780, height = 360 })
end

SLASH_EXSAR1 = "/exsar"
SlashCmdList["EXSAR"] = function(msg)
    local cmd = msg:match("^(%S+)") or ""
    cmd = cmd:lower()

    if cmd == "config" then
        ToggleConfig()
    elseif cmd == "debugframe" then
        DebugTargetFrameRegions()
    elseif slashHandlers[cmd] then
        slashHandlers[cmd]()
    else
        print(ADDON_NAME .. ": /exsar config - Open configuration")
        for c in pairs(slashHandlers) do
            print("  /exsar " .. c)
        end
    end
end
