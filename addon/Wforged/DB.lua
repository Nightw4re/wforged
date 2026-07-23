local addonName, addon = ...

local DB = {}
addon.DB = DB

local function matchesWeaponFilter(haystack, weaponType)
  local normalized = string.lower(weaponType or "")
  local twoHandedType = normalized:match("^two%-handed (.+)$")
  if twoHandedType then
    return haystack:find("two-hand", 1, true) ~= nil
      and haystack:find(twoHandedType, 1, true) ~= nil
  end
  return haystack:find(normalized, 1, true) ~= nil
end

local function hasBindOnPickup(entry)
  return entry and string.lower(tostring(entry.tooltipText or "")):find("binds when picked up", 1, true) ~= nil
end

local function isUpgradeEntry(entry)
  return entry and (entry.isUpgrade == true or (tonumber(entry.upgradeLevel or 0) or 0) > 0)
end

local function matchesItemType(haystack, itemType)
  if not itemType or itemType == "" or itemType == "base" or itemType == "upgrade" then
    return true
  end
  if itemType == "bags" then
    return haystack:find("slot bag", 1, true) ~= nil
      or haystack:find("slots bag", 1, true) ~= nil
  end
  if itemType == "food" then
    return haystack:find("food", 1, true) ~= nil
      or haystack:find("drink", 1, true) ~= nil
      or haystack:find("consumable", 1, true) ~= nil
      or haystack:find("eating", 1, true) ~= nil
      or haystack:find("drinking", 1, true) ~= nil
      or haystack:find("well fed", 1, true) ~= nil
      or haystack:find("restores", 1, true) ~= nil
  end
  if itemType == "equipment" then
    return haystack:find("requires level", 1, true) ~= nil
      and (haystack:find("armor", 1, true) ~= nil
        or haystack:find("weapon", 1, true) ~= nil
        or haystack:find("one-hand", 1, true) ~= nil
        or haystack:find("two-hand", 1, true) ~= nil
        or haystack:find("finger", 1, true) ~= nil
        or haystack:find("trinket", 1, true) ~= nil)
  end
  if itemType == "other" then
    return not matchesItemType(haystack, "bags")
      and not matchesItemType(haystack, "food")
      and not matchesItemType(haystack, "equipment")
  end
  return true
end

local function ensureTable(root, key)
  if type(root[key]) ~= "table" then
    root[key] = {}
  end
  return root[key]
end

local function normalizeNumber(value)
  if type(value) ~= "number" then
    return nil
  end
  return tonumber(string.format("%.4f", value))
end

local function countTableEntries(tbl)
  local count = 0
  if type(tbl) ~= "table" then
    return count
  end
  for _ in pairs(tbl) do
    count = count + 1
  end
  return count
end

local function isLocationlessSource(source)
  return source == "inventory" or source == "equipped" or source == "upgrade-frame" or source == "upgrade-tooltip"
end

function DB:Init()
  if type(WforgedDB) ~= "table" then
    WforgedDB = {}
  end

  local db = WforgedDB
  db.meta = db.meta or {}
  db.meta.version = addon.version
  db.meta.lastPlayer = UnitName("player")
  db.meta.lastRealm = GetRealmName()
  db.meta.lastUpdatedAt = time()

  ensureTable(db, "itemsByFingerprint")
  ensureTable(db, "spawnPointsByItem")
  ensureTable(db, "vendorsByNpcId")
  ensureTable(db, "upgradeCostsByItem")
  ensureTable(db, "upgradeSourcesByItem")
  ensureTable(db, "observations")
  ensureTable(db, "sync")
  ensureTable(db, "itemsByKey")
  ensureTable(db, "pendingItems")
  ensureTable(db, "settings")
  if db.settings.showDebugLogs == nil then
    db.settings.showDebugLogs = false
  end
  if db.settings.autoConfirmWorldforged == nil then
    db.settings.autoConfirmWorldforged = true
  end
  if db.settings.sendGuildUpdates == nil then db.settings.sendGuildUpdates = true end
  if db.settings.receiveGuildUpdates == nil then db.settings.receiveGuildUpdates = true end

  self.data = db
  local currentRealm = self:GetCurrentRealm()
  for _, entry in pairs(db.itemsByFingerprint or {}) do
    if entry and not entry.realm and entry.lastSource ~= "import" and entry.lastSource ~= "guild" then
      entry.realm = currentRealm
    end
  end
  self:CleanupInvalidUpgradePlaceholders()
  self:CleanupInvalidUpgradeCosts()
  self:PurgeUnknownMapLocations()
  self:ClearInventoryLocations()
  self:RestoreDeadminesMapLocation()
