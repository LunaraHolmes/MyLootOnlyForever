local ADDON_NAME = ...

local DEFAULTS = {
    enabled = true,
    hideOtherLoot = true,
    minOtherLootQuality = 6,
    hideOtherCrafting = true,
    hideOtherRolls = false,
}

local HEX_TO_QUALITY = {
    ff9d9d9d = 0,
    ffffffff = 1,
    ff1eff00 = 2,
    ff0070dd = 3,
    ffa335ee = 4,
    ffff8000 = 5,
    ffe6cc80 = 6,
    ff00ccff = 7,
}

local function GetLootLinkQuality(msg)
    local hex, itemLink = msg:match("|c(%x%x%x%x%x%x%x%x)(|Hitem:.-|h.-|h)|r")
    if not itemLink then
        return nil
    end

    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if getItemInfo then
        local _, _, quality = getItemInfo(itemLink)
        if type(quality) == "number" then
            return quality
        end
    end

    if hex then
        return HEX_TO_QUALITY[hex:lower()]
    end

    return nil
end

local function GlobalStringToPattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
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
            local minQuality = MyLootOnlyForeverDB.minOtherLootQuality or 6
            if minQuality <= 5 then
                local quality = GetLootLinkQuality(msg)
                if quality and quality >= minQuality then
                    return false
                end
            end
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
    AddCheckbox("hideOtherLoot", "Hide Other Players' Loot", "Hides other players' loot lines while keeping your own.")

    if Settings.CreateDropdown and Settings.CreateControlTextContainer then
        pcall(function()
            local qualitySetting = Settings.RegisterAddOnSetting(
                category,
                "MLOF_minOtherLootQuality",
                "minOtherLootQuality",
                MyLootOnlyForeverDB,
                Settings.VarType.Number,
                "Other Players' Loot Quality Threshold",
                DEFAULTS.minOtherLootQuality
            )

            local function GetQualityOptions()
                local container = Settings.CreateControlTextContainer()
                container:Add(6, "Hide All Other Loot")
                container:Add(2, "Uncommon (Green) & Above")
                container:Add(3, "Rare (Blue) & Above")
                container:Add(4, "Epic (Purple) & Above")
                container:Add(5, "Legendary (Orange) & Above")
                return container:GetData()
            end

            Settings.CreateDropdown(
                category,
                qualitySetting,
                GetQualityOptions,
                "Choose the minimum item quality to allow through when Hide Other Players' Loot is enabled."
            )
        end)
    end

    AddCheckbox("hideOtherCrafting", "Hide Other Players' Crafting", "Hides other players' crafting lines while keeping your own.")
    AddCheckbox("hideOtherRolls", "Hide Other Players' Loot Rolls", "Hides Need, Greed, Pass, and roll winner lines for other players.")

    Settings.RegisterAddOnCategory(category)
end

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

local function GetQualityLabel(q)
    if q == 2 then return "|cff1eff00Uncommon (Green) & Above|r"
    elseif q == 3 then return "|cff0070ddRare (Blue) & Above|r"
    elseif q == 4 then return "|cffa335eeEpic (Purple) & Above|r"
    elseif q == 5 then return "|cffff8000Legendary (Orange) & Above|r"
    else return "|cffff4444Hide All|r" end
end

local function ParseQualityArg(arg)
    if arg == "all" or arg == "hide" or arg == "none" then return 6
    elseif arg == "uncommon" or arg == "green" or arg == "2" then return 2
    elseif arg == "rare" or arg == "blue" or arg == "3" then return 3
    elseif arg == "epic" or arg == "purple" or arg == "4" then return 4
    elseif arg == "legendary" or arg == "orange" or arg == "5" then return 5
    else return nil end
end

local function PrintStatus(label, state)
    local color = state and "|cff00ff00ON|r" or "|cffff4444OFF|r"
    print("|cff33ff99(MyLootOnlyForever)|r " .. label .. ": " .. color)
end

SLASH_MYLOOTONLYFOREVER1 = "/mlo"
SLASH_MYLOOTONLYFOREVER2 = "/mylootonly"
SlashCmdList.MYLOOTONLYFOREVER = function(input)
    local cmd, arg = (input or ""):lower():trim():match("^(%S+)%s*(.*)$")
    cmd = cmd or ""

    if cmd == "" or cmd == "options" or cmd == "config" then
        if settingsCategoryID and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(settingsCategoryID)
        else
            print("|cff33ff99(MyLootOnlyForever)|r Commands: /mlo toggle, /mlo loot, /mlo quality, /mlo craft, /mlo rolls, /mlo status")
        end
    elseif cmd == "toggle" then
        MyLootOnlyForeverDB.enabled = not MyLootOnlyForeverDB.enabled
        PrintStatus("Addon enabled", MyLootOnlyForeverDB.enabled)
    elseif cmd == "loot" then
        MyLootOnlyForeverDB.hideOtherLoot = not MyLootOnlyForeverDB.hideOtherLoot
        PrintStatus("Hide other players' loot", MyLootOnlyForeverDB.hideOtherLoot)
    elseif cmd == "quality" or cmd == "rarity" then
        local q = ParseQualityArg(arg)
        if q then
            MyLootOnlyForeverDB.minOtherLootQuality = q
            print("|cff33ff99(MyLootOnlyForever)|r Other loot threshold: " .. GetQualityLabel(q))
        else
            print("|cff33ff99(MyLootOnlyForever)|r Usage: /mlo quality all | uncommon | rare | epic | legendary")
        end
    elseif cmd == "craft" or cmd == "crafting" then
        MyLootOnlyForeverDB.hideOtherCrafting = not MyLootOnlyForeverDB.hideOtherCrafting
        PrintStatus("Hide other players' crafting", MyLootOnlyForeverDB.hideOtherCrafting)
    elseif cmd == "rolls" or cmd == "roll" then
        MyLootOnlyForeverDB.hideOtherRolls = not MyLootOnlyForeverDB.hideOtherRolls
        PrintStatus("Hide other players' rolls", MyLootOnlyForeverDB.hideOtherRolls)
    elseif cmd == "status" then
        PrintStatus("Addon enabled", MyLootOnlyForeverDB.enabled)
        PrintStatus("Hide other loot", MyLootOnlyForeverDB.hideOtherLoot)
        print("|cff33ff99(MyLootOnlyForever)|r Other loot threshold: " .. GetQualityLabel(MyLootOnlyForeverDB.minOtherLootQuality))
        PrintStatus("Hide other crafting", MyLootOnlyForeverDB.hideOtherCrafting)
        PrintStatus("Hide other rolls", MyLootOnlyForeverDB.hideOtherRolls)
    else
        print("|cff33ff99(MyLootOnlyForever)|r Usage: /mlo, /mlo toggle, /mlo loot, /mlo quality, /mlo craft, /mlo rolls, /mlo status")
    end
end
