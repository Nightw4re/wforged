local addonName, addon = ...

local Sync = {}
addon.Sync = Sync

Sync.prefix = "WFORGED"
Sync.exportFormat = "WFGDB8"
Sync.importBatchSize = 2
Sync.importInterval = 0.5
Sync.shareChunkSize = 180
Sync.shareChunkDelay = 0.15
Sync.collectorEnabled = false
Sync.collectorTargets = { "Nightware", "Kunhuta" }

local function shareChecksum(value)
  local sum = 0
  for index = 1, #value do
    sum = (sum + string.byte(value, index)) % 2147483647
  end
  return tostring(sum)
end

local function shortName(value)
  return tostring(value or ""):gsub("%-.*$", "")
end
Sync.testImport = "WFGDB6;WFG6|450559|40|0.7154|0.7379|1784222003;WFG6|450557|40|0.5317|0.7906|1784195081;WFG6|450748|40|0.6078|0.5827|1784194402;WFG6|1388996||1784192678;WFG6|1388679||1784192678;WFG6|450934||1784192669;WFG6|521267||1784192669;WFG6|450556|40|0.428|0.885|1784221802;WFG6|1388570||1784192678;WFG6|450555|40|0.3356|0.8647|1784221687;WFG6|1388779||1784192678;WFG6|450551||1784192669;WFG6|515681||1784192669;WFG6|1388546||1784192678;WFG6|515687|40|0.3573|0.904|1784221326;WFG6|450564|40|0.4137|0.6647|1784197106;WFG6|515430||1784192669;WFG6|450562|40|0.4007|0.68|1784194762;WFG6|451117||1784192669;WFG6|450593|35|0.1914|0.5561|1784222456;WFG6|450563|15|0.409|0.8196|1784200008;WFG6|515684|40|0.7007|0.7482|1784222170;WFG6|450528||1784192669;WFG6|450594|35|0.1747|0.5636|1784222299;WFG6|1388997||1784192678;WFG6|450673||1784192669;WFG6|1389367||1784192678;WFG6|450909||1784192669;WFG6|1388771||1784192678;WFG6|515429||1784192669"

local function encode(value)
  return (tostring(value or ""):gsub("%%", "%%25"):gsub("|", "%%7C"):gsub(";", "%%3B"):gsub("\n", "%%0A"))
end

local function decode(value)
  return tostring(value or ""):gsub("%%0A", "\n"):gsub("%%3B", ";"):gsub("%%7C", "|"):gsub("%%25", "%%")
end