end

function DB:RestoreDeadminesMapLocation()
  if not self.data or self.data.meta.deadminesMapRestoredV2 then return end
  for fingerprint, entry in pairs(self.data.itemsByFingerprint or {}) do
    if entry and entry.itemName == "Defias Sprig" then
      entry.lastMapId, entry.lastX, entry.lastY = 15, 0.409, 0.8196
      entry.lastZoneName = "The Deadmines"
      local points = self.data.spawnPointsByItem[fingerprint]
      if points then
        for pointKey in pairs(points) do points[pointKey] = nil end
        points[string.format("15:%.4f:%.4f", 0.409, 0.8196)] = {
          mapId = 15, x = 0.409, y = 0.8196, zoneName = "The Deadmines", count = 1, firstSeenAt = entry.firstSeenAt, lastSeenAt = entry.lastSeenAt,
        }
      end
    end
  end
  self.data.meta.deadminesMapRestoredV2 = true
end

function DB:ClearInventoryLocations()
  if not self.data then return end
  for _, entry in pairs(self.data.itemsByFingerprint or {}) do
    if entry and isLocationlessSource(entry.lastSource) then
      entry.lastMapId = nil
      entry.lastContinent = nil
      entry.lastZone = nil
      entry.lastZoneName = nil
      entry.lastX = nil
      entry.lastY = nil
    end
  end
end

function DB:PurgeUnknownMapLocations()
  if not self.data or self.data.meta.unknownMapsPurged then return end
  local invalidMaps = { [20] = true, [31] = true, [750] = true, [1220] = true }
  for fingerprint, points in pairs(self.data.spawnPointsByItem or {}) do
    for pointKey, point in pairs(points) do
      if point and invalidMaps[tonumber(point.mapId)] then points[pointKey] = nil end
    end
    if countTableEntries(points) == 0 then self.data.spawnPointsByItem[fingerprint] = nil end
  end
  for _, entry in pairs(self.data.itemsByFingerprint or {}) do
    if entry and invalidMaps[tonumber(entry.lastMapId)] then
      entry.lastMapId = nil
      entry.lastContinent = nil
      entry.lastZone = nil
      entry.lastZoneName = nil
      entry.lastX = nil
      entry.lastY = nil
    end
  end
  self.data.meta.unknownMapsPurged = true
end

function DB:GetCharacterKey()
  return string.format("%s-%s", UnitName("player") or "unknown", GetRealmName() or "unknown")
end

function DB:GetCurrentRealm()
  return (GetRealmName and GetRealmName()) or "Unknown"
end

function DB:CleanupInvalidUpgradePlaceholders()
  if not self.data then
    return
  end

  for fingerprint, entry in pairs(self.data.itemsByFingerprint) do
    if entry and entry.lastSource == "upgrade-frame" and not entry.itemLink then
      self.data.itemsByFingerprint[fingerprint] = nil
    end
  end

  for itemKey, bucket in pairs(self.data.itemsByKey) do
    if bucket and bucket.bestFingerprint and not self.data.itemsByFingerprint[bucket.bestFingerprint] then
      local keptVariants = {}
      local keptCount = 0

      for variantKey, variant in pairs(bucket.variants or {}) do
        if variant and variant.fingerprint and self.data.itemsByFingerprint[variant.fingerprint] then
          keptVariants[variantKey] = variant
          keptCount = keptCount + 1
        end
      end

      if keptCount == 0 then
        self.data.itemsByKey[itemKey] = nil
      else
        bucket.variants = keptVariants
        bucket.variantCount = keptCount
        for _, variant in pairs(keptVariants) do
          bucket.bestFingerprint = variant.fingerprint
          break
        end
      end
    end
  end
end

function DB:CleanupInvalidUpgradeCosts()
  if not self.data then
    return
  end

  for itemKey, bucket in pairs(self.data.upgradeCostsByItem or {}) do
    if type(bucket) == "table" then
      for levelKey, info in pairs(bucket) do
        if info and info.currency == "rune" and tonumber(info.cost or 0) and tonumber(info.cost or 0) > 100000 then
          bucket[levelKey] = nil
        end
      end

      if next(bucket) == nil then
        self.data.upgradeCostsByItem[itemKey] = nil
      end
    end
  end

  for npcId, vendorEntry in pairs(self.data.vendorsByNpcId or {}) do
    if type(vendorEntry) == "table" and type(vendorEntry.upgrades) == "table" then
      for itemKey, info in pairs(vendorEntry.upgrades) do
        if info and info.currency == "rune" and tonumber(info.cost or 0) and tonumber(info.cost or 0) > 100000 then
          vendorEntry.upgrades[itemKey] = nil
        end
      end

      if next(vendorEntry.upgrades) == nil then
        self.data.vendorsByNpcId[npcId] = nil
      end
    end
  end
