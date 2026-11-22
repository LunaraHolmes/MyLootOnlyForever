local ADDON_NAME = ...

local DEFAULTS = {
    enabled = true,
    hideOtherLoot = true,
    minOtherLootQuality = 6,
    hideOtherCrafting = true,
    hideOtherRolls = false,
    lootWhitelist = {},
    allowGuildLootCrafting = false,
    allowFriendLootCrafting = false,
    allowGroupLoot = false,
    showSpecialMounts = false,
    showSpecialPets = false,
    showSpecialToys = false,
    showSpecialRecipes = false,
}

local ActiveDB

local function GetAddonVersion()
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version"))
        or (GetAddOnMetadata and GetAddOnMetadata(ADDON_NAME, "Version"))
    return version or "Unknown"
end

local function SanitizeSettings(settings)
    if type(settings) ~= "table" then settings = {} end

    for key, defaultValue in pairs(DEFAULTS) do
        if type(settings[key]) ~= type(defaultValue) then
            settings[key] = type(defaultValue) == "table" and {} or defaultValue
        elseif key == "minOtherLootQuality" then
            local quality = settings[key]
            if quality ~= 2 and quality ~= 3 and quality ~= 4 and quality ~= 5 and quality ~= 6 then
                settings[key] = defaultValue
            end
        end
    end

    local safeWhitelist = {}
    for name, enabled in pairs(settings.lootWhitelist) do
        if type(name) == "string" and enabled == true and #name <= 64 and not name:find("[%c|]") then
            name = name:match("^%s*(.-)%s*$")
            if name ~= "" then safeWhitelist[name] = true end
        end
    end
    settings.lootWhitelist = safeWhitelist
    return settings
end

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

local function GetLootItemID(msg)
    local itemID = msg:match("|Hitem:(%d+)")
    return itemID and tonumber(itemID)
end

local function IsSpecialLootItem(msg)
    local wantsMount = ActiveDB.showSpecialMounts
    local wantsPet = ActiveDB.showSpecialPets
    local wantsToy = ActiveDB.showSpecialToys
    local wantsRecipe = ActiveDB.showSpecialRecipes
    if not (wantsMount or wantsPet or wantsToy or wantsRecipe) then return false end

    local itemID = GetLootItemID(msg)
    if not itemID then return false end

    if wantsToy and C_ToyBox and C_ToyBox.GetToyInfo then
        local ok, toyInfo = pcall(C_ToyBox.GetToyInfo, itemID)
        if ok and toyInfo then return true end
    end

    if wantsPet and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local ok, petName = pcall(C_PetJournal.GetPetInfoByItemID, itemID)
        if ok and petName then return true end
    end

    local getItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not getItemInfoInstant then return false end
    local ok, _itemID, _itemType, _itemSubType, _itemEquipLoc, _icon, classID, subclassID = pcall(getItemInfoInstant, itemID)
    if not ok then return false end

    local itemClass = Enum and Enum.ItemClass or {}
    local miscSubclass = Enum and Enum.ItemMiscellaneousSubclass or {}
    local miscellaneousClassID = itemClass.Miscellaneous or 15

    if wantsRecipe and classID == (itemClass.Recipe or 9) then return true end
    if classID == miscellaneousClassID then
        if wantsMount and subclassID == (miscSubclass.Mount or 5) then return true end
        if wantsPet and subclassID == (miscSubclass.CompanionPet or 2) then return true end
        if wantsToy and miscSubclass.Toy and subclassID == miscSubclass.Toy then return true end
    end

    return false
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

local function BuildLootPlayerPatterns()
    local compiled = {}
    for _, name in ipairs({
        "LOOT_ITEM", "LOOT_ITEM_MULTIPLE", "LOOT_ITEM_PUSHED",
        "LOOT_ITEM_PUSHED_MULTIPLE", "LOOT_ITEM_BONUS_ROLL",
        "LOOT_ITEM_BONUS_ROLL_MULTIPLE",
    }) do
        local fmt = _G[name]
        if type(fmt) == "string" and fmt ~= "" then
            local pattern = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            local captured = false
            pattern = pattern:gsub("%%%%%d*%$?[sd]", function()
                if not captured then captured = true; return "(.+)" end
                return ".+"
            end)
            if captured then table.insert(compiled, "^" .. pattern .. "$") end
        end
    end
    table.insert(compiled, "^(.+) receives loot:")
    return compiled
end

local LOOT_PLAYER_PATTERNS = BuildLootPlayerPatterns()

local function BuildMessagePlayerPatterns(globalNames, fallback)
    local compiled = {}
    for _, name in ipairs(globalNames) do
        local fmt = _G[name]
        if type(fmt) == "string" and fmt ~= "" then
            local pattern = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            local captured = false
            pattern = pattern:gsub("%%%%%d*%$?[sd]", function()
                if not captured then captured = true; return "(.+)" end
                return ".+"
            end)
            if captured then table.insert(compiled, "^" .. pattern .. "$") end
        end
    end
    table.insert(compiled, fallback)
    return compiled
