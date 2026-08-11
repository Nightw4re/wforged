local addonName, addon = ...

addon = addon or {}
_G[addonName] = addon

addon.name = addonName
addon.version = "1.4.1"
addon.debug = false
addon.AutoConfirm = addon.AutoConfirm or {}
addon.MinimapButton = addon.MinimapButton or {}
addon.MapNotes = addon.MapNotes or {}
addon.MapNotes.allMarkers = addon.MapNotes.allMarkers or {}

local eventFrame = CreateFrame("Frame")
addon.eventFrame = eventFrame

local function safeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    addon:PrintError(err)
  end
end

function addon:GetChatFrame()
  if type(DEFAULT_CHAT_FRAME) == "table" and DEFAULT_CHAT_FRAME.AddMessage then
    return DEFAULT_CHAT_FRAME
  end

  if type(ChatFrame1) == "table" and ChatFrame1.AddMessage then
    return ChatFrame1
  end

  return nil
end

function addon:Print(message)
  local chatFrame = self:GetChatFrame()
  if chatFrame then
    chatFrame:AddMessage("|cff33ff99Wforged|r " .. tostring(message))
  end
end

function addon:PrintError(message)
  local chatFrame = self:GetChatFrame()
  if chatFrame then
    chatFrame:AddMessage("|cffff5555Wforged error:|r " .. tostring(message))
  end
end

function addon:Debug(message)
  if self.debug then
    self:Print(message)
  end
end

function addon:LootDebug(message)
  local settings = self.DB and self.DB.GetSettings and self.DB:GetSettings()
  if settings and not settings.showDebugLogs then
    return
  end
  self:Print("|cffffff66[loot]|r " .. tostring(message))
end

function addon:GetPlayerPosition()
  if SetMapToCurrentZone then
    SetMapToCurrentZone()
  end

  local mapId = nil
  if GetCurrentMapAreaID then
    mapId = GetCurrentMapAreaID()
  elseif C_Map and C_Map.GetBestMapForUnit then
    mapId = C_Map.GetBestMapForUnit("player")
  end

  local x, y = GetPlayerMapPosition("player")
  if x == 0 and y == 0 then
    x = nil
    y = nil
  end
  return mapId, x, y
end

function addon:DebugMapContext()
  local inInstance, instanceType = IsInInstance and IsInInstance() or false, nil
  if IsInInstance then
    inInstance, instanceType = IsInInstance()
  end
  local mapId, x, y = self:GetPlayerPosition()
  local continent = GetCurrentMapContinent and GetCurrentMapContinent() or nil
  local zone = GetCurrentMapZone and GetCurrentMapZone() or nil
  local mapName = GetMapInfo and GetMapInfo() or nil
  self:Print(string.format(
    "Map debug: instance=%s type=%s realZone=%s zone=%s subZone=%s mapId=%s mapName=%s continent=%s zoneIndex=%s x=%s y=%s",
    tostring(inInstance), tostring(instanceType), tostring(GetRealZoneText and GetRealZoneText() or "?"),
    tostring(GetZoneText and GetZoneText() or "?"), tostring(GetSubZoneText and GetSubZoneText() or "?"),
    tostring(mapId), tostring(mapName), tostring(continent), tostring(zone), tostring(x), tostring(y)
  ))
  if GetMapZones then
    for continent = 1, 8 do
      local zones = { GetMapZones(continent) }
      for zone = 1, #zones do
        if zones[zone] == "The Deadmines" then
          self:Print(string.format("Map candidate: continent=%d zoneIndex=%d name=%s", continent, zone, zones[zone]))
        end
      end
    end
  end
end

function addon:NormalizeLootLocation(mapId, zoneName, x, y)
  -- Do not remap instances to an entrance: each item has only one stored map location.
  return mapId, zoneName, x, y, false
end

function addon:RegisterEvent(eventName, handler)
  eventFrame:RegisterEvent(eventName)
  eventFrame[eventName] = handler
end