end

function DB:GetItemEntry(itemKey)
  if not self.data or not itemKey then
    return nil, nil
  end

  local bucket = self.data.itemsByKey[itemKey]
  local fingerprint = bucket and bucket.bestFingerprint or nil
  return bucket, fingerprint and self.data.itemsByFingerprint[fingerprint] or nil
end

function DB:GetPreferredFingerprint(itemKey, bucket)
  bucket = bucket or self.data.itemsByKey[itemKey]
  if not bucket then return nil end
  for _, variant in pairs(bucket.variants or {}) do
    local fingerprint = variant and variant.fingerprint
    local entry = fingerprint and self.data.itemsByFingerprint[fingerprint]
    if entry and (entry.lastSource == "loot-chat" or entry.lastSource == "loot") and entry.lastMapId and entry.lastX and entry.lastY then
      return fingerprint
    end
  end
  return bucket.bestFingerprint
end

function DB:BuildFingerprint(itemLink, upgradeLevel, statsText)
  local itemString = itemLink or "unknown-item"
  local statBlob = statsText or "no-stats"
  local levelBlob = tostring(upgradeLevel or 0)
  return table.concat({ itemString, levelBlob, statBlob }, "||")
end

function DB:BuildItemKey(itemId, itemName)
  if itemId then
    return "item:" .. tostring(itemId)
  end
  return "name:" .. string.lower(itemName or "unknown-item")
end

function DB:BuildVariantKey(payload)
  return table.concat({
    tostring(payload.effectiveLevel or 0),
    tostring(payload.upgradeLevel or 0),
    payload.statsText or "no-stats",
  }, "||")
end

function DB:ShouldReplaceSnapshot(existing, candidate)
  if not existing then
    return true
  end

  local existingLevel = tonumber(existing.effectiveLevel or existing.itemLevel or 0) or 0
  local candidateLevel = tonumber(candidate.effectiveLevel or candidate.itemLevel or 0) or 0
  if candidateLevel ~= existingLevel then
    return candidateLevel > existingLevel
  end

  local existingUpgrade = tonumber(existing.upgradeLevel or 0) or 0
  local candidateUpgrade = tonumber(candidate.upgradeLevel or 0) or 0
  if candidateUpgrade ~= existingUpgrade then
    return candidateUpgrade > existingUpgrade
  end

  return (candidate.lastSeenAt or time()) >= (existing.lastSeenAt or 0)
end

function DB:MergeItemSnapshot(itemKey, fingerprint, payload)
  local bucket = self.data.itemsByKey[itemKey]
  if not bucket then
    bucket = {
      itemId = payload.itemId,
      itemName = payload.itemName,
      bestFingerprint = fingerprint,
      highestLevel = payload.effectiveLevel or payload.itemLevel or 0,
      variants = {},
      variantCount = 0,
    }
    self.data.itemsByKey[itemKey] = bucket
  end

  bucket.itemId = payload.itemId or bucket.itemId
  bucket.itemName = payload.itemName or bucket.itemName
  local variantKey = self:BuildVariantKey(payload)
  if not bucket.variants[variantKey] then
    bucket.variantCount = (bucket.variantCount or 0) + 1
  end

  bucket.variants[variantKey] = {
    fingerprint = fingerprint,
    effectiveLevel = payload.effectiveLevel,
    upgradeLevel = payload.upgradeLevel,
    statsText = payload.statsText,
    lastSeenAt = time(),
  }

  local currentBest = bucket.bestFingerprint and self.data.itemsByFingerprint[bucket.bestFingerprint]
  if self:ShouldReplaceSnapshot(currentBest, payload) then
    bucket.bestFingerprint = fingerprint
    bucket.highestLevel = payload.effectiveLevel or payload.itemLevel or bucket.highestLevel
  end
end