end

local CRAFT_PLAYER_PATTERNS = BuildMessagePlayerPatterns({ "CREATED_ITEM", "CREATED_ITEM_MULTIPLE" }, "^(.+) creates[: ]")

local function GetLootPlayer(msg)
    for _, pattern in ipairs(LOOT_PLAYER_PATTERNS) do
        local player = msg:match(pattern)
        if player then return player end
    end
end

local function NormalizePlayerIdentity(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    return name:gsub("%s+", " "):lower()
end

local function SamePlayerName(firstName, secondName)
    local first = NormalizePlayerIdentity(firstName)
    local second = NormalizePlayerIdentity(secondName)
    return first ~= nil and first ~= "" and first == second
end

local function IsLootWhitelisted(msg)
    local player = GetLootPlayer(msg)
    if not player then return false end
    for name in pairs(ActiveDB.lootWhitelist or {}) do
        if SamePlayerName(player, name) then return true end
    end
    return false
end

local function GetMessagePlayer(msg, isLoot)
    local patterns = isLoot and LOOT_PLAYER_PATTERNS or CRAFT_PLAYER_PATTERNS
    for _, pattern in ipairs(patterns) do
        local player = msg:match(pattern)
        if player then return player end
    end
end

local function IsPartyOrRaidMember(player)
    if not player or not IsInGroup or not IsInGroup() then return false end
    if IsInRaid and IsInRaid() and GetRaidRosterInfo and GetNumGroupMembers then
        for index = 1, GetNumGroupMembers() do
            local name = GetUnitName and GetUnitName("raid" .. index)
            if not name then name = GetRaidRosterInfo(index) end
            if SamePlayerName(player, name) then return true end
        end
    elseif GetNumSubgroupMembers and UnitName then
        for index = 1, GetNumSubgroupMembers() do
            local unit = "party" .. index
            local name = GetUnitName and GetUnitName(unit)
            if not name then
                local firstName, surname = UnitName(unit)
                name = firstName
                if firstName and surname and surname ~= "" then name = firstName .. " " .. surname end
            end
            if SamePlayerName(player, name) then return true end
        end
    end
    return false
end

local function IsGuildmate(player)
    if not player or not IsInGuild or not IsInGuild() then return false end
    local count = GetNumGuildMembers and GetNumGuildMembers()
    if not count or not GetGuildRosterInfo then return false end
    for index = 1, count do
        local name = GetGuildRosterInfo(index)
        if SamePlayerName(player, name) then return true end
    end
    return false
end

local function IsCharacterFriend(player)
    if not player then return false end
    if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
        for index = 1, C_FriendList.GetNumFriends() do
            local info = C_FriendList.GetFriendInfoByIndex(index)
            if info and SamePlayerName(player, info.name) then return true end
        end
    elseif GetNumFriends and GetFriendInfo then
        for index = 1, GetNumFriends() do
            local name = GetFriendInfo(index)
            if SamePlayerName(player, name) then return true end
        end
    end
    return false
end

local function IsBattleNetWoWFriend(player)
    if not player then return false end
    if C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendGameAccountInfo and C_BattleNet.GetFriendNumGameAccounts then
        local count = C_BattleNet.GetFriendCount and C_BattleNet.GetFriendCount()
            or (BNGetNumFriends and BNGetNumFriends()) or 0
        for friendIndex = 1, count do
            local account = C_BattleNet.GetFriendAccountInfo(friendIndex)
            local gameCount = C_BattleNet.GetFriendNumGameAccounts(friendIndex) or 0
            for gameIndex = 1, gameCount do
                local game = C_BattleNet.GetFriendGameAccountInfo(friendIndex, gameIndex)
                if game and game.characterName and SamePlayerName(player, game.characterName) then return true end
            end
            if account and account.gameAccountInfo and account.gameAccountInfo.characterName
                and SamePlayerName(player, account.gameAccountInfo.characterName) then return true end
        end
    elseif BNGetNumFriends and BNGetFriendInfo and BNGetNumFriendGameAccounts and BNGetFriendGameAccountInfo then
        for friendIndex = 1, BNGetNumFriends() do
            local presenceID = BNGetFriendInfo(friendIndex)
            if presenceID then
                for gameIndex = 1, BNGetNumFriendGameAccounts(presenceID) do
                    local _, _, characterName = BNGetFriendGameAccountInfo(presenceID, gameIndex)
                    if SamePlayerName(player, characterName) then return true end
                end
            end
        end
    end
    return false
end

local function IsSocialLootCraftException(msg, isLoot)
    local player = GetMessagePlayer(msg, isLoot)
    if not player then return false end
    if ActiveDB.allowGuildLootCrafting and IsGuildmate(player) then return true end
    if ActiveDB.allowFriendLootCrafting
        and (IsCharacterFriend(player) or IsBattleNetWoWFriend(player)) then return true end
    return false
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
    if not ActiveDB or not ActiveDB.enabled then
        return false
    end
    if type(msg) ~= "string" then
        return false
    end
    if issecretvalue and issecretvalue(msg) then
        return false
    end

    local ok, result = pcall(function()
        if ActiveDB.hideOtherLoot and MatchesAny(msg, LOOT_PATTERNS) then
            if IsLootWhitelisted(msg)
                or (ActiveDB.allowGroupLoot and IsPartyOrRaidMember(GetMessagePlayer(msg, true)))
                or IsSocialLootCraftException(msg, true)
                or IsSpecialLootItem(msg) then return false end
            local minQuality = ActiveDB.minOtherLootQuality or 6
            if minQuality <= 5 then
                local quality = GetLootLinkQuality(msg)
                if quality and quality >= minQuality then
                    return false
                end
            end
            return true
        end

        if ActiveDB.hideOtherCrafting and MatchesAny(msg, CRAFT_PATTERNS) then
            if IsSocialLootCraftException(msg, false) then return false end
            return true
        end

        if ActiveDB.hideOtherRolls then
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
local legacySettingsPanel
local customOptionsFrame
local OpenCustomOptions

local function RegisterSettingsPanel()
    if not OpenCustomOptions then return false end
    OpenCustomOptions(false)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(customOptionsFrame, "MyLootOnlyForever")
        settingsCategoryID = category:GetID()
        Settings.RegisterAddOnCategory(category)
        return true
    end
    return false
end

local function RegisterLegacySettingsPanel()
    if not InterfaceOptions_AddCategory then return false end
    if not OpenCustomOptions then return false end
    OpenCustomOptions(false)
    legacySettingsPanel = customOptionsFrame
    legacySettingsPanel.name = "MyLootOnlyForever"
    InterfaceOptions_AddCategory(legacySettingsPanel)
    return true
end

local function GetCharacterGameMode()
    if not C_GameRules or not C_GameRules.IsGameRuleActive or not Enum or not Enum.GameRule then
        return "Unknown"
    end

    local function IsActive(ruleName)
        local rule = Enum.GameRule[ruleName]
        if rule == nil then return false end
        local ok, active = pcall(C_GameRules.IsGameRuleActive, rule)
        return ok and active == true
    end

    local isHardcore = IsActive("HardcoreRuleset")
    local isRoleplay = IsActive("RPRuleset")
    local isPvP = IsActive("PvPRuleset")
    if isHardcore then return "Hardcore" end
    if isRoleplay and isPvP then return "Roleplay-PvP" end
    if isRoleplay then return "Roleplay" end
    if isPvP then return "PvP" end
    return "Normal"
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon ~= ADDON_NAME then return end

    if type(MyLootOnlyForeverDB) ~= "table" then MyLootOnlyForeverDB = {} end
    if type(MyLootOnlyForeverProfiles) ~= "table" then MyLootOnlyForeverProfiles = {} end
    if type(MyLootOnlyForeverProfiles.characters) ~= "table" then
        MyLootOnlyForeverProfiles.characters = {}
    end
    for key, savedProfile in pairs(MyLootOnlyForeverProfiles.characters) do
        if type(key) ~= "string" or type(savedProfile) ~= "table" then
            MyLootOnlyForeverProfiles.characters[key] = nil
        elseif type(savedProfile.settings) ~= "table" then
            savedProfile.settings = {}
        end
    end

    local characterName, surname
    if UnitName then characterName, surname = UnitName("player") end
    characterName = characterName or "Unknown"
    local realmName = GetRealmName and GetRealmName() or ""
    local fullCharacterName
    if surname and surname ~= "" and surname ~= realmName then
        fullCharacterName = characterName .. " " .. surname
    elseif realmName ~= "" then
        fullCharacterName = characterName .. " (" .. realmName .. ")"
    else
        fullCharacterName = characterName
    end
    local gameMode = GetCharacterGameMode()
    local profileKey = fullCharacterName .. " [" .. gameMode .. "]"
    local profile = MyLootOnlyForeverProfiles.characters[profileKey]
    if not profile then
        local previousKeys = { fullCharacterName, realmName .. "-" .. characterName }
        for _, previousKey in ipairs(previousKeys) do
            profile = MyLootOnlyForeverProfiles.characters[previousKey]
            if profile then
                MyLootOnlyForeverProfiles.characters[previousKey] = nil
                break
            end
        end
    end
    if not profile then
        local settings = {}
        if not MyLootOnlyForeverProfiles.migratedLegacy then
            for k, v in pairs(DEFAULTS) do
                local oldValue = MyLootOnlyForeverDB[k]
                if oldValue ~= nil then
                    settings[k] = oldValue
                else
                    settings[k] = type(v) == "table" and {} or v
                end
            end
            MyLootOnlyForeverProfiles.migratedLegacy = true
        end
        profile = { settings = settings }
        MyLootOnlyForeverProfiles.characters[profileKey] = profile
    end
    MyLootOnlyForeverProfiles.characters[profileKey] = profile
    ActiveDB = SanitizeSettings(profile.settings)
    profile.settings = ActiveDB
    ActiveDB._profileKey = profileKey
    ActiveDB._displayName = fullCharacterName
    ActiveDB._displayMode = gameMode

    local ok, registered = pcall(RegisterSettingsPanel)
    if not ok or not registered then
        local legacyOK, legacyRegistered = pcall(RegisterLegacySettingsPanel)
        if not legacyOK or not legacyRegistered then
            print("|cffff4444(MyLootOnlyForever)|r Could not register the settings panel. Check that your client supports the WoW settings API or Interface Options.")
        elseif not ok then
            print("|cffffcc00(MyLootOnlyForever)|r Using compatibility settings panel after settings registration failed: " .. tostring(registered))
        end
    end
    self:UnregisterEvent("ADDON_LOADED")
end)

local loginNotice = CreateFrame("Frame")
loginNotice:RegisterEvent("PLAYER_LOGIN")
loginNotice:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if ActiveDB and ActiveDB.enabled then
        local version = GetAddonVersion()
        local previousVersion = MyLootOnlyForeverDB.lastAnnouncedVersion
        if version ~= "Unknown" and previousVersion and previousVersion ~= version then
            print("|cff33ff99(MyLootOnlyForever)|r updated to v" .. version .. ".")
        else
            print("|cff33ff99(MyLootOnlyForever)|r is active. Type /mlo to open settings.")
        end
        if version ~= "Unknown" then MyLootOnlyForeverDB.lastAnnouncedVersion = version end
    end
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

local function NormalizePlayerName(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" or #name > 64 or name:find("[%c|]") then return nil end
    return name:sub(1, 1):upper() .. name:sub(2):lower()
end

local function PrintWhitelist()
    local names = {}
    for name in pairs(ActiveDB.lootWhitelist) do table.insert(names, name) end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    if #names == 0 then
        print("|cff33ff99(MyLootOnlyForever)|r Loot exceptions: none")
    else
        print("|cff33ff99(MyLootOnlyForever)|r Loot exceptions: " .. table.concat(names, ", "))
    end
end

local function CopyCharacterProfile(sourceKey)
    local sourceProfile = MyLootOnlyForeverProfiles.characters[sourceKey]
    if type(sourceProfile) ~= "table" or type(sourceProfile.settings) ~= "table"
        or sourceKey == ActiveDB._profileKey then return false end
    local targetKey = ActiveDB._profileKey
    local targetDisplayName = ActiveDB._displayName
    local targetDisplayMode = ActiveDB._displayMode
    local copied = {}
    sourceProfile.settings = SanitizeSettings(sourceProfile.settings)
    for k, v in pairs(sourceProfile.settings) do
        if type(v) == "table" then
            local nested = {}
            for nestedKey, nestedValue in pairs(v) do nested[nestedKey] = nestedValue end
            copied[k] = nested
        else
            copied[k] = v
        end
    end
    for k in pairs(ActiveDB) do ActiveDB[k] = nil end
    for k, v in pairs(copied) do ActiveDB[k] = v end
    ActiveDB._profileKey = targetKey
    ActiveDB._displayName = targetDisplayName
    ActiveDB._displayMode = targetDisplayMode
    return true
end

OpenCustomOptions = function(showFrame)
    if not customOptionsFrame then
        local panel = CreateFrame("Frame", "MyLootOnlyForeverCustomOptions")
        customOptionsFrame = panel
        local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
        scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 0)
        local content = CreateFrame("Frame", nil, scrollFrame)
        content:SetSize(640, 790)
        scrollFrame:SetScrollChild(content)
        local frame = content
        local function EnlargeText(fontString, points)
            if not fontString then return end
            local font, size, flags = fontString:GetFont()
            if font and size then fontString:SetFont(font, size + points, flags) end
        end
        local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 16, -16)
        title:SetText("MyLootOnlyForever")

        local versionText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        versionText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -20)
        versionText:SetJustifyH("RIGHT")
        versionText:SetText("Version " .. GetAddonVersion())
        EnlargeText(versionText, 1)

        local enableCheckbox = CreateFrame("CheckButton", "MyLootOnlyForeverHeaderEnabled", frame, "InterfaceOptionsCheckButtonTemplate")
        enableCheckbox:SetPoint("TOPLEFT", 300, -12)
        local enableLabel = enableCheckbox.Text or _G[enableCheckbox:GetName() .. "Text"]
        if enableLabel then
            enableLabel:SetText("Enable Add-on")
            EnlargeText(enableLabel, 2)
        end
        enableCheckbox:SetScript("OnClick", function(self)
            ActiveDB.enabled = self:GetChecked() and true or false
        end)

        local function AddSectionDivider(y)
            local divider = frame:CreateTexture(nil, "ARTWORK")
            divider:SetColorTexture(0.78, 0.62, 0.24, 0.42)
            divider:SetPoint("TOPLEFT", 16, y)
            divider:SetSize(460, 1)
        end

        local characterHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        characterHeader:SetPoint("TOPLEFT", 16, -46)
        characterHeader:SetText("Current Character")

        local activeText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        activeText:SetPoint("TOPLEFT", 18, -70)
        activeText:SetJustifyH("LEFT")
        EnlargeText(activeText, 2)

        local activeModeText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        activeModeText:SetPoint("TOPLEFT", 18, -90)
        activeModeText:SetJustifyH("LEFT")
        EnlargeText(activeModeText, 3)
        AddSectionDivider(-106)

        local profileTitle = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        profileTitle:SetPoint("TOPLEFT", 20, -116)
        profileTitle:SetText("Copy settings from")
        EnlargeText(profileTitle, 2)

        local selectedProfile
        local selectedProfileDetails
        local refresh
        local copyButton
        local profileDropdown = CreateFrame("Frame", "MyLootOnlyForeverProfileDropdown", frame, "UIDropDownMenuTemplate")
        profileDropdown:SetPoint("TOPLEFT", 4, -142)
        UIDropDownMenu_SetWidth(profileDropdown, 250)
        UIDropDownMenu_Initialize(profileDropdown, function(self, level)
            local keys = {}
            for key in pairs(MyLootOnlyForeverProfiles.characters) do table.insert(keys, key) end
            table.sort(keys)
            for _, key in ipairs(keys) do
                local profileKey = key
                local info = UIDropDownMenu_CreateInfo()
                info.text = profileKey
                info.value = profileKey
                info.checked = selectedProfile == profileKey
                info.disabled = profileKey == ActiveDB._profileKey
                info.func = function()
                    selectedProfile = profileKey
                    UIDropDownMenu_SetSelectedValue(profileDropdown, profileKey)
                    local characterName, gameMode = profileKey:match("^(.-)%s%[(.-)%]$")
                    UIDropDownMenu_SetText(profileDropdown, characterName or profileKey)
                    selectedProfileDetails:SetText("Selected: " .. (characterName or profileKey) .. "  |  Game Mode: " .. (gameMode or "Unknown"))
                    copyButton:Enable()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)

        copyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        copyButton:SetSize(170, 24)
        copyButton:SetPoint("TOPLEFT", 304, -142)
        copyButton:SetText("Copy to this character")
        copyButton:Disable()
        copyButton:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Copy the selected character's settings to this character.")
            GameTooltip:AddLine("This replaces the current options and loot exceptions.", 1, 0.82, 0)
            GameTooltip:Show()
        end)
        copyButton:SetScript("OnLeave", GameTooltip_Hide)
        copyButton:SetScript("OnClick", function()
            if selectedProfile and CopyCharacterProfile(selectedProfile) then
                refresh()
                print("|cff33ff99(MyLootOnlyForever)|r Copied settings from " .. selectedProfile .. ".")
            end
        end)

        selectedProfileDetails = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        selectedProfileDetails:SetPoint("TOPLEFT", 22, -172)
        selectedProfileDetails:SetText("Select a character to see its name and game mode before copying.")
        EnlargeText(selectedProfileDetails, 3)

        local section = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        section:SetPoint("TOPLEFT", 20, -210)
        section:SetText("Basic Options")
        AddSectionDivider(-192)

        local controls = {
            { "hideOtherLoot", "Hide other players' loot" },
            { "hideOtherCrafting", "Hide other players' crafting" },
            { "hideOtherRolls", "Hide other players' loot rolls" },
        }
        local checkboxes = {}
        for index, entry in ipairs(controls) do
            local key = entry[1]
            local checkbox = CreateFrame("CheckButton", "MyLootOnlyForeverCustomOption" .. key, frame, "InterfaceOptionsCheckButtonTemplate")
            checkbox:SetPoint("TOPLEFT", 22, -242 - ((index - 1) * 32))
            local label = checkbox.Text or _G[checkbox:GetName() .. "Text"]
            if label then
                label:SetText(entry[2])
                EnlargeText(label, 2)
            end
            checkbox:SetScript("OnClick", function(self)
                ActiveDB[key] = self:GetChecked() and true or false
            end)
            checkboxes[key] = checkbox
        end

        local socialSection = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        socialSection:SetPoint("TOPLEFT", 20, -350)
        socialSection:SetText("Allow loot from")
        AddSectionDivider(-334)

        local socialControls = {
            { "allowGroupLoot", "Party and raid members' loot" },
            { "allowGuildLootCrafting", "Guildmates' loot and crafting" },
            { "allowFriendLootCrafting", "Friends' loot and crafting" },
        }
        local socialCheckboxes = {}
        for index, entry in ipairs(socialControls) do
            local key = entry[1]
            local checkbox = CreateFrame("CheckButton", "MyLootOnlyForeverCustomOption" .. key, frame, "InterfaceOptionsCheckButtonTemplate")
            checkbox:SetPoint("TOPLEFT", 22, -374 - ((index - 1) * 30))
            local label = checkbox.Text or _G[checkbox:GetName() .. "Text"]
            if label then
                label:SetText(entry[2])
                EnlargeText(label, 2)
            end
            checkbox:SetScript("OnClick", function(self)
                ActiveDB[key] = self:GetChecked() and true or false
            end)
            socialCheckboxes[key] = checkbox
        end

        local qualityTitle = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        qualityTitle:SetPoint("TOPLEFT", 20, -482)
        qualityTitle:SetText("Minimum loot quality to show")
        EnlargeText(qualityTitle, 2)
        AddSectionDivider(-474)

        local qualityOptions = {
            { value = 6, text = "Hide All Other Loot" },
            { value = 2, text = "Uncommon (Green) & Above" },
            { value = 3, text = "Rare (Blue) & Above" },
            { value = 4, text = "Epic (Purple) & Above" },
            { value = 5, text = "Legendary (Orange) & Above" },
        }
        local qualityDropdown = CreateFrame("Frame", "MyLootOnlyForeverQualityDropdown", frame, "UIDropDownMenuTemplate")
        qualityDropdown:SetPoint("TOPLEFT", 4, -508)
        UIDropDownMenu_SetWidth(qualityDropdown, 220)
        UIDropDownMenu_Initialize(qualityDropdown, function(self, level)
            for _, option in ipairs(qualityOptions) do
                local value = option.value
                local label = option.text
                local info = UIDropDownMenu_CreateInfo()
                info.text = label
                info.value = value
                info.checked = ActiveDB.minOtherLootQuality == value
                info.func = function()
                    ActiveDB.minOtherLootQuality = value
                    UIDropDownMenu_SetSelectedValue(qualityDropdown, value)
                    UIDropDownMenu_SetText(qualityDropdown, label)
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end)

        local specialLootTitle = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        specialLootTitle:SetPoint("TOPLEFT", 20, -560)
        specialLootTitle:SetText("Special Loot")
        AddSectionDivider(-552)
        local specialLootDescription = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        specialLootDescription:SetPoint("TOPLEFT", 22, -580)
        specialLootDescription:SetText("Show selected item types even when other players' loot is filtered.")
        EnlargeText(specialLootDescription, 3)

        local specialLootControls = {
            { "showSpecialMounts", "Mounts", 22, "Always show mount items from other players." },
            { "showSpecialPets", "Companion Pets", 165, "Always show companion pet items from other players." },
            { "showSpecialToys", "Toys", 345, "Always show toy items from other players." },
            { "showSpecialRecipes", "Recipes", 445, "Always show recipe items from other players." },
        }
        local specialLootCheckboxes = {}
        for _, entry in ipairs(specialLootControls) do
            local key = entry[1]
            local helpText = entry[4]
            local checkbox = CreateFrame("CheckButton", "MyLootOnlyForeverCustomOption" .. key, frame, "InterfaceOptionsCheckButtonTemplate")
            checkbox:SetPoint("TOPLEFT", entry[3], -602)
            local label = checkbox.Text or _G[checkbox:GetName() .. "Text"]
            if label then
                label:SetText(entry[2])
                EnlargeText(label, 2)
            end
            checkbox:SetScript("OnClick", function(self)
                ActiveDB[key] = self:GetChecked() and true or false
            end)
            checkbox:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(helpText, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            checkbox:SetScript("OnLeave", GameTooltip_Hide)
            specialLootCheckboxes[key] = checkbox
        end

        local exceptionsTitle = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        exceptionsTitle:SetPoint("TOPLEFT", 20, -640)
        exceptionsTitle:SetText("Loot Exceptions")
        AddSectionDivider(-632)

        local addExceptionLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        addExceptionLabel:SetPoint("TOPLEFT", 20, -658)
        addExceptionLabel:SetText("Add a player to the exceptions list")
        EnlargeText(addExceptionLabel, 2)
        local savedExceptionsLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        savedExceptionsLabel:SetPoint("TOPLEFT", 20, -720)
        savedExceptionsLabel:SetText("Saved exceptions")
        EnlargeText(savedExceptionsLabel, 2)
        AddSectionDivider(-708)

        local exceptionInput = CreateFrame("EditBox", "MyLootOnlyForeverExceptionInput", frame, "InputBoxTemplate")
        exceptionInput:SetSize(165, 24)
        exceptionInput:SetPoint("TOPLEFT", 24, -680)
        exceptionInput:SetAutoFocus(false)
        exceptionInput:SetMaxLetters(64)
        local exceptionButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        exceptionButton:SetSize(130, 26)
        exceptionButton:SetPoint("LEFT", exceptionInput, "RIGHT", 10, 0)
        exceptionButton:SetText("Add player")
        exceptionButton:SetScript("OnClick", function()
            local enteredName = exceptionInput:GetText()
            local name = NormalizePlayerName(enteredName)
            if name then
                ActiveDB.lootWhitelist[name] = true
                exceptionInput:SetText("")
                print("|cff33ff99(MyLootOnlyForever)|r Added loot exception for " .. name .. ".")
                refresh()
            elseif enteredName:match("%S") then
                print("|cffff4444(MyLootOnlyForever)|r Enter a valid player name (up to 64 characters).")
            end
        end)
        exceptionInput:SetScript("OnEnterPressed", function() exceptionButton:Click() end)

        local savedExceptionRows = {}

        refresh = function()
            activeText:SetText(tostring(ActiveDB._displayName or ActiveDB._profileKey))
            activeModeText:SetText("Game Mode: " .. tostring(ActiveDB._displayMode or "Unknown"))
            enableCheckbox:SetChecked(ActiveDB.enabled)
            if selectedProfile then
                local characterName, gameMode = selectedProfile:match("^(.-)%s%[(.-)%]$")
                UIDropDownMenu_SetText(profileDropdown, characterName or selectedProfile)
                selectedProfileDetails:SetText("Selected: " .. (characterName or selectedProfile) .. "  |  Game Mode: " .. (gameMode or "Unknown"))
            else
                UIDropDownMenu_SetText(profileDropdown, "Select a character")
                selectedProfileDetails:SetText("Choose a character to preview their name and game mode.")
            end
            for key, checkbox in pairs(checkboxes) do checkbox:SetChecked(ActiveDB[key]) end
            for key, checkbox in pairs(socialCheckboxes) do checkbox:SetChecked(ActiveDB[key]) end
            for key, checkbox in pairs(specialLootCheckboxes) do checkbox:SetChecked(ActiveDB[key]) end
            local exceptionNames = {}
            for name in pairs(ActiveDB.lootWhitelist or {}) do table.insert(exceptionNames, name) end
            table.sort(exceptionNames, function(a, b) return a:lower() < b:lower() end)
            if #exceptionNames == 0 then
                if not savedExceptionRows.emptyText then
                    savedExceptionRows.emptyText = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                    savedExceptionRows.emptyText:SetPoint("TOPLEFT", 22, -742)
                    EnlargeText(savedExceptionRows.emptyText, 3)
                end
                savedExceptionRows.emptyText:SetText("None yet")
                savedExceptionRows.emptyText:Show()
            elseif savedExceptionRows.emptyText then
                savedExceptionRows.emptyText:Hide()
            end
            for index, name in ipairs(exceptionNames) do
                local row = savedExceptionRows[index]
                if not row then
                    row = CreateFrame("Frame", nil, frame)
                    row:SetSize(560, 24)
                    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
                    row.name:SetPoint("LEFT", 0, 0)
                    row.name:SetWidth(470)
                    row.name:SetJustifyH("LEFT")
                    EnlargeText(row.name, 3)
                    row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                    row.remove:SetSize(70, 22)
                    row.remove:SetPoint("RIGHT", 0, 0)
                    row.remove:SetText("Remove")
                    savedExceptionRows[index] = row
                end
                row:SetPoint("TOPLEFT", 22, -742 - ((index - 1) * 26))
                row.name:SetText(name)
                row.remove:SetScript("OnClick", function()
                    ActiveDB.lootWhitelist[name] = nil
                    refresh()
                end)
                row:Show()
            end
            for index = #exceptionNames + 1, #savedExceptionRows do
                savedExceptionRows[index]:Hide()
            end
            content:SetHeight(math.max(806, 752 + math.max(1, #exceptionNames) * 26))
            local selectedQuality = ActiveDB.minOtherLootQuality or 6
            local selectedText = qualityOptions[1].text
            for _, option in ipairs(qualityOptions) do
                if option.value == selectedQuality then
                    selectedText = option.text
                    break
                end
            end
            UIDropDownMenu_SetSelectedValue(qualityDropdown, selectedQuality)
            UIDropDownMenu_SetText(qualityDropdown, selectedText)
        end
        customOptionsFrame.refreshOptions = refresh
        refresh()
    end
    if customOptionsFrame.refreshOptions then customOptionsFrame.refreshOptions() end
    if showFrame ~= false then
        if settingsCategoryID and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(settingsCategoryID)
        elseif legacySettingsPanel and InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory(legacySettingsPanel)
            InterfaceOptionsFrame_OpenToCategory(legacySettingsPanel)
        else
            print("|cffff4444(MyLootOnlyForever)|r The AddOns options page is not available. Open it from Escape > Options > AddOns.")
        end
    end
end

SLASH_MYLOOTONLYFOREVER1 = "/mlo"
SLASH_MYLOOTONLYFOREVER2 = "/mylootonly"
SlashCmdList.MYLOOTONLYFOREVER = function(input)
    local cmd, arg = (input or ""):lower():trim():match("^(%S+)%s*(.*)$")
    cmd = cmd or ""

    if cmd == "" or cmd == "options" or cmd == "config" then
        OpenCustomOptions()
    elseif cmd == "profiles" then
        local names = {}
        for key in pairs(MyLootOnlyForeverProfiles and MyLootOnlyForeverProfiles.characters or {}) do
            table.insert(names, key)
        end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        print("|cff33ff99(MyLootOnlyForever)|r Saved character profiles: " .. (#names > 0 and table.concat(names, ", ") or "none"))
        print("|cff33ff99(MyLootOnlyForever)|r Copy with: /mlo copy <character or realm-character>")
    elseif cmd == "copy" then
        local source = (arg or ""):lower()
        local foundKey
        for key in pairs(MyLootOnlyForeverProfiles and MyLootOnlyForeverProfiles.characters or {}) do
            local shortName = key:match("%-([^%-]+)$")
            if key:lower() == source or (shortName and shortName:lower() == source) then
                foundKey = key
                break
            end
        end
        local sourceProfile = foundKey and MyLootOnlyForeverProfiles.characters[foundKey]
        if not sourceProfile or not sourceProfile.settings then
            print("|cff33ff99(MyLootOnlyForever)|r Profile not found. Use /mlo profiles to list saved characters.")
        elseif foundKey == ActiveDB._profileKey then
            print("|cff33ff99(MyLootOnlyForever)|r That is already this character's profile.")
        else
            CopyCharacterProfile(foundKey)
            if customOptionsFrame and customOptionsFrame:IsShown() then customOptionsFrame.refreshOptions() end
            print("|cff33ff99(MyLootOnlyForever)|r Copied settings from " .. foundKey .. ". Reopen the settings panel if it is already open.")
        end
    elseif cmd == "toggle" then
        ActiveDB.enabled = not ActiveDB.enabled
        PrintStatus("Addon enabled", ActiveDB.enabled)
    elseif cmd == "loot" then
        ActiveDB.hideOtherLoot = not ActiveDB.hideOtherLoot
        PrintStatus("Hide other players' loot", ActiveDB.hideOtherLoot)
    elseif cmd == "quality" or cmd == "rarity" then
        local q = ParseQualityArg(arg)
        if q then
            ActiveDB.minOtherLootQuality = q
            print("|cff33ff99(MyLootOnlyForever)|r Other loot threshold: " .. GetQualityLabel(q))
        else
            print("|cff33ff99(MyLootOnlyForever)|r Usage: /mlo quality all | uncommon | rare | epic | legendary")
        end
    elseif cmd == "exception" or cmd == "exceptions" then
        local action, name = arg:match("^(%S+)%s*(.-)%s*$")
        action = action and action:lower()
        ActiveDB.lootWhitelist = ActiveDB.lootWhitelist or {}
        if action == "add" and NormalizePlayerName(name) then
            name = NormalizePlayerName(name)
            ActiveDB.lootWhitelist[name] = true
            print("|cff33ff99(MyLootOnlyForever)|r Added loot exception for " .. name .. ".")
        elseif (action == "remove" or action == "delete") and NormalizePlayerName(name) then
            name = NormalizePlayerName(name)
            local removed = ActiveDB.lootWhitelist[name] ~= nil
            ActiveDB.lootWhitelist[name] = nil
            print("|cff33ff99(MyLootOnlyForever)|r " .. (removed and ("Removed loot exception for " .. name .. ".") or ("No loot exception found for " .. name .. ".")))
        elseif action == "list" then
            PrintWhitelist()
        else
            print("|cff33ff99(MyLootOnlyForever)|r Usage: /mlo exception add <player> | remove <player> | list")
        end
        if customOptionsFrame and customOptionsFrame.refreshOptions then customOptionsFrame.refreshOptions() end
    elseif cmd == "craft" or cmd == "crafting" then
        ActiveDB.hideOtherCrafting = not ActiveDB.hideOtherCrafting
        PrintStatus("Hide other players' crafting", ActiveDB.hideOtherCrafting)
    elseif cmd == "rolls" or cmd == "roll" then
        ActiveDB.hideOtherRolls = not ActiveDB.hideOtherRolls
        PrintStatus("Hide other players' rolls", ActiveDB.hideOtherRolls)
    elseif cmd == "status" then
        PrintStatus("Addon enabled", ActiveDB.enabled)
        PrintStatus("Hide other loot", ActiveDB.hideOtherLoot)
        print("|cff33ff99(MyLootOnlyForever)|r Other loot threshold: " .. GetQualityLabel(ActiveDB.minOtherLootQuality))
        PrintStatus("Hide other crafting", ActiveDB.hideOtherCrafting)
        PrintStatus("Hide other rolls", ActiveDB.hideOtherRolls)
        PrintStatus("Always show mounts", ActiveDB.showSpecialMounts)
        PrintStatus("Always show companion pets", ActiveDB.showSpecialPets)
        PrintStatus("Always show toys", ActiveDB.showSpecialToys)
        PrintStatus("Always show recipes", ActiveDB.showSpecialRecipes)
    else
        print("|cff33ff99(MyLootOnlyForever)|r Usage: /mlo, /mlo toggle, /mlo loot, /mlo quality, /mlo craft, /mlo rolls, /mlo status")
    end
end
