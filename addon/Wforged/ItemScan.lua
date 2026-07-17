local addonName, addon = ...

local ItemScan = {}
addon.ItemScan = ItemScan

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
    isWorldforged = self:IsWorldforgedItem(record.itemLink, true),
    quality = quality,
    itemLevel = itemLevel,
    effectiveLevel = effectiveLevel,
    upgradeLevel = upgradeLevel,
    statsText = statsText,
    tooltipText = tooltipText,
    sourceType = record.sourceType or "manual",
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