function DB:RecordItemObservation(payload)
  if not self.data then
    return nil
  end

  local fingerprint = payload.fingerprint
  if not fingerprint then
    return nil
  end

  local itemsByFingerprint = self.data.itemsByFingerprint
  local observations = self.data.observations
  local itemKey = payload.itemKey or self:BuildItemKey(payload.itemId, payload.itemName)
  local entry = itemsByFingerprint[fingerprint] or {
    firstSeenAt = time(),
    sources = {},
  }
  payload.realm = payload.realm or self:GetCurrentRealm()
  if entry.realm and entry.realm == self:GetCurrentRealm() and payload.realm ~= entry.realm
    and (payload.sourceType == "import" or payload.sourceType == "guild") then
    return entry
  end

  entry.itemKey = itemKey
  entry.itemLink = payload.itemLink
  entry.itemName = payload.itemName
  entry.itemId = payload.itemId
  entry.itemTexture = payload.itemTexture
  entry.isWorldforged = entry.isWorldforged or (payload.isWorldforged and true or false)
  entry.upgradeCandidate = (not entry.isWorldforged) and (payload.upgradeCandidate and true or entry.upgradeCandidate) or nil
  entry.realm = payload.realm
  entry.quality = payload.quality
  entry.itemLevel = payload.itemLevel
  entry.effectiveLevel = payload.effectiveLevel or payload.itemLevel
  entry.upgradeLevel = payload.upgradeLevel
  entry.isUpgrade = entry.isUpgrade or (payload.isUpgrade and true or false)
  entry.statsText = payload.statsText
  entry.tooltipText = payload.tooltipText
  entry.lastSeenAt = payload.observedAt or time()
  entry.lastSource = payload.sourceType
  local hasLocation = payload.mapId and payload.x and payload.y
  if hasLocation or not isLocationlessSource(payload.sourceType) then
    entry.lastMapId = payload.mapId
    entry.lastContinent = payload.continent
    entry.lastZone = payload.zone
    entry.lastZoneName = payload.zoneName
    entry.lastX = normalizeNumber(payload.x)
    entry.lastY = normalizeNumber(payload.y)
  end
  entry.observationCount = (entry.observationCount or 0) + 1
  entry.sources[payload.sourceType or "unknown"] = true
  itemsByFingerprint[fingerprint] = entry

  observations[#observations + 1] = {
    fingerprint = fingerprint,
    sourceType = payload.sourceType,
    mapId = payload.mapId,
    x = normalizeNumber(payload.x),
    y = normalizeNumber(payload.y),
    observedAt = payload.observedAt or time(),
    character = self:GetCharacterKey(),
  }

  self:MergeItemSnapshot(itemKey, fingerprint, entry)
  return entry
end

function DB:RecordSpawnPoint(fingerprint, mapId, x, y, context)
  if not self.data or not fingerprint or not mapId or not x or not y then
    return
  end

  local bucket = self.data.spawnPointsByItem[fingerprint]
  if not bucket then
    bucket = {}
    self.data.spawnPointsByItem[fingerprint] = bucket
  end

  local key = string.format("%s:%.4f:%.4f", tostring(mapId), x, y)
  local existing = bucket[key] or {
    mapId = mapId,
    x = normalizeNumber(x),
    y = normalizeNumber(y),
    continent = context and context.continent or nil,
    zone = context and context.zone or nil,
    zoneName = context and context.zoneName or nil,
    firstSeenAt = time(),
    seenCount = 0,
  }

  existing.lastSeenAt = time()
  existing.continent = (context and context.continent) or existing.continent
  existing.zone = (context and context.zone) or existing.zone
  existing.zoneName = (context and context.zoneName) or existing.zoneName
  existing.seenCount = (existing.seenCount or 0) + 1
  bucket[key] = existing
end