function addon:ResolveZoneName(mapId, continent, zone, zoneName, allowCurrentFallback)
  local genericName = type(zoneName) == "string" and zoneName:match("^Map %d+$")
  if zoneName and zoneName ~= "" and not genericName then
    return zoneName
  end

  if continent and zone and continent > 0 and zone > 0 and GetMapZones then
    local zones = { GetMapZones(continent) }
    if zones[zone] and zones[zone] ~= "" then
      return zones[zone]
    end
  end

  if mapId and GetMapNameByID then
    local resolved = GetMapNameByID(mapId)
    if resolved and resolved ~= "" then
      return resolved
    end
  end

  if mapId and GetMapName then
    local resolved = GetMapName(mapId)
    if resolved and resolved ~= "" and not tostring(resolved):match("^Map %d+$") then
      return resolved
    end
  end

  -- GetMapInfo() is current-map-only on this client. It is safe to use only
  -- when the current map ID matches the requested one. Ascension's custom
  -- zone maps can expose the loaded detail map as mapId + 1.
  if allowCurrentFallback ~= false and mapId and GetCurrentMapAreaID and GetMapInfo
    and (tonumber(GetCurrentMapAreaID()) == tonumber(mapId)
      or tonumber(GetCurrentMapAreaID()) == tonumber(mapId) + 1) then
    if GetCurrentMapContinent and GetCurrentMapZone and GetMapZones then
      local currentContinent = GetCurrentMapContinent()
      local currentZone = GetCurrentMapZone()
      local zones = currentContinent and { GetMapZones(currentContinent) } or nil
      local localizedName = zones and currentZone and zones[currentZone] or nil
      if localizedName and localizedName ~= "" then
        return localizedName
      end
    end
    local currentName = GetMapInfo()
    if currentName and currentName ~= "" and not tostring(currentName):match("^Map %d+$") then
      return currentName
    end
  end

  return nil
end

function addon:DebugOpenMapZone()
  local mapId = GetCurrentMapAreaID and GetCurrentMapAreaID() or nil
  local continent = GetCurrentMapContinent and GetCurrentMapContinent() or nil
  local zone = GetCurrentMapZone and GetCurrentMapZone() or nil
  local mapName = GetMapInfo and GetMapInfo() or nil
  local zonesName = nil
  local zoneInfo = nil
  if continent and zone and GetMapZones then
    local zones = { GetMapZones(continent) }
    zonesName = zones[zone]
  end
  if continent and zone and GetMapZoneInfo then
    local ok, value = pcall(GetMapZoneInfo, continent, zone)
    if ok then zoneInfo = value end
  end
  local inInstance, instanceType = false, nil
  if IsInInstance then
    inInstance, instanceType = IsInInstance()
  end
  self:Print(string.format(
    "Open map zone: mapId=%s map=%s playerReal=%s playerZone=%s playerSubZone=%s continent=%s zoneIndex=%s indexedName=%s zoneInfo=%s instance=%s/%s dungeon=%s/%s",
    tostring(mapId), tostring(mapName or "?"),
    tostring(GetRealZoneText and GetRealZoneText() or "?"),
    tostring(GetZoneText and GetZoneText() or "?"),
    tostring(GetSubZoneText and GetSubZoneText() or "?"), tostring(continent or "?"),
    tostring(zone or "?"), tostring(zonesName or "?"), tostring(zoneInfo or "?"),
    tostring(inInstance), tostring(instanceType or "none"),
    tostring(GetCurrentMapDungeonLevel and GetCurrentMapDungeonLevel() or "?"),
    tostring(GetNumDungeonMapLevels and GetNumDungeonMapLevels() or "?")
  ))
  if continent and GetMapZones then
    local zones = { GetMapZones(continent) }
    self:Print("Open map zone list: " .. table.concat(zones, ", "))
  end
end

