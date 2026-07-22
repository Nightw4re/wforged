local addonName, addon = ...

local Sync = {}
addon.Sync = Sync

Sync.prefix = "WFORGED"
Sync.exportFormat = "WFGDB7"
Sync.importBatchSize = 2
Sync.importInterval = 0.5
Sync.testImport = "WFGDB6;WFG6|450559|40|0.7154|0.7379|1784222003;WFG6|450557|40|0.5317|0.7906|1784195081;WFG6|450748|40|0.6078|0.5827|1784194402;WFG6|1388996||1784192678;WFG6|1388679||1784192678;WFG6|450934||1784192669;WFG6|521267||1784192669;WFG6|450556|40|0.428|0.885|1784221802;WFG6|1388570||1784192678;WFG6|450555|40|0.3356|0.8647|1784221687;WFG6|1388779||1784192678;WFG6|450551||1784192669;WFG6|515681||1784192669;WFG6|1388546||1784192678;WFG6|515687|40|0.3573|0.904|1784221326;WFG6|450564|40|0.4137|0.6647|1784197106;WFG6|515430||1784192669;WFG6|450562|40|0.4007|0.68|1784194762;WFG6|451117||1784192669;WFG6|450593|35|0.1914|0.5561|1784222456;WFG6|450563|15|0.409|0.8196|1784200008;WFG6|515684|40|0.7007|0.7482|1784222170;WFG6|450528||1784192669;WFG6|450594|35|0.1747|0.5636|1784222299;WFG6|1388997||1784192678;WFG6|450673||1784192669;WFG6|1389367||1784192678;WFG6|450909||1784192669;WFG6|1388771||1784192678;WFG6|515429||1784192669"