function DB:RecordVendorUpgrade(payload)
  if not self.data or not payload.npcId or not payload.itemKey then
    return
  end

  local promoted = 0
  for _, entry in pairs(self.data.itemsByFingerprint or {}) do
    if tonumber(entry.itemId) == tonumber(payload.itemId) and entry.quality ~= 0 and hasBindOnPickup(entry) then
      entry.isWorldforged = true
      entry.isUpgrade = true
      entry.upgradeCandidate = nil
      promoted = promoted + 1
    end
  end
  if promoted > 0 then
    addon:LootDebug(string.format("Promoted upgrade candidate: itemId=%s variants=%d", tostring(payload.itemId), promoted))
    if addon.SearchUI and addon.SearchUI.frame and addon.SearchUI.frame:IsShown() then
      addon.SearchUI:Refresh(addon.SearchUI.frame.editBox and addon.SearchUI.frame.editBox:GetText() or "")
    end
  end

  local vendors = self.data.vendorsByNpcId
  local upgrades = self.data.upgradeCostsByItem
  local upgradeSources = self.data.upgradeSourcesByItem
  local vendorEntry = vendors[payload.npcId] or {
    npcName = payload.npcName,
    mapId = payload.mapId,
    x = normalizeNumber(payload.x),
    y = normalizeNumber(payload.y),
    upgrades = {},
    firstSeenAt = time(),
  }

  vendorEntry.npcName = payload.npcName or vendorEntry.npcName
  vendorEntry.mapId = payload.mapId or vendorEntry.mapId
  vendorEntry.x = normalizeNumber(payload.x) or vendorEntry.x
  vendorEntry.y = normalizeNumber(payload.y) or vendorEntry.y
  vendorEntry.lastSeenAt = time()
  vendorEntry.upgrades[payload.itemKey] = {
    cost = payload.cost,
    currency = payload.currency,
    sourceItemName = payload.sourceItemName,
    fromLevel = payload.fromLevel,
    toLevel = payload.toLevel,
    observedAt = time(),
  }
  vendors[payload.npcId] = vendorEntry

  upgrades[payload.itemKey] = upgrades[payload.itemKey] or {}
  upgrades[payload.itemKey][payload.toLevel or 0] = {
    npcId = payload.npcId,
    npcName = payload.npcName,
    itemLink = payload.itemLink,
    itemName = payload.itemName,
    cost = payload.cost,
    currency = payload.currency,
    sourceItemName = payload.sourceItemName,
    fromLevel = payload.fromLevel,
    toLevel = payload.toLevel,
    observedAt = time(),
  }

  if payload.sourceItemKey or payload.sourceItemId or payload.sourceItemName then
    upgradeSources[payload.itemKey] = {
      targetItemKey = payload.itemKey,
      targetItemId = payload.itemId,
      targetItemName = payload.itemName,
      sourceItemKey = payload.sourceItemKey,
      sourceItemId = payload.sourceItemId,
      sourceItemName = payload.sourceItemName,
      cost = payload.cost,
      currency = payload.currency,
      npcId = payload.npcId,
      npcName = payload.npcName,
      fromLevel = payload.fromLevel,
      toLevel = payload.toLevel,
      observedAt = time(),
    }
  end
end

function DB:GetUpgradeInfo(itemKey)
  if not self.data or not itemKey then
    return nil
  end

  local bucket = self.data.upgradeCostsByItem[itemKey]
  if not bucket then
    return nil
  end

  local best = nil
  for _, info in pairs(bucket) do
    if not best then
      best = info
    elseif (tonumber(info.toLevel or 0) or 0) > (tonumber(best.toLevel or 0) or 0) then
      best = info
    elseif (tonumber(info.observedAt or 0) or 0) > (tonumber(best.observedAt or 0) or 0) then
      best = info
    end
  end

  return best
end

function DB:GetUpgradeSourceInfo(itemKey)
  if not self.data or not itemKey then
    return nil
  end

  return self.data.upgradeSourcesByItem[itemKey]
end

function DB:GetResolvedSourceLocation(itemKey, visited)
  if not self.data or not itemKey then
    return nil
  end

  visited = visited or {}
  if visited[itemKey] then
    return nil
  end
  visited[itemKey] = true

  local bucket, entry = self:GetItemEntry(itemKey)
  local sourceInfo = self:GetUpgradeSourceInfo(itemKey)

  -- Upgrade entries inherit the source item's discovery location first.
  if sourceInfo then
    if sourceInfo.sourceItemKey then
      local location, resolvedKey = self:GetResolvedSourceLocation(sourceInfo.sourceItemKey, visited)
      if location then return location, resolvedKey end
    end

    for candidateKey, candidateBucket in pairs(self.data.itemsByKey or {}) do
      local candidateFingerprint = candidateBucket.bestFingerprint
      local candidateEntry = candidateFingerprint and self.data.itemsByFingerprint[candidateFingerprint]
      local idMatches = sourceInfo.sourceItemId and candidateEntry and tonumber(candidateEntry.itemId) == tonumber(sourceInfo.sourceItemId)
      local nameMatches = sourceInfo.sourceItemName and candidateBucket.itemName and string.lower(candidateBucket.itemName) == string.lower(sourceInfo.sourceItemName)
      if idMatches or nameMatches then
        local location, resolvedKey = self:GetResolvedSourceLocation(candidateKey, visited)
        if location then return location, resolvedKey end
      end
    end
  end

  if bucket and bucket.bestFingerprint then
    local directLocation = self:GetBestLocationForFingerprint(bucket.bestFingerprint)
    if directLocation and directLocation.mapId and directLocation.x and directLocation.y and entry and not isLocationlessSource(entry.lastSource) then
      return directLocation, itemKey
    end
  end

  return nil
end

