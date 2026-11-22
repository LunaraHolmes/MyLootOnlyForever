local ADDON_NAME = ...

-- Default settings for new users
local DEFAULTS = {
    enabled = true,
    hideOtherLoot = true,
    hideOtherCrafting = true,
    hideOtherRolls = false,
}

-- Convert a Blizzard GlobalString (e.g. "%s receives loot: %s.") into a Lua pattern
local function GlobalStringToPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    -- Escape Lua magic characters, then replace format tokens (%s, %d, %1$s, etc.)
    local pattern = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    pattern = pattern:gsub("%%%%%d*%$?[sd]", ".+")
    return "^" .. pattern .. "$"
end

local function BuildPatterns(globalNames, fallbackLiterals)
    local compiled = {}
    for _, name in ipairs(globalNames) do
        local pat = GlobalStringToPattern(_G[name])
        if pat then
            table.insert(compiled, { pattern = pat, plain = false })
        end
    end
    for _, lit in ipairs(fallbackLiterals) do
        table.insert(compiled, { pattern = lit, plain = true })
    end
    return compiled
end

-- Localized patterns built automatically from WoW's built-in GlobalStrings
local LOOT_PATTERNS = BuildPatterns({
    "LOOT_ITEM",
    "LOOT_ITEM_MULTIPLE",
    "LOOT_ITEM_PUSHED",
    "LOOT_ITEM_PUSHED_MULTIPLE",
    "LOOT_ITEM_BONUS_ROLL",
    "LOOT_ITEM_BONUS_ROLL_MULTIPLE",
}, { "receives loot:" })

local CRAFT_PATTERNS = BuildPatterns({
    "CREATED_ITEM",
    "CREATED_ITEM_MULTIPLE",
}, { " creates ", " creates:" })

local SELF_ROLL_PATTERNS = BuildPatterns({
    "LOOT_ROLL_YOU_WON",
    "LOOT_ROLL_YOU_WON_NO_SPAM_NEED",
    "LOOT_ROLL_YOU_WON_NO_SPAM_GREED",
    "LOOT_ROLL_YOU_WON_NO_SPAM_DE",
    "LOOT_ROLL_PASSED_SELF",
    "LOOT_ROLL_PASSED_SELF_AUTO",
    "LOOT_ROLL_GREED_SELF",
    "LOOT_ROLL_NEED_SELF",
    "LOOT_ROLL_DISENCHANT_SELF",
    "LOOT_ROLL_ROLLED_NEED_SELF",
    "LOOT_ROLL_ROLLED_GREED_SELF",
    "LOOT_ROLL_ROLLED_DE_SELF",
}, { "You rolled", "You passed", "You have selected", "You won:" })

local OTHER_ROLL_PATTERNS = BuildPatterns({
    "LOOT_ROLL_WON",
    "LOOT_ROLL_WON_NO_SPAM_NEED",
    "LOOT_ROLL_WON_NO_SPAM_GREED",
    "LOOT_ROLL_WON_NO_SPAM_DE",
    "LOOT_ROLL_PASSED",
    "LOOT_ROLL_PASSED_AUTO",
    "LOOT_ROLL_GREED",
    "LOOT_ROLL_NEED",
    "LOOT_ROLL_DISENCHANT",
    "LOOT_ROLL_ROLLED_NEED",
    "LOOT_ROLL_ROLLED_GREED",
    "LOOT_ROLL_ROLLED_DE",
}, { "Roll - ", "passed on:", "has selected Greed", "has selected Need", "has selected Disenchant", " won:" })

local function MatchesAny(msg, list)
    for _, entry in ipairs(list) do
        if msg:find(entry.pattern, 1, entry.plain) then
            return true
        end
    end
    return false
end

-- Helper to match messages safely (handles 12.0+ secret values)
local function ShouldFilterMessage(msg)
    if not MyLootOnlyForeverDB or not MyLootOnlyForeverDB.enabled then
        return false
    end
    if type(msg) ~= "string" then
        return false
    end
    if issecretvalue and issecretvalue(msg) then
        return false
    end

    local ok, result = pcall(function()
        if MyLootOnlyForeverDB.hideOtherLoot and MatchesAny(msg, LOOT_PATTERNS) then
            return true
        end
        if MyLootOnlyForeverDB.hideOtherCrafting and MatchesAny(msg, CRAFT_PATTERNS) then
            return true
        end
        if MyLootOnlyForeverDB.hideOtherRolls then
            if not MatchesAny(msg, SELF_ROLL_PATTERNS) and MatchesAny(msg, OTHER_ROLL_PATTERNS) then
                return true
            end
        end
        return false
    end)

    return ok and result or false
end

