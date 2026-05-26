-- PetManagementWidget module
-- A compact, keybindable mini action bar of pet-management actions. Each slot is
-- a SecureActionButtonTemplate button driven by macrotext (type="macro"), so a
-- single button can carry a conditional smart-macro (e.g. Call/Revive/Dismiss).
--
-- Macro source model:
--   * PET_ACTIONS below holds the macrotext for each action. Macros are fully
--     addon-controlled -- there is no user override; whatever PET_ACTIONS
--     specifies is pushed onto the secure button (out of combat).
--
-- Each slot is keybindable via Blizzard's Key Bindings UI (see Bindings.xml,
-- EXSAR_PET_ACTION1..MAX_SLOTS) under the "ExsarAddon Pet" category; the bound
-- key is bridged to the secure button by ExsarUI.SetupKeybindBridge and shown
-- top-right of the icon. Keys live in Blizzard's binding set (no SavedVariables).
--
-- Settings stored under ExsarAddonDB.petManagement.

local ADDON_NAME = "ExsarAddon"

local pmDB = ExsarUI.MakeDB("petManagement")

-- =========================================================
-- Action definitions
-- =========================================================
-- The real actions/icons/macros are supplied here. Each entry:
--   key      = stable id for the action (handy if keyed lookups are ever needed)
--   name     = label (Key Bindings UI row + tooltip)
--   icon     = texture path or fileID (use one of icon/iconItem/iconSpell/dynamicIcon)
--   iconItem = item ID or name; the icon is resolved from the item via
--              GetItemInfo (with retry), like UsableItemsWidget
--   iconSpell= spell ID or name; the icon is resolved via GetSpellTexture
--              (with retry), avoiding hardcoded spell icon paths
--   dynamicIcon = pet-state-dependent icon: a map of state key (from
--              ExsarLogic.PetStateKey: "alive"/"dead"/"missing") to an icon spec
--              (a texture path string, or { spell = name } / { item = id|name }).
--              Re-resolved on each pet-state poll so the icon tracks pet state.
--   countItem= item ID or name; shows that item's bag count bottom-right of the
--              icon (omit for no count)
--   countCharges = if true, GetItemCount sums charges/uses across stacks rather
--              than counting items (like Drums of Battle in UsableItemsWidget)
--   cooldownItem = item ID or name; shows a cooldown sweep + countdown when that
--              item is on cooldown (resolved to an ID once, then read from bags
--              via C_Container.GetContainerItemCooldown — TBC has no GetItemCooldown)
--   gcd      = if true, the macro casts a GCD-triggering spell (Mend/Dismiss/Call
--              Pet), so show the global cooldown sweep while it would be blocked
--   macro    = the macrotext pushed onto the secure button (addon-controlled)
--   requires = optional pet-state token gating availability (see
--              ExsarLogic.PetActionEnabled): nil/"any", "active", "alive",
--              "dead", "missing", "notdead". Actions whose requirement isn't met
--              are greyed out (Dimmed effect); the click still fires but the
--              macro no-ops.
--
-- MAX_SLOTS must match the number of EXSAR_PET_ACTION bindings declared in
-- Bindings.xml — currently kept equal to the number of actions for a clean Key
-- Bindings menu. When adding actions, grow PET_ACTIONS, MAX_SLOTS, and the
-- Bindings.xml entries together.
local MAX_SLOTS = 5

