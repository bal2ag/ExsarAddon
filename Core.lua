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
    if sText then sText:SetText(label) end
    if sLow  then sLow:SetText(tostring(minV)) end
    if sHigh then sHigh:SetText(tostring(maxV)) end

    s._ignore = true
    s:SetValue(getter())
    s._ignore = false

    s:SetScript("OnShow", function(self)
        self._ignore = true
        self:SetValue(getter())
        self._ignore = false
    end)
    s:SetScript("OnValueChanged", function(self, v)
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

    -- Scroll container so the panel works in both old and new Settings UI
    local scroll = CreateFrame("ScrollFrame", ADDON_NAME .. "OptionsScroll", Options, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     Options, "TOPLEFT",     0,   0)
    scroll:SetPoint("BOTTOMRIGHT", Options, "BOTTOMRIGHT", -30, 0)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local sb = self.ScrollBar or _G[self:GetName() .. "ScrollBar"]
        if not sb then return end
        local minv, maxv = sb:GetMinMaxValues()
        local cur = self:GetVerticalScroll() or 0
        if delta < 0 then
            self:SetVerticalScroll(math.min(cur + 40, maxv))
        else
            self:SetVerticalScroll(math.max(cur - 40, minv))
        end
    end)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    Options:SetScript("OnSizeChanged", function()
        local w = Options:GetWidth() or 0
        if w > 0 then content:SetWidth(math.max(400, w - 45)) end
    end)

    local y = -16

    for _, module in ipairs(registeredModules) do
        -- Section header
        local header = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", content, "TOPLEFT", 16, y)
        header:SetText(module.name)
        y = y - 24

        local line = content:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(0.4, 0.4, 0.4, 0.6)
        line:SetHeight(1)
        line:SetPoint("TOPLEFT",  content, "TOPLEFT",  16,  y)
        line:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, y)
        y = y - 14

        -- Module builds its own widgets and returns the final Y
        y = module.BuildConfig(content, y)
        y = y - 24  -- gap between sections
    end

    content:SetHeight(math.abs(y) + 30)
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

SLASH_EXSAR1 = "/exsar"
SlashCmdList["EXSAR"] = function(msg)
    local cmd = msg:match("^(%S+)") or ""
    cmd = cmd:lower()

    if cmd == "config" then
        ToggleConfig()
    elseif slashHandlers[cmd] then
        slashHandlers[cmd]()
    else
        print(ADDON_NAME .. ": /exsar config - Open configuration")
        for c in pairs(slashHandlers) do
            print("  /exsar " .. c)
        end
    end
end
