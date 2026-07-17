local addonName, addon = ...

local SearchUI = {}
addon.SearchUI = SearchUI

local function getUIState()
  WforgedDB.searchUI = WforgedDB.searchUI or {}
  return WforgedDB.searchUI
end

local filterOptions = {
  armorType = {"", "Cloth", "Leather", "Mail", "Plate"},
  slot = {"", "Head", "Shoulder", "Chest", "Back", "Wrist", "Hands", "Waist", "Legs", "Feet", "Finger", "Trinket", "Neck", "Weapon", "Off Hand"},
  weaponType = {"", "Axe", "Bow", "Crossbow", "Dagger", "Fist", "Gun", "Mace", "Polearm", "Shield", "Staff", "Sword", "Two-Handed Axe", "Two-Handed Sword", "Two-Handed Mace", "Wand"},
  quality = {"", "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary"},
  stat1 = {"", "Strength", "Agility", "Intellect", "Spirit", "Stamina", "Crit", "Haste", "Mastery", "Versatility", "Spell Power"},
  stat2 = {"", "Strength", "Agility", "Intellect", "Spirit", "Stamina", "Crit", "Haste", "Mastery", "Versatility", "Spell Power"},
  level = {"", "base", "upgrade", "10", "20", "30", "40", "50", "60"},
}

local function filterLabel(value, kind)
  if value == "" then
    if kind == "level" then return "Any level" end
    if kind == "weaponType" then return "Any weapon" end
    if kind == "armorType" then return "Any armor type" end
    if kind == "quality" then return "Any quality" end
    return "Any " .. kind
  end
  if value == "base" then return "Base items" end
  if value == "upgrade" then return "Upgrades" end
  if kind == "level" then return "Level " .. value .. "+" end
  return value
end