function DB:GetSummary()
  if not self.data then
    return {
      items = 0,
      spawnPoints = 0,
      vendors = 0,
      observations = 0,
      pending = 0,
    }
  end

  local spawnCount = 0
  for _, bucket in pairs(self.data.spawnPointsByItem) do
    for _ in pairs(bucket) do
      spawnCount = spawnCount + 1
    end
  end

  local itemCount = 0
  for _ in pairs(self.data.itemsByKey) do
    itemCount = itemCount + 1
  end

  local vendorCount = 0
  for _ in pairs(self.data.vendorsByNpcId) do
    vendorCount = vendorCount + 1
  end

  return {
    items = itemCount,
    spawnPoints = spawnCount,
    vendors = vendorCount,
    observations = #self.data.observations,
    pending = countTableEntries(self.data.pendingItems),
  }
end

function DB:UpsertPendingItem(pendingKey, payload)
  if not self.data or not pendingKey or type(payload) ~= "table" then
    return
  end

  local entry = self.data.pendingItems[pendingKey] or {
    firstSeenAt = time(),
    attempts = 0,
  }

  for key, value in pairs(payload) do
    entry[key] = value
  end

  entry.lastSeenAt = time()
  entry.attempts = (entry.attempts or 0) + 1
  self.data.pendingItems[pendingKey] = entry
end

function DB:GetPendingItems()
  if not self.data then
    return {}
  end
  return self.data.pendingItems
end

function DB:RemovePendingItem(pendingKey)
  if self.data then
    self.data.pendingItems[pendingKey] = nil
  end
end

function DB:RemoveItemById(itemId)
  if not self.data or not tonumber(itemId) then
    return 0
  end

  itemId = tonumber(itemId)
  local removed = 0
  local removedKeys = {}
  for fingerprint, entry in pairs(self.data.itemsByFingerprint or {}) do
    if entry and tonumber(entry.itemId) == itemId then
      removed = removed + 1
      removedKeys[entry.itemKey] = true
      self.data.itemsByFingerprint[fingerprint] = nil
      self.data.spawnPointsByItem[fingerprint] = nil
    end
  end

  for itemKey in pairs(removedKeys) do
    self.data.itemsByKey[itemKey] = nil
    self.data.upgradeCostsByItem[itemKey] = nil
    self.data.upgradeSourcesByItem[itemKey] = nil
  end

  for key, observation in pairs(self.data.observations or {}) do
    if observation and tonumber(observation.itemId) == itemId then
      self.data.observations[key] = nil
    end
  end

  for pendingKey, pending in pairs(self.data.pendingItems or {}) do
    local pendingId = pending and pending.itemId
    if not pendingId and type(pendingKey) == "string" then
      pendingId = pendingKey:match("item:(%d+)")
    end
    if tonumber(pendingId) == itemId then
      self.data.pendingItems[pendingKey] = nil
    end
  end

  return removed
end

function DB:RemoveItemsByName(itemName)
  if not self.data or not itemName or itemName == "" then
    return 0
  end
  local target = string.lower(itemName)
  local removed = 0
  local ids = {}
  for _, entry in pairs(self.data.itemsByFingerprint or {}) do
    if entry and string.lower(tostring(entry.itemName or "")) == target and entry.itemId then
      ids[tonumber(entry.itemId)] = true
    end
  end
  for itemId in pairs(ids) do
    removed = removed + self:RemoveItemById(itemId)
  end
  return removed
end

function DB:CleanupInvalidItems(apply)
  if not self.data then return 0 end
  local removeIds = {}
  local baseCount, upgradeCount = 0, 0
  for _, entry in pairs(self.data.itemsByFingerprint or {}) do
    local upgradeInfo = self:GetUpgradeInfo(entry.itemKey)
    local hasUpgradeSource = self.data.upgradeSourcesByItem[entry.itemKey] ~= nil
    local isUpgrade = entry.isUpgrade == true
      or (tonumber(entry.upgradeLevel or 0) or 0) > 0
      or upgradeInfo ~= nil
      or hasUpgradeSource
    local mapId = tonumber(entry.lastMapId)
    local x = tonumber(entry.lastX)
    local y = tonumber(entry.lastY)
    local hasLocation = mapId and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1
    local hasCorruptLocation = (entry.lastMapId ~= nil and not mapId)
      or (entry.lastX ~= nil and (not x or x < 0 or x > 1))
      or (entry.lastY ~= nil and (not y or y < 0 or y > 1))
    local hasUpgradeCost = entry.upgradeCost ~= nil or (upgradeInfo and upgradeInfo.cost ~= nil)
    if entry.itemId and entry.isWorldforged == true
      and ((not isUpgrade and hasCorruptLocation) or (isUpgrade and not hasUpgradeCost)) then
      local id = tonumber(entry.itemId)
      if not removeIds[id] then
        removeIds[id] = isUpgrade and "upgrade" or "base"
        if isUpgrade then upgradeCount = upgradeCount + 1 else baseCount = baseCount + 1 end
      end
    end
  end

  local removed = 0
  for itemId in pairs(removeIds) do
    if apply then
      removed = removed + self:RemoveItemById(itemId)
    else
      removed = removed + 1
    end
  end
  return removed, baseCount, upgradeCount
