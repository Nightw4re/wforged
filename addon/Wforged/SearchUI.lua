local addonName, addon = ...

local SearchUI = {}
addon.SearchUI = SearchUI
SearchUI.sortKey = "level"
SearchUI.sortAscending = false
SearchUI.pageSize = 100
SearchUI.page = 1
SearchUI.selectedUpgrades = {}

local function getUIState()
  WforgedDB.searchUI = WforgedDB.searchUI or {}
  return WforgedDB.searchUI
end

local filterOptions = {
  armorType = {"", "Cloth", "Leather", "Mail", "Plate"},
  slot = {"", "Head", "Shoulder", "Chest", "Back", "Wrist", "Hands", "Waist", "Legs", "Feet", "Finger", "Trinket", "Neck", "Weapon", "Off Hand"},
  weaponType = {"", "Axe", "Bow", "Crossbow", "Dagger", "Fist", "Gun", "Mace", "Polearm", "Shield", "Staff", "Sword", "Two-Handed Axe", "Two-Handed Sword", "Two-Handed Mace", "Wand"},
  quality = {"", "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary"},
  variant = {"", "base", "upgrade", "equipment", "bags", "food", "other"},
  stat1 = {"", "Strength", "Agility", "Intellect", "Spirit", "Stamina", "Critical Strike", "Hit Rating", "Expertise", "Haste Rating", "Spell Power", "Attack Power"},
  stat2 = {"", "Strength", "Agility", "Intellect", "Spirit", "Stamina", "Critical Strike", "Hit Rating", "Expertise", "Haste Rating", "Spell Power", "Attack Power"},
  stat3 = {"", "Strength", "Agility", "Intellect", "Spirit", "Stamina", "Critical Strike", "Hit Rating", "Expertise", "Haste Rating", "Spell Power", "Attack Power"},
  stat4 = {"", "Strength", "Agility", "Intellect", "Spirit", "Stamina", "Critical Strike", "Hit Rating", "Expertise", "Haste Rating", "Spell Power", "Attack Power"},
  level = {"", "base", "upgrade", "10", "20", "30", "40", "50", "60"},
}

local function filterLabel(value, kind)
  if value == "" then
    if kind == "level" then return "Any level" end
    if kind == "weaponType" then return "Any weapon" end
    if kind == "armorType" then return "Any armor type" end
    if kind == "quality" then return "Any quality" end
    if kind == "variant" then return "All item types" end
    if kind:match("^stat%d$") then return "Any stat" end
    return "Any " .. kind
  end
  if value == "base" then return "Base items" end
  if value == "upgrade" then return "Upgrades" end
  if value == "equipment" then return "Equipment" end
  if value == "bags" then return "Bags" end
  if value == "food" then return "Food/Drink" end
  if value == "other" then return "Other items" end
  if kind == "level" then return "Level " .. value .. "+" end
  return value
end

local function updateFilterVisual(button)
  if not button then return end
  local active = button.value and button.value ~= ""
  local fontString = button.GetFontString and button:GetFontString() or nil
  if fontString and fontString.SetTextColor then
    fontString:SetTextColor(1, active and 0.82 or 1, active and 0 or 1, 1)
  end
  if button.SetBackdrop and button.SetBackdropColor and button.SetBackdropBorderColor then
    button:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1})
    button:SetBackdropColor(0.15, 0.12, 0.02, active and 0.85 or 0.35)
    button:SetBackdropBorderColor(active and 1 or 0.25, active and 0.65 or 0.25, 0.05, 1)
  end
end

local function createFilter(parent, kind, x, y)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(108, 22)
  button:SetPoint("TOPLEFT", x, y)
  button.kind = kind
      button.value = ""
      button:SetText(filterLabel("", kind))
      updateFilterVisual(button)
  button.arrow = button:CreateTexture(nil, "OVERLAY")
  button.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
  button.arrow:SetSize(12, 12)
  button.arrow:SetPoint("RIGHT", -5, 0)
  button.arrow:SetVertexColor(1, 0.82, 0, 1)
  button:SetScript("OnClick", function(self)
    if not UIDropDownMenu_Initialize or not ToggleDropDownMenu then return end
    local menu = _G["WforgedFilterMenu"]
    if not menu then
      menu = CreateFrame("Frame", "WforgedFilterMenu", UIParent, "UIDropDownMenuTemplate")
    end
    if menu:IsShown() and menu.filterButton == self then
      if CloseDropDownMenus then CloseDropDownMenus() end
      menu.filterButton = nil
      return
    end
    UIDropDownMenu_Initialize(menu, function(_, level)
      for _, value in ipairs(filterOptions[kind]) do
        local info = UIDropDownMenu_CreateInfo()
        local label = filterLabel(value, kind)
        info.text = value == "" and "|cff888888" .. label .. "|r" or label
        info.checked = self.value == value
        info.func = function()
          self.value = value
          self:SetText(filterLabel(value, kind))
          updateFilterVisual(self)
          if SearchUI.filters then SearchUI.filters[kind] = value end
          SearchUI.page = 1
          SearchUI:Refresh()
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)
    menu.filterButton = self
    ToggleDropDownMenu(1, nil, menu, self, 0, -2)
  end)
  return button
end