local function createFilter(parent, kind, x, y)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(108, 22)
  button:SetPoint("TOPLEFT", x, y)
  button.kind = kind
  button.value = ""
  button:SetText(filterLabel("", kind))
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
    UIDropDownMenu_Initialize(menu, function(_, level)
      for _, value in ipairs(filterOptions[kind]) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = filterLabel(value, kind)
        info.checked = self.value == value
        info.func = function()
          self.value = value
          self:SetText(filterLabel(value, kind))
          if SearchUI.filters then SearchUI.filters[kind] = value end
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
    return tostring(cost) .. " Rune"
  end

  return tostring(cost) .. (currency and (" " .. tostring(currency)) or "")
end

local function getQualityColorCode(quality)
  if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
    return ITEM_QUALITY_COLORS[quality].hex
  end
  return "|cffffffff"
end

local function openChatWithText(text)
  if not text or text == "" then
    return
  end

  local editBox = ChatFrameEditBox
  if ChatEdit_ChooseBoxForSend then
    editBox = ChatEdit_ChooseBoxForSend() or editBox
  end
  if ChatEdit_ActivateChat then
    ChatEdit_ActivateChat(editBox)
  elseif editBox and editBox.Show then
    editBox:Show()
    editBox:SetFocus()
  end

  if editBox and editBox.SetText then
    editBox:SetText(text)
    if editBox.HighlightText then
      editBox:HighlightText(0, 0)
    end
    if editBox.SetCursorPosition then
      editBox:SetCursorPosition(string.len(text))
    end
  end
end

local function buildChatItemLink(result)
  if not result then
    return "item"
  end

  local itemLink = result.itemLink or result.itemName or "item"
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

  local zoneName = addon.ResolveZoneName and addon:ResolveZoneName(
    result.lastMapId,
    result.lastContinent,
    result.lastZone,
    result.lastZoneName
  ) or result.lastZoneName

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
  return string.format("%s - %s", buildChatItemLink(result), locationText)
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

  if result.lastX <= 0 or result.lastX >= 1 or result.lastY <= 0 or result.lastY >= 1 then
    return false
  end

  local zoneName = addon.ResolveZoneName and addon:ResolveZoneName(
    result.lastMapId,
    result.lastContinent,
    result.lastZone,
    result.lastZoneName
  ) or result.lastZoneName

  return (zoneName and zoneName ~= "") or (result.lastMapId ~= nil)
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
  row:SetPoint("TOPLEFT", 8, -8 - ((index - 1) * 30))
  row:SetPoint("TOPRIGHT", -28, -8 - ((index - 1) * 30))

  row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.nameText:SetPoint("LEFT", 0, 0)
  row.nameText:SetPoint("RIGHT", -166, 0)
  row.nameText:SetJustifyH("LEFT")

  row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
  row.highlight:SetAllPoints(row)
  row.highlight:SetTexture(1, 1, 1, 0.08)

  row.shareButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.shareButton:SetWidth(44)
  row.shareButton:SetHeight(22)
  row.shareButton:SetPoint("RIGHT", -138, 0)
  row.shareButton:SetText("Share")

  row.showMapButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.showMapButton:SetWidth(36)
  row.showMapButton:SetHeight(20)
  row.showMapButton:SetPoint("LEFT", row.shareButton, "RIGHT", 8, 0)
  row.showMapButton:SetText("Map")

  return row
end

local function configureRow(row)
  row:SetScript("OnClick", function(clickedRow)
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
      if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink and clickedRow.result.itemLink then
        addon:LootDebug("Search click inserted item link into chat.")
        ChatEdit_InsertLink(clickedRow.result.itemLink)
        return
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
    self.frame.content:SetHeight(math.max(930, 16 + (count * 30)))
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
  end
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
  if not self.rows then
    return
  end

  local filters = self.filters or {}
  local results = addon.DB:SearchItems(query or (self.frame and self.frame.editBox and self.frame.editBox:GetText()) or "", filters)
  self.results = results
  self:EnsureRows(#results)
  for index, row in ipairs(self.rows) do
    local result = results[index]
    if result then
      row.result = result
      local upgradeText = formatUpgradeCost(result.upgradeCost, result.upgradeCurrency)
      local canShareLocation = hasUsableLocation(result)
      local metadataPending = not result.itemLevel or result.itemLevel <= 0
        or not result.quality or result.quality < 0
      row.nameText:SetText(string.format(
        "%s%s|r %s%s",
        metadataPending and "|cffaaaaaa" or getQualityColorCode(result.quality),
        result.itemName,
        metadataPending and "|cffcc8844[loading item data...]|r" or string.format("|cff888888[ilvl %d]|r", result.itemLevel),
        upgradeText and (" |cffffcc66" .. upgradeText .. "|r") or ""
      ))
      if canShareLocation then
        row.shareButton:SetScript("OnClick", function()
          openChatWithText(buildShareText(result))
        end)
        row.showMapButton:SetScript("OnClick", function()
          if addon.MapNotes then
            addon.MapNotes:ShowOnMap(result, true)
          end
        end)
        row.shareButton:Show()
        row.showMapButton:Show()
      else
        row.shareButton:SetScript("OnClick", nil)
        row.showMapButton:SetScript("OnClick", nil)
        row.shareButton:Hide()
        row.showMapButton:Hide()
      end
      row:Show()
    else
      row.result = nil
      row.shareButton:Hide()
      row.showMapButton:Hide()
      row:Hide()
    end
  end

  self:SetSelectedResult(results[1])
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
  if self.frame.receiveGuildCheckbox then self.frame.receiveGuildCheckbox:SetChecked(settings.receiveGuildUpdates ~= false) end
end

function SearchUI:ResetFilters()
  if not self.frame then return end
  self.filters = {}
  for kind, button in pairs(self.frame.filters or {}) do
    self.filters[kind] = ""
    button.value = ""
    button:SetText(filterLabel("", kind))
  end
  self.frame.editBox:SetText("")
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
    editBox:SetScript("OnTextChanged", function(box)
      SearchUI:Refresh(box:GetText())
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
    local filterKinds = {"armorType", "weaponType", "slot", "quality", "stat1", "stat2", "level"}
    for index, kind in ipairs(filterKinds) do
      local filterRow = index <= 4 and 0 or 1
      local filterColumn = (index - 1) % 4
      frame.filters[kind] = createFilter(frame, kind, 16 + (filterColumn * 150), -70 - (filterRow * 32))
      self.filters[kind] = state.filters and state.filters[kind] or ""
      frame.filters[kind].value = self.filters[kind]
      frame.filters[kind]:SetText(filterLabel(self.filters[kind], kind))
      local originalClick = frame.filters[kind]:GetScript("OnClick")
      frame.filters[kind]:SetScript("OnClick", function(button)
        self.filters[kind] = button.value or ""
        originalClick(button)
      end)
    end

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("LEFT", editBox, "RIGHT", 12, 0)
    hint:SetText("Search by name, stats, level, or upgrade.")

    frame.logsCheckbox = createCheckbox(frame, "Show logs")
    frame.logsCheckbox:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", -4, -42)
    frame.logsCheckbox:SetScript("OnClick", function(button)
      addon.DB:GetSettings().showDebugLogs = button:GetChecked() and true or false
    end)

    frame.autoConfirmCheckbox = createCheckbox(frame, "Auto-confirm Worldforged")
    frame.autoConfirmCheckbox:SetPoint("LEFT", frame.logsCheckbox, "RIGHT", 180, 0)
    frame.autoConfirmCheckbox:SetScript("OnClick", function(button)
      addon.DB:GetSettings().autoConfirmWorldforged = button:GetChecked() and true or false
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

    for _, control in ipairs({ frame.logsCheckbox, frame.autoConfirmCheckbox, frame.allMapItemsCheckbox, frame.sendGuildCheckbox, frame.receiveGuildCheckbox, frame.dataBox, frame.exportButton, frame.importButton }) do
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
    local debugControls = { settings.debugSection, frame.logsCheckbox, frame.mapDebugButton, frame.importTestButton, frame.resetDataButton, frame.testBroadcastButton }
    local playerControls = { settings.playerSection, frame.autoConfirmCheckbox, frame.allMapItemsCheckbox, frame.sendGuildCheckbox, frame.receiveGuildCheckbox, settings.dataBackground, settings.dataScroll, frame.exportButton, frame.importButton }
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
      else
        settings.debugSection:SetPoint("TOPLEFT", 18, -268)
        frame.logsCheckbox:SetPoint("TOPLEFT", 18, -300)
        frame.mapDebugButton:SetPoint("TOPLEFT", 300, -300)
        frame.importTestButton:SetPoint("TOPLEFT", 18, -328)
        frame.resetDataButton:SetPoint("TOPLEFT", 300, -328)
        frame.allMapItemsCheckbox:SetPoint("TOPLEFT", 18, -48)
        frame.receiveGuildCheckbox:SetPoint("TOPLEFT", 18, -88)
        settings.dataBackground:SetPoint("TOPLEFT", 18, -130)
        frame.exportButton:SetPoint("TOPLEFT", 426, -130)
        frame.importButton:SetPoint("TOPLEFT", 426, -158)
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
    scroll:SetPoint("TOPLEFT", 12, -178)
    scroll:SetPoint("BOTTOMRIGHT", -28, 12)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(820, 930)
    scroll:SetScrollChild(content)
    frame.scrollBar = scroll.ScrollBar or (scroll.GetName and _G[scroll:GetName() .. "ScrollBar"])
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
    if frame.exportButton then S:HandleButton(frame.exportButton) end
    if frame.importButton then S:HandleButton(frame.importButton) end
    if frame.settingsButton then S:HandleButton(frame.settingsButton) end
    if frame.mapDebugButton then S:HandleButton(frame.mapDebugButton) end
    if frame.resetDataButton then S:HandleButton(frame.resetDataButton) end
    if frame.importTestButton then S:HandleButton(frame.importTestButton) end
    if frame.testBroadcastButton then S:HandleButton(frame.testBroadcastButton) end
    for _, row in ipairs(self.rows or {}) do self:ApplyElvUIRowSkin(row) end
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
    S:HandleCheckBox(frame.receiveGuildCheckbox)
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