end

function DB:GetSettings()
  if not self.data then
    return {
      showDebugLogs = false,
      autoConfirmWorldforged = true,
    }
  end

  return self.data.settings
end

function DB:GetBestLocationForFingerprint(fingerprint)
  if not self.data or not fingerprint then
    return nil
  end

  local bucket = self.data.spawnPointsByItem[fingerprint]
  if bucket then
    local best = nil
    for _, point in pairs(bucket) do
      if not best or (point.seenCount or 0) > (best.seenCount or 0) then
        best = point
      end
    end
    if best then
    return {
      mapId = best.mapId,
      continent = best.continent,
      zone = best.zone,
      zoneName = best.zoneName,
      x = best.x,
      y = best.y,
    }
    end
  end

  local entry = self.data.itemsByFingerprint[fingerprint]
  if entry and not isLocationlessSource(entry.lastSource) and entry.lastMapId and entry.lastX and entry.lastY then
    return {
      mapId = entry.lastMapId,
      continent = entry.lastContinent,
      zone = entry.lastZone,
      zoneName = entry.lastZoneName,
      x = entry.lastX,
      y = entry.lastY,
    }
  end

  return nil
end

function DB:SearchItems(query, filters)
  local results = {}
  if not self.data then
    return results
  end

  local normalizedQuery = string.lower(strtrim(query or ""))
  filters = filters or {}
  local terms = {}
  for term in normalizedQuery:gmatch("%S+") do
    terms[#terms + 1] = term
  end

  for itemKey, bucket in pairs(self.data.itemsByKey) do
    local hasUpgradeInfo = self:GetUpgradeInfo(itemKey) ~= nil
    local fingerprint = self:GetPreferredFingerprint(itemKey, bucket)
    if filters.variant == "base" or filters.variant == "upgrade" then
      local wantUpgrade = filters.variant == "upgrade"
      for _, variant in pairs(bucket.variants or {}) do
        local candidateFingerprint = variant and variant.fingerprint
        local candidate = candidateFingerprint and self.data.itemsByFingerprint[candidateFingerprint]
        local isUpgrade = isUpgradeEntry(candidate) or hasUpgradeInfo
        if candidate and isUpgrade == wantUpgrade then
          fingerprint = candidateFingerprint
          break
        end
      end
    end
    local entry = fingerprint and self.data.itemsByFingerprint[fingerprint]
    if entry then
      local zoneName = addon.ResolveZoneName and addon:ResolveZoneName(
        entry.lastMapId, entry.lastContinent, entry.lastZone, entry.lastZoneName
      ) or entry.lastZoneName
      local upgradeInfo = self:GetUpgradeInfo(itemKey)
      local haystack = string.lower(table.concat({
        bucket.itemName or "",
        tostring(entry.itemId or bucket.itemId or ""),
        zoneName or "",
        entry.zoneRepairPending and "unknown zone" or "",
        entry.statsText or "",
        entry.tooltipText or "",
        tostring(entry.itemLevel or ""),
        tostring(entry.effectiveLevel or ""),
        tostring(entry.upgradeLevel or ""),
        tostring(upgradeInfo and upgradeInfo.cost or ""),
      }, " "))

      local matches = true
      for _, term in ipairs(terms) do
        if not haystack:find(term, 1, true) then
          matches = false
          break
        end
      end

      if matches and filters.armorType and filters.armorType ~= "" and not haystack:find(string.lower(filters.armorType), 1, true) then
        matches = false
      end
      if matches and filters.weaponType and filters.weaponType ~= "" and not matchesWeaponFilter(haystack, filters.weaponType) then
        matches = false
      end
      if matches and filters.quality and filters.quality ~= "" then
        local qualityNames = { [0] = "poor", [1] = "common", [2] = "uncommon", [3] = "rare", [4] = "epic", [5] = "legendary" }
        if qualityNames[tonumber(entry.quality)] ~= string.lower(filters.quality) then
          matches = false
        end
      end
      if matches and filters.slot and filters.slot ~= "" and not haystack:find(string.lower(filters.slot), 1, true) then
        matches = false
      end
      if matches and filters.stat1 and filters.stat1 ~= "" and not haystack:find(string.lower(filters.stat1), 1, true) then
        matches = false
      end
      if matches and filters.stat2 and filters.stat2 ~= "" and not haystack:find(string.lower(filters.stat2), 1, true) then
        matches = false
      end
      if matches and filters.level and filters.level ~= "" then
        local level = tonumber(entry.itemLevel or entry.effectiveLevel or 0) or 0
        local entryIsUpgrade = isUpgradeEntry(entry) or hasUpgradeInfo
        if filters.level == "upgrade" and not entryIsUpgrade then
          matches = false
        elseif filters.level == "base" and entryIsUpgrade then
          matches = false
        elseif tonumber(filters.level) and level < tonumber(filters.level) then
          matches = false
        end
      end
      if matches and filters.variant and filters.variant ~= "" then
        local isUpgrade = isUpgradeEntry(entry) or hasUpgradeInfo
        if filters.variant == "upgrade" and not isUpgrade then
          matches = false
        elseif filters.variant == "base" and isUpgrade then
          matches = false
        end
      end
      if matches and filters.variant and filters.variant ~= ""
        and filters.variant ~= "base" and filters.variant ~= "upgrade"
        and not matchesItemType(haystack, filters.variant) then
        matches = false
      end

      if matches then
        if entry.isWorldforged == true and entry.quality ~= 0 and hasBindOnPickup(entry) and entry.itemLink then
          local location = self:GetBestLocationForFingerprint(fingerprint)
          local upgradeInfo = self:GetUpgradeInfo(itemKey)
          local sourceInfo = self:GetUpgradeSourceInfo(itemKey)
          local sourceLocation, resolvedSourceItemKey = self:GetResolvedSourceLocation(itemKey)
          local sourceBucket, sourceEntry = self:GetItemEntry(resolvedSourceItemKey)
          if sourceLocation and sourceLocation.mapId then
            location = sourceLocation
          end
          if isLocationlessSource(entry.lastSource) then
            location = nil
          end
          results[#results + 1] = {
            itemKey = itemKey,
            fingerprint = fingerprint,
            itemId = entry.itemId or bucket.itemId,
            realm = entry.realm or "Unknown",
            itemName = bucket.itemName or entry.itemName or "Unknown",
            itemLink = entry.itemLink,
            itemTexture = entry.itemTexture,
            quality = entry.quality,
            itemLevel = entry.itemLevel or 0,
            effectiveLevel = entry.effectiveLevel or 0,
            upgradeLevel = entry.upgradeLevel or (isUpgrade and 1 or 0),
            statsText = entry.statsText or "",
            tooltipText = entry.tooltipText or "",
            variantCount = bucket.variantCount or countTableEntries(bucket.variants),
            lastSeenAt = entry.lastSeenAt or 0,
            lastSource = entry.lastSource or "",
            observationCount = entry.observationCount or 0,
            upgradeCost = upgradeInfo and upgradeInfo.cost or nil,
            upgradeCurrency = upgradeInfo and upgradeInfo.currency or nil,
            upgradeVendorName = upgradeInfo and upgradeInfo.npcName or nil,
            upgradeToLevel = upgradeInfo and upgradeInfo.toLevel or nil,
            sourceItemKey = sourceInfo and sourceInfo.sourceItemKey or nil,
            sourceItemId = sourceInfo and sourceInfo.sourceItemId or nil,
            sourceItemName = sourceInfo and sourceInfo.sourceItemName or nil,
            resolvedSourceItemKey = resolvedSourceItemKey,
            resolvedSourceItemName = sourceBucket and sourceBucket.itemName or sourceEntry and sourceEntry.itemName or nil,
            lastMapId = (location and location.mapId) or (not isLocationlessSource(entry.lastSource) and entry.lastMapId or nil),
            lastContinent = (location and location.continent) or (not isLocationlessSource(entry.lastSource) and entry.lastContinent or nil),
            lastZone = (location and location.zone) or (not isLocationlessSource(entry.lastSource) and entry.lastZone or nil),
            lastZoneName = (location and location.zoneName) or (not isLocationlessSource(entry.lastSource) and entry.lastZoneName or nil),
            zoneRepairPending = entry.zoneRepairPending == true,
            lastX = (location and location.x) or (not isLocationlessSource(entry.lastSource) and entry.lastX or nil),
            lastY = (location and location.y) or (not isLocationlessSource(entry.lastSource) and entry.lastY or nil),
          }
        end
      end
    end
  end

  table.sort(results, function(a, b)
    if a.effectiveLevel ~= b.effectiveLevel then
      return a.effectiveLevel > b.effectiveLevel
    end
    return a.itemName < b.itemName
  end)

  return results
end