local function encode(value)
  return (tostring(value or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub(";", "%%3B"):gsub("\n", "%%0A"))
end

local function decode(value)
  return tostring(value or ""):gsub("%%0A", "\n"):gsub("%%3B", ";"):gsub("%%7C", "|"):gsub("%%25", "%%")
end

local function splitPayload(record)
  local fields = {}
  for value in string.gmatch(tostring(record or ""), "[^|]+") do
    fields[#fields + 1] = decode(value)
  end
  return fields
end

local function makeItemPayload(entry)
  local mapId, x, y = entry.lastMapId, entry.lastX, entry.lastY
  local numericX, numericY = tonumber(x), tonumber(y)
  local malformedLocation = (x and (not numericX or numericX < 0 or numericX > 1))
    or (y and (not numericY or numericY < 0 or numericY > 1))
  if malformedLocation then
    mapId, x, y = nil, nil, nil
  else
    x, y = numericX, numericY
  end
  local observedAt = tonumber(entry.lastSeenAt or 0) or 0
  if observedAt <= 0 then observedAt = entry.firstSeenAt or time() end
  if not mapId or not x or not y then
    return table.concat({ "WFG6", encode(entry.itemId), "", encode(observedAt), encode(entry.realm or "Unknown") }, "|")
  end
  return table.concat({
    "WFG6", encode(entry.itemId), encode(mapId), encode(x), encode(y), encode(observedAt), encode(entry.realm or "Unknown"),
  }, "|")
end

local function decodePayload(fields)
  if fields[1] ~= "WFG6" then
    return nil
  end
  local itemId = tonumber(fields[2])
  local itemName = itemId and GetItemInfo(itemId) or nil
  itemName = itemName or ("Item #" .. tostring(itemId or "?"))
  local itemLink = itemId and string.format("|Hitem:%d:0:0:0:0:0:0:0:0|h[%s]|h", itemId, itemName) or nil
  local itemInfoName, _, quality, itemLevel, _, _, _, _, _, itemTexture = itemLink and GetItemInfo(itemLink) or nil
  itemName = itemInfoName or itemName
  local hasLocation = fields[3] and fields[3] ~= "" and fields[4] and fields[5]
  local observedAt = hasLocation and fields[6] or fields[3]
  local realm = hasLocation and fields[7] or fields[4]
  local mapId = hasLocation and tonumber(fields[3]) or nil
  local zoneName = mapId and GetMapNameByID and GetMapNameByID(mapId) or nil
  if not zoneName and mapId and addon.ResolveZoneName then
    zoneName = addon:ResolveZoneName(mapId, nil, nil, nil)
  end
  local knownZoneNames = {
    [15] = "The Deadmines",
    [35] = "Duskwood",
    [40] = "Westfall",
  }
  zoneName = zoneName or (mapId and knownZoneNames[mapId]) or nil
  return {
    fingerprint = string.format("id:%d", itemId or 0),
    itemId = itemId, itemName = itemName, itemLink = itemLink,
    itemTexture = itemTexture, quality = quality, itemLevel = itemLevel,
    effectiveLevel = itemLevel, upgradeLevel = 0, sourceType = "import", mapId = mapId, zoneName = zoneName,
    x = hasLocation and tonumber(fields[4]) or nil, y = hasLocation and tonumber(fields[5]) or nil,
    observedAt = tonumber(observedAt) or time(), isWorldforged = true, realm = realm ~= "" and realm or "Unknown",
  }
end

function Sync:RefreshItemInfo(itemId)
  itemId = tonumber(itemId)
  if not itemId or not GetItemInfo then return end
  local queryLink = string.format("|Hitem:%d:0:0:0:0:0:0:0:0|h[Item]|h", itemId)
  local name, link, quality, level, _, _, _, _, _, texture = GetItemInfo(queryLink)
  if not name then return end
  local finalize = addon.ItemScan and addon.ItemScan.FinalizePendingRecord
  for _, entry in pairs(addon.DB.data.itemsByFingerprint or {}) do
    if tonumber(entry.itemId) == itemId then
      if finalize and (not entry.statsText or entry.statsText == "" or not entry.tooltipText or entry.tooltipText == "") then
        finalize(addon.ItemScan, {
          itemId = itemId,
          itemLink = entry.itemLink or link,
          pendingKey = "import:item:" .. tostring(itemId),
          mapId = entry.lastMapId,
          x = entry.lastX,
          y = entry.lastY,
          upgradeLevel = entry.upgradeLevel or 0,
          sourceType = entry.lastSource or "import",
        })
      end
      entry.itemName = name or entry.itemName
      entry.itemLink = link or entry.itemLink
      entry.quality = quality or entry.quality
      entry.itemLevel = level or entry.itemLevel
      entry.effectiveLevel = entry.effectiveLevel or level
      entry.itemTexture = texture or entry.itemTexture
    end
  end
  if addon.DB.Save then addon.DB:Save() end
  if addon.SearchUI and addon.SearchUI.frame and addon.SearchUI.frame:IsShown() then
    addon.SearchUI:Refresh(addon.SearchUI.frame.editBox and addon.SearchUI.frame.editBox:GetText() or "")
  end
end

local function serializeSummary(summary)
  return table.concat({
    tostring(summary.items or 0),
    tostring(summary.spawnPoints or 0),
    tostring(summary.vendors or 0),
    tostring(summary.observations or 0),
  }, ",")
end

function Sync:Init()
  self.pendingImports = self.pendingImports or {}
  self.pendingImportIndex = self.pendingImportIndex or 1
  self.importElapsed = 0
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(self.prefix)
  elseif RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix(self.prefix)
  end
end

function Sync:BroadcastSummary(channel)
  local settings = addon.DB:GetSettings()
  if channel == "GUILD" and settings.sendGuildUpdates == false then return false end
  local summary = addon.DB:GetSummary()
  local payload = "SUMMARY:" .. serializeSummary(summary)

  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(self.prefix, payload, channel or "GUILD")
  elseif SendAddonMessage then
    SendAddonMessage(self.prefix, payload, channel or "GUILD")
  end
end

function Sync:Export()
  addon:LootDebug("Export format: WFGDB7 / grouped locations")
  local groups = {}
  for fingerprint, entry in pairs(addon.DB.data.itemsByFingerprint or {}) do
    if entry.isWorldforged and entry.itemId and entry.lastMapId and entry.lastX and entry.lastY then
      local realm = encode(entry.realm or "Unknown")
      local mapId = encode(entry.lastMapId)
      local x = encode(entry.lastX)
      local y = encode(entry.lastY)
      local key = table.concat({ realm, mapId, x, y }, "|")
      groups[key] = groups[key] or { realm = realm, mapId = mapId, x = x, y = y, items = {} }
      groups[key].items[#groups[key].items + 1] = table.concat({ entry.itemId, tonumber(entry.lastSeenAt or entry.firstSeenAt or 0) or 0 }, ":")
    end
  end
  local parts = { "WFGDB7" }
  for _, group in pairs(groups) do
    table.sort(group.items)
    parts[#parts + 1] = table.concat({ group.realm, group.mapId, group.x, group.y, table.concat(group.items, ",") }, "|")
  end
  return table.concat(parts, ";")
end

function Sync:Import(textValue)
  if type(textValue) ~= "string" then return 0, "invalid format" end
  textValue = textValue:gsub("^%s+", ""):gsub("%s+$", "")
  if textValue:sub(1, 5) == "WFG6|" then
    textValue = "WFGDB6;" .. textValue
  end
  local format = textValue:match("^(WFGDB%d+)")
  if format ~= "WFGDB6" and format ~= "WFGDB7" then
    if textValue:sub(1, 5) == "WFGDB" then
      return 0, string.format("Unsupported export format %s. Update Wforged and generate a new WFGDB7 export.", tostring(format or "unknown"))
    end
    return 0, "invalid format"
  end
  if format == "WFGDB6" then
    addon:LootDebug("Legacy import format WFGDB6 detected; prefer WFGDB7 exports.")
  end
  WforgedLastImport = textValue
  self.pendingImports = self.pendingImports or {}
  self.pendingImportIndex = self.pendingImportIndex or 1
  local queued = 0
  local scanned = 0
  local firstType, firstId = nil, nil
  local importedRecords = {}
  local firstRecordDebug = nil
  local groupedFormat = textValue:sub(1, 6) == "WFGDB7"
  local headerLength = 8
  for record in textValue:sub(headerLength):gmatch("[^;]+") do
    if groupedFormat then
      local grouped = splitPayload(record)
      local realm, mapId, x, y, itemList = grouped[1], grouped[2], grouped[3], grouped[4], grouped[5]
      for itemRecord in string.gmatch(itemList or "", "[^,]+") do
        local itemId, observedAt = itemRecord:match("^(%d+):(%d+)$")
        if itemId then
          importedRecords[#importedRecords + 1] = { "WFG6", itemId, mapId, x, y, observedAt, realm }
          queued = queued + 1
        end
      end
      scanned = scanned + 1
    end
    local fields = splitPayload(record)
    local rawType = string.sub(record, 1, 4)
    local rawItemId = fields[2]
    scanned = scanned + 1
    if not firstRecordDebug then
      firstRecordDebug = string.format("raw=%s len=%d extracted=%s", string.sub(record, 1, 100), #record, tostring(rawItemId))
    end
    if not firstType then
      firstType, firstId = rawType, rawItemId
    end
    if rawType == "WFG6" and tonumber(rawItemId) then
      fields[1] = rawType
      fields[2] = rawItemId
      importedRecords[#importedRecords + 1] = fields
      queued = queued + 1
      addon:LootDebug(string.format("Import record: id=%s map=%s x=%s y=%s time=%s fields=%d", tostring(fields[2]), tostring(fields[3]), tostring(fields[4]), tostring(fields[5]), tostring(fields[6] or fields[3]), #fields))
    end
  end
  addon:LootDebug(string.format("Import input: len=%d prefix=%s first=%s fields=%s/%s/%s", #textValue, string.sub(textValue, 1, 80), tostring(firstRecordDebug), tostring(importedRecords[1] and importedRecords[1][1]), tostring(importedRecords[1] and importedRecords[1][2]), tostring(importedRecords[1] and importedRecords[1][3])))
  table.sort(importedRecords, function(left, right)
    return tostring(left[2] or "") < tostring(right[2] or "")
  end)
  for _, fields in ipairs(importedRecords) do
    self.pendingImports[#self.pendingImports + 1] = fields
  end
  addon:LootDebug(string.format("Import scan: records=%d queued=%d firstType=%s firstId=%s", scanned, queued, tostring(firstType), tostring(firstId)))
  if scanned > 0 and queued == 0 then
    return 0, string.format("Invalid %s data. Update Wforged and generate a fresh WFGDB7 export.", format)
  end
  return queued
end

function Sync:ImportLast()
  return self:Import(self.testImport)
end

function Sync:ProcessImportQueue(elapsed)
  if not self.pendingImports or self.pendingImportIndex > #self.pendingImports then
    return
  end

  self.importElapsed = (self.importElapsed or 0) + (elapsed or 0)
  if self.importElapsed < self.importInterval then
    return
  end
  self.importElapsed = 0

  for _ = 1, self.importBatchSize do
    local fields = self.pendingImports[self.pendingImportIndex]
    if not fields then break end
    self.pendingImportIndex = self.pendingImportIndex + 1
    local payload = decodePayload(fields)
    if payload then
      addon:LootDebug(string.format("Import decoded: id=%s name=%s map=%s x=%s y=%s time=%s quality=%s level=%s", tostring(payload.itemId), tostring(payload.itemName), tostring(payload.mapId), tostring(payload.x), tostring(payload.y), tostring(payload.observedAt), tostring(payload.quality), tostring(payload.itemLevel)))
      self:MergeRemoteItem(payload)
      if addon.ItemScan and addon.ItemScan.FinalizePendingRecord and payload.itemLink then
        payload.pendingKey = "import:item:" .. tostring(payload.itemId)
        addon.DB:UpsertPendingItem(payload.pendingKey, payload)
        addon.ItemScan:FinalizePendingRecord(payload)
      end
    end
  end

  if self.pendingImportIndex > #self.pendingImports then
    local total = #self.pendingImports
    self.pendingImports = {}
    self.pendingImportIndex = 1
    addon:Print("Import complete: " .. tostring(total) .. " items processed.")
    if addon.SearchUI and addon.SearchUI.frame and addon.SearchUI.frame:IsShown() then
      addon.SearchUI:Refresh(addon.SearchUI.frame.editBox and addon.SearchUI.frame.editBox:GetText() or "")
    end
  end
end

function Sync:BroadcastItem(fingerprint)
  if addon.DB:GetSettings().sendGuildUpdates == false then
    addon:LootDebug("Guild broadcast skipped: sending is disabled.")
    return false
  end
  local entry = addon.DB.data.itemsByFingerprint[fingerprint]
  if not entry or not entry.isWorldforged then
    addon:LootDebug("Guild broadcast skipped: item record is unavailable.")
    return false
  end
  local payload = makeItemPayload(entry)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(self.prefix, payload, "GUILD")
  elseif SendAddonMessage then
    SendAddonMessage(self.prefix, payload, "GUILD")
  else
    addon:LootDebug("Guild broadcast skipped: addon-message API is unavailable.")
    return false
  end
  addon:LootDebug("Guild broadcast sent: " .. tostring(entry.itemName or entry.itemId))
  return true
end

function Sync:BroadcastTestItem()
  if addon.DB:GetSettings().sendGuildUpdates == false then
    addon:LootDebug("Test broadcast skipped: sending is disabled.")
    return false
  end
  local payload = "WFG6|450559|40|0.7154|0.7379|" .. tostring(time())
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(self.prefix, payload, "GUILD")
  elseif SendAddonMessage then
    SendAddonMessage(self.prefix, payload, "GUILD")
  else
    addon:LootDebug("Test broadcast skipped: addon-message API is unavailable.")
    return false
  end
  addon:LootDebug("Test guild broadcast sent: " .. payload)
  return true
end

function Sync:OnAddonMessage(prefix, message, channel, sender)
  if prefix ~= self.prefix or type(WforgedDB) ~= "table" then
    return
  end
  addon:LootDebug(string.format("Guild message received: sender=%s channel=%s payload=%s", tostring(sender), tostring(channel), tostring(message)))
  local playerName = UnitName and UnitName("player") or nil
  local isSelf = playerName and sender and (sender == playerName or sender:match("^" .. playerName .. "-"))
  if isSelf then
    addon:LootDebug("Guild message ignored: sender is this player.")
    return
  end
  if addon.DB:GetSettings().receiveGuildUpdates == false and channel == "GUILD" then
    addon:LootDebug("Guild message ignored: receiving is disabled.")
    return
  end

  if message and message:sub(1, 5) == "WFG6|" then
    local fields = splitPayload(message)
    local payload = decodePayload(fields)
    addon:LootDebug(string.format("Guild payload decoded: id=%s map=%s x=%s y=%s time=%s", tostring(payload and payload.itemId), tostring(payload and payload.mapId), tostring(payload and payload.x), tostring(payload and payload.y), tostring(payload and payload.observedAt)))
    self:MergeRemoteItem(payload)
  end
  WforgedDB.sync[sender or "unknown"] = {
    message = message,
    channel = channel,
    receivedAt = time(),
  }
end

function Sync:MergeRemoteItem(payload)
  if type(payload) ~= "table" then
    return false
  end

  if not payload.itemId then
    return false
  end

  local itemKey = addon.DB:BuildItemKey(payload.itemId, payload.itemName)
  local bucket = addon.DB.data.itemsByKey[itemKey]
  local fingerprint = bucket and bucket.bestFingerprint or payload.fingerprint
  local existing = fingerprint and addon.DB.data.itemsByFingerprint[fingerprint] or nil

  if (not existing) or (tonumber(payload.observedAt or 0) >= tonumber(existing.lastSeenAt or 0)) then
    if existing then
      -- Compact sync data only owns location and timestamp; retain locally resolved item details.
      payload.itemLink = existing.itemLink
      payload.itemName = existing.itemName
      payload.itemTexture = existing.itemTexture
      payload.quality = existing.quality
      payload.itemLevel = existing.itemLevel
      payload.effectiveLevel = existing.effectiveLevel
      payload.upgradeLevel = existing.upgradeLevel
      payload.statsText = existing.statsText
      payload.tooltipText = existing.tooltipText
    end
    payload.itemKey = itemKey
    payload.fingerprint = fingerprint
    local stored = addon.DB:RecordItemObservation(payload)
    if addon.ItemScan and addon.ItemScan.RepairStoredItems then
      addon.ItemScan:RepairStoredItems(payload.itemId)
    end
    addon:LootDebug(string.format("Import stored: id=%s name=%s map=%s x=%s y=%s quality=%s level=%s", tostring(payload.itemId), tostring(stored and stored.itemName or payload.itemName), tostring(stored and stored.lastMapId), tostring(stored and stored.lastX), tostring(stored and stored.lastY), tostring(stored and stored.quality), tostring(stored and stored.itemLevel)))
    return true
  end

  return false
end