local function splitPayload(record)
  local fields = {}
  local text = tostring(record or "")
  local start = 1
  while true do
    local separator = string.find(text, "|", start, true)
    if separator then
      fields[#fields + 1] = decode(string.sub(text, start, separator - 1))
      start = separator + 1
    else
      fields[#fields + 1] = decode(string.sub(text, start))
      break
    end
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
  local knownZoneName
  for _, existing in pairs(addon.DB.data.itemsByFingerprint or {}) do
    if existing and tonumber(existing.itemId) == itemId and not existing.zoneRepairPending and existing.lastZoneName
      and existing.lastZoneName ~= "" and not existing.lastZoneName:match("^Map %d+$") then
      knownZoneName = existing.lastZoneName
      break
    end
  end
  local itemName = itemId and GetItemInfo(itemId) or nil
  itemName = itemName or ("Item #" .. tostring(itemId or "?"))
  local itemLink = itemId and string.format("|Hitem:%d:0:0:0:0:0:0:0:0|h[%s]|h", itemId, itemName) or nil
  local itemInfoName, _, quality, itemLevel, _, _, _, _, _, itemTexture = itemLink and GetItemInfo(itemLink) or nil
  itemName = itemInfoName or itemName
  local hasLocation = fields[3] and fields[3] ~= "" and fields[4] and fields[5]
  local observedAt = hasLocation and fields[6] or fields[3]
  local realm = hasLocation and fields[7] or fields[4]
  local mapId = hasLocation and tonumber(fields[3]) or nil
  local upgradeCost = hasLocation and tonumber(fields[9]) or tonumber(fields[8])
  local upgradeCurrency = hasLocation and fields[10] or fields[9]
  local upgradeLevel = hasLocation and tonumber(fields[11]) or tonumber(fields[10]) or 0
  local fingerprint = fields[12] or fields[11]
  return {
    fingerprint = fingerprint ~= "" and fingerprint or string.format("id:%d", itemId or 0),
    itemId = itemId, itemName = itemName, itemLink = itemLink,
    itemTexture = itemTexture, quality = quality, itemLevel = itemLevel,
    effectiveLevel = itemLevel, upgradeLevel = 0, sourceType = fields.importSource or "import", mapId = mapId,
    x = hasLocation and tonumber(fields[4]) or nil, y = hasLocation and tonumber(fields[5]) or nil,
    zoneName = knownZoneName or fields[8],
    upgradeCost = upgradeCost, upgradeCurrency = upgradeCurrency,
    isUpgrade = upgradeLevel > 0 or upgradeCost ~= nil,
    zoneRepairPending = hasLocation and not knownZoneName or false,
    observedAt = tonumber(observedAt) or time(), isWorldforged = true, realm = realm ~= "" and realm or "Unknown",
  }
end

function Sync:RefreshItemInfo(itemId)
  if self.importActive then return end
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
  addon:LootDebug("Export format: " .. tostring(self.exportFormat) .. " / grouped locations")
  local groups = {}
  for fingerprint, entry in pairs(addon.DB.data.itemsByFingerprint or {}) do
    if entry.isWorldforged and entry.itemId and entry.lastMapId and entry.lastX and entry.lastY then
      local realm = encode(entry.realm or "Unknown")
      local mapId = encode(entry.lastMapId)
      local zoneName = encode(entry.lastZoneName or "")
      local x = encode(entry.lastX)
      local y = encode(entry.lastY)
      local key = table.concat({ realm, mapId, zoneName, x, y }, "|")
      groups[key] = groups[key] or { realm = realm, mapId = mapId, zoneName = zoneName, x = x, y = y, items = {} }
      groups[key].items[#groups[key].items + 1] = table.concat({ entry.itemId, tonumber(entry.lastSeenAt or entry.firstSeenAt or 0) or 0 }, ":")
    end
  end
  local parts = { "WFGDB8" }
  for _, group in pairs(groups) do
    table.sort(group.items)
    parts[#parts + 1] = table.concat({ group.realm, group.mapId, group.zoneName, group.x, group.y, table.concat(group.items, ",") }, "|")
  end
  return table.concat(parts, ";")
end

local function makeBroadcastPayload(entry)
  local mapId, x, y = tonumber(entry.lastMapId), tonumber(entry.lastX), tonumber(entry.lastY)
  if not entry.itemId or not mapId or not x or not y then
    return nil
  end
  local realm = encode(entry.realm or "Unknown")
  local item = string.format("%d:%d", entry.itemId, tonumber(entry.lastSeenAt or entry.firstSeenAt or 0) or 0)
  return table.concat({ "WFGDB8", realm, mapId, encode(entry.lastZoneName or ""), x, y, item }, "|")
end

function Sync:Import(textValue, context)
  if type(textValue) ~= "string" then return 0, "invalid format" end
  textValue = textValue:gsub("^%s+", ""):gsub("%s+$", "")
  if textValue:sub(1, 5) == "WFG6|" then
    textValue = "WFGDB6;" .. textValue
  end
  local format = textValue:match("^(WFGDB%d+)")
  if format ~= "WFGDB6" and format ~= "WFGDB7" and format ~= "WFGDB8" then
    if textValue:sub(1, 5) == "WFGDB" then
      return 0, string.format("Unsupported export format %s. Update Wforged and generate a new WFGDB7 export.", tostring(format or "unknown"))
    end
    return 0, "invalid format"
  end
  if format == "WFGDB6" then
    addon:LootDebug("Legacy import format WFGDB6 detected; prefer WFGDB7 exports.")
  end
  WforgedLastImport = textValue
  self.importActive = true
  self.pendingImports = self.pendingImports or {}
  self.pendingImportIndex = self.pendingImportIndex or 1
  local queued = 0
  local scanned = 0
  local firstType, firstId = nil, nil
  local importedRecords = {}
  local firstRecordDebug = nil
  local groupedFormat = textValue:sub(1, 6) == "WFGDB7" or textValue:sub(1, 6) == "WFGDB8"
  local namedGroupedFormat = textValue:sub(1, 6) == "WFGDB8"
  local headerLength = 8
  for record in textValue:sub(headerLength):gmatch("[^;]+") do
    if groupedFormat then
      local grouped = splitPayload(record)
      local realm, mapId, zoneName, x, y, itemList
      if namedGroupedFormat then
        realm, mapId, zoneName, x, y, itemList = grouped[1], grouped[2], grouped[3], grouped[4], grouped[5], grouped[6]
      else
        realm, mapId, x, y, itemList = grouped[1], grouped[2], grouped[3], grouped[4], grouped[5]
      end
      for itemRecord in string.gmatch(itemList or "", "[^,]+") do
        local itemId, observedAt = itemRecord:match("^(%d+):(%d+)$")
        if itemId then
          importedRecords[#importedRecords + 1] = { "WFG6", itemId, mapId, x, y, observedAt, realm, zoneName }
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
    fields.importSource = context and context.source or "manual"
    fields.importSender = context and context.sender or nil
    self.pendingImports[#self.pendingImports + 1] = fields
  end
  addon:LootDebug(string.format("Import scan: records=%d queued=%d firstType=%s firstId=%s", scanned, queued, tostring(firstType), tostring(firstId)))
  if scanned > 0 and queued == 0 then
    return 0, string.format("Invalid %s data. Update Wforged and generate a fresh WFGDB8 export.", format)
  end
  return queued
end

function Sync:ImportLast()
  return self:Import(self.testImport)
end

local function databaseHasItemId(itemId)
  for _, entry in pairs(addon.DB and addon.DB.data and addon.DB.data.itemsByFingerprint or {}) do
    if tonumber(entry.itemId) == tonumber(itemId) then return true end
  end
  return false
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
      local partyImport = fields.importSource == "party"
      if partyImport then
        self.partyImportStats = self.partyImportStats or { newItems = 0, located = 0 }
        if not databaseHasItemId(payload.itemId) then
          self.partyImportStats.newItems = self.partyImportStats.newItems + 1
          if payload.mapId and payload.x and payload.y then
            self.partyImportStats.located = self.partyImportStats.located + 1
          end
        end
      end
      addon:LootDebug(string.format("Import decoded: sender=%s id=%s name=%s map=%s x=%s y=%s time=%s quality=%s level=%s", tostring(fields.importSender or "manual"), tostring(payload.itemId), tostring(payload.itemName), tostring(payload.mapId), tostring(payload.x), tostring(payload.y), tostring(payload.observedAt), tostring(payload.quality), tostring(payload.itemLevel)))
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
    self.importActive = false
    if self.partyImportStats then
      addon:Print(string.format(
        "Party database import complete: %d new item(s), %d with location.",
        self.partyImportStats.newItems, self.partyImportStats.located
      ))
      self.partyImportStats = nil
    else
      addon:LootDebug("Import complete: " .. tostring(total) .. " items processed.")
    end
    if addon.ItemScan and addon.ItemScan.ResetZoneNameRepair then
      addon.ItemScan:ResetZoneNameRepair()
    end
    if addon.SearchUI and addon.SearchUI.frame and addon.SearchUI.frame:IsShown() then
      addon.SearchUI:Refresh(addon.SearchUI.frame.editBox and addon.SearchUI.frame.editBox:GetText() or "")
    end
  end
end

function Sync:BroadcastItem(fingerprint)
  local entry = addon.DB.data.itemsByFingerprint[fingerprint]
  if not entry or not entry.isWorldforged then
    addon:LootDebug("Guild broadcast skipped: item record is unavailable.")
    return false
  end
  local payload = makeBroadcastPayload(entry)
  if not payload then
    addon:LootDebug("Guild broadcast skipped: item has no usable location.")
    return false
  end
  local settings = addon.DB:GetSettings()
  if settings.sendGuildUpdates ~= false then
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
      C_ChatInfo.SendAddonMessage(self.prefix, payload, "GUILD")
    elseif SendAddonMessage then
      SendAddonMessage(self.prefix, payload, "GUILD")
    else
      addon:LootDebug("Guild broadcast skipped: addon-message API is unavailable.")
    end
    addon:LootDebug("Guild broadcast sent: " .. tostring(entry.itemName or entry.itemId))

    -- Collector whispers use the same compact payload as the guild update.
    -- The receiver must explicitly enable collector mode before importing it.
    if settings.sendCollectorUpdates == true then
      for _, target in ipairs(self.collectorTargets) do
        if C_ChatInfo and C_ChatInfo.SendAddonMessage then
          C_ChatInfo.SendAddonMessage(self.prefix, payload, "WHISPER", target)
        elseif SendAddonMessage then
          SendAddonMessage(self.prefix, payload, "WHISPER", target)
        end
        addon:LootDebug("Collector whisper sent to " .. tostring(target))
      end
    else
      addon:LootDebug("Collector whisper skipped: sending is disabled.")
    end
  else
    addon:LootDebug("Guild broadcast skipped: sending is disabled.")
  end
  local function send(channel, channelId)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
      C_ChatInfo.SendAddonMessage(self.prefix, payload, channel, channelId)
    elseif SendAddonMessage then
      SendAddonMessage(self.prefix, payload, channel, channelId)
    end
  end
  if IsInGroup and IsInGroup() then
    send("PARTY")
    addon:LootDebug("Party broadcast sent: " .. tostring(entry.itemName or entry.itemId))
  end
  return true
end

function Sync:BroadcastTestItem()
  if addon.DB:GetSettings().sendGuildUpdates == false then
    addon:LootDebug("Test broadcast skipped: sending is disabled.")
    return false
  end
  local payload = "WFGDB7|Unknown|40|0.7154|0.7379|450559:" .. tostring(time())
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

function Sync:ShareDatabaseWithParty(targetName)
  if not targetName or targetName == "" then
    addon:Print("Select a party member as your target first.")
    return false
  end
  if not IsInGroup or not IsInGroup() then
    addon:Print("Party share requires a party or raid.")
    return false
  end
  local requestId = tostring(time()) .. tostring(math.random(100, 999))
  self.pendingShareRequests = self.pendingShareRequests or {}
  self.pendingShareRequests[requestId] = { target = shortName(targetName), expiresAt = time() + 30 }
  local senderName = UnitName and UnitName("player") or ""
  local request = string.format("WFGSHARE_REQ|%s|%s|%s", requestId, senderName, targetName)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(self.prefix, request, "PARTY")
  elseif SendAddonMessage then
    SendAddonMessage(self.prefix, request, "PARTY")
  end
  addon:Print("Party database share request sent to " .. targetName .. ".")
  return true
end

function Sync:SendDatabaseToParty()
  if not IsInGroup or not IsInGroup() then
    return false
  end
  local export = self:Export()
  local total = math.ceil(#export / self.shareChunkSize)
  local shareId = tostring(time()) .. tostring(math.random(100, 999))
  local target = self.activeShareTarget
  if not target or total == 0 then return false end
  local function sendChunk(index)
    local chunk = export:sub((index - 1) * self.shareChunkSize + 1, index * self.shareChunkSize)
    local payload = string.format("WFGSHARE1|%s|%s|%s|%d|%d|%s|%s", shareId, UnitName and UnitName("player") or "", target, index, total, shareChecksum(chunk), chunk)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then C_ChatInfo.SendAddonMessage(self.prefix, payload, "PARTY")
    elseif SendAddonMessage then SendAddonMessage(self.prefix, payload, "PARTY") end
    if index < total and C_Timer and C_Timer.After then
      C_Timer.After(self.shareChunkDelay, function() sendChunk(index + 1) end)
    end
  end
  sendChunk(1)
  addon:LootDebug(string.format("Party database share sent: chunks=%d bytes=%d", total, #export))
  return true
end

function Sync:OnAddonMessage(prefix, message, channel, sender, localTest)
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
  if channel == "WHISPER" and not self.collectorEnabled and addon.DB:GetSettings().receiveCollectorUpdates ~= true then
    addon:LootDebug("Collector whisper ignored: collector mode is disabled.")
    return
  end
  local settings = addon.DB:GetSettings()
  if settings.receiveGuildUpdates == false and channel == "GUILD" then
    addon:LootDebug("Guild message ignored: receiving is disabled.")
    return
  end

  if channel == "PARTY" and message and message:sub(1, 10) == "WFGSHARE1|" then
    local shareId, senderName, targetName, index, total, checksum, chunk = message:match("^WFGSHARE1|([^|]+)|([^|]*)|([^|]+)|(%d+)|(%d+)|(%d+)|(.+)$")
    local playerName = UnitName and UnitName("player") or ""
    if targetName and shortName(targetName) ~= shortName(playerName) then return end
    if shareId and index and total and chunk and shareChecksum(chunk) == checksum then
      self.partyShares = self.partyShares or {}
      local share = self.partyShares[shareId]
      if share and share.expiresAt and time() > share.expiresAt then
        self.partyShares[shareId] = nil
        share = nil
      end
      share = share or { sender = shortName(senderName), target = shortName(targetName), total = tonumber(total), chunks = {}, count = 0, expiresAt = time() + 60 }
      if share.sender ~= shortName(senderName) or share.target ~= shortName(targetName) or share.total ~= tonumber(total) then
        addon:LootDebug("Party database share chunk ignored: transfer identity mismatch.")
        return
      end
      if not share.chunks[tonumber(index)] then
        share.chunks[tonumber(index)] = chunk
        share.count = share.count + 1
      end
      self.partyShares[shareId] = share
      addon:LootDebug(string.format("Party database share received: %d/%d", share.count, share.total))
      if share.count >= share.total then
        local parts = {}
        for part = 1, share.total do parts[#parts + 1] = share.chunks[part] or "" end
        local data = table.concat(parts)
        if data:sub(1, 7) == "WFGDB8;" then
          self:Import(data, { source = "party", sender = sender })
        else
          addon:Print("Party database share rejected: invalid data.")
        end
        self.partyShares[shareId] = nil
        addon:Print("Party database import complete.")
      end
    end
    return
  end

  if channel == "PARTY" and message and message:sub(1, 13) == "WFGSHARE_REQ|" then
    local requestId, senderName, targetName = message:match("^WFGSHARE_REQ|([^|]+)|([^|]+)|(.+)$")
    local playerName = UnitName and UnitName("player") or ""
    if requestId and targetName and targetName == playerName then
      addon:LootDebug(string.format("Party share request accepted for local player: sender=%s request=%s", tostring(sender), tostring(requestId)))
      StaticPopupDialogs.WFORGED_SHARE_CONFIRM = {
        text = string.format("%s wants to send you the Wforged database.%s", tostring(sender or "A party member"), localTest and "\n\n(TEST REQUEST)" or ""),
        button1 = ACCEPT,
        button2 = CANCEL,
        OnAccept = function()
          addon:LootDebug(string.format("Party share confirmation accepted: request=%s sender=%s", tostring(requestId), tostring(senderName)))
          if localTest then
            local export = addon.Sync:Export()
            addon:LootDebug(string.format("Local party share test: database prepared for sending, chunks=%d bytes=%d", math.ceil(#export / addon.Sync.shareChunkSize), #export))
            return
          end
          local response = string.format("WFGSHARE_ACK|%s|%s|%s", requestId, senderName, playerName)
          if C_ChatInfo and C_ChatInfo.SendAddonMessage then
            C_ChatInfo.SendAddonMessage("WFORGED", response, "PARTY")
          elseif SendAddonMessage then
            SendAddonMessage("WFORGED", response, "PARTY")
          end
        end,
        OnCancel = function()
          addon:LootDebug(string.format("Party share confirmation declined: request=%s", tostring(requestId)))
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
      }
      StaticPopup_Show("WFORGED_SHARE_CONFIRM")
      addon:LootDebug("Party share confirmation dialog shown.")
    end
    return
  end

  if channel == "PARTY" and message and message:sub(1, 13) == "WFGSHARE_ACK|" then
    local requestId, targetName, approver = message:match("^WFGSHARE_ACK|([^|]+)|([^|]+)|(.+)$")
    self.pendingShareRequests = self.pendingShareRequests or {}
    local pending = self.pendingShareRequests[requestId]
    if pending and time() <= (pending.expiresAt or 0)
      and shortName(sender) == shortName(pending.target)
      and shortName(approver) == shortName(pending.target) then
      self.pendingShareRequests[requestId] = nil
      self.activeShareTarget = pending.target
      self:SendDatabaseToParty()
      addon:Print("Party database share approved; sending data.")
    end
    return
  end

  if message and (message:sub(1, 7) == "WFGDB7|" or message:sub(1, 7) == "WFGDB8|") then
    self:Import(message, { source = channel == "WHISPER" and "collector" or "guild", sender = sender })
    addon:LootDebug("Guild payload queued as WFGDB7.")
  elseif message and message:sub(1, 5) == "WFG6|" then
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

  local bundledSource = payload.sourceType == "bundled"
  if bundledSource or (not existing) or (tonumber(payload.observedAt or 0) >= tonumber(existing.lastSeenAt or 0)) then
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
    if not self.importActive and addon.ItemScan and addon.ItemScan.RepairStoredItems then
      addon.ItemScan:RepairStoredItems(payload.itemId)
    end
    if not self.importActive and addon.ItemScan and addon.ItemScan.ResetZoneNameRepair then
      addon.ItemScan:ResetZoneNameRepair()
    end
    addon:LootDebug(string.format("Import stored: id=%s name=%s map=%s x=%s y=%s quality=%s level=%s", tostring(payload.itemId), tostring(stored and stored.itemName or payload.itemName), tostring(stored and stored.lastMapId), tostring(stored and stored.lastX), tostring(stored and stored.lastY), tostring(stored and stored.quality), tostring(stored and stored.itemLevel)))
    return true
  end

  return false
end