local function ensureMapPin()
  if addon.MapNotes.pin then
    return addon.MapNotes.pin
  end

  if not WorldMapDetailFrame then
    return nil
  end

  local pin = CreateFrame("Button", "WforgedMapPin", WorldMapFrame)
  pin:SetWidth(30)
  pin:SetHeight(30)
  pin:SetFrameStrata("HIGH")
  pin:SetFrameLevel(50)

  pin.shadow = pin:CreateTexture(nil, "BACKGROUND")
  pin.shadow:SetPoint("TOPLEFT", 1, -1)
  pin.shadow:SetPoint("BOTTOMRIGHT", -1, 1)
  pin.shadow:SetTexture(0, 0, 0, 0.85)

  pin.icon = pin:CreateTexture(nil, "ARTWORK")
  pin.icon:SetPoint("CENTER", 0, 0)
  pin.icon:SetWidth(20)
  pin.icon:SetHeight(20)
  pin.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

  pin.borderTop = pin:CreateTexture(nil, "OVERLAY")
  pin.borderTop:SetTexture(1, 0.82, 0.12, 1)
  pin.borderTop:SetPoint("TOPLEFT", 0, 0)
  pin.borderTop:SetPoint("TOPRIGHT", 0, 0)
  pin.borderTop:SetHeight(2)

  pin.borderBottom = pin:CreateTexture(nil, "OVERLAY")
  pin.borderBottom:SetTexture(1, 0.82, 0.12, 1)
  pin.borderBottom:SetPoint("BOTTOMLEFT", 0, 0)
  pin.borderBottom:SetPoint("BOTTOMRIGHT", 0, 0)
  pin.borderBottom:SetHeight(2)

  pin.borderLeft = pin:CreateTexture(nil, "OVERLAY")
  pin.borderLeft:SetTexture(1, 0.82, 0.12, 1)
  pin.borderLeft:SetPoint("TOPLEFT", 0, 0)
  pin.borderLeft:SetPoint("BOTTOMLEFT", 0, 0)
  pin.borderLeft:SetWidth(2)

  pin.borderRight = pin:CreateTexture(nil, "OVERLAY")
  pin.borderRight:SetTexture(1, 0.82, 0.12, 1)
  pin.borderRight:SetPoint("TOPRIGHT", 0, 0)
  pin.borderRight:SetPoint("BOTTOMRIGHT", 0, 0)
  pin.borderRight:SetWidth(2)

  pin.glow = pin:CreateTexture(nil, "HIGHLIGHT")
  pin.glow:SetPoint("TOPLEFT", -2, 2)
  pin.glow:SetPoint("BOTTOMRIGHT", 2, -2)
  pin.glow:SetTexture("Interface\\Buttons\\WHITE8X8")
  pin.glow:SetVertexColor(1, 0.85, 0.2, 0.18)
  pin.glow:SetBlendMode("ADD")

  pin:SetScript("OnEnter", function(self)
    if not self.result then
      return
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.result.itemLink then
      GameTooltip:SetHyperlink(self.result.itemLink)
    else
      GameTooltip:SetText(tostring(self.result.itemName or "Unknown item"))
    end

    if self.result.lastZoneName and self.result.lastX and self.result.lastY then
      GameTooltip:AddLine(string.format("%s @ %.1f, %.1f", self.result.lastZoneName, self.result.lastX * 100, self.result.lastY * 100), 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
  end)

  pin:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  pin:SetScript("OnClick", function(self, button)
    if button == "LeftButton" and addon.SearchUI and addon.SearchUI.ShareResult then
      addon.SearchUI:ShareResult(self.result)
    end
  end)

  pin:Hide()
  addon.MapNotes.pin = pin

  if WorldMapFrame and not addon.MapNotes.closeHooked then
    WorldMapFrame:HookScript("OnShow", function()
      addon.MapNotes:EnsureAllMapCheckbox()
      if addon.MapNotes and addon.MapNotes.RefreshPinVisibility then
        addon.MapNotes:RefreshPinVisibility()
      end
      addon.MapNotes:RefreshAllMarkers()
    end)
    WorldMapFrame:HookScript("OnHide", function()
      if addon.MapNotes.pin and addon.MapNotes.pin.isTemporary then
        addon.MapNotes.pin:Hide()
        addon.MapNotes.pin.result = nil
        addon.MapNotes.pin.isTemporary = false
      end
      for _, marker in pairs(addon.MapNotes.allMarkers or {}) do marker:Hide() end
    end)
    WorldMapFrame:HookScript("OnUpdate", function()
      if not WorldMapDetailFrame or not WorldMapFrame:IsShown() then return end
      if addon.ItemScan and addon.ItemScan.RepairZoneNamesFromOpenMap then
        addon.ItemScan:RepairZoneNamesFromOpenMap()
      end
      local width = WorldMapDetailFrame:GetWidth()
      local height = WorldMapDetailFrame:GetHeight()
      if addon.MapNotes.lastMapWidth ~= width or addon.MapNotes.lastMapHeight ~= height then
        addon.MapNotes.lastMapWidth = width
        addon.MapNotes.lastMapHeight = height
        addon.MapNotes:RefreshPinVisibility()
        addon.MapNotes:RefreshAllMarkers()
      end
    end)
    addon.MapNotes.closeHooked = true
  end

  return pin
end

local function resolveZoneName(result)
  return addon:ResolveZoneName(result.lastMapId, result.lastContinent, result.lastZone, result.lastZoneName)
end

local function setMapToZoneName(zoneName)
  if not zoneName or not GetMapZones or not SetMapZoom then
    return false
  end

  local continentNames = GetMapContinents and { GetMapContinents() } or {}
  for continent = 1, #continentNames do
    local zones = { GetMapZones(continent) }
    if #zones > 0 then
      for zone = 1, #zones do
        if zones[zone] == zoneName then
          SetMapZoom(continent)
          SetMapZoom(continent, zone)
          return true
        end
      end
    end
  end

  for continent = 1, #continentNames do
    SetMapZoom(continent)
    local zones = { GetMapZones(continent) }
    for zone = 1, #zones do
      if zones[zone] == zoneName then
        SetMapZoom(continent, zone)
        return true
      end
    end
  end

  return false
end

local function isViewingTargetZone(result)
  if not result then
    return false
  end

  local targetZoneName = resolveZoneName(result)
  if GetMapInfo and targetZoneName then
    local currentMapName = GetMapInfo()
    if currentMapName and currentMapName ~= "" then
      return currentMapName == targetZoneName
    end
  end

  if GetCurrentMapContinent and GetCurrentMapZone then
    local continent = GetCurrentMapContinent()
    local zone = GetCurrentMapZone()
    if continent and zone and continent > 0 and zone > 0 and result.lastContinent and result.lastZone then
      return continent == result.lastContinent and zone == result.lastZone
    end

    if continent and zone and continent > 0 and zone > 0 and result.lastZoneName and GetMapZones then
      local zones = { GetMapZones(continent) }
      if zones[zone] and zones[zone] == result.lastZoneName then
        return true
      end
    end
  end

  return false
end

local function usesContinentFallback(result)
  -- This Deadmines blind spot has continent coordinates but no matching detail-map location.
  return result and result.lastMapId == 15 and result.lastZoneName == "The Deadmines"
end

local function ensureAllMapCheckbox()
  if addon.MapNotes.allMapCheckbox or not WorldMapFrame then return addon.MapNotes.allMapCheckbox end
  local checkbox = CreateFrame("CheckButton", "WforgedAllMapItemsCheckbox", WorldMapFrame, "UICheckButtonTemplate")
  checkbox:SetSize(22, 22)
  checkbox:SetFrameStrata("TOOLTIP")
  checkbox:SetFrameLevel(1000)
  if checkbox.EnableMouse then checkbox:EnableMouse(true) end
  if checkbox.RegisterForClicks then checkbox:RegisterForClicks("LeftButtonUp") end
  checkbox:SetPoint("BOTTOMLEFT", WorldMapFrame, "BOTTOMLEFT", 18, 12)
  checkbox:Hide()
  checkbox:SetNormalTexture("Interface\\Buttons\\WHITE8X8")
  checkbox:GetNormalTexture():SetVertexColor(0.05, 0.05, 0.05, 0.95)
  checkbox:SetPushedTexture("Interface\\Buttons\\WHITE8X8")
  checkbox:GetPushedTexture():SetVertexColor(0.2, 0.2, 0.2, 0.95)
  checkbox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  local border = checkbox:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Buttons\\WHITE8X8")
  border:SetPoint("TOPLEFT", 0, 0)
  border:SetPoint("BOTTOMRIGHT", 0, 0)
  border:SetVertexColor(1, 0.82, 0.12, 1)
  local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT", checkbox, "RIGHT", 5, 0)
  label:SetText("Show all Wforged items")
  checkbox:SetScript("OnClick", function(self)
    WforgedDB.showAllMapItems = self:GetChecked() and true or false
    addon.MapNotes:RefreshAllMarkers()
    addon.MapNotes:SchedulePinRefresh()
  end)
  checkbox:SetChecked(WforgedDB.showAllMapItems and true or false)
  addon.MapNotes.allMapCheckbox = checkbox
  return checkbox
end

function addon.MapNotes:EnsureAllMapCheckbox()
  return ensureAllMapCheckbox()
end

function addon.MapNotes:RefreshAllMarkers()
  local checkbox = ensureAllMapCheckbox()
  if checkbox then checkbox:SetChecked(WforgedDB.showAllMapItems and true or false) end
  if not WforgedDB.showAllMapItems or not WorldMapFrame or not WorldMapFrame:IsShown() or not WorldMapDetailFrame then
    for _, marker in pairs(self.allMarkers) do marker:Hide() end
    return
  end
  local visible = {}
  local results = addon.DB and addon.DB.SearchItems and addon.DB:SearchItems("") or {}
  for _, result in ipairs(results) do
    local currentMapId = GetCurrentMapAreaID and GetCurrentMapAreaID() or nil
    local sameMapId = currentMapId and currentMapId == result.lastMapId
    if result.lastX and result.lastY and (sameMapId or isViewingTargetZone(result)) then
      local key = result.itemKey or result.fingerprint
      visible[key] = true
      local marker = self.allMarkers[key]
      if not marker then
        marker = CreateFrame("Button", nil, WorldMapDetailFrame)
        marker:SetSize(16, 16)
        marker:SetFrameStrata("HIGH")
        marker:SetFrameLevel(50)
        marker.texture = marker:CreateTexture(nil, "BACKGROUND")
        marker.texture:SetAllPoints(marker)
        marker.texture:SetTexture("Interface\\Buttons\\WHITE8X8")
        marker.texture:SetVertexColor(0, 0, 0, 1)
        marker.dot = marker:CreateTexture(nil, "ARTWORK")
        marker.dot:SetSize(12, 12)
        marker.dot:SetPoint("CENTER")
        marker.dot:SetTexture("Interface\\Buttons\\WHITE8X8")
        marker.dot:SetVertexColor(1, 0.95, 0.2, 1)
        marker:SetScript("OnEnter", function(button)
          if button.result and button.result.itemLink then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(button.result.itemLink)
            GameTooltip:Show()
          end
        end)
        marker:SetScript("OnLeave", function() GameTooltip:Hide() end)
        marker:SetScript("OnClick", function(button, mouseButton)
          if mouseButton == "LeftButton" and addon.SearchUI and addon.SearchUI.ShareResult then
            addon.SearchUI:ShareResult(button.result)
          end
        end)
        self.allMarkers[key] = marker
      end
      marker:SetParent(WorldMapDetailFrame)
      marker:ClearAllPoints()
      marker:SetPoint("CENTER", WorldMapDetailFrame, "TOPLEFT", result.lastX * WorldMapDetailFrame:GetWidth(), -result.lastY * WorldMapDetailFrame:GetHeight())
      marker.dot:SetTexture(result.itemTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
      local currentRealm = addon.DB and addon.DB.GetCurrentRealm and addon.DB:GetCurrentRealm() or "Unknown"
      local foreignRealm = result.realm and result.realm ~= "Unknown" and result.realm ~= currentRealm
      marker:SetAlpha(foreignRealm and 0.35 or 1)
      marker.dot:SetVertexColor(foreignRealm and 0.55 or 1, foreignRealm and 0.55 or 1, foreignRealm and 0.55 or 1, 1)
      marker.result = result
      marker:Show()
    end
  end
  for key, marker in pairs(self.allMarkers) do
    if not visible[key] then marker:Hide() end
  end
end

local function pinMatchesForcedMap(pin)
  if not pin or not pin.forcedMapState then
    return false
  end

  local forced = pin.forcedMapState
  if forced.zoneName and GetMapInfo then
    local currentMapName = GetMapInfo()
    if currentMapName and currentMapName ~= "" and currentMapName == forced.zoneName then
      return true
    end
  end

  if GetCurrentMapContinent and GetCurrentMapZone then
    local continent = GetCurrentMapContinent()
    local zone = GetCurrentMapZone()
    if forced.continent and forced.zone and continent == forced.continent and zone == forced.zone then
      return true
    end
  end

  return false
end

function addon.MapNotes:RefreshPinVisibility()
  local pin = self.pin
  if not pin or not pin.result then
    return
  end

  if not WorldMapFrame or not WorldMapFrame:IsShown() then
    pin:Hide()
    return
  end

  if not WorldMapDetailFrame then
    pin:Hide()
    return
  end

  local currentMapId = GetCurrentMapAreaID and GetCurrentMapAreaID() or nil
  local hasNamedZone = resolveZoneName(pin.result) ~= nil and not usesContinentFallback(pin.result)
  local sameMapId = not hasNamedZone and currentMapId and currentMapId == pin.result.lastMapId
  local transitionVisible = pin.forceVisibleUntil and GetTime() <= pin.forceVisibleUntil
  if not transitionVisible and not sameMapId and not isViewingTargetZone(pin.result) and not pinMatchesForcedMap(pin) then
    pin:Hide()
    return
  end

  if pin:GetParent() ~= WorldMapFrame then
    pin:SetParent(WorldMapFrame)
  end
  pin:ClearAllPoints()
  local detailScale = WorldMapDetailFrame.GetEffectiveScale and WorldMapDetailFrame:GetEffectiveScale() or 1
  local pinScale = pin.GetEffectiveScale and pin:GetEffectiveScale() or 1
  local scaleRatio = detailScale / pinScale
  pin:SetPoint("CENTER", WorldMapDetailFrame, "TOPLEFT", pin.result.lastX * WorldMapDetailFrame:GetWidth() * scaleRatio, -pin.result.lastY * WorldMapDetailFrame:GetHeight() * scaleRatio)
  addon:LootDebug(string.format(
    "Map pin layout: zone=%s x=%.4f y=%.4f frame=%.1fx%.1f left=%.1f top=%.1f",
    tostring(resolveZoneName(pin.result) or "?"),
    pin.result.lastX,
    pin.result.lastY,
    WorldMapDetailFrame:GetWidth(),
    WorldMapDetailFrame:GetHeight(),
    WorldMapDetailFrame:GetLeft() or 0,
    WorldMapDetailFrame:GetTop() or 0
  ))
  pin:Show()
end

function addon.MapNotes:SchedulePinRefresh()
  self.pinRefreshTicks = 8
end

function addon.MapNotes:ShowOnMap(result, isTemporary)
  if not result or not result.lastX or not result.lastY then
    addon:Print("Selected item has no saved map position yet.")
    return false
  end

  if WorldMapFrame and not WorldMapFrame:IsShown() then
    ToggleFrame(WorldMapFrame)
  end

  local zoneName = resolveZoneName(result)
  if not zoneName and not (result.lastContinent and result.lastZone) and not result.lastMapId then
    addon:Print("Selected item has no verified map or zone data.")
    return false
  end
  if not usesContinentFallback(result) and zoneName and setMapToZoneName(zoneName) then
    addon:LootDebug(string.format("Map jump via zoneName: %s", tostring(zoneName)))
  elseif result.lastContinent and result.lastZone and SetMapZoom then
    SetMapZoom(result.lastContinent)
    SetMapZoom(result.lastContinent, result.lastZone)
    addon:LootDebug(string.format("Map jump via continent/zone: %s/%s", tostring(result.lastContinent), tostring(result.lastZone)))
  elseif result.lastMapId and SetMapByID then
    SetMapByID(result.lastMapId)
    addon:LootDebug(string.format("Map jump via mapId: %s", tostring(result.lastMapId)))
  elseif result.lastMapId and WorldMapFrame_SetMapID then
    WorldMapFrame_SetMapID(result.lastMapId)
    addon:LootDebug(string.format("Map jump via WorldMapFrame_SetMapID: %s", tostring(result.lastMapId)))
  else
    addon:LootDebug("Map jump failed: no usable map target data.")
  end

  local pin = ensureMapPin()
  if not pin or not WorldMapDetailFrame then
    addon:Print("World map pin is not available in this client.")
    return false
  end

  pin.result = result
  pin.isTemporary = isTemporary and true or false
  pin.forceVisibleUntil = GetTime() + 3
  pin.forcedMapState = {
    zoneName = zoneName,
    continent = result.lastContinent,
    zone = result.lastZone,
    mapId = result.lastMapId,
  }
  if result.itemTexture then
    pin.icon:SetTexture(result.itemTexture)
  elseif result.itemId and GetItemIcon then
    pin.icon:SetTexture(GetItemIcon(result.itemId) or "Interface\\Icons\\INV_Misc_QuestionMark")
  else
    pin.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  end

  pin:Show()
  self:RefreshPinVisibility()
  self:RefreshAllMarkers()
  self:SchedulePinRefresh()
  return true
end

function addon.MapNotes:IsPinned(result)
  local pin = self.pin
  if not pin or not pin:IsShown() or pin.isTemporary then
    return false
  end
  if not result or not pin.result then
    return false
  end
  return pin.result.fingerprint == result.fingerprint
end

function addon.MapNotes:RemoveFromMap(result)
  local pin = self.pin
  if not pin or not pin:IsShown() or pin.isTemporary then
    return false
  end
  if result and pin.result and pin.result.fingerprint ~= result.fingerprint then
    return false
  end

  pin:Hide()
  pin.result = nil
  pin.isTemporary = false
  pin.forcedMapState = nil
  return true
end

function addon.MapNotes:AddToMap(result)
  if self:ShowOnMap(result, false) then
    addon:Print("Map marker added for " .. tostring(result.itemName or "item"))
    return true
  end
  return false
end

local function ensureMinimapConfig()
  WforgedDB.minimapButton = WforgedDB.minimapButton or {}
  local config = WforgedDB.minimapButton
  if type(config.angle) ~= "number" then
    config.angle = 45
  end
  return config
end

function addon.MinimapButton:UpdatePosition()
  if not self.button or not Minimap then
    return
  end

  local config = ensureMinimapConfig()
  local angle = math.rad(config.angle)
  local radius = 80
  local x = math.cos(angle) * radius
  local y = math.sin(angle) * radius
  self.button:ClearAllPoints()
  self.button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function addon.MinimapButton:Create()
  if not Minimap or type(WforgedDB) ~= "table" then
    return
  end

  if self.button then
    self:UpdatePosition()
    self.button:Show()
    return
  end

  local button = CreateFrame("Button", "WforgedMinimapButton", Minimap)
  button:SetWidth(31)
  button:SetHeight(31)
  button:SetFrameStrata("MEDIUM")
  button:EnableMouse(true)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")

  button.border = button:CreateTexture(nil, "OVERLAY")
  button.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  button.border:SetWidth(54)
  button.border:SetHeight(54)
  button.border:SetPoint("CENTER", 12, -12)

  button.icon = button:CreateTexture(nil, "ARTWORK")
  button.icon:SetTexture("Interface\\Icons\\INV_Sword_04")
  button.icon:SetWidth(18)
  button.icon:SetHeight(18)
  button.icon:SetPoint("CENTER", 0, 1)
  button.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)


  button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "LeftButton" and IsShiftKeyDown and IsShiftKeyDown() then
      WforgedDB.showAllMapItems = not WforgedDB.showAllMapItems
      if addon.MapNotes and addon.MapNotes.allMapCheckbox then
        addon.MapNotes.allMapCheckbox:SetChecked(WforgedDB.showAllMapItems and true or false)
      end
      if addon.MapNotes and addon.MapNotes.RefreshAllMarkers then
        addon.MapNotes:RefreshAllMarkers()
      end
      addon:Print("Show all map items: " .. (WforgedDB.showAllMapItems and "enabled" or "disabled"))
    elseif mouseButton == "RightButton" and addon.SearchUI and addon.SearchUI.ToggleSettings then
      addon.SearchUI:ToggleSettings()
    elseif addon.SearchUI and addon.SearchUI.Toggle then
      addon.SearchUI:Toggle()
    end
  end)

  button:SetScript("OnEnter", function(selfButton)
    GameTooltip:SetOwner(selfButton, "ANCHOR_LEFT")
    GameTooltip:SetText("Wforged")
    GameTooltip:AddLine("Left click: search items", 1, 1, 1)
    GameTooltip:AddLine("Shift + left click: show all map items", 1, 1, 1)
    GameTooltip:AddLine("Right click: settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: move around minimap", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)

  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  button:SetScript("OnDragStart", function(selfButton)
    selfButton:SetScript("OnUpdate", function(frame)
      local mx, my = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      local cx, cy = Minimap:GetCenter()
      mx = mx / scale
      my = my / scale
      ensureMinimapConfig().angle = math.deg(math.atan2(my - cy, mx - cx))
      addon.MinimapButton:UpdatePosition()
    end)
  end)

  button:SetScript("OnDragStop", function(selfButton)
    selfButton:SetScript("OnUpdate", nil)
  end)

  self.button = button
  self:UpdatePosition()
end

local popupMarkers = {
  "worldforged",
}

local function popupTextMatches(text)
  local normalized = string.lower(text or "")
  for _, marker in ipairs(popupMarkers) do
    if normalized:find(marker, 1, true) then
      return true
    end
  end
  return false
end

local function isLootBindPopup(text)
  local normalized = string.lower(text or "")
  return normalized:find("looting ", 1, true) ~= nil
    and normalized:find("bind", 1, true) ~= nil
end

function addon.AutoConfirm:RequestDebugScan(reason)
  self.debugUntil = GetTime() + 3
  self.debugReason = reason or "unknown"
  self.loggedNoPopup = false
end

function addon.AutoConfirm:SetLootContext(hasWorldforged)
  self.hasWorldforgedLoot = hasWorldforged and true or false
  if not self.hasWorldforgedLoot then
    self.loggedDisabled = false
  end
  if self.hasWorldforgedLoot then
    self:RequestDebugScan("worldforged-loot-opened")
    addon:LootDebug("Loot context marked as worldforged.")
  else
    addon:LootDebug("Loot context cleared.")
  end
end

function addon.AutoConfirm:ScanOpenLootSlots()
  if not GetNumLootItems or not GetLootSlotLink or not addon.ItemScan then return false end
  for slot = 1, GetNumLootItems() do
    local link = GetLootSlotLink(slot)
    if link and addon.ItemScan:IsWorldforgedItem(link, true) then
      self.hasWorldforgedLoot = true
      addon:LootDebug("Delayed Worldforged loot detection: slot " .. tostring(slot))
      return true
    end
  end
  return false
end

function addon.AutoConfirm:DebugScan()
  local foundAny = false
  for index = 1, 4 do
    local popup = _G["StaticPopup" .. index]
    if popup and popup.IsShown and popup:IsShown() then
      foundAny = true
      local textRegion = _G[popup:GetName() .. "Text"]
      local button1 = _G[popup:GetName() .. "Button1"]
      local button2 = _G[popup:GetName() .. "Button2"]
      addon:LootDebug(string.format(
        "Popup %s shown: text='%s' button1='%s' button2='%s'",
        tostring(popup:GetName()),
        tostring(textRegion and textRegion:GetText() or ""),
        tostring(button1 and button1:GetText() or ""),
        tostring(button2 and button2:GetText() or "")
      ))
    end
  end

  if not foundAny then
    if not self.loggedNoPopup then
      addon:LootDebug("No StaticPopup visible during auto-confirm scan.")
      self.loggedNoPopup = true
    end
  else
    self.loggedNoPopup = false
  end

  local candidates = {
    "LootBindFrame",
    "LootFrame",
    "GroupLootFrame1",
    "GroupLootFrame2",
    "GroupLootFrame3",
    "GroupLootFrame4",
  }

  for _, frameName in ipairs(candidates) do
    local frame = _G[frameName]
    if frame and frame.IsShown and frame:IsShown() then
      addon:LootDebug("Visible candidate frame: " .. tostring(frameName))
    end
  end
end

local function tryNamedButton(frameName, buttonSuffix)
  local button = _G[frameName .. buttonSuffix]
  if button and button.IsShown and button:IsShown() and button.IsEnabled and button:IsEnabled() then
    button:Click()
    return true
  end
  return false
end

function addon.AutoConfirm:TryNonStaticPopupConfirm()
  local settings = addon.DB and addon.DB.GetSettings and addon.DB:GetSettings()
  if not settings or settings.autoConfirmWorldforged == false or not self.hasWorldforgedLoot then
    return false
  end

  if tryNamedButton("LootBind", "AcceptButton") then
    addon:LootDebug("Auto-confirm via LootBindAcceptButton")
    return true
  end

  if tryNamedButton("LootBindFrame", "AcceptButton") then
    addon:LootDebug("Auto-confirm via LootBindFrameAcceptButton")
    return true
  end

  return false
end

function addon.AutoConfirm:TryConfirm()
  local settings = addon.DB and addon.DB.GetSettings and addon.DB:GetSettings()
  if not self.lootWindowOpen then
    return false
  end
  if not settings or settings.autoConfirmWorldforged == false then
    self.hasWorldforgedLoot = false
    if not self.loggedDisabled then
      addon:LootDebug(string.format("AutoConfirm blocked: enabled=%s", tostring(settings and settings.autoConfirmWorldforged)))
      self.loggedDisabled = true
    end
    return false
  end
  self.loggedDisabled = false

  local sawPopup = false
  if self.lootScanUntil and GetTime() <= self.lootScanUntil and not self.hasWorldforgedLoot then
    self:ScanOpenLootSlots()
  end
  if self.debugUntil and GetTime() <= self.debugUntil then
    self:DebugScan()
  end

  if self:TryNonStaticPopupConfirm() then
    return true
  end

  for index = 1, 4 do
    local popup = _G["StaticPopup" .. index]
    if popup and popup.IsShown and popup:IsShown() then
      sawPopup = true
      local textRegion = _G[popup:GetName() .. "Text"]
      local text = textRegion and textRegion:GetText() or ""
      if not self.hasWorldforgedLoot and addon.DB and addon.DB.GetPendingItems then
        for _, pending in pairs(addon.DB:GetPendingItems()) do
          if pending.isWorldforged and pending.itemName and text:find(pending.itemName, 1, true) then
            self.hasWorldforgedLoot = true
            addon:LootDebug("Worldforged popup matched pending item: " .. tostring(pending.itemName))
            break
          end
        end
      end
      local popupKey = popup:GetName() .. "::" .. text
      if self.lastSeenPopupKey ~= popupKey then
        self.lastSeenPopupKey = popupKey
        addon:LootDebug("Visible popup: " .. tostring(text))
      end
      if self.hasWorldforgedLoot and isLootBindPopup(text) then
        local button1 = _G[popup:GetName() .. "Button1"]
        if button1 and button1:IsShown() and button1:IsEnabled() then
          addon:LootDebug("Auto-confirm popup: " .. tostring(text))
          button1:Click()
          return true
        end
      end
    end
  end

  if not sawPopup then
    self.lastSeenPopupKey = nil
  end

  return false
end

eventFrame:SetScript("OnEvent", function(_, eventName, ...)
  local handler = eventFrame[eventName]
  if handler then
    safeCall(handler, addon, ...)
  end
end)