local PET_ACTIONS = {
    -- "Do the right thing" pet button: heals a living pet, revives a dead one,
    -- or calls/revives when you have none. Never greyed (handles every state);
    -- the icon tracks state via dynamicIcon. See chat discussion for the macro.
    { key = "petaio", name = "Pet (All-in-One)",
      dynamicIcon = {
          alive   = { spell = "Mend Pet" },
          dead    = { spell = "Revive Pet" },
          missing = { spell = "Call Pet" },
      },
      gcd = true,
      macro = [[/use [@pet,nodead,exists] Mend Pet
/stopmacro [@pet,nodead,exists]
/use [@pet,dead,exists] Revive Pet
/stopmacro [@pet,exists]
/use [nopet] Call Pet]] },

    -- Send the pet in: Dash for the speed boost, then command the attack.
    -- Needs a living pet, so greyed when the pet is missing or dead.
    { key = "petdashattack", name = "Send Pet to Attack",
      icon = "Interface\\Icons\\Ability_GhoulFrenzy",  -- default pet-bar Attack icon
      macro = [[/cast Dash(Rank 3)
/petattack]],
      requires = "alive" },

    -- Recall the pet: Dash for speed, then passive stance to break off and
    -- return. Needs a living pet, so greyed when the pet is missing or dead.
    { key = "petrecall", name = "Pet Recall",
      icon = "Interface\\Icons\\Spell_Nature_Sleep",  -- default pet-bar Passive icon
      macro = [[/cast Dash(Rank 3)
/petpassive]],
      requires = "alive" },

    -- Dismiss the active pet. Channeled; requires a living pet (can't dismiss a
    -- dead or absent one), so greyed otherwise.
    { key = "dismisspet", name = "Dismiss Pet",
      iconSpell = "Dismiss Pet",
      macro = "/cast Dismiss Pet",
      gcd = true,
      requires = "alive" },

    -- The classic TBC hunter "save your pet" trick. Using the Steam Tonk
    -- Controller instantly puts your active pet away (no Dismiss Pet channel),
    -- so a living pet is yanked out of lethal damage (boss AoE / wipe) and comes
    -- back unharmed instead of dead. CASING MATTERS: the /cancelaura name must
    -- exactly match the buff ("Steam Tonk Controller") or you stay trapped in
    -- the tonk. Worked as THREE deliberate clicks, not a fast mash (mashing can
    -- leave you movement-locked): click 1 (have a living pet) uses the
    -- controller -> pet saved + you transform (the /cancelaura no-ops because the
    -- buff hasn't applied server-side yet, and Call Pet skips since you still
    -- have a pet); click 2 (now pet-less + still the tonk) drops the tonk via
    -- /cancelaura -- the Call Pet on the next line fails this press because the
    -- cancel hasn't resolved server-side yet, so you're still a tonk; click 3
    -- (untransformed, pet-less) finally fires Call Pet to resummon. The same
    -- round-trip latency that forces the cancel onto its own click also forces
    -- the resummon onto a third. Greyed when the pet is dead (requires="notdead"
    -- -- the trick can't help a corpse, and we don't tonk-dismiss a dead pet).
    -- Shows net Steam Tonk Controller charges in bags (countCharges sums charges
    -- across stacks, like Drums of Battle in UsableItemsWidget).
    { key = "steamtonk", name = "Steam Tonk",
      iconItem = "Steam Tonk Controller",
      countItem = "Steam Tonk Controller", countCharges = true,
      cooldownItem = "Steam Tonk Controller",
      gcd = true,  -- macro's Call Pet branch triggers the GCD
      macro = [[/use [@pet,exists,nodead] Steam Tonk Controller
/cancelaura Steam Tonk Controller
/use [nopet] Call Pet]],
      requires = "notdead" },
}

-- =========================================================
-- Layout constants
-- =========================================================

-- Matches the ConsumableBuffWidget bar (29 / 4 / 6) for visual consistency.
local ICON_SIZE = 29
local ICON_GAP  = 4
local PADDING   = 6

-- =========================================================
-- Main frame
-- =========================================================

local frame = CreateFrame("Frame", ADDON_NAME .. "PetManagementFrame", UIParent)
ExsarUI.SetupMovableFrame(frame, pmDB)

local placeholderText = ExsarUI.CreatePlaceholder(frame, "Pet")

frame:Hide()

-- =========================================================
-- Slot construction
-- =========================================================
-- Each icon is a SecureActionButtonTemplate button so the secure system can run
-- the macro on click. RegisterForClicks("AnyUp", "AnyDown") is required on TBC
-- Classic Anniversary (the modern client only fires SecureActionButton_OnClick
-- on down-events when ActionButtonUseKeyDown is set, the default).

local slots = {}