local function formatUpgradeCost(cost, currency)
  if not cost then
    return nil
  end

  if currency == "copper" then
    local gold = math.floor(cost / 10000)
    local silver = math.floor(math.mod(cost, 10000) / 100)
    local copper = math.mod(cost, 100)
    local parts = {}
    if gold > 0 then
      parts[#parts + 1] = tostring(gold) .. "g"
    end
    if silver > 0 then
      parts[#parts + 1] = tostring(silver) .. "s"
    end
    if copper > 0 or #parts == 0 then
      parts[#parts + 1] = tostring(copper) .. "c"
    end
    return table.concat(parts, " ")
  end

  if currency == "rune" then
    return tostring(cost)
  end

  return tostring(cost) .. (currency and (" " .. tostring(currency)) or "")
end

local function getQualityColorCode(quality)
  if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
    return ITEM_QUALITY_COLORS[quality].hex
  end
  return "|cffffffff"
end

local function openChatWithText(text, itemLink, prefix, suffix)
  if not text or text == "" then
    return
  end

  if SearchUI.frame and SearchUI.frame.editBox then
    SearchUI.frame.editBox:ClearFocus()
  end

  local editBox = ChatFrame1EditBox or ChatFrameEditBox
  if ChatEdit_ChooseBoxForSend then
    local chosen = ChatEdit_ChooseBoxForSend()
    if chosen and chosen.IsVisible and chosen:IsVisible() then
      editBox = chosen
    end
  end
  if ChatEdit_ActivateChat then
    ChatEdit_ActivateChat(editBox)
  elseif editBox and editBox.Show then
    editBox:Show()
  end

  if editBox and editBox.SetText then
    if editBox.Show then editBox:Show() end
    if editBox.SetFocus then editBox:SetFocus() end
    local insertedLink = false
    if itemLink and itemLink:find("|Hitem:", 1, true) and ChatEdit_InsertLink then
      if ChatEdit_ActivateChat then
        ChatEdit_ActivateChat(editBox)
      end
      if ChatEdit_GetActiveWindow then
        local activeBox = ChatEdit_GetActiveWindow()
        if activeBox then
          editBox = activeBox
        end
      end
      if prefix and editBox.Insert then
        editBox:Insert(prefix)
      end
      -- The legacy client inserts the link but does not return a boolean.
      ChatEdit_InsertLink(itemLink)
      insertedLink = true
      if suffix and editBox.Insert then
        editBox:Insert(suffix)
      end
    end
    if not insertedLink then
      editBox:SetText(text)
    end
    if editBox.SetCursorPosition then
      editBox:SetCursorPosition(string.len(insertedLink and text or text))
    end
    if editBox.SetFocus then editBox:SetFocus() end
    if addon.LootDebug then
      addon:LootDebug(string.format(
        "Share chat: box=%s linkInserted=%s textLength=%d",
        tostring(editBox.GetName and editBox:GetName() or "unknown"),
        tostring(insertedLink),
        string.len(text)
      ))
    end
  end
end

local function buildChatItemLink(result)
  if not result then
    return "item"
  end

  local itemLink = result.itemLink or result.itemName or "item"
  if GetItemInfo and result.itemId then
    local _, canonicalLink = GetItemInfo(result.itemId)
    if canonicalLink and canonicalLink:find("|Hitem:", 1, true) then
      itemLink = canonicalLink
    end
  end
  if not itemLink:find("|Hitem:", 1, true) then
    return itemLink
  end

  local colorCode = "ffffffff"
  if result.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[result.quality] and ITEM_QUALITY_COLORS[result.quality].hex then
    colorCode = ITEM_QUALITY_COLORS[result.quality].hex:gsub("|c", "")
  end

  if itemLink:find("|c", 1, true) then
    return itemLink
  end

  return string.format("|c%s%s|r", colorCode, itemLink)
end

local function buildShareText(result)
  if not result then
    return ""
  end

  local zoneName = result.zoneRepairPending and nil or (addon.ResolveZoneName and addon:ResolveZoneName(
    result.lastMapId,
    result.lastContinent,
    result.lastZone,
    result.lastZoneName
  ) or result.lastZoneName)

  local locationParts = {}
  if zoneName and zoneName ~= "" then
    locationParts[#locationParts + 1] = tostring(zoneName)
  elseif result.lastMapId then
    locationParts[#locationParts + 1] = "map " .. tostring(result.lastMapId)
  end
  if result.lastX and result.lastY then
    locationParts[#locationParts + 1] = string.format("%.1f, %.1f", result.lastX * 100, result.lastY * 100)
  end

  local locationText = #locationParts > 0 and table.concat(locationParts, " @ ") or "location unknown"
  return string.format("Wforged Addon: %s - %s", buildChatItemLink(result), locationText)
end

function SearchUI:ShareResult(result)
  if result then
    local text = buildShareText(result)
    local itemLink = buildChatItemLink(result)
    local linkStart = text:find(itemLink, 1, true)
    if linkStart and itemLink:find("|Hitem:", 1, true) then
      openChatWithText(text, itemLink, text:sub(1, linkStart - 1), text:sub(linkStart + #itemLink))
      return
    end
    openChatWithText(text)
  end
end

local function hasUsableLocation(result)
  if not result then
    return false
  end

  if result.lastSource == "inventory" or result.lastSource == "equipped" then
    return false
  end

  if type(result.lastX) ~= "number" or type(result.lastY) ~= "number" then
    return false
  end
  if not tonumber(result.lastMapId) then
    return false
  end

  if result.lastX <= 0 or result.lastX >= 1 or result.lastY <= 0 or result.lastY >= 1 then
    return false
  end

  return true
end

local function getLocationText(result)
  if not hasUsableLocation(result) then return "-" end
  if result.zoneRepairPending then return "unknown zone" end
  local location = {
    mapId = result.lastMapId,
    continent = result.lastContinent,
    zone = result.lastZone,
    zoneName = result.lastZoneName,
    x = result.lastX,
    y = result.lastY,
  }
  local zoneName = result.zoneRepairPending and nil or (addon.ResolveZoneName and addon:ResolveZoneName(
    result.lastMapId, result.lastContinent, result.lastZone, result.lastZoneName
  ) or result.lastZoneName)
  if (not zoneName or zoneName == "" or zoneName:match("^Map %d+$"))
    and addon.DB and addon.DB.GetStoredLocationName then
    local stored = addon.DB:GetStoredLocationName(result.itemId, location)
    zoneName = stored and stored.zoneName or zoneName
  end
  if not zoneName or zoneName == "" or zoneName:match("^Map %d+$") then
    return "unknown zone"
  end
  return zoneName
end

local function getQualityName(quality)
  return ({ [0] = "Poor", [1] = "Common", [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" })[tonumber(quality)] or "-"
end

local function closeFilterDropdown()
  if CloseDropDownMenus then CloseDropDownMenus() end
end

local function findSourceResult(result)
  if not result or not addon.DB or not addon.DB.SearchItems then return nil end
  local sourceKey = result.sourceItemKey or result.resolvedSourceItemKey
  local sourceId = result.sourceItemId
  local sourceName = result.sourceItemName or result.resolvedSourceItemName
  local candidates = addon.DB:SearchItems(sourceName or "", {})
  local best
  for _, candidate in ipairs(candidates or {}) do
    local keyMatch = sourceKey and candidate.itemKey == sourceKey
    local idMatch = sourceId and tonumber(candidate.itemId) == tonumber(sourceId)
    local nameMatch = sourceName and string.lower(candidate.itemName or "") == string.lower(sourceName)
    if keyMatch or idMatch or nameMatch then
      local candidateUpgrade = candidate.isUpgrade == true or candidate.upgradeCost ~= nil
      if not candidateUpgrade and (not best or (candidate.itemLevel or 0) < (best.itemLevel or 0)) then
        best = candidate
      end
    end
  end
  return best
end

local function getMapResult(result)
  if not result then return nil end
  local source = findSourceResult(result)
  if source and source.lastX and source.lastY then return source end
  if addon.DB and result.itemKey then
    local resolver = addon.DB.GetMapLocationForItem or addon.DB.GetResolvedSourceLocation
    local location = resolver and resolver(addon.DB, result.itemKey) or nil
    if location and location.x and location.y then
      local resolved = {}
      for key, value in pairs(result) do resolved[key] = value end
      resolved.lastMapId = location.mapId
      resolved.lastContinent = location.continent
      resolved.lastZone = location.zone
      resolved.lastZoneName = location.zoneName
      resolved.lastX = location.x
      resolved.lastY = location.y
      return resolved
    end
  end
  return source or result
end

local function buildUpgradeShareText(result)
  local source = findSourceResult(result)
  if not source then return buildShareText(result) end
  local zoneName = getLocationText(source)
  if zoneName == "-" or zoneName == "unknown zone" then
    return buildChatItemLink(result) .. " found in unknown zone as " .. buildChatItemLink(source)
  end
  local coords = ""
  if source.lastX and source.lastY then
    coords = string.format(" @ %.1f, %.1f", source.lastX * 100, source.lastY * 100)
  end
  return string.format(
    "Wforged Addon: %s found in %s as %s%s",
    buildChatItemLink(result), zoneName, buildChatItemLink(source), coords
  )
end

local function quotedFilterStats(text)
  local found = {}
  local known = {}
  for _, value in ipairs(filterOptions.stat1) do
    if value ~= "" then known[string.lower(value)] = value end
  end
  local cleaned = tostring(text or ""):gsub('"([^"]+)"', function(value)
    local stat = known[string.lower(value)]
    if stat and #found < 4 then
      found[#found + 1] = stat
      return ""
    end
    return '"' .. value .. '"'
  end)
  return cleaned:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""), found
end

local function getQuotedStatNames(query)
  local stats = {}
  local known = {
    ["strength"] = true, ["agility"] = true, ["stamina"] = true,
    ["intellect"] = true, ["spirit"] = true, ["critical strike"] = true,
    ["hit rating"] = true, ["expertise"] = true, ["haste rating"] = true, ["spell power"] = true,
    ["attack power"] = true, ["armor penetration"] = true,
    ["fire resistance"] = true, ["frost resistance"] = true,
    ["nature resistance"] = true, ["shadow resistance"] = true,
  }
  for phrase in string.lower(tostring(query or "")):gmatch('"([^"]+)"') do
    if known[phrase] and #stats < 4 then stats[#stats + 1] = phrase end
  end
  return stats
end

local function getStatValue(result, statName)
  local text = string.lower(tostring(result.statsText or "") .. " | " .. tostring(result.tooltipText or ""))
  local escaped = statName:gsub("%W", "%%%0")
  local value = text:match("([%+%-]?%d+)[^|\n]*" .. escaped)
  return value and tostring(tonumber(value) or value) or "-"
end

local function getStatAbbreviation(statName)
  return ({
    ["strength"] = "STR",
    ["agility"] = "AGI",
    ["stamina"] = "STA",
    ["intellect"] = "INT",
    ["spirit"] = "SPI",
    ["critical strike"] = "CRIT",
    ["hit rating"] = "HIT",
    ["expertise"] = "EXP",
    ["haste rating"] = "HASTE",
    ["spell power"] = "SP",
    ["attack power"] = "AP",
    ["armor penetration"] = "ARP",
    ["fire resistance"] = "FR",
    ["frost resistance"] = "FROST",
    ["nature resistance"] = "NR",
    ["shadow resistance"] = "SR",
  })[string.lower(statName or "")] or statName
end

local function isForeignRealm(result)
  local current = addon.DB and addon.DB.GetCurrentRealm and addon.DB:GetCurrentRealm() or "Unknown"
  return result and result.realm and result.realm ~= "Unknown" and result.realm ~= current
end

local function createCheckbox(parent, labelText)
  local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  local name = checkbox:GetName()
  checkbox.text = name and _G[name .. "Text"] or nil
  if checkbox.text then
    checkbox.text:SetText(labelText)
  else
    checkbox.label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 2, 1)
    checkbox.label:SetText(labelText)
  end
  return checkbox
end

local function createRow(parent, index)
  local row = CreateFrame("Button", nil, parent)
  row:SetHeight(28)
  local rowOffset = -2 - ((index - 1) * 30)
  row:SetPoint("TOPLEFT", 8, rowOffset)
  row:SetPoint("TOPRIGHT", 0, rowOffset)

  row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", 0, 0)
  row.nameText:SetPoint("LEFT", 26, 0)
  row.nameText:SetWidth(234)
  row.nameText:SetJustifyH("LEFT")
  row.levelText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.levelText:SetPoint("LEFT", 270, 0)
  row.levelText:SetWidth(45)
  row.qualityText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.qualityText:SetPoint("LEFT", 320, 0)
  row.qualityText:SetWidth(85)
  row.statTexts = {}
  for statIndex = 1, 4 do
    local statText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statText:SetWidth(80)
    statText:SetJustifyH("RIGHT")
    statText:Hide()
    row.statTexts[statIndex] = statText
  end
  row.locationText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.locationText:SetPoint("LEFT", 405, 0)
  row.locationText:SetWidth(263)
  row.locationText:SetJustifyH("LEFT")
  row.locationText:SetWordWrap(false)
  row.currencyButton = CreateFrame("Button", nil, row)
  row.currencyButton:SetSize(14, 14)
  row.currencyButton:SetPoint("LEFT", row.locationText, "LEFT", 0, 0)
  row.currencyButton.texture = row.currencyButton:CreateTexture(nil, "ARTWORK")
  row.currencyButton.texture:SetAllPoints()
  row.currencyButton.count = row.currencyButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  row.currencyButton.count:SetPoint("BOTTOMRIGHT", 2, -2)
  row.currencyButton:SetScript("OnEnter", function(button)
    if not button.itemLink or not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(button.itemLink)
    GameTooltip:Show()
  end)
  row.currencyButton:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
  row.currencyButton:Hide()
  row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
  row.highlight:SetAllPoints(row)
  row.highlight:SetTexture(1, 1, 1, 0.08)
  row.searchHighlight = row:CreateTexture(nil, "BACKGROUND")
  row.searchHighlight:SetAllPoints(row)
  row.searchHighlight:SetTexture(1, 0.75, 0.1, 0.28)
  row.searchHighlight:Hide()
  row.selectionHighlight = row:CreateTexture(nil, "BACKGROUND")
  row.selectionHighlight:SetPoint("TOPLEFT", 1, 0)
  row.selectionHighlight:SetPoint("BOTTOMRIGHT", -1, 0)
  row.selectionHighlight:SetTexture(0.2, 0.65, 0.25, 0.22)
  row.selectionHighlight:Hide()

  row.shareButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.shareButton:SetWidth(44)
  row.shareButton:SetHeight(22)
  row.shareButton:SetPoint("LEFT", row, "LEFT", 700, 0)
  row.shareButton:SetFrameLevel(row:GetFrameLevel() + 2)
  row.shareButton:SetText("Share")

  row.showMapButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.showMapButton:SetWidth(36)
  row.showMapButton:SetHeight(20)
  row.showMapButton:SetPoint("LEFT", row, "LEFT", 750, 0)
  row.showMapButton:SetFrameLevel(row:GetFrameLevel() + 2)
  row.showMapButton:EnableMouse(true)
  row.showMapButton:SetText("Map")

  row.findButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.findButton:SetWidth(22)
  row.findButton:SetHeight(22)
  row.findButton:SetPoint("LEFT", row, "LEFT", 800, 0)
  row.findButton:SetFrameLevel(row:GetFrameLevel() + 2)
  row.findButton:SetText("")
  row.findButton.icon = row.findButton:CreateTexture(nil, "ARTWORK")
  row.findButton.icon:SetSize(14, 14)
  row.findButton.icon:SetPoint("CENTER")
  row.findButton.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
  row.findButton:SetScript("OnEnter", function(button)
    if not button:IsShown() or not GameTooltip then return end
    GameTooltip:SetOwner(button, "ANCHOR_TOP")
    GameTooltip:SetText("Find previous item")
    GameTooltip:Show()
  end)
  row.findButton:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)

  return row
end

local function createTableHeader(parent, text, key, x, width)
  local header = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  header:SetPoint("TOPLEFT", x, 0)
  header:SetSize(width, 22)
  header.label = text
  header.sortKey = key
  header.sortArrow = header:CreateTexture(nil, "OVERLAY")
  header.sortArrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
  header.sortArrow:SetSize(10, 10)
  header.sortArrow:SetPoint("CENTER", header, "RIGHT", -11, 0)
  header.sortArrow:Hide()
  header:SetScript("OnClick", function()
    closeFilterDropdown()
    if SearchUI.sortKey == key then
      SearchUI.sortAscending = not SearchUI.sortAscending
    else
      SearchUI.sortKey = key
      SearchUI.sortAscending = key ~= "quality"
    end
    SearchUI.page = 1
    SearchUI:UpdateHeaderSortState()
    SearchUI:Refresh()
  end)
  return header
end

local function safeSortNumber(value, fallback)
  local number = tonumber(value)
  if not number or number ~= number then
    return fallback or 0
  end
  return number
end

function SearchUI:UpdateHeaderSortState()
  for _, header in ipairs((self.frame and self.frame.headers) or {}) do
    local active = header.sortKey == self.sortKey
    header:SetText(header.label)
    if header.sortArrow then
      if active then
        -- Use the same atlas region for both directions. Flipping its vertical
        -- coordinates avoids the position shift caused by texture rotation.
        if self.sortAscending then
          header.sortArrow:SetTexCoord(0, 0.5, 1, 0.5)
        else
          header.sortArrow:SetTexCoord(0, 0.5, 0.5, 1)
        end
        header.sortArrow:Show()
      else
        header.sortArrow:Hide()
      end
    end
    local fontString = header.GetFontString and header:GetFontString()
    if fontString and fontString.SetTextColor then
      if active then
        fontString:SetTextColor(1, 0.82, 0, 1)
      else
        fontString:SetTextColor(0.75, 0.75, 0.75, 1)
      end
    end
  end
end

local function selectionKey(result)
  return result and (result.itemKey or string.format("%s:%s:%s", tostring(result.itemId or "?"), tostring(result.itemLevel or 0), tostring(result.upgradeCost or 0)))
end

local function isUpgradeResult(result)
  return result and (result.isUpgrade == true
    or (tonumber(result.upgradeLevel or 0) or 0) > 0
    or result.upgradeCost ~= nil)
end

function SearchUI:UpdateDynamicColumns(query)
  local frame = self.frame
  if not frame or not frame.headers then return end
  local statNames = {}
  for index = 1, 4 do
    local selected = self.filters and self.filters["stat" .. index]
    if selected and selected ~= "" then statNames[#statNames + 1] = string.lower(selected) end
  end
  for _, quoted in ipairs(getQuotedStatNames(query)) do
    if #statNames >= 4 then break end
    statNames[#statNames + 1] = quoted
  end
  local baseX = 320
  local statWidth = 55
  local qualityHeader = frame.qualityHeader
  if qualityHeader then
    qualityHeader:SetShown(#statNames == 0)
  end
  for index, header in ipairs(frame.statHeaders or {}) do
    local active = statNames[index]
    if index == 1 and #statNames > 0 then
      local labels = {}
      for _, statName in ipairs(statNames) do labels[#labels + 1] = getStatAbbreviation(statName) end
      header.label = table.concat(labels, "   |   ")
    else
      header.label = ""
    end
    header:SetText(header.label)
    header:SetShown(index == 1 and #statNames > 0)
    if index == 1 and #statNames > 0 then
      header:SetPoint("TOPLEFT", baseX, 0)
      header:SetWidth(statWidth * #statNames)
    end
  end
  local locationX = baseX + (#statNames * statWidth)
  if #statNames == 0 then locationX = 405 end
  local actionX = 700
  local locationWidth = math.max(120, actionX - locationX - 8)
  frame.locationHeader:SetPoint("TOPLEFT", locationX, 0)
  frame.locationHeader:SetWidth(locationWidth)
  for _, row in ipairs(self.rows or {}) do
    row.locationText:SetPoint("LEFT", row, "LEFT", locationX, 0)
    row.locationText:SetWidth(locationWidth)
    row.qualityText:SetShown(#statNames == 0)
    for index, statText in ipairs(row.statTexts or {}) do
      if statNames[index] then
        statText:SetText("")
        statText:SetWidth(statWidth)
        statText:SetPoint("LEFT", row, "LEFT", baseX + ((index - 1) * statWidth), 0)
        statText:Show()
      else
        statText:Hide()
      end
    end
  end
  frame.dynamicStatNames = statNames
end

function SearchUI:UpdateRepairIndicator()
  local indicator = self.frame and self.frame.repairIndicator
  if not indicator then return end
  local state, pending = "idle", 0
  if addon.ItemScan and addon.ItemScan.GetRepairStatus then
    state, pending = addon.ItemScan:GetRepairStatus()
  end
  if state == "active" then
    indicator:SetText(string.format("Loading item data... %d remaining", pending))
    indicator:SetTextColor(1, 0.82, 0, 1)
    indicator:Show()
  else
    indicator:Hide()
  end
end

local function configureRow(row)
  row:SetScript("OnMouseUp", function(clickedRow, button)
    closeFilterDropdown()
    if not clickedRow.result or not isUpgradeResult(clickedRow.result) then return end
    local key = selectionKey(clickedRow.result)
    if button == "RightButton" then
      SearchUI.selectedUpgrades[key] = nil
      SearchUI:Refresh()
    end
  end)
  row:SetScript("OnClick", function(clickedRow)
    closeFilterDropdown()
    if clickedRow.result then
      local clicked = clickedRow.result
      addon:LootDebug(string.format(
        "Search click: name=%s itemId=%s source=%s mapId=%s zone=%s x=%s y=%s",
        tostring(clicked.itemName or "?"),
        tostring(clicked.itemId or "?"),
        tostring(clicked.lastSource or "?"),
        tostring(clicked.lastMapId or "?"),
        tostring(clicked.lastZoneName or clicked.lastZone or "?"),
        tostring(clicked.lastX or "?"),
        tostring(clicked.lastY or "?")
      ))
      if IsControlKeyDown and IsControlKeyDown() and clickedRow.result.itemLink and DressUpItemLink then
        addon:LootDebug("Search click opened dress room.")
        DressUpItemLink(clickedRow.result.itemLink)
        return
      end
      if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink and clickedRow.result.itemLink then
        addon:LootDebug("Search click inserted item link into chat.")
        ChatEdit_InsertLink(buildChatItemLink(clickedRow.result))
        return
      end
      if isUpgradeResult(clickedRow.result) then
        SearchUI.selectedUpgrades[selectionKey(clickedRow.result)] = true
        SearchUI:Refresh()
      end
      SearchUI:SetSelectedResult(clickedRow.result)
    end
  end)
  row:SetScript("OnEnter", function(hoveredRow)
    if hoveredRow.result and hoveredRow.result.itemLink then
      GameTooltip:SetOwner(hoveredRow, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink(hoveredRow.result.itemLink)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function SearchUI:EnsureRows(count)
  count = count or 0
  self.rows = self.rows or {}
  for index = #self.rows + 1, count do
    self.rows[index] = createRow(self.frame.content, index)
    configureRow(self.rows[index])
    self:ApplyElvUIRowSkin(self.rows[index])
  end
  if self.frame and self.frame.content then
    local viewportHeight = self.frame.scroll and self.frame.scroll:GetHeight() or 0
    local viewportWidth = self.frame.scroll and self.frame.scroll:GetWidth() or 0
    if viewportWidth > 0 then
      self.frame.content:SetWidth(viewportWidth)
    end
    self.frame.content:SetHeight(math.max(viewportHeight, 2 + (count * 30)))
  end
end

function SearchUI:ApplyElvUIRowSkin(row)
  if not row then return end
  local E = _G.ElvUI and _G.ElvUI[1]
  local S = E and E.GetModule and E:GetModule("Skins", true)
  if not S then return end
  if S.HandleButton then
    S:HandleButton(row.shareButton)
    S:HandleButton(row.showMapButton)
    S:HandleButton(row.findButton)
  end
end

function SearchUI:HighlightResult(result)
  if not result then return end
  for _, row in ipairs(self.rows or {}) do
    if row.result and (row.result.fingerprint == result.fingerprint or row.result.itemKey == result.itemKey) then
      row.searchHighlight:Show()
      if C_Timer and C_Timer.After then
        C_Timer.After(3, function()
          if row.searchHighlight then row.searchHighlight:Hide() end
        end)
      end
      return
    end
  end
end

function SearchUI:SearchForSource(result)
  if not result then return end
  local sourceName = result.sourceItemName or result.resolvedSourceItemName or result.itemName
  local sourceKey = result.sourceItemKey or result.resolvedSourceItemKey
  self.filters = {}
  for kind, button in pairs(self.frame.filters or {}) do
    self.filters[kind] = ""
    button.value = ""
    button:SetText(filterLabel("", kind))
  end
  local quotedSourceName = sourceName and ('"' .. tostring(sourceName):gsub('"', '') .. '"') or ""
  self.frame.editBox:SetText(quotedSourceName)
  self:Refresh(quotedSourceName)
  local targetLevel = tonumber(result.itemLevel or result.effectiveLevel or 0) or 0
  local bestPrevious
  local directPrevious
  for _, row in ipairs(self.rows or {}) do
    if row.result then
      local candidate = row.result
      local candidateLevel = tonumber(candidate.itemLevel or candidate.effectiveLevel or 0) or 0
      local sameItem = candidate.itemName == sourceName
      local directMatch = sourceKey and candidate.itemKey == sourceKey
      if directMatch then
        directPrevious = candidate
      elseif sameItem and candidateLevel < targetLevel
        and (not bestPrevious or candidateLevel > (tonumber(bestPrevious.itemLevel or bestPrevious.effectiveLevel or 0) or 0)) then
        bestPrevious = candidate
      end
    end
  end
  bestPrevious = bestPrevious or directPrevious
  if bestPrevious then self:HighlightResult(bestPrevious) end
end

function SearchUI:SetSelectedResult(result)
  self.selectedResult = result
  if not self.frame then
    return
  end

  if not result then
    return
  end
end

function SearchUI:Refresh(query)
  self:UpdateDynamicColumns(query or (self.frame and self.frame.editBox and self.frame.editBox:GetText()) or "")
  if not self.rows then
    return
  end

  if self.frame and self.frame.scroll then
    self.frame.scroll:SetVerticalScroll(0)
  end

  local filters = self.filters or {}
  local results = addon.DB:SearchItems(query or (self.frame and self.frame.editBox and self.frame.editBox:GetText()) or "", filters)
  local compactResults = {}
  for _, result in pairs(results or {}) do
    if result then compactResults[#compactResults + 1] = result end
  end
  results = compactResults
  local key = self.sortKey or "name"
  local ascending = self.sortAscending ~= false
  for index, result in ipairs(results) do
    local value, rank
    if key == "level" then
      value = safeSortNumber(result.itemLevel)
    elseif key == "quality" then
      value = safeSortNumber(result.quality)
    elseif key == "location" then
      local isUpgrade = result.isUpgrade == true
        or (tonumber(result.upgradeLevel or 0) or 0) > 0
        or result.upgradeCost ~= nil
      local location = getLocationText(result)
      local missing = not isUpgrade and location == "-"
      rank = missing and 3 or (isUpgrade and 1 or 2)
      value = isUpgrade and safeSortNumber(result.upgradeCost, -1) or location
    elseif key == "upgrade" then
      value = safeSortNumber(result.upgradeLevel)
    elseif key:match("^stat%d$") then
      local statIndex = tonumber(key:match("%d+"))
      local statName = self.frame and self.frame.dynamicStatNames and self.frame.dynamicStatNames[statIndex]
        value = statName and safeSortNumber(getStatValue(result, statName), -1) or -1
    elseif key == "stats" then
      local values = {}
      for _, statName in ipairs(self.frame.dynamicStatNames or {}) do
        values[#values + 1] = string.format("%010d", safeSortNumber(getStatValue(result, statName), -1) + 1)
      end
      value = table.concat(values, ":")
    else
      value = string.lower(tostring(result.itemName or ""))
    end
    result._searchSortRank = rank or 0
    result._searchSortValue = value
    result._searchSortIndex = index
    local valueToken
    if type(value) == "number" then
      valueToken = string.format("%020.6f", value + 1000000000)
    else
      valueToken = tostring(value or "")
    end
    result._searchSortToken = string.format(
      "%03d:%s:%s:%010d:%010d",
      result._searchSortRank,
      valueToken,
      string.lower(tostring(result.itemName or "")),
      safeSortNumber(result.itemId),
      index
    )
  end
  table.sort(results, function(left, right)
    if left._searchSortToken == right._searchSortToken then return false end
    if ascending then return left._searchSortToken < right._searchSortToken end
    return left._searchSortToken > right._searchSortToken
  end)
  for _, result in ipairs(results) do
    result._searchSortRank = nil
    result._searchSortValue = nil
    result._searchSortIndex = nil
    result._searchSortToken = nil
  end
  self.allResults = results
  local pageCount = math.max(1, math.ceil(#results / self.pageSize))
  self.page = math.min(math.max(self.page or 1, 1), pageCount)
  local first = ((self.page - 1) * self.pageSize) + 1
  local last = math.min(first + self.pageSize - 1, #results)
  local pageResults = {}
  for index = first, last do
    pageResults[#pageResults + 1] = results[index]
  end
  self.results = pageResults
  local selectedTotal = 0
  for _, result in ipairs(results) do
    if isUpgradeResult(result) and self.selectedUpgrades[selectionKey(result)] then
      selectedTotal = selectedTotal + safeSortNumber(result.upgradeCost)
    end
  end
  if self.frame and self.frame.upgradeTotal then
    self.frame.upgradeTotal:SetText(string.format("Selected: %6d", selectedTotal))
    if self.frame.upgradeTotalIcon then
      self.frame.upgradeTotalIcon.itemLink = GetItemInfo and select(2, GetItemInfo(375250)) or nil
    end
  end
  if self.frame and self.frame.pageLabel then
    if #results > 0 then
      self.frame.pageLabel:SetText(string.format("Items %d-%d / %d", first, last, #results))
    else
      self.frame.pageLabel:SetText("Items 0 / 0")
    end
    self.frame.previousPage:SetEnabled(self.page > 1)
    self.frame.nextPage:SetEnabled(self.page < pageCount)
  end
  self:UpdateHeaderSortState()
  self:EnsureRows(#pageResults)
  for index, row in ipairs(self.rows) do
    local result = pageResults[index]
    if result then
      row.result = result
      if row.selectionHighlight then
        row.selectionHighlight:SetShown(isUpgradeResult(result) and self.selectedUpgrades[selectionKey(result)] == true)
      end
      row:SetAlpha(isForeignRealm(result) and 0.45 or 1)
      local upgradeText = formatUpgradeCost(result.upgradeCost, result.upgradeCurrency)
      local canShareLocation = hasUsableLocation(result)
      -- Bags and some utility items legitimately have item level 0.  That is
      -- not the same as item data still being unavailable.
      local metadataPending = not result.itemName or result.itemName == ""
        or not result.quality or result.quality < 0
      row.nameText:SetText(string.format(
        "%s%s|r",
        metadataPending and "|cffaaaaaa" or getQualityColorCode(result.quality),
        result.itemName or (result.itemId and ("Item #" .. tostring(result.itemId)) or "Unknown item")
      ))
      local icon = result.itemTexture
      if not icon and result.itemId and GetItemIcon then icon = GetItemIcon(result.itemId) end
      row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
      row.levelText:SetText(metadataPending and "-" or tostring(result.itemLevel or 0))
      row.qualityText:SetText(metadataPending and "-" or getQualityName(result.quality))
      for statIndex, statName in ipairs(self.frame.dynamicStatNames or {}) do
        if row.statTexts and row.statTexts[statIndex] then
          row.statTexts[statIndex]:SetText(getStatValue(result, statName))
        end
      end
      local isUpgrade = result.isUpgrade == true
        or (tonumber(result.upgradeLevel or 0) or 0) > 0
        or result.upgradeCost ~= nil
      -- Action controls are recycled between rows. Always reset their state
      -- before showing the one valid action for the current result.
      row.findButton:Hide()
      row.shareButton:Hide()
      row.showMapButton:Hide()
      row.findButton:SetText("")
      row.shareButton:SetText("")
      row.showMapButton:SetText("")
      row.findButton:SetScript("OnClick", nil)
      row.shareButton:SetScript("OnClick", nil)
      row.showMapButton:SetScript("OnClick", nil)
      row.showMapButton:SetScript("OnMouseUp", nil)
      if isUpgrade then
        row.locationText:SetText(upgradeText or "unknown cost")
        row.locationText:SetJustifyH("RIGHT")
        row.locationText:SetWidth(self.frame.locationHeader:GetWidth())
        row.shareButton:ClearAllPoints()
        row.shareButton:SetPoint("LEFT", row, "LEFT", 700, 0)
        row.showMapButton:ClearAllPoints()
        row.showMapButton:SetPoint("LEFT", row, "LEFT", 750, 0)
        row.findButton:ClearAllPoints()
        row.findButton:SetPoint("LEFT", row, "LEFT", 800, 0)
        if result.upgradeCurrency == "rune" and GetItemIcon then
          local currencyId = 375250
          row.currencyButton.texture:SetTexture(GetItemIcon(currencyId) or "Interface\\Icons\\INV_Misc_QuestionMark")
          row.currencyButton.itemLink = GetItemInfo and select(2, GetItemInfo(currencyId)) or nil
          row.currencyButton.count:SetText("")
          row.currencyButton.count:Hide()
          row.currencyButton:ClearAllPoints()
          row.locationText:SetWidth(self.frame.locationHeader:GetWidth() - 20)
          row.currencyButton:SetPoint("LEFT", row.locationText, "RIGHT", 4, 0)
          row.currencyButton:Show()
        else
          row.currencyButton:Hide()
        end
      else
        local locationText = getLocationText(result)
        row.locationText:SetText(locationText)
        if result.zoneRepairPending and locationText == "unknown zone" then
          row.locationText:SetTextColor(0.55, 0.55, 0.55)
        else
          row.locationText:SetTextColor(1, 0.82, 0)
        end
        row.locationText:SetJustifyH("LEFT")
        row.locationText:SetWidth(self.frame.locationHeader:GetWidth())
        row.findButton:ClearAllPoints()
        row.findButton:SetPoint("LEFT", row, "LEFT", 800, 0)
        row.currencyButton:Hide()
      end
      if isUpgrade then
        row.findButton:SetScript("OnClick", function()
          SearchUI:SearchForSource(result)
        end)
        row.findButton:SetText("")
        row.findButton:Show()
        row.shareButton:SetScript("OnClick", function()
          openChatWithText(buildUpgradeShareText(result))
        end)
        row.showMapButton:SetScript("OnClick", function()
          local source = getMapResult(result)
          addon:LootDebug(string.format("Search map click: itemId=%s sourceId=%s mapId=%s", tostring(result.itemId or "?"), tostring(source and source.itemId or "?"), tostring(source and source.lastMapId or "?")))
          if addon.MapNotes and source then addon.MapNotes:ShowOnMap(source, true) end
        end)
        row.shareButton:SetText("Share")
        row.showMapButton:SetText("Map")
        row.shareButton:Show()
        row.showMapButton:Show()
      elseif canShareLocation then
        row.shareButton:ClearAllPoints()
        row.shareButton:SetPoint("LEFT", row, "LEFT", 700, 0)
        row.showMapButton:ClearAllPoints()
        row.showMapButton:SetPoint("LEFT", row, "LEFT", 750, 0)
        row.shareButton:SetScript("OnClick", function()
          openChatWithText(buildShareText(result))
        end)
        row.showMapButton:SetScript("OnClick", function()
          addon:LootDebug(string.format("Search map click: itemId=%s", tostring(result.itemId or "?")))
          if addon.MapNotes then addon.MapNotes:ShowOnMap(result, true) end
        end)
        row.shareButton:SetText("Share")
        row.showMapButton:SetText("Map")
        row.shareButton:Show()
        row.showMapButton:Show()
      end
      row:Show()
    else
      row.result = nil
      if row.selectionHighlight then row.selectionHighlight:Hide() end
      row:SetAlpha(1)
      row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      row.findButton:Hide()
      row.shareButton:Hide()
      row.showMapButton:Hide()
      row:Hide()
    end
  end

  self:SetSelectedResult(pageResults[1])
end

function SearchUI:ScheduleRefresh(query)
  if not C_Timer or not C_Timer.After then
    self:Refresh(query)
    return
  end
  self.searchRefreshToken = (self.searchRefreshToken or 0) + 1
  local token = self.searchRefreshToken
  C_Timer.After(0.12, function()
    if self.searchRefreshToken == token then
      self:Refresh(query)
    end
  end)
end

function SearchUI:SaveState()
  if not self.frame then return end
  local state = getUIState()
  local point, _, relativePoint, x, y = self.frame:GetPoint()
  state.point = point
  state.relativePoint = relativePoint
  state.x = x
  state.y = y
  state.width = self.frame:GetWidth()
  state.height = self.frame:GetHeight()
  state.query = self.frame.editBox and self.frame.editBox:GetText() or ""
  state.filters = {}
  for kind, button in pairs(self.frame.filters or {}) do
    state.filters[kind] = button.value or ""
  end
end

function SearchUI:RefreshSettings()
  if not self.frame then
    return
  end

  local settings = addon.DB:GetSettings()
  if self.frame.logsCheckbox then
    self.frame.logsCheckbox:SetChecked(settings.showDebugLogs and true or false)
  end
  if self.frame.autoConfirmCheckbox then
    self.frame.autoConfirmCheckbox:SetChecked(settings.autoConfirmWorldforged and true or false)
  end
  if self.frame.allMapItemsCheckbox then
    self.frame.allMapItemsCheckbox:SetChecked(WforgedDB.showAllMapItems and true or false)
  end
  if self.frame.sendGuildCheckbox then self.frame.sendGuildCheckbox:SetChecked(settings.sendGuildUpdates ~= false) end
  if self.frame.sendCollectorCheckbox then self.frame.sendCollectorCheckbox:SetChecked(settings.sendCollectorUpdates == true) end
  if self.frame.receiveCollectorCheckbox then self.frame.receiveCollectorCheckbox:SetChecked(settings.receiveCollectorUpdates == true) end
  if self.frame.receiveGuildCheckbox then self.frame.receiveGuildCheckbox:SetChecked(settings.receiveGuildUpdates ~= false) end
end

function SearchUI:ResetFilters()
  if not self.frame then return end
  self.page = 1
  self.suppressRefresh = true
  self.filters = {}
  for kind, button in pairs(self.frame.filters or {}) do
    self.filters[kind] = ""
    button.value = ""
    button:SetText(filterLabel("", kind))
    updateFilterVisual(button)
  end
  self.frame.editBox:SetText("")
  self.suppressRefresh = nil
  self:Refresh("")
end

function SearchUI:Toggle()
  if not self.frame then
    local frame = CreateFrame("Frame", "WforgedSearchFrame", UIParent)
    local state = getUIState()
    frame:SetSize(state.width or 920, state.height or 600)
    frame:SetPoint(state.point or "CENTER", UIParent, state.relativePoint or "CENTER", state.x or 0, state.y or 0)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function()
      closeFilterDropdown()
    end)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:HookScript("OnHide", function()
      SearchUI:SaveState()
    end)
    frame:Hide()
    table.insert(UISpecialFrames, "WforgedSearchFrame")

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    frame.bg:SetTexture(0, 0, 0, 0.85)

    frame.border = CreateFrame("Frame", nil, frame)
    frame.border:SetPoint("TOPLEFT", -1, 1)
    frame.border:SetPoint("BOTTOMRIGHT", 1, -1)
    frame.border:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 14,
    })
    frame.border:SetBackdropBorderColor(0.6, 0.8, 1, 1)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", 0, -14)
    frame.title:SetText("Wforged Search")

    local closeButton = CreateFrame("Button", nil, frame)
    if closeButton then
      closeButton:SetSize(24, 24)
      closeButton:SetPoint("TOPRIGHT", -4, -4)
      closeButton:SetNormalTexture(nil)
      closeButton:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
      closeButton:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
      closeButton.xText = closeButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
      closeButton.xText:SetPoint("CENTER", 0, 0)
      closeButton.xText:SetText("X")
      closeButton.xText:SetTextColor(1, 1, 1, 1)
      closeButton:SetScript("OnClick", function() frame:Hide() end)
      frame.closeButton = closeButton
    end

    frame.settingsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.settingsButton:SetSize(78, 22)
    frame.settingsButton:SetPoint("TOPRIGHT", -34, -40)
    frame.settingsButton:SetText("Settings")

    local editBox = CreateFrame("EditBox", nil, frame)
    editBox:SetSize(240, 24)
    editBox:SetPoint("TOPLEFT", 16, -40)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetScript("OnEscapePressed", function()
      editBox:ClearFocus()
    end)
    editBox:SetScript("OnMouseUp", function(box, button)
      if button == "RightButton" then
        box:SetText("")
        box:ClearFocus()
      end
    end)
    editBox:SetScript("OnTextChanged", function(box)
      if not SearchUI.suppressRefresh then
        local cleaned, statValues = quotedFilterStats(box:GetText())
        if #statValues > 0 then
          SearchUI.suppressRefresh = true
          for index, statValue in ipairs(statValues) do
            local kind = "stat" .. index
            SearchUI.filters[kind] = statValue
            local button = frame.filters and frame.filters[kind]
            if button then
              button.value = statValue
              button:SetText(filterLabel(statValue, kind))
              updateFilterVisual(button)
            end
          end
          box:SetText(cleaned)
          SearchUI.suppressRefresh = false
        end
        SearchUI.page = 1
        SearchUI:ScheduleRefresh(cleaned or box:GetText())
      end
    end)
    frame.editBox = editBox
    editBox:SetText(state.query or "")
    editBox:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 12,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    editBox:SetBackdropColor(0.02, 0.02, 0.02, 0.9)
    editBox:SetBackdropBorderColor(0.35, 0.45, 0.55, 1)
    editBox:SetTextColor(1, 1, 1, 1)

    self.filters = {}
    frame.filters = {}
    local filterKinds = {"armorType", "weaponType", "slot", "quality", "stat1", "stat2", "stat3", "stat4", "level", "variant"}
    for index, kind in ipairs(filterKinds) do
      local filterRow = index <= 4 and 0 or (index <= 8 and 1 or 2)
      local filterColumn = (index - 1) % 4
      frame.filters[kind] = createFilter(frame, kind, 16 + (filterColumn * 150), -70 - (filterRow * 32))
      self.filters[kind] = state.filters and state.filters[kind] or ""
      frame.filters[kind].value = self.filters[kind]
      frame.filters[kind]:SetText(filterLabel(self.filters[kind], kind))
      updateFilterVisual(frame.filters[kind])
      local originalClick = frame.filters[kind]:GetScript("OnClick")
      frame.filters[kind]:SetScript("OnClick", function(button)
        self.filters[kind] = button.value or ""
        originalClick(button)
      end)
    end

    frame.selectAllUpgrades = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.selectAllUpgrades:SetSize(82, 22)
    frame.selectAllUpgrades:SetPoint("TOPLEFT", 610, -166)
    frame.selectAllUpgrades:SetText("Select all")
    frame.selectAllUpgrades:SetScript("OnClick", function()
      closeFilterDropdown()
      for _, result in ipairs(SearchUI.allResults or {}) do
        if isUpgradeResult(result) then
          SearchUI.selectedUpgrades[selectionKey(result)] = true
        end
      end
      SearchUI:Refresh()
    end)
    frame.clearSelectedUpgrades = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.clearSelectedUpgrades:SetSize(62, 22)
    frame.clearSelectedUpgrades:SetPoint("LEFT", frame.selectAllUpgrades, "RIGHT", 5, 0)
    frame.clearSelectedUpgrades:SetText("Clear")
    frame.clearSelectedUpgrades:SetScript("OnClick", function()
      closeFilterDropdown()
      SearchUI.selectedUpgrades = {}
      SearchUI:Refresh()
    end)
    frame.upgradeTotal = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.upgradeTotal:SetPoint("LEFT", frame.clearSelectedUpgrades, "RIGHT", 10, 0)
    frame.upgradeTotal:SetText("Selected: 0")
    frame.upgradeTotalIcon = CreateFrame("Button", nil, frame)
    frame.upgradeTotalIcon:SetSize(14, 14)
    frame.upgradeTotalIcon:SetPoint("LEFT", frame.upgradeTotal, "RIGHT", 5, 0)
    frame.upgradeTotalIcon.texture = frame.upgradeTotalIcon:CreateTexture(nil, "ARTWORK")
    frame.upgradeTotalIcon.texture:SetAllPoints()
    frame.upgradeTotalIcon.texture:SetTexture((GetItemIcon and GetItemIcon(375250)) or "Interface\\Icons\\INV_Misc_QuestionMark")
    frame.upgradeTotalIcon:SetScript("OnEnter", function(button)
      if not GameTooltip then return end
      GameTooltip:SetOwner(button, "ANCHOR_TOP")
      if button.itemLink and GameTooltip.SetHyperlink then
        GameTooltip:SetHyperlink(button.itemLink)
      else
        GameTooltip:SetText("Rune of Ascension")
      end
      GameTooltip:Show()
    end)
    frame.upgradeTotalIcon:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", editBox, "RIGHT", 12, 0)
    hint:SetText("Search by name, stats, level, or upgrade.")
    frame.repairIndicator = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.repairIndicator:SetPoint("LEFT", hint, "RIGHT", 12, 0)
    frame.repairIndicator:SetWidth(190)
    frame.repairIndicator:SetJustifyH("LEFT")
    frame.repairIndicator:Hide()

    frame.logsCheckbox = createCheckbox(frame, "Show logs")
    frame.logsCheckbox:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", -4, -42)
    frame.logsCheckbox:SetScript("OnClick", function(button)
      addon.DB:GetSettings().showDebugLogs = button:GetChecked() and true or false
    end)

    frame.autoConfirmCheckbox = createCheckbox(frame, "Auto-confirm Worldforged")
    frame.autoConfirmCheckbox:SetPoint("LEFT", frame.logsCheckbox, "RIGHT", 180, 0)
    frame.autoConfirmCheckbox:SetScript("OnClick", function(button)
      addon.DB:GetSettings().autoConfirmWorldforged = button:GetChecked() and true or false
      addon:LootDebug(string.format("AutoConfirm setting changed: enabled=%s", tostring(button:GetChecked() and true or false)))
      if not button:GetChecked() and addon.AutoConfirm then
        addon.AutoConfirm:SetLootContext(false)
      end
    end)

    frame.allMapItemsCheckbox = createCheckbox(frame, "Show all map items")
    frame.allMapItemsCheckbox:SetPoint("LEFT", frame.autoConfirmCheckbox, "RIGHT", 180, 0)
    frame.allMapItemsCheckbox:SetScript("OnClick", function(button)
      WforgedDB.showAllMapItems = button:GetChecked() and true or false
      if addon.MapNotes and addon.MapNotes.RefreshAllMarkers then
        addon.MapNotes:RefreshAllMarkers()
      end
    end)

    frame.sendGuildCheckbox = createCheckbox(frame, "Send guild updates")
    frame.sendGuildCheckbox:SetPoint("TOPLEFT", frame.logsCheckbox, "BOTTOMLEFT", -4, -8)
    frame.sendGuildCheckbox:SetScript("OnClick", function(button)
      addon.DB:GetSettings().sendGuildUpdates = button:GetChecked() and true or false
    end)
    frame.receiveGuildCheckbox = createCheckbox(frame, "Receive guild updates")
    frame.receiveGuildCheckbox:SetPoint("LEFT", frame.sendGuildCheckbox, "RIGHT", 180, 0)
    frame.receiveGuildCheckbox:SetScript("OnClick", function(button)
      addon.DB:GetSettings().receiveGuildUpdates = button:GetChecked() and true or false
    end)
    frame.sendCollectorCheckbox = createCheckbox(frame, "Send friend updates")
    frame.sendCollectorCheckbox:SetPoint("TOPLEFT", frame.sendGuildCheckbox, "BOTTOMLEFT", 0, -8)
    frame.sendCollectorCheckbox:SetScript("OnClick", function(button)
      addon.DB:GetSettings().sendCollectorUpdates = button:GetChecked() and true or false
    end)
    frame.receiveCollectorCheckbox = createCheckbox(frame, "Receive friend updates")
    frame.receiveCollectorCheckbox:SetPoint("TOPLEFT", frame.receiveGuildCheckbox, "BOTTOMLEFT", 0, -8)
    frame.receiveCollectorCheckbox:SetScript("OnClick", function(button)
      local enabled = button:GetChecked() and true or false
      addon.DB:GetSettings().receiveCollectorUpdates = enabled
      if addon.Sync then addon.Sync.collectorEnabled = enabled end
    end)

    frame.sharePartyButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.sharePartyButton:SetSize(180, 22)
    frame.sharePartyButton:SetPoint("TOPLEFT", frame.receiveCollectorCheckbox, "BOTTOMLEFT", 20, -12)
    frame.sharePartyButton:SetText("Share database with party")
    frame.sharePartyButton:SetScript("OnClick", function()
      local targetName = UnitName and UnitName("target") or nil
      if not targetName or not UnitIsPlayer or not UnitIsPlayer("target") then
        addon:Print("Target a party member before sharing the database.")
        return
      end
      if UnitInParty and not UnitInParty("target") and UnitInRaid and not UnitInRaid("target") then
        addon:Print("The target must be in your party or raid.")
        return
      end
      if addon.Sync and addon.Sync.ShareDatabaseWithParty then addon.Sync:ShareDatabaseWithParty(targetName) end
    end)

    frame.resetButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.resetButton:SetSize(90, 22)
    frame.resetButton:SetPoint("TOPRIGHT", -42, -106)
    frame.resetButton:SetText("Reset filters")
    frame.resetButton:SetScript("OnClick", function()
      SearchUI:ResetFilters()
    end)

    frame.dataBox = CreateFrame("EditBox", nil, frame)
    frame.dataBox:SetSize(260, 22)
    frame.dataBox:SetPoint("TOPLEFT", 16, -140)
    frame.dataBox:SetAutoFocus(false)
    frame.dataBox:SetTextColor(1, 1, 1, 1)
    frame.dataBox:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Buttons\\WHITE8X8",
      edgeSize = 1,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame.dataBox:SetBackdropColor(0.02, 0.02, 0.02, 0.95)
    frame.dataBox:SetBackdropBorderColor(0.28, 0.32, 0.36, 1)
    frame.dataBox:SetFontObject(GameFontHighlightSmall)

    frame.exportButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.exportButton:SetSize(58, 22)
    frame.exportButton:SetPoint("LEFT", frame.dataBox, "RIGHT", 8, 0)
    frame.exportButton:SetText("Export")
    frame.exportButton:SetScript("OnClick", function()
      frame.dataBox:SetText(addon.Sync:Export() or "")
      frame.dataBox:SetWidth(400)
      frame.dataBox:SetFocus()
      frame.dataBox:HighlightText()
    end)

    frame.importButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.importButton:SetSize(58, 22)
    frame.importButton:SetPoint("LEFT", frame.exportButton, "RIGHT", 8, 0)
    frame.importButton:SetText("Import")
    frame.importButton:SetScript("OnClick", function()
      local count, err = addon.Sync:Import(frame.dataBox:GetText() or "")
      if err then addon:PrintError("Import failed: " .. tostring(err)) else addon:Print("Imported items: " .. tostring(count)) end
      SearchUI:Refresh()
    end)

    local settings = CreateFrame("Frame", "WforgedSettingsFrame", UIParent)
    settings:SetSize(560, 430)
    settings:SetPoint("CENTER")
    settings:SetFrameStrata("DIALOG")
    settings:EnableMouse(true)
    settings:SetMovable(true)
    settings:RegisterForDrag("LeftButton")
    settings:SetScript("OnDragStart", function(self) self:StartMoving() end)
    settings:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    settings:Hide()
    table.insert(UISpecialFrames, "WforgedSettingsFrame")
    settings.bg = settings:CreateTexture(nil, "BACKGROUND")
    settings.bg:SetAllPoints(settings)
    settings.bg:SetTexture(0, 0, 0, 0.9)
    settings.border = CreateFrame("Frame", nil, settings)
    settings.border:SetPoint("TOPLEFT", -1, 1)
    settings.border:SetPoint("BOTTOMRIGHT", 1, -1)
    settings.border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 })
    settings.border:SetBackdropBorderColor(0.6, 0.8, 1, 1)
    settings.title = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    settings.title:SetPoint("TOP", 0, -14)
    settings.title:SetText("Wforged Settings")
    if settings.title.EnableMouse then
      settings.title:EnableMouse(true)
      settings.title:SetScript("OnMouseDown", function() settings:StartMoving() end)
      settings.title:SetScript("OnMouseUp", function() settings:StopMovingOrSizing() end)
    end
    local settingsClose = CreateFrame("Button", nil, settings)
    settingsClose:SetSize(24, 24)
    settingsClose:SetPoint("TOPRIGHT", -4, -4)
    settingsClose:SetNormalTexture(nil)
    settingsClose.text = settingsClose:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    settingsClose.text:SetPoint("CENTER")
    settingsClose.text:SetText("X")
    settingsClose:SetScript("OnClick", function() settings:Hide() end)
    frame.settingsClose = settingsClose
    settings.devToggle = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    settings.devToggle:SetSize(38, 22)
    settings.devToggle:SetPoint("TOPRIGHT", -32, -5)
    settings.devToggle:SetText("Dev")

    for _, control in ipairs({ frame.logsCheckbox, frame.autoConfirmCheckbox, frame.allMapItemsCheckbox, frame.sendGuildCheckbox, frame.sendCollectorCheckbox, frame.receiveGuildCheckbox, frame.receiveCollectorCheckbox, frame.sharePartyButton, frame.dataBox, frame.exportButton, frame.importButton }) do
      control:SetParent(settings)
    end
    settings.dataBackground = CreateFrame("Frame", nil, settings)
    settings.dataBackground:SetSize(400, 100)
    settings.dataBackground:SetPoint("TOPLEFT", 18, -130)
    settings.dataBackground:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Buttons\\WHITE8X8",
      edgeSize = 1,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    settings.dataBackground:SetBackdropColor(0.02, 0.02, 0.02, 0.95)
    settings.dataBackground:SetBackdropBorderColor(0.28, 0.32, 0.36, 1)
    settings.dataScroll = CreateFrame("ScrollFrame", "WforgedSettingsDataScrollFrame", settings, "UIPanelScrollFrameTemplate")
    settings.dataScroll:SetPoint("TOPLEFT", settings.dataBackground, "TOPLEFT", 5, -5)
    settings.dataScroll:SetPoint("BOTTOMRIGHT", settings.dataBackground, "BOTTOMRIGHT", -22, 5)
    frame.dataBox:SetParent(settings.dataScroll)
    frame.dataBox:ClearAllPoints()
    frame.dataBox:SetAllPoints(settings.dataScroll)
    frame.dataBox:SetBackdrop(nil)
    settings.dataScroll:SetScrollChild(frame.dataBox)
    frame.logsCheckbox:SetPoint("TOPLEFT", 18, -48)
    frame.autoConfirmCheckbox:SetPoint("TOPLEFT", 300, -48)
    frame.allMapItemsCheckbox:SetPoint("TOPLEFT", 18, -48)
    frame.sendGuildCheckbox:SetPoint("TOPLEFT", 300, -88)
    frame.receiveGuildCheckbox:SetPoint("TOPLEFT", 18, -88)
    frame.sendCollectorCheckbox:SetPoint("TOPLEFT", 300, -128)
    frame.receiveCollectorCheckbox:SetPoint("TOPLEFT", 18, -128)
    frame.mapDebugButton = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    frame.mapDebugButton:SetSize(160, 22)
    frame.mapDebugButton:SetPoint("TOPLEFT", 300, -300)
    frame.mapDebugButton:SetText("Debug map context")
    frame.mapDebugButton:SetScript("OnClick", function()
      if addon.DebugMapContext then addon:DebugMapContext() end
    end)
    frame.resetDataButton = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    frame.resetDataButton:SetSize(160, 22)
    frame.resetDataButton:SetPoint("TOPLEFT", 300, -328)
    frame.resetDataButton:SetText("Reset data & Reload UI")
    frame.resetDataButton:SetScript("OnClick", function()
      StaticPopupDialogs.WFORGED_RESET_DATABASE = {
        text = "Reset all Wforged data and reload UI?",
        button1 = "Reset and reload",
        button2 = "Cancel",
        OnAccept = function()
          addon:ResetDatabase()
          ReloadUI()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
      }
      StaticPopup_Show("WFORGED_RESET_DATABASE")
    end)
    frame.importTestButton = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    frame.importTestButton:SetSize(160, 22)
    frame.importTestButton:SetPoint("TOPLEFT", 18, -328)
    frame.importTestButton:SetText("Import test data")
    frame.importTestButton:SetScript("OnClick", function()
      local count, err = addon.Sync:ImportLast()
      if err then addon:PrintError("Import failed: " .. tostring(err)) else addon:Print("Imported items: " .. tostring(count)) end
    end)
    frame.testBroadcastButton = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    frame.testBroadcastButton:SetSize(160, 22)
    frame.testBroadcastButton:SetPoint("TOPLEFT", 18, -128)
    frame.testBroadcastButton:SetText("Send test broadcast")
    frame.testBroadcastButton:SetScript("OnClick", function()
      if addon.Sync and addon.Sync.BroadcastTestItem then addon.Sync:BroadcastTestItem() end
    end)
    frame.testPartyButton = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    frame.testPartyButton:SetSize(180, 22)
    frame.testPartyButton:SetText("Test party share request")
    frame.testPartyButton:SetScript("OnClick", function()
      local playerName = UnitName and UnitName("player") or "TestPlayer"
      if addon.Sync and addon.Sync.OnAddonMessage then
        addon.Sync:OnAddonMessage("WFORGED", "WFGSHARE_REQ|local-test|TestSender|" .. playerName, "PARTY", "TestSender", true)
      end
      addon:Print("Local party-share request test triggered. No data was sent or changed.")
    end)
    settings.playerSection = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settings.playerSection:SetPoint("TOPLEFT", 18, -30)
    settings.playerSection:SetText("Player features")
    settings.debugSection = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settings.debugSection:SetPoint("TOPLEFT", 18, -268)
    settings.debugSection:SetText("Debug / maintenance")
    frame.logsCheckbox:SetPoint("TOPLEFT", 18, -300)
    frame.resetButton:SetParent(frame)
    frame.resetButton:SetPoint("TOPRIGHT", -42, -106)
    if frame.resetButton.GetFontString and frame.resetButton:GetFontString() then
      frame.resetButton:GetFontString():SetTextColor(1, 0.25, 0.25, 1)
    end
    frame.dataBox:SetMultiLine(true)
    frame.dataBox:SetMaxLetters(0)
    frame.dataBox:SetJustifyV("TOP")
    frame.dataBox:SetTextInsets(3, 3, 2, 2)
    frame.dataBox:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)
    frame.dataBox:SetScript("OnCursorChanged", function(box, _, y, _, cursorHeight)
      local offset = settings.dataScroll:GetVerticalScroll()
      local cursorTop = -y
      if cursorTop < offset then
        settings.dataScroll:SetVerticalScroll(cursorTop)
      elseif cursorTop + cursorHeight - settings.dataScroll:GetHeight() > offset then
        settings.dataScroll:SetVerticalScroll(cursorTop + cursorHeight - settings.dataScroll:GetHeight())
      end
    end)
    settings.dataScroll:HookScript("OnVerticalScroll", function(scrollFrame, offset)
      frame.dataBox:SetHitRectInsets(0, 0, offset, frame.dataBox:GetHeight() - offset - scrollFrame:GetHeight())
    end)
    frame.exportButton:SetPoint("TOPLEFT", 426, -130)
    frame.importButton:SetPoint("TOPLEFT", 426, -158)
    local debugControls = { settings.debugSection, frame.logsCheckbox, frame.mapDebugButton, frame.importTestButton, frame.resetDataButton, frame.testBroadcastButton, frame.testPartyButton }
    local playerControls = { settings.playerSection, frame.autoConfirmCheckbox, frame.allMapItemsCheckbox, frame.sendGuildCheckbox, frame.sendCollectorCheckbox, frame.receiveGuildCheckbox, frame.receiveCollectorCheckbox, frame.sharePartyButton, settings.dataBackground, settings.dataScroll, frame.exportButton, frame.importButton }
    local function setDebugVisible(visible)
      settings.debugVisible = visible and true or false
      for _, control in ipairs(debugControls) do
        if visible then control:Show() else control:Hide() end
      end
      for _, control in ipairs(playerControls) do
        if visible then control:Hide() else control:Show() end
      end
      if visible then
        settings.debugSection:SetPoint("TOPLEFT", 18, -42)
        frame.logsCheckbox:SetPoint("TOPLEFT", 18, -72)
        frame.mapDebugButton:SetPoint("TOPLEFT", 300, -72)
        frame.importTestButton:SetPoint("TOPLEFT", 18, -100)
        frame.resetDataButton:SetPoint("TOPLEFT", 300, -100)
        frame.testBroadcastButton:SetPoint("TOPLEFT", 18, -128)
        frame.testPartyButton:SetPoint("TOPLEFT", 300, -128)
      else
        settings.debugSection:SetPoint("TOPLEFT", 18, -268)
        frame.logsCheckbox:SetPoint("TOPLEFT", 18, -300)
        frame.mapDebugButton:SetPoint("TOPLEFT", 300, -300)
        frame.importTestButton:SetPoint("TOPLEFT", 18, -328)
        frame.resetDataButton:SetPoint("TOPLEFT", 300, -328)
        frame.allMapItemsCheckbox:SetPoint("TOPLEFT", 18, -48)
        frame.receiveGuildCheckbox:SetPoint("TOPLEFT", 18, -88)
        frame.sendCollectorCheckbox:SetPoint("TOPLEFT", 300, -128)
        frame.receiveCollectorCheckbox:SetPoint("TOPLEFT", 18, -128)
        settings.dataBackground:ClearAllPoints()
        settings.dataBackground:SetPoint("TOPLEFT", frame.sharePartyButton, "BOTTOMLEFT", -20, -18)
        frame.exportButton:ClearAllPoints()
        frame.exportButton:SetPoint("TOPLEFT", settings.dataBackground, "TOPRIGHT", 26, 0)
        frame.importButton:ClearAllPoints()
        frame.importButton:SetPoint("TOPLEFT", settings.dataBackground, "TOPRIGHT", 26, -28)
      end
      settings.devToggle:SetText(visible and "Player" or "Dev")
    end
    settings.devToggle:SetScript("OnClick", function()
      setDebugVisible(not settings.debugVisible)
    end)
    setDebugVisible(false)
    frame.settings = settings
    frame.settingsButton:SetScript("OnClick", function() settings:Show() end)
    settings:HookScript("OnShow", function()
      settings.dataScroll:SetVerticalScroll(0)
    end)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -230)
    scroll:SetPoint("BOTTOMRIGHT", -28, 42)

    local previousPage = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    previousPage:SetSize(28, 22)
    previousPage:SetPoint("BOTTOMLEFT", 16, 10)
    previousPage:SetText("<")
    previousPage:SetScript("OnClick", function()
      if SearchUI.page > 1 then
        SearchUI.page = SearchUI.page - 1
        SearchUI:Refresh()
      end
    end)
    local pageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pageLabel:SetPoint("BOTTOM", 0, 15)
    pageLabel:SetText("Items 0 / 0")
    local nextPage = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    nextPage:SetSize(28, 22)
    nextPage:SetPoint("BOTTOMRIGHT", -34, 10)
    nextPage:SetText(">")
    nextPage:SetScript("OnClick", function()
      local pageCount = math.max(1, math.ceil(#(SearchUI.allResults or {}) / SearchUI.pageSize))
      if SearchUI.page < pageCount then
        SearchUI.page = SearchUI.page + 1
        SearchUI:Refresh()
      end
    end)
    frame.previousPage = previousPage
    frame.pageLabel = pageLabel
    frame.nextPage = nextPage

    local headerFrame = CreateFrame("Frame", nil, frame)
    headerFrame:SetPoint("TOPLEFT", 20, -204)
    headerFrame:SetPoint("TOPRIGHT", -28, -204)
    headerFrame:SetHeight(24)
    frame.headers = {
      createTableHeader(headerFrame, "Item", "name", 0, 270),
      createTableHeader(headerFrame, "iLvl", "level", 270, 50),
      createTableHeader(headerFrame, "Quality", "quality", 320, 85),
      createTableHeader(headerFrame, "Location/Price", "location", 405, 263),
    }
    frame.qualityHeader = frame.headers[3]
    frame.locationHeader = frame.headers[4]
    frame.statHeaders = {}
    for index = 1, 4 do
      frame.statHeaders[index] = createTableHeader(headerFrame, "", index == 1 and "stats" or ("stat" .. index), 320 + ((index - 1) * 80), 80)
      frame.headers[#frame.headers + 1] = frame.statHeaders[index]
    end
    for _, header in ipairs(frame.statHeaders) do header:Hide() end
    self:UpdateHeaderSortState()

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(820, 930)
    scroll:SetScrollChild(content)
    frame.scrollBar = scroll.ScrollBar or (scroll.GetName and _G[scroll:GetName() .. "ScrollBar"])
    frame.scroll = scroll
    frame.content = content

    self.rows = {}
    self.frame = frame
    self:EnsureRows(0)

    self:SetSelectedResult(nil)
    self:ApplyElvUISkin(frame)
  end

  if self.frame:IsShown() then
    self.frame:Hide()
  else
    -- ElvUI can keep the map background behind addon panels while its controls
    -- remain visible. Close the map before showing the search window.
    if WorldMapFrame and WorldMapFrame:IsShown() then
      if HideUIPanel then
        HideUIPanel(WorldMapFrame)
      else
        WorldMapFrame:Hide()
      end
    end
    self:RefreshSettings()
    self.frame:Show()
    self.frame.editBox:SetText(self.frame.editBox:GetText() or "")
    self.frame.editBox:ClearFocus()
    self:Refresh(self.frame.editBox:GetText())
  end
end

function SearchUI:ToggleSettings()
  if not self.frame then
    self:Toggle()
    -- Toggle() creates the shared frame and opens the list on first use.
    -- Settings opened from the minimap should show only the settings panel.
    if self.frame then
      self.frame:Hide()
    end
  end
  if self.frame and self.frame.settings then
    self.frame.settings:Show()
  end
end

function SearchUI:ApplyElvUISkin(frame)
  if not frame or frame.elvUISkinned then return end
  local E = _G.ElvUI and _G.ElvUI[1]
  local S = E and E.GetModule and E:GetModule("Skins", true)
  if not S then return end
  -- ElvUI uses borderless windows; hide the addon's fallback border when active.
  if frame.border then frame.border:Hide() end
  if frame.settings and frame.settings.border then frame.settings.border:Hide() end
  if S.HandleFrame then S:HandleFrame(frame) end
  if S.HandleButton then
    -- Keep the close control native/custom; ElvUI skins hide it on this client.
    if frame.resetButton then S:HandleButton(frame.resetButton) end
    if frame.selectAllUpgrades then S:HandleButton(frame.selectAllUpgrades) end
    if frame.clearSelectedUpgrades then S:HandleButton(frame.clearSelectedUpgrades) end
    if frame.exportButton then S:HandleButton(frame.exportButton) end
    if frame.importButton then S:HandleButton(frame.importButton) end
    if frame.settingsButton then S:HandleButton(frame.settingsButton) end
    if frame.mapDebugButton then S:HandleButton(frame.mapDebugButton) end
    if frame.resetDataButton then S:HandleButton(frame.resetDataButton) end
    if frame.importTestButton then S:HandleButton(frame.importTestButton) end
    if frame.testBroadcastButton then S:HandleButton(frame.testBroadcastButton) end
    if frame.previousPage then S:HandleButton(frame.previousPage) end
    if frame.nextPage then S:HandleButton(frame.nextPage) end
    for _, row in ipairs(self.rows or {}) do self:ApplyElvUIRowSkin(row) end
    for _, header in ipairs(frame.headers or {}) do S:HandleButton(header) end
    for _, button in pairs(frame.filters or {}) do
      S:HandleButton(button)
    end
  end
  if S.HandleEditBox and frame.editBox then
    frame.editBox:SetBackdrop(nil)
    S:HandleEditBox(frame.editBox)
  end
  if S.HandleScrollBar and frame.settings and frame.settings.dataScroll then
    local scrollBar = frame.settings.dataScroll.ScrollBar or (frame.settings.dataScroll.GetName and _G[frame.settings.dataScroll:GetName() .. "ScrollBar"])
    if scrollBar then S:HandleScrollBar(scrollBar) end
  end
  if frame.settings and S.HandleFrame then S:HandleFrame(frame.settings) end
  if frame.settings and S.HandleButton then S:HandleButton(frame.settingsClose) end
  if frame.settings and frame.settings.devToggle and S.HandleButton then S:HandleButton(frame.settings.devToggle) end
  if S.HandleCheckBox then
    S:HandleCheckBox(frame.logsCheckbox)
    S:HandleCheckBox(frame.autoConfirmCheckbox)
    S:HandleCheckBox(frame.allMapItemsCheckbox)
    S:HandleCheckBox(frame.sendGuildCheckbox)
    S:HandleCheckBox(frame.sendCollectorCheckbox)
    S:HandleCheckBox(frame.receiveGuildCheckbox)
    S:HandleCheckBox(frame.receiveCollectorCheckbox)
    if S.HandleButton then S:HandleButton(frame.sharePartyButton) end
    if S.HandleButton then S:HandleButton(frame.testPartyButton) end
  end
  if frame.settings and frame.settings.dataBackground then
    frame.settings.dataBackground:SetSize(400, 100)
    if frame.resetButton and frame.resetButton.GetFontString and frame.resetButton:GetFontString() then
      frame.resetButton:GetFontString():SetTextColor(1, 0.25, 0.25, 1)
    end
  end
  if frame.closeButton then
    frame.closeButton:SetFrameStrata("DIALOG")
    frame.closeButton:SetFrameLevel(frame:GetFrameLevel() + 20)
    frame.closeButton:SetAlpha(1)
    frame.closeButton:Show()
  end
  if S.HandleScrollBar and frame.scrollBar then
    S:HandleScrollBar(frame.scrollBar)
  end
  frame.elvUISkinned = true
end
