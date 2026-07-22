local addonName, addon = ...

local ItemScan = {}
addon.ItemScan = ItemScan
ItemScan.zoneRepairDryRun = false

local tooltip = CreateFrame("GameTooltip", "WforgedScanTooltip", nil, "GameTooltipTemplate")
tooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local statPatterns = {
  ITEM_MOD_STRENGTH_SHORT,
  ITEM_MOD_AGILITY_SHORT,
  ITEM_MOD_INTELLECT_SHORT,
  ITEM_MOD_SPIRIT_SHORT,
  ITEM_MOD_STAMINA_SHORT,
  ITEM_MOD_CRIT_RATING_SHORT,
  ITEM_MOD_HASTE_RATING_SHORT,
  ITEM_MOD_MASTERY_RATING_SHORT,
  ITEM_MOD_VERSATILITY,
}

local worldforgedMarkers = {
  "worldforged",
}

local function collectTooltipData(itemLink)
  if not itemLink then
    return nil, nil
  end

  tooltip:ClearLines()
  tooltip:SetHyperlink(itemLink)

  local parts = {}
  local fullTextParts = {}
  for lineIndex = 2, tooltip:NumLines() do
    local leftRegion = _G["WforgedScanTooltipTextLeft" .. lineIndex]
    local rightRegion = _G["WforgedScanTooltipTextRight" .. lineIndex]
    local text = leftRegion and leftRegion:GetText()
    local rightText = rightRegion and rightRegion:GetText()
    if text then
      fullTextParts[#fullTextParts + 1] = text
      for _, pattern in ipairs(statPatterns) do
        if text:find(pattern, 1, true) then
          parts[#parts + 1] = text
          break
        end
      end
    end
    if rightText and rightText ~= "" then
      fullTextParts[#fullTextParts + 1] = rightText
    end
  end

  local statsText = nil
  if #parts > 0 then
    table.sort(parts)
    statsText = table.concat(parts, " | ")
  end

  local tooltipText = nil
  if #fullTextParts > 0 then
    tooltipText = table.concat(fullTextParts, " | ")
  end

  return statsText, tooltipText
end

local function buildPendingKey(itemLink, itemId)
  if itemId then
    return "item:" .. tostring(itemId)
  end
  return itemLink
end

local function extractItemId(itemLink)
  if type(itemLink) ~= "string" then
    return nil
  end

  local itemId = itemLink:match("item:(%d+)")
  if itemId then
    return tonumber(itemId)
  end

  return nil
end

local function isItemInfoReady(itemName, itemLevel)
  return itemName ~= nil and itemLevel ~= nil
end

local function tooltipContainsWorldforgedMarker(itemLink)
  if not itemLink then
    return false
  end

  tooltip:ClearLines()
  tooltip:SetHyperlink(itemLink)

  for lineIndex = 2, tooltip:NumLines() do
    local leftRegion = _G["WforgedScanTooltipTextLeft" .. lineIndex]
    local rightRegion = _G["WforgedScanTooltipTextRight" .. lineIndex]
    local leftText = leftRegion and string.lower(leftRegion:GetText() or "")
    local rightText = rightRegion and string.lower(rightRegion:GetText() or "")

    for _, marker in ipairs(worldforgedMarkers) do
      if leftText:find(marker, 1, true) or rightText:find(marker, 1, true) then
        addon:LootDebug(string.format(
          "Worldforged marker matched on line %s: L='%s' R='%s'",
          tostring(lineIndex),
          tostring(leftRegion and leftRegion:GetText() or ""),
          tostring(rightRegion and rightRegion:GetText() or "")
        ))
        return true
      end
    end
  end

  return false
end

local function debugDumpTooltip(itemLink)
  if not itemLink then
    return
  end

  tooltip:ClearLines()
  tooltip:SetHyperlink(itemLink)
  addon:LootDebug("Tooltip dump for " .. tostring(itemLink))

  for lineIndex = 1, tooltip:NumLines() do
    local leftRegion = _G["WforgedScanTooltipTextLeft" .. lineIndex]
    local rightRegion = _G["WforgedScanTooltipTextRight" .. lineIndex]
    local leftText = leftRegion and leftRegion:GetText() or ""
    local rightText = rightRegion and rightRegion:GetText() or ""
    addon:LootDebug(string.format("TT[%d] L='%s' R='%s'", lineIndex, tostring(leftText), tostring(rightText)))
  end
end

function ItemScan:IsWorldforgedItem(itemLink, skipDebugDump)
  if not itemLink then
    return false
  end

  if not skipDebugDump then
    debugDumpTooltip(itemLink)
  end

  return tooltipContainsWorldforgedMarker(itemLink)
end

function ItemScan:FinalizePendingRecord(record)
  if not record or not record.itemLink then
    return nil
  end

  local itemName, _, quality, itemLevel, _, _, _, _, _, itemTexture = GetItemInfo(record.itemLink)
  local itemId = extractItemId(record.itemLink) or record.itemId
  if not isItemInfoReady(itemName, itemLevel) then
    addon:LootDebug("Waiting for item info: " .. tostring(record.itemLink))
    return nil
  end

  local statsText, tooltipText = collectTooltipData(record.itemLink)
  local upgradeLevel = record.upgradeLevel
  local effectiveLevel = itemLevel
  local itemKey = addon.DB:BuildItemKey(itemId, itemName)
  local fingerprint = addon.DB:BuildFingerprint(record.itemLink, upgradeLevel, statsText)

  addon.DB:RecordItemObservation({
    fingerprint = fingerprint,
    itemKey = itemKey,
    itemLink = record.itemLink,
    itemName = itemName,
    itemId = itemId,
    itemTexture = itemTexture,
    isWorldforged = record.isWorldforged or self:IsWorldforgedItem(record.itemLink, true),
    upgradeCandidate = record.upgradeCandidate,
    quality = quality,
    itemLevel = itemLevel,
    effectiveLevel = effectiveLevel,
    upgradeLevel = upgradeLevel,
    statsText = statsText,
    tooltipText = tooltipText,
    sourceType = record.sourceType or "manual",
    realm = addon.DB:GetCurrentRealm(),
    mapId = record.mapId,
    x = record.x,
    y = record.y,
  })

  if addon.SearchUI and addon.SearchUI.frame and addon.SearchUI.frame:IsShown() then
    addon.SearchUI:Refresh(addon.SearchUI.frame.editBox and addon.SearchUI.frame.editBox:GetText() or "")
  end

  if record.mapId and record.x and record.y then
    addon.DB:RecordSpawnPoint(fingerprint, record.mapId, record.x, record.y, {
      continent = record.continent,
      zone = record.zone,
      zoneName = record.zoneName,
    })
  end

  addon.DB:RemovePendingItem(record.pendingKey)
  if record.sourceType == "loot-chat" and addon.Sync and addon.Sync.BroadcastItem then
    local settings = addon.DB:GetSettings()
    if settings.sendGuildUpdates ~= false then
      addon:LootDebug("Guild broadcast enabled; sending Worldforged item.")
    end
    addon.Sync:BroadcastItem(fingerprint)
  end
  addon:LootDebug(string.format(
    "Stored %s (itemId=%s, level=%s, source=%s)",
    tostring(itemName or record.itemLink),
    tostring(itemId or "?"),
    tostring(effectiveLevel or "?"),
    tostring(record.sourceType or "unknown")
  ))
  return fingerprint
end

local function isGenericZoneName(name)
  return type(name) == "string" and name:match("^Map %d+$") ~= nil
end

local function isCurrentMapNameForDifferentMap(record)
  local recordMapId = record and (record.mapId or record.lastMapId)
  local recordZoneName = record and (record.zoneName or record.lastZoneName)
  if not record or not recordZoneName or not GetMapInfo or not GetCurrentMapAreaID then
    return false
  end
  local currentMapId = GetCurrentMapAreaID()
  local currentMapName = GetMapInfo()
  return currentMapId and recordMapId and tonumber(recordMapId) ~= tonumber(currentMapId)
    and currentMapName and recordZoneName == currentMapName
end

local function logZoneNameCandidates(mapId, continent, zone)
  local candidates = {
    real = GetRealZoneText and GetRealZoneText() or nil,
    zone = GetZoneText and GetZoneText() or nil,
    map = GetMapInfo and GetMapInfo() or nil,
  }
  if continent and zone and GetMapZones then
    local zones = { GetMapZones(continent) }
    candidates.index = zones[zone]
  end
  addon:LootDebug(string.format(
    "Zone candidates: mapId=%s playerReal=%s playerZone=%s map=%s index=%s",
    tostring(mapId), tostring(candidates.real or "?"), tostring(candidates.zone or "?"),
    tostring(candidates.map or "?"), tostring(candidates.index or "?")
  ))
end

function ItemScan:RepairStoredItem(itemId, entry)
  if not itemId or not entry then
    return false
  end

  local repairedZone = false
  if isCurrentMapNameForDifferentMap({ mapId = entry.lastMapId, zoneName = entry.lastZoneName }) then
    local oldZone = entry.lastZoneName
    addon:LootDebug(string.format("Removed invalid location: itemId=%s %s -> unknown (current map name did not match mapId)", tostring(entry.itemId), tostring(oldZone)))
    if not self.zoneRepairDryRun then
      entry.lastMapId = nil
      entry.lastContinent = nil
      entry.lastZone = nil
      entry.lastX = nil
      entry.lastY = nil
      entry.lastZoneName = nil
      repairedZone = true
    end
  elseif isGenericZoneName(entry.lastZoneName) and addon.ResolveZoneName then
    local oldZone = entry.lastZoneName
    local resolvedZone = addon:ResolveZoneName(entry.lastMapId, entry.lastContinent, entry.lastZone, nil)
    if resolvedZone then
      addon:LootDebug(string.format("Zone repair preview: itemId=%s %s -> %s", tostring(entry.itemId), tostring(oldZone), tostring(resolvedZone)))
      if not self.zoneRepairDryRun then
        entry.lastZoneName = resolvedZone
        repairedZone = true
      end
    end
  end

  if not GetItemInfo then
    return repairedZone
  end

  local itemName, itemLink, quality, itemLevel, _, _, _, _, _, itemTexture = GetItemInfo(itemId)
  if not isItemInfoReady(itemName, itemLevel) or not itemLink then
    return repairedZone
  end

  local statsText, tooltipText = collectTooltipData(itemLink)
  entry.itemId = tonumber(itemId) or itemId
  entry.itemLink = itemLink
  entry.itemName = itemName
  entry.quality = quality
  entry.itemLevel = itemLevel
  entry.effectiveLevel = entry.effectiveLevel or itemLevel
  entry.itemTexture = itemTexture
  entry.statsText = entry.statsText or statsText
  entry.tooltipText = entry.tooltipText or tooltipText
  entry.isWorldforged = true
  return true
end

function ItemScan:RepairStoredItems(itemId, limit)
  if not addon.DB or not addon.DB.data then
    return 0
  end

  if itemId then
    limit = limit or 1
  else
    if not self.repairQueueInitialized then
      self.repairQueue = {}
      for _, entry in pairs(addon.DB.data.itemsByFingerprint or {}) do
        if entry.itemId and (not entry.itemLink or not entry.itemLevel or not entry.quality or isGenericZoneName(entry.lastZoneName)) then
          self.repairQueue[#self.repairQueue + 1] = entry
        end
      end
      self.repairQueueInitialized = true
    end
  end

  local repaired = 0
  if itemId then
    for _, entry in pairs(addon.DB.data.itemsByFingerprint or {}) do
      if tonumber(entry.itemId) == tonumber(itemId) and self:RepairStoredItem(entry.itemId, entry) then
        repaired = 1
        break
      end
    end
  else
    for _ = 1, (limit or 1) do
      local entry = table.remove(self.repairQueue, 1)
      if not entry then break end
      if self:RepairStoredItem(entry.itemId, entry) then
        repaired = repaired + 1
        addon:LootDebug(string.format("Repaired stored item metadata: id=%s name=%s level=%s quality=%s", tostring(entry.itemId), tostring(entry.itemName), tostring(entry.itemLevel), tostring(entry.quality)))
      end
    end
  end

  if repaired > 0 and addon.SearchUI and addon.SearchUI.frame and addon.SearchUI.frame:IsShown() then
    addon.SearchUI:Refresh(addon.SearchUI.frame.editBox and addon.SearchUI.frame.editBox:GetText() or "")
  end
  if repaired > 0 and addon.MapNotes and addon.MapNotes.RefreshAllMarkers then
    addon.MapNotes:RefreshAllMarkers()
  end
  return repaired
end

function ItemScan:RepairStoredZoneNames(limit)
  if not addon.DB or not addon.DB.data or not addon.ResolveZoneName then
    return 0
  end
  if self.zoneRepairFinished then
    return 0
  end

  if not self.zoneRepairQueue then
    self.zoneRepairQueue = {}
    local unresolvedMaps = {}
    addon:LootDebug("Zone repair started.")
    for _, entry in pairs(addon.DB.data.itemsByFingerprint or {}) do
      if tonumber(entry.lastMapId) and (isGenericZoneName(entry.lastZoneName) or isCurrentMapNameForDifferentMap({ mapId = entry.lastMapId, zoneName = entry.lastZoneName })) then
        self.zoneRepairQueue[#self.zoneRepairQueue + 1] = entry
      elseif tonumber(entry.lastMapId) and not entry.lastZoneName then
        unresolvedMaps[tonumber(entry.lastMapId)] = { entry.lastContinent, entry.lastZone }
      end
    end
    for _, bucket in pairs(addon.DB.data.spawnPointsByItem or {}) do
      for _, point in pairs(bucket) do
        if tonumber(point.mapId) and (isGenericZoneName(point.zoneName) or isCurrentMapNameForDifferentMap(point)) then
          self.zoneRepairQueue[#self.zoneRepairQueue + 1] = point
        elseif tonumber(point.mapId) and not point.zoneName then
          unresolvedMaps[tonumber(point.mapId)] = { point.continent, point.zone }
        end
      end
    end
    for mapId, context in pairs(unresolvedMaps) do
      addon:LootDebug(string.format("Zone repair preview: mapId=%s -> no known zone name", tostring(mapId)))
      logZoneNameCandidates(mapId, context[1], context[2])
    end
    addon:LootDebug(string.format("Zone repair candidates: %d", #self.zoneRepairQueue))
  end

  local repaired = 0
  local checked = 0
  for _ = 1, (limit or 1) do
    local record = table.remove(self.zoneRepairQueue, 1)
    if not record then break end
    checked = checked + 1
    local recordMapId = record.mapId or record.lastMapId
    if not tonumber(recordMapId) then
      addon:LootDebug("Zone repair skipped: locationless item has no mapId.")
    else
      local resolved = addon:ResolveZoneName(recordMapId, record.continent or record.lastContinent, record.zone or record.lastZone, nil)
    if resolved then
      local oldZone = record.zoneName or record.lastZoneName
      addon:LootDebug(string.format("Zone repair preview: mapId=%s %s -> %s", tostring(recordMapId), tostring(oldZone), tostring(resolved)))
      if not self.zoneRepairDryRun then
        record.zoneName = resolved
        record.lastZoneName = resolved
        repaired = repaired + 1
      end
    elseif isCurrentMapNameForDifferentMap(record) then
      local oldZone = record.zoneName or record.lastZoneName
      addon:LootDebug(string.format("Removed invalid location: mapId=%s %s -> unknown (current map name did not match mapId)", tostring(recordMapId), tostring(oldZone)))
      if not self.zoneRepairDryRun then
        if record.lastMapId then
          record.lastMapId = nil
          record.lastContinent = nil
          record.lastZone = nil
          record.lastX = nil
          record.lastY = nil
          record.lastZoneName = nil
        else
          record.mapId = nil
          record.continent = nil
          record.zone = nil
          record.x = nil
          record.y = nil
          record.zoneName = nil
          record.lastZoneName = nil
        end
        repaired = repaired + 1
      end
    else
      addon:LootDebug(string.format("Zone repair preview: mapId=%s -> no known zone name", tostring(recordMapId)))
      logZoneNameCandidates(recordMapId, record.continent or record.lastContinent, record.zone or record.lastZone)
    end
    end
  end

  if #self.zoneRepairQueue == 0 then
    addon:LootDebug(string.format("Zone repair finished: checked=%d repaired=%d", checked, repaired))
    self.zoneRepairFinished = true
  end

  if repaired > 0 and addon.SearchUI and addon.SearchUI.frame and addon.SearchUI.frame:IsShown() then
    addon.SearchUI:Refresh(addon.SearchUI.frame.editBox and addon.SearchUI.frame.editBox:GetText() or "")
  end
  if repaired > 0 and addon.MapNotes and addon.MapNotes.RefreshAllMarkers then
    addon.MapNotes:RefreshAllMarkers()
  end
  return repaired
end

function ItemScan:QueuePendingItem(itemLink, sourceType, context)
  if not itemLink then
    return nil
  end

  local itemName, _, _, itemLevel, _, _, _, _, _, itemTexture = GetItemInfo(itemLink)
  local itemId = extractItemId(itemLink)
  local mapId, x, y = addon:GetPlayerPosition()
  local continent = GetCurrentMapContinent and GetCurrentMapContinent() or nil
  local zone = GetCurrentMapZone and GetCurrentMapZone() or nil
  local rawZoneName = GetRealZoneText and GetRealZoneText() or GetZoneText and GetZoneText() or nil
  local suppressLocation = sourceType == "upgrade-frame" or sourceType == "inventory" or sourceType == "equipped"
  local pendingKey = buildPendingKey(itemLink, itemId)
  local storedMapId = suppressLocation and nil or ((context and context.mapId) or mapId)
  local storedContinent = suppressLocation and nil or ((context and context.continent) or continent)
  local storedZone = suppressLocation and nil or ((context and context.zone) or zone)
  local storedZoneName = suppressLocation and nil or ((context and context.zoneName) or rawZoneName)
  if not suppressLocation and addon.ResolveZoneName then
    storedZoneName = addon:ResolveZoneName(storedMapId, storedContinent, storedZone, storedZoneName)
  end
  if not suppressLocation and addon.NormalizeLootLocation then
    local normalizedMapId, normalizedZoneName, normalizedX, normalizedY, changed = addon:NormalizeLootLocation(storedMapId, storedZoneName, x, y)
    storedMapId, storedZoneName = normalizedMapId, normalizedZoneName
    x, y = normalizedX, normalizedY
    if changed then
      storedContinent, storedZone = nil, nil
      addon:LootDebug("Normalized The Deadmines location to the Westfall instance entrance.")
    end
  end
  local payload = {
    pendingKey = pendingKey,
    itemLink = itemLink,
    itemId = itemId,
    itemName = itemName,
    itemTexture = itemTexture,
    itemLevel = itemLevel,
    sourceType = sourceType or "manual",
    mapId = storedMapId,
    x = suppressLocation and nil or ((context and context.x) or x),
    y = suppressLocation and nil or ((context and context.y) or y),
    continent = storedContinent,
    zone = storedZone,
    zoneName = storedZoneName,
    upgradeLevel = context and context.upgradeLevel or nil,
    isWorldforged = context and context.isWorldforged or nil,
    upgradeCandidate = context and context.upgradeCandidate or nil,
  }

  addon.DB:UpsertPendingItem(pendingKey, payload)
  addon:LootDebug(string.format(
    "Queued %s (source=%s, pendingKey=%s, mapId=%s, continent=%s, zone=%s, zoneName=%s, x=%s, y=%s)",
    tostring(itemLink),
    tostring(sourceType or "manual"),
    tostring(pendingKey),
    tostring(payload.mapId or "?"),
    tostring(payload.continent or "?"),
    tostring(payload.zone or "?"),
    tostring(payload.zoneName or "?"),
    tostring(payload.x or "?"),
    tostring(payload.y or "?")
  ))
  if payload.upgradeCandidate then
    addon:LootDebug("Stored as hidden upgrade candidate until vendor confirmation.")
  end
  return self:FinalizePendingRecord(payload)
end

function ItemScan:CaptureItem(itemLink, sourceType)
  if not itemLink then
    return nil
  end
  return self:QueuePendingItem(itemLink, sourceType)
end

function ItemScan:ScanPlayerItems()
  if not GetContainerNumSlots or not GetContainerItemLink then return 0 end
  local found = 0
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, slot)
      if link and self:IsWorldforgedItem(link, true) then
        self:CaptureItem(link, "inventory")
        found = found + 1
      end
    end
  end
  if GetInventoryItemLink then
    for slot = 1, 19 do
      local link = GetInventoryItemLink("player", slot)
      if link and self:IsWorldforgedItem(link, true) then
        self:CaptureItem(link, "equipped")
        found = found + 1
      end
    end
  end
  return found
end

function ItemScan:CaptureMouseover()
  local _, unit = GameTooltip:GetUnit()
  if unit and UnitExists(unit) then
    local itemLink = GetInventoryItemLink(unit, 16) or GetInventoryItemLink(unit, 17)
    if itemLink then
      self:CaptureItem(itemLink, "mouseover-unit")
      return true
    end
  end

  local _, itemLink = GameTooltip:GetItem()
  if itemLink then
    self:CaptureItem(itemLink, "tooltip")
    return true
  end

  return false
end

function ItemScan:CaptureLootMessage(message)
  if type(message) ~= "string" then
    return false
  end

  local found = false
  for itemLink in message:gmatch("|Hitem:.-|h%[.-%]|h") do
    addon:LootDebug("Loot chat match: " .. tostring(itemLink))
    if self:IsWorldforgedItem(itemLink) then
      if addon.AutoConfirm and addon.AutoConfirm.RequestDebugScan then
        addon.AutoConfirm:RequestDebugScan("worldforged-loot")
      end
      self:QueuePendingItem(itemLink, "loot-chat", { isWorldforged = true })
      found = true
    else
      addon:LootDebug("Ignored non-worldforged loot: " .. tostring(itemLink))
    end
  end

  return found
end

function ItemScan:RetryPendingItems(itemId)
  local pendingItems = addon.DB:GetPendingItems()
  for pendingKey, record in pairs(pendingItems) do
    if not itemId or tostring(record.itemId) == tostring(itemId) then
      addon:LootDebug(string.format(
        "Retry pending item %s for itemId=%s",
        tostring(pendingKey),
        tostring(itemId or record.itemId or "?")
      ))
      self:FinalizePendingRecord(record)
    end
  end
end