-- Register chat event filters
local CHAT_EVENTS = {
    "CHAT_MSG_LOOT",
    "CHAT_MSG_TRADESKILLS",
    "CHAT_MSG_OPENING",
    "CHAT_MSG_SYSTEM",
    "CHAT_MSG_SKILL",
}

for _, event in ipairs(CHAT_EVENTS) do
    ChatFrame_AddMessageEventFilter(event, function(self, ev, msg, ...)
        return ShouldFilterMessage(msg)
    end)
end

-- Build the native Options > AddOns settings panel
local settingsCategoryID

local function RegisterSettingsPanel()
    if not Settings or not Settings.RegisterVerticalLayoutCategory then
        return
    end

    local category = Settings.RegisterVerticalLayoutCategory("MyLootOnlyForever")
    settingsCategoryID = category:GetID()

    local function AddCheckbox(key, label, tooltip)
        local setting = Settings.RegisterAddOnSetting(
            category,
            "MLOF_" .. key,
            key,
            MyLootOnlyForeverDB,
            Settings.VarType.Boolean,
            label,
            DEFAULTS[key]
        )
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    AddCheckbox("enabled", "Enable Addon", "Master toggle to turn MyLootOnlyForever filtering on or off.")
    AddCheckbox("hideOtherLoot", "Hide Other Players' Loot", "Hides '[Player] receives loot:' messages while keeping your own 'You receive loot:' lines.")
    AddCheckbox("hideOtherCrafting", "Hide Other Players' Crafting", "Hides '[Player] creates ...' messages while keeping your own 'You create ...' lines.")
    AddCheckbox("hideOtherRolls", "Hide Other Players' Loot Rolls", "Hides Need, Greed, Pass, and roll winner lines for other players.")

    Settings.RegisterAddOnCategory(category)
end

-- Initialize SavedVariables on login
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon ~= ADDON_NAME then return end

    MyLootOnlyForeverDB = MyLootOnlyForeverDB or {}
    for k, v in pairs(DEFAULTS) do
        if MyLootOnlyForeverDB[k] == nil then
            MyLootOnlyForeverDB[k] = v
        end
    end

    RegisterSettingsPanel()
    self:UnregisterEvent("ADDON_LOADED")
end)

-- Slash commands (/mlo and /mylootonly)
local function PrintStatus(label, state)
    local color = state and "|cff00ff00ON|r" or "|cffff4444OFF|r"
    print("|cff33ff99[MyLootOnlyForever]|r " .. label .. ": " .. color)
end

SLASH_MYLOOTONLYFOREVER1 = "/mlo"
SLASH_MYLOOTONLYFOREVER2 = "/mylootonly"
SlashCmdList["MYLOOTONLYFOREVER"] = function(input)
    local cmd = (input or ""):lower():trim()

    if cmd == "" or cmd == "options" or cmd == "config" then
        if settingsCategoryID and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(settingsCategoryID)
        else
            print("|cff33ff99[MyLootOnlyForever]|r Commands: /mlo toggle, /mlo loot, /mlo craft, /mlo rolls, /mlo status")
        end
    elseif cmd == "toggle" then
        MyLootOnlyForeverDB.enabled = not MyLootOnlyForeverDB.enabled
        PrintStatus("Addon enabled", MyLootOnlyForeverDB.enabled)
    elseif cmd == "loot" then
        MyLootOnlyForeverDB.hideOtherLoot = not MyLootOnlyForeverDB.hideOtherLoot
        PrintStatus("Hide other players' loot", MyLootOnlyForeverDB.hideOtherLoot)
    elseif cmd == "craft" or cmd == "crafting" then
        MyLootOnlyForeverDB.hideOtherCrafting = not MyLootOnlyForeverDB.hideOtherCrafting
        PrintStatus("Hide other players' crafting", MyLootOnlyForeverDB.hideOtherCrafting)
    elseif cmd == "rolls" or cmd == "roll" then
        MyLootOnlyForeverDB.hideOtherRolls = not MyLootOnlyForeverDB.hideOtherRolls
        PrintStatus("Hide other players' rolls", MyLootOnlyForeverDB.hideOtherRolls)
    elseif cmd == "status" then
        PrintStatus("Addon enabled", MyLootOnlyForeverDB.enabled)
        PrintStatus("Hide other loot", MyLootOnlyForeverDB.hideOtherLoot)
        PrintStatus("Hide other crafting", MyLootOnlyForeverDB.hideOtherCrafting)
        PrintStatus("Hide other rolls", MyLootOnlyForeverDB.hideOtherRolls)
    else
        print("|cff33ff99[MyLootOnlyForever]|r Usage: /mlo (opens settings), /mlo toggle, /mlo loot, /mlo craft, /mlo rolls, /mlo status")
    end
end