for i, action in ipairs(PET_ACTIONS) do
    local s = { action = action }

    s.btn = CreateFrame("Button", ADDON_NAME .. "PetActionBtn" .. i, frame,
                        "SecureActionButtonTemplate")
    s.btn:SetSize(ICON_SIZE, ICON_SIZE)
    s.btn:RegisterForClicks("AnyUp", "AnyDown")
    s.btn:SetAttribute("type", "macro")
    s.btn:SetAttribute("macrotext", action.macro)
    s.btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(action.name, 1, 1, 1)
        GameTooltip:AddLine(action.macro, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    s.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Plain black slot backing (no border highlight), matching ConsumableBuffWidget.
    local slotBg = s.btn:CreateTexture(nil, "BACKGROUND")
    slotBg:SetAllPoints()
    slotBg:SetColorTexture(0, 0, 0, 1.0)

    s.icon = ExsarUI.CreateIcon(s.btn)
    if action.icon then
        s.icon:SetTexture(action.icon)
    else
        -- Item-based icon; resolved by ResolveIcons (fallback shown until cached).
        s.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Cooldown sweep (mouse disabled so it doesn't block the secure click).
    s.cooldown = ExsarUI.CreateSweep(s.btn)
    s.cooldown:EnableMouse(false)
    -- Cooldown countdown (center).
    s.timeText = ExsarUI.CreateCountdownText(s.btn)

    -- Hotkey label (top-right; default-UI style). Driven by the keybind bridge.
    s.keyText = s.btn:CreateFontString(nil, "OVERLAY")
    s.keyText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    s.keyText:SetPoint("TOPRIGHT", s.btn, "TOPRIGHT", 1, -1)
    s.keyText:SetJustifyH("RIGHT")
    s.keyText:SetTextColor(0.9, 0.9, 0.9, 1)
    s.keyText:SetText("")

    -- Bag count / charges (bottom-right; empty unless the action defines countItem).
    s.countText = s.btn:CreateFontString(nil, "OVERLAY")
    s.countText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    s.countText:SetPoint("BOTTOMRIGHT", s.btn, "BOTTOMRIGHT", 1, 1)
    s.countText:SetTextColor(1, 1, 0.8, 1)
    s.countText:SetText("")

    slots[i] = s
end

-- =========================================================
-- Layout
-- =========================================================
-- Horizontal row of icons. Secure buttons must not be moved/hidden by
-- non-secure code during combat, so the whole pass is skipped under lockdown
-- and re-run on PLAYER_REGEN_ENABLED.

local function ApplyLayout()
    if InCombatLockdown() then return end

    local n = #slots
    if n == 0 then
        placeholderText:Show()
        frame:SetSize(ICON_SIZE + PADDING * 2, ICON_SIZE + PADDING * 2)
        frame:Show()
        return
    end

    for i, s in ipairs(slots) do
        s.btn:ClearAllPoints()
        s.btn:SetPoint("TOPLEFT", frame, "TOPLEFT",
            PADDING + (i - 1) * (ICON_SIZE + ICON_GAP), -PADDING)
        s.btn:Show()
    end

    placeholderText:Hide()
    frame:SetSize(PADDING * 2 + n * ICON_SIZE + (n - 1) * ICON_GAP,
                  ICON_SIZE + PADDING * 2)
    frame:Show()
end

-- =========================================================
-- Item-based icon resolution
-- =========================================================
-- Actions with iconItem load their texture from the item's data, which may not
-- be cached at load time; retried on GET_ITEM_INFO_RECEIVED / PLAYER_ENTERING_WORLD.

-- Resolve an icon spec to a texture: a string path, { spell = name }, or
-- { item = id|name }. Returns nil if not yet resolvable (e.g. uncached item).
local function ResolveIconSpec(spec)
    if type(spec) == "string" then return spec end
    if type(spec) == "table" then
        if spec.spell then return GetSpellTexture(spec.spell) end
        if spec.item  then return select(10, GetItemInfo(spec.item)) end
    end
    return nil
end

local function ResolveIcons()
    for _, s in ipairs(slots) do
        if not s.iconResolved then
            local tex
            if s.action.iconItem then
                tex = select(10, GetItemInfo(s.action.iconItem))
            elseif s.action.iconSpell then
                tex = GetSpellTexture(s.action.iconSpell)
            end
            if tex then
                s.icon:SetTexture(tex)
                s.iconResolved = true
            end
        end
    end
end

-- =========================================================
-- Bag count / charges
-- =========================================================
-- Shows the net count (or charges, if countCharges) of an action's countItem,
-- like the Drums of Battle charge display in UsableItemsWidget.

local function UpdateCounts()
    for _, s in ipairs(slots) do
        local item = s.action.countItem
        if item then
            local n = GetItemCount(item, false, s.action.countCharges and true or false)
            s.countText:SetText(tostring(n or 0))
        end
    end
end

-- =========================================================
-- Cooldown sweep (item cooldown + GCD)
-- =========================================================
-- Two sources feed each slot's sweep:
--   * Item cooldown (cooldownItem) — TBC has no GetItemCooldown, so it's read
--     from whichever bag slot holds the item via C_Container.GetContainerItemCooldown
--     (also reflects shared category cooldowns). Item name resolved to an ID once.
--   * GCD (gcd = true) — actions whose macro casts a GCD-triggering spell (Mend
--     Pet, Dismiss Pet, Call Pet) show the global cooldown so it's clear the cast
--     would be blocked. Probed with Wing Clip, which has no cooldown of its own,
--     so GetSpellCooldown returns only the GCD (same technique as GlobalCooldownTracker).
-- When both apply, the longer-remaining one wins. Only a real item cooldown shows
-- a countdown number; the brief GCD is sweep-only.

local FormatCooldown  = ExsarLogic.FormatCooldown
local GCD_PROBE_SPELL = "Wing Clip"

local function GetSlotCooldown(s)
    local item = s.action.cooldownItem
    if not item then return nil, nil end
    if not s.cooldownItemId then
        s.cooldownItemId = select(1, GetItemInfoInstant(item))
    end
    local itemId = s.cooldownItemId
    if not itemId then return nil, nil end
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if C_Container.GetContainerItemID(bag, slot) == itemId then
                return C_Container.GetContainerItemCooldown(bag, slot)
            end
        end
    end
    return nil, nil
end

local function UpdateCooldowns()
    local now = GetTime()
    -- GCD probe: Wing Clip has no CD of its own, so this is purely the GCD.
    local gcdStart, gcdDuration = GetSpellCooldown(GCD_PROBE_SPELL)
    local gcdActive = gcdStart and gcdStart > 0 and gcdDuration and gcdDuration > 0

    for _, s in ipairs(slots) do
        if s.action.cooldownItem or s.action.gcd then
            local start, duration, isRealCD

            -- Real item cooldown (CooldownState filters out GCD-length durations).
            if s.action.cooldownItem then
                local st, dur = GetSlotCooldown(s)
                if ExsarLogic.CooldownState(st, dur) == "cooldown" then
                    start, duration, isRealCD = st, dur, true
                end
            end

            -- GCD on GCD-affected actions, unless a longer real cooldown is up.
            if s.action.gcd and gcdActive then
                if not start or (gcdStart + gcdDuration) > (start + duration) then
                    start, duration, isRealCD = gcdStart, gcdDuration, false
                end
            end

            if start then
                s.cooldown:SetCooldown(start, duration)
                -- Countdown number only for real cooldowns, not the brief GCD.
                if isRealCD then
                    local remaining = (start + duration) - now
                    s.timeText:SetText(remaining > 0 and FormatCooldown(remaining) or "")
                else
                    s.timeText:SetText("")
                end
            else
                s.cooldown:SetCooldown(0, 0)
                s.timeText:SetText("")
            end
        end
    end
end

-- =========================================================
-- Availability (pet-state grey-out)
-- =========================================================
-- The widget always shows; actions whose pet-state requirement isn't met are
-- greyed out via the standard Dimmed effect. The secure click is left enabled
-- (the macro simply no-ops), so this is non-protected and safe in combat.

local function GetPetState()
    local exists = UnitExists("pet")
    return {
        exists = exists and true or false,
        alive  = (exists and not UnitIsDead("pet")) and true or false,
    }
end

local function UpdateAvailability()
    local state = GetPetState()
    local stateKey = ExsarLogic.PetStateKey(state)
    for _, s in ipairs(slots) do
        -- State-dependent icon (e.g. Mend / Revive / Call on the all-in-one button).
        if s.action.dynamicIcon then
            local tex = ResolveIconSpec(s.action.dynamicIcon[stateKey])
            if tex then s.icon:SetTexture(tex) end
        end
        -- Grey-out actions whose pet-state requirement isn't met.
        local enabled = ExsarLogic.PetActionEnabled(s.action.requires, state)
        s.icon:SetDesaturated(not enabled)
        s.icon:SetAlpha(enabled and 1.0 or 0.35)
    end
end

-- =========================================================
-- Macro application
-- =========================================================
-- Push current macrotext onto each secure button. SetAttribute is protected, so
-- this is skipped under combat lockdown and re-applied on PLAYER_REGEN_ENABLED.

local function ApplyMacros()
    if InCombatLockdown() then return end
    for _, s in ipairs(slots) do
        s.btn:SetAttribute("macrotext", s.action.macro)
    end
end

-- =========================================================
-- Polling: refresh grey-out as pet state changes (every 0.2s)
-- =========================================================

ExsarUI.CreatePoller(frame, 0.2, function()
    UpdateAvailability()
    UpdateCounts()
    UpdateCooldowns()
end)

-- =========================================================
-- Events
-- =========================================================

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("UNIT_PET")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("BAG_UPDATE")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        ExsarUI.RestorePosition(self, pmDB, 200, -200)
        ApplyLayout()
        ApplyMacros()
        ResolveIcons()
        UpdateAvailability()
        UpdateCounts()
        UpdateCooldowns()
    elseif event == "PLAYER_ENTERING_WORLD" then
        ApplyLayout()
        ApplyMacros()
        ResolveIcons()
        UpdateAvailability()
        UpdateCounts()
        UpdateCooldowns()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Re-apply protected ops deferred while in combat.
        ApplyLayout()
        ApplyMacros()
    elseif event == "UNIT_PET" and arg1 == "player" then
        UpdateAvailability()
    elseif event == "BAG_UPDATE" then
        UpdateCounts()
    elseif event == "BAG_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
        UpdateCooldowns()
    elseif event == "GET_ITEM_INFO_RECEIVED" or event == "SPELLS_CHANGED" then
        ResolveIcons()
    end
end)

-- =========================================================
-- Slash sub-commands
-- =========================================================

ExsarUI.AddSlashReset("petmgmtreset", frame, pmDB, "Pet management widget", 200, -200)

-- =========================================================
-- Keybindings
-- =========================================================
-- Named bindings EXSAR_PET_ACTION1..MAX_SLOTS (Bindings.xml, "ExsarAddon Pet"
-- category). Labels resolve via the BINDING_NAME_EXSAR_PET_ACTIONn globals set
-- below; defined-action slots use the action name, surplus slots a generic
-- label. SetupKeybindBridge reads the assigned key, bridges it to the secure
-- button (works in combat via the override layer), and drives the on-icon label.

BINDING_HEADER_EXSARADDONPET = "ExsarAddon Pet"
for i = 1, MAX_SLOTS do
    local act = PET_ACTIONS[i]
    _G["BINDING_NAME_EXSAR_PET_ACTION" .. i] = act and act.name or ("Pet Action " .. i)
end

local function UpdateHotkeyLabel(index, key)
    local s = slots[index]
    if not s then return end
    s.keyText:SetText(ExsarLogic.AbbreviateBindingKey(key) or "")
end

ExsarUI.SetupKeybindBridge({
    owner         = frame,
    bindingPrefix = "EXSAR_PET_ACTION",
    buttonPrefix  = ADDON_NAME .. "PetActionBtn",
    count         = #slots,
    onSlotKey     = UpdateHotkeyLabel,
})

-- =========================================================
-- Register with Core
-- =========================================================

ExsarAddon.RegisterModule({
    name = "Pet Management",
    BuildConfig = function(parent, y)
        y = ExsarUI.AddScaleSlider(parent, y, pmDB, frame)

        y = ExsarUI.AddLockCheckbox(parent, y, pmDB, frame, function()
            ApplyLayout()
        end)

        y = ExsarUI.AddResetButton(parent, y, pmDB, frame, "Pet management", 200, -200)

        return y
    end,
})
