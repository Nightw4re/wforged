local addonName, addon = ...

addon.curseForgeURL = "https://www.curseforge.com/wow/addons/wforged"

function addon:ResetDatabase()
  WforgedDB = {}
  self.DB:Init()
  if self.SearchUI and self.SearchUI.frame then
    self.SearchUI:Refresh("")
  end
end

local function handleSlashCommand(message)
  local rawMessage = strtrim(message or "")
  local command = string.lower(rawMessage)

  if command == "scan" then
    if addon.ItemScan:CaptureMouseover() then
      addon:Print("Item under cursor was recorded.")
    else
      addon:Print("No item found under cursor.")
    end
    return
  end

  if command == "vendor" then
    addon.VendorScan:ScanMerchantItems()
    addon:Print("Vendor items were scanned.")
    return
  end

  if command == "sync" then
    addon.Sync:BroadcastSummary("GUILD")
    addon:Print("Summary broadcast sent to guild.")
    return
  end

  if command == "export" then
    addon:Print("Export: " .. addon.Sync:Export())
    return
  end

  if command:sub(1, 7) == "import " then
    local count, err = addon.Sync:Import(rawMessage:sub(8))
    addon:Print(err and ("Import failed: " .. err) or ("Imported items: " .. tostring(count)))
    return
  end

  if command == "broadcast" then
    addon.Sync:BroadcastSummary("GUILD")
    addon:Print("Guild broadcast sent.")
    return
  end

  if command == "collector on" or command == "friends on" then
    addon.Sync.collectorEnabled = true
    addon.DB:GetSettings().receiveCollectorUpdates = true
    addon:Print("Friend data receiving enabled. Incoming Wforged whispers will be imported after normal validation.")
    return
  end

  if command == "collector off" or command == "friends off" then
    addon.Sync.collectorEnabled = false
    addon.DB:GetSettings().receiveCollectorUpdates = false
    addon:Print("Friend data receiving disabled. Incoming Wforged whispers will be ignored.")
    return
  end

  if command == "collector" or command == "friends" then
    local enabled = addon.Sync.collectorEnabled or addon.DB:GetSettings().receiveCollectorUpdates == true
    addon:Print("Friend data receiving: " .. (enabled and "enabled" or "disabled") .. ". Use /wforged friends on|off.")
    return
  end

  if command == "search" or command == "ui" then
    addon.SearchUI:Toggle()
    return
  end

  if command == "debug" then
    addon.debug = not addon.debug
    addon:Print("Debug mode: " .. (addon.debug and "on" or "off"))
    return
  end

  if command == "mapdebug" or command == "debugmap" then
    if addon.DebugOpenMapZone then
      addon:DebugOpenMapZone()
    else
      addon:PrintError("Open map debug is not available yet.")
    end
    return
  end

  if command == "test-party-request" then
    local playerName = UnitName and UnitName("player") or "TestPlayer"
    if addon.Sync and addon.Sync.OnAddonMessage then
      addon.Sync:OnAddonMessage("WFORGED", "WFGSHARE_REQ|local-test|TestSender|" .. playerName, "PARTY", "TestSender", true)
      addon:Print("Local party-share request test triggered. No data was sent or changed.")
    end
    return
  end

  if command == "repair-zones" then
    if addon.ItemScan then
      addon.ItemScan.zoneRepairInteractive = not addon.ItemScan.zoneRepairInteractive
      if addon.ItemScan.zoneRepairInteractive and addon.ItemScan.RepairZoneNamesFromOpenMap then
        local repaired = addon.ItemScan:RepairZoneNamesFromOpenMap()
        addon:Print(string.format("Zone repair: %d item(s) repaired on the open map.", repaired or 0))
      else
        addon:Print("Zone map repair mode: disabled")
      end
    else
      addon:PrintError("Zone map repair is not available.")
    end
    return
  end

  if command == "fix-corrupt-import" then
    local changed = 0
    local realm = GetRealmName and GetRealmName() or "Unknown"
    local data = addon.DB and addon.DB.data
    if data then
      for _, entry in pairs(data.itemsByFingerprint or {}) do
        local numericRealm = tonumber(entry.realm)
        if entry.lastSource == "import" and numericRealm and numericRealm >= 0 and numericRealm <= 1 then
          entry.realm = realm
          changed = changed + 1
          addon:LootDebug(string.format("Fixed corrupt import realm: id=%s %s -> %s", tostring(entry.itemId), tostring(numericRealm), tostring(realm)))
        end
      end
    end
    addon:Print("Fixed corrupt import records: " .. tostring(changed) .. ".")
    if addon.SearchUI and addon.SearchUI.frame and addon.SearchUI.frame:IsShown() then
      addon.SearchUI:Refresh(addon.SearchUI.frame.editBox and addon.SearchUI.frame.editBox:GetText() or "")
    end
    return
  end

  local fixItemId = command:match("^fix%-item%s+(%d+)$")
  if fixItemId then
    local itemId = tonumber(fixItemId)
    if addon.Sync and addon.Sync.RefreshItemInfo then
      addon.Sync:RefreshItemInfo(itemId)
    end
    if addon.ItemScan and addon.ItemScan.RepairStoredItems then
      addon.ItemScan:RepairStoredItems(itemId, 1)
    end
    addon:Print("Requested item data repair for item " .. tostring(itemId) .. ". Reopen the search window after the item data loads.")
    return
  end

  local cleanItemId = command:match("^item%-clean%s+(%d+)$")
  if cleanItemId then
    local itemId = tonumber(cleanItemId)
    local cleaned = 0
    for _, entry in pairs(addon.DB.data.itemsByFingerprint or {}) do
      if entry and tonumber(entry.itemId) == itemId then
        -- Keep location, timestamps, realm and upgrade relations. Only force
        -- the client item/tooltip cache to be rebuilt on the next query.
        entry.itemName = nil
        entry.itemLink = nil
        entry.itemTexture = nil
        entry.quality = nil
        entry.itemLevel = nil
        entry.effectiveLevel = nil
        entry.statsText = nil
        entry.tooltipText = nil
        entry.lastZoneName = nil
        entry.zoneRepairPending = true
        local points = addon.DB.data.spawnPointsByItem and addon.DB.data.spawnPointsByItem[entry.fingerprint]
        for _, point in pairs(points or {}) do
          point.zoneName = nil
        end
        cleaned = cleaned + 1
      end
    end
    if cleaned > 0 and addon.DB.Save then addon.DB:Save() end
    if addon.Sync and addon.Sync.RefreshItemInfo then
      addon.Sync:RefreshItemInfo(itemId)
    end
    if addon.ItemScan and addon.ItemScan.RepairStoredItems then
      addon.ItemScan:RepairStoredItems(itemId, 1)
    end
    if addon.SearchUI and addon.SearchUI.frame and addon.SearchUI.frame:IsShown() then
      addon.SearchUI:Refresh(addon.SearchUI.frame.editBox and addon.SearchUI.frame.editBox:GetText() or "")
    end
    addon:Print(string.format("Cleaned cached item data for %s variant(s) of item %d; location was preserved.", tostring(cleaned), itemId))
    return
  end

  local mapInfoId = command:match("^map%-info%s+(%d+)$")
  if mapInfoId then
    local mapId = tonumber(mapInfoId)
    local currentId = GetCurrentMapAreaID and GetCurrentMapAreaID() or nil
    local currentName = GetMapInfo and GetMapInfo() or nil
    local byId = GetMapNameByID and GetMapNameByID(mapId) or nil
    local resolved = addon.ResolveZoneName and addon:ResolveZoneName(mapId, nil, nil, nil) or nil
    addon:Print(string.format(
      "Map info id=%s currentId=%s currentName=%s GetMapNameByID=%s resolved=%s",
      tostring(mapId), tostring(currentId or "nil"), tostring(currentName or "nil"),
      tostring(byId or "nil"), tostring(resolved or "nil")
    ))
    local function probeMapFunction(name, fn)
      if not fn then return end
      local ok, value = pcall(fn)
      addon:Print(string.format("Map info %s()=%s", name, tostring(ok and value or "error")))
      local okWithId, valueWithId = pcall(fn, mapId)
      addon:Print(string.format("Map info %s(%d)=%s", name, mapId, tostring(okWithId and valueWithId or "error")))
    end
    probeMapFunction("GetActiveMapID", GetActiveMapID)
    probeMapFunction("GetActiveMapName", GetActiveMapName)
    probeMapFunction("GetMapID", GetMapID)
    probeMapFunction("GetWorldMapAreaID", GetWorldMapAreaID)
    probeMapFunction("GetZoneId", GetZoneId)
    if GetMapName then
      for candidate = mapId - 1, mapId + 1 do
        addon:Print(string.format("Map info GetMapName(%d)=%s", candidate, tostring(GetMapName(candidate) or "nil")))
      end
    end
    if SetMapByID and C_Timer and C_Timer.After then
      SetMapByID(mapId)
      C_Timer.After(0.5, function()
        local loadedName = GetMapInfo and GetMapInfo() or nil
        addon:Print(string.format(
          "Map info loaded id=%s name=%s continent=%s zone=%s zoneName=%s",
          tostring(GetCurrentMapAreaID and GetCurrentMapAreaID() or "nil"),
          tostring(loadedName or "nil"),
          tostring(GetCurrentMapContinent and GetCurrentMapContinent() or "nil"),
          tostring(GetCurrentMapZone and GetCurrentMapZone() or "nil"),
          tostring(GetCurrentMapContinent and GetCurrentMapZone and GetMapZones and ({ GetMapZones(GetCurrentMapContinent()) })[GetCurrentMapZone()] or "nil")
        ))
        if currentId then
          SetMapByID(currentId)
        end
      end)
    else
      addon:Print("Map info probe unavailable: SetMapByID or C_Timer.After missing.")
    end
    return
  end

  local mapFunctionsPage = command:match("^map%-functions%s*(%d*)$")
  if mapFunctionsPage then
    local names = {}
    for name, value in pairs(_G) do
      if type(value) == "function" and (name:lower():find("map", 1, true) or name:lower():find("zone", 1, true)) then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    local pageSize = 20
    local page = math.max(1, tonumber(mapFunctionsPage) or 1)
    local pageCount = math.max(1, math.ceil(#names / pageSize))
    page = math.min(page, pageCount)
    addon:Print(string.format("Map/zone functions page %d/%d:", page, pageCount))
    local first = (page - 1) * pageSize + 1
    local last = math.min(first + pageSize - 1, #names)
    for index = first, last do
      local name = names[index]
      addon:Print("  " .. name)
    end
    return
  end

  local mapZonesQuery = command:match("^map%-zones%s*(.*)$")
  if mapZonesQuery then
    mapZonesQuery = string.lower(strtrim(mapZonesQuery or ""))
    if not GetMapContinents or not GetMapZones then
      addon:Print("Map zone list is unavailable in this client.")
      return
    end
    local continents = { GetMapContinents() }
    local found = 0
    for continent, continentName in ipairs(continents) do
      local zones = { GetMapZones(continent) }
      for zone, zoneName in ipairs(zones) do
        if mapZonesQuery == "" or string.lower(tostring(zoneName or "")):find(mapZonesQuery, 1, true) then
          found = found + 1
          addon:Print(string.format(
            "Map zone: continent=%d zone=%d name=%s",
            continent, zone, tostring(zoneName or "nil")
          ))
        end
      end
    end
    addon:Print(string.format("Map zone matches: %d", found))
    return
  end

  if command == "update" or command == "check" or command == "checkupdate" then
    addon:Print("Installed version: " .. tostring(addon.version or "unknown"))
    addon:Print("Check CurseForge for the latest release: " .. addon.curseForgeURL)
    return
  end

  if command == "retry" then
    addon.ItemScan:RetryPendingItems()
    addon:Print("Pending items retry requested.")
    return
  end

  if command == "reset" then
    addon:ResetDatabase()
    addon:Print("Database reset. Use /reload or log out to save the empty database.")
    return
  end

  if command == "cleanup" or command == "cleanup confirm" then
    addon:Print("Cleanup is temporarily disabled. No data was changed.")
    return
  end

  local inspectId = command:match("^inspect%s+(%d+)$")
  if inspectId then
    local found = 0
    for fingerprint, entry in pairs(addon.DB.data.itemsByFingerprint or {}) do
      if tonumber(entry.itemId) == tonumber(inspectId) then
        found = found + 1
        addon:Print(string.format(
          "Inspect id=%s name=%s realm=%s source=%s upgrade=%s map=%s continent=%s zone=%s zoneName=%s x=%s y=%s quality=%s level=%s",
          tostring(entry.itemId), tostring(entry.itemName or "?"), tostring(entry.realm or "?"),
          tostring(entry.lastSource or "?"), tostring(entry.isUpgrade or entry.upgradeLevel or 0),
          tostring(entry.lastMapId or "nil"), tostring(entry.lastContinent or "nil"),
          tostring(entry.lastZone or "nil"), tostring(entry.lastZoneName or "nil"),
          tostring(entry.lastX or "nil"), tostring(entry.lastY or "nil"),
          tostring(entry.quality or "nil"), tostring(entry.itemLevel or "nil")
        ))
        addon:LootDebug("Inspect fingerprint: " .. tostring(fingerprint))
      end
    end
    addon:Print(string.format("Inspect found %d variant(s).", found))
    return
  end

  local removeId = command:match("^remove%s+(%d+)$")
  if removeId then
    local removed = addon.DB:RemoveItemById(removeId)
    if addon.SearchUI and addon.SearchUI.frame and addon.SearchUI.frame:IsShown() then
      addon.SearchUI:Refresh(addon.SearchUI.frame.editBox and addon.SearchUI.frame.editBox:GetText() or "")
    end
    if addon.MapNotes and addon.MapNotes.RefreshAllMarkers then
      addon.MapNotes:RefreshAllMarkers()
    end
    addon:Print(string.format("Removed item %s (%d variants).", removeId, removed))
    return
  end

  local removeName = rawMessage:match('^remove%-name%s+(.+)$')
  if removeName and removeName ~= "" then
    local removed = addon.DB:RemoveItemsByName(removeName)
    if addon.SearchUI and addon.SearchUI.frame and addon.SearchUI.frame:IsShown() then
      addon.SearchUI:Refresh(addon.SearchUI.frame.editBox and addon.SearchUI.frame.editBox:GetText() or "")
    end
    if addon.MapNotes and addon.MapNotes.RefreshAllMarkers then
      addon.MapNotes:RefreshAllMarkers()
    end
    addon:Print(string.format("Removed item name %s (%d variants).", removeName, removed))
    return
  end

  local summary = addon.DB:GetSummary()
  addon:Print(string.format(
    "Items: %d, spawn points: %d, vendors: %d, observations: %d, pending: %d",
    summary.items,
    summary.spawnPoints,
    summary.vendors,
    summary.observations,
    summary.pending
  ))
end

SLASH_WFORGED1 = "/wforged"
SlashCmdList.WFORGED = handleSlashCommand

local function registerEvent(eventName, handler)
  if addon.RegisterEvent then
    addon:RegisterEvent(eventName, handler)
    return
  end

  -- Keep event registration working if this file is loaded before Core.lua's helper.
  local frame = addon.eventFrame
  if frame and frame.RegisterEvent then
    frame:RegisterEvent(eventName)
    frame[eventName] = handler
  end
end

registerEvent("PLAYER_LOGIN", function(self)
  self.DB:Init()
  self.Sync:Init()
  if WforgedBundledData and WforgedBundledDataVersion and self.DB.data.meta.bundledDataVersion ~= WforgedBundledDataVersion then
    self.Sync:Import(WforgedBundledData)
    self.DB.data.meta.bundledDataVersion = WforgedBundledDataVersion
    self:Print("Bundled database imported.")
  end
  self.MinimapButton:Create()
  if self.DB:GetSummary().items == 0 and self.ItemScan.ScanPlayerItems then
    self.ItemScan:ScanPlayerItems()
  end
  if self.MapNotes and self.MapNotes.EnsureAllMapCheckbox then
    self.MapNotes:EnsureAllMapCheckbox()
  end
  if self.AutoConfirm and self.AutoConfirm.TryConfirm then
    self:LootDebug("AutoConfirm module ready.")
  else
    self:LootDebug("AutoConfirm module missing.")
  end
  if C_Timer and C_Timer.After and self.ItemScan and self.ItemScan.RepairStoredItems then
    C_Timer.After(5, function()
      self.ItemScan:RepairStoredItems(nil, 1)
    end)
  end
  self.eventFrame:SetScript("OnUpdate", function(frame, elapsed)
    frame.elapsed = (frame.elapsed or 0) + elapsed
    frame.pendingElapsed = (frame.pendingElapsed or 0) + elapsed
    frame.vendorElapsed = (frame.vendorElapsed or 0) + elapsed
    if frame.elapsed >= 0.2 then
      frame.elapsed = 0
      if self.AutoConfirm and self.AutoConfirm.TryConfirm then
        self.AutoConfirm:TryConfirm()
      end
      if self.ItemScan and self.ItemScan.repairQueue and self.ItemScan.RepairStoredItems then
        local repaired = self.ItemScan:RepairStoredItems(nil, 1)
      end
      if frame.pendingElapsed >= 1 and self.ItemScan and self.ItemScan.RetryPendingItems then
        frame.pendingElapsed = 0
        self.ItemScan:RetryPendingItems(nil, 1)
      end
      if self.SearchUI and self.SearchUI.UpdateRepairIndicator then
        self.SearchUI:UpdateRepairIndicator()
      end
      if self.Sync and self.Sync.ProcessImportQueue then
        self.Sync:ProcessImportQueue(0.2)
      end
    end
    if frame.vendorElapsed >= (self.VendorScan and self.VendorScan.frameScanInterval or 0.5) then
      frame.vendorElapsed = 0
      if self.VendorScan and self.VendorScan.DebugScanUpgradeFrame then
        self.VendorScan:DebugScanUpgradeFrame()
      end
    end
    if self.MapNotes and self.MapNotes.pinRefreshTicks then
      self.MapNotes.pinRefreshTicks = self.MapNotes.pinRefreshTicks - 1
      if self.MapNotes.pinRefreshTicks <= 0 then
        self.MapNotes.pinRefreshTicks = nil
        self.MapNotes:RefreshPinVisibility()
      end
    end
  end)
end)

registerEvent("MERCHANT_SHOW", function(self)
  self.VendorScan:ScanMerchantItems()
end)

registerEvent("CHAT_MSG_LOOT", function(self, message)
  local foundWorldforged = self.ItemScan:CaptureLootMessage(message)
  if foundWorldforged and self.AutoConfirm and self.AutoConfirm.lootWindowOpen and self.AutoConfirm.SetLootContext then
    self.AutoConfirm:SetLootContext(true)
    self.AutoConfirm:TryConfirm()
  end
end)

registerEvent("LOOT_OPENED", function(self)
  self:LootDebug("LOOT_OPENED fired.")
  if self.AutoConfirm then
    self.AutoConfirm.lootWindowOpen = true
    self.AutoConfirm.hasWorldforgedLoot = false
    self.AutoConfirm.lastSeenPopupKey = nil
    self.AutoConfirm.lootScanUntil = GetTime() + 2
  end
  local hasWorldforged = false
  local lootMapId, lootX, lootY = self:GetPlayerPosition()
  local lootContinent = GetCurrentMapContinent and GetCurrentMapContinent() or nil
  local lootZone = GetCurrentMapZone and GetCurrentMapZone() or nil
  local lootZoneName = GetRealZoneText and GetRealZoneText() or GetZoneText and GetZoneText() or nil
  if self.ResolveZoneName then
    lootZoneName = self:ResolveZoneName(lootMapId, lootContinent, lootZone, lootZoneName)
  end
  if GetNumLootItems and GetLootSlotLink then
    for slot = 1, GetNumLootItems() do
      local itemLink = GetLootSlotLink(slot)
      if itemLink then
        self:LootDebug("LOOT_OPENED slot item: " .. tostring(itemLink))
        local isWorldforged = self.ItemScan:IsWorldforgedItem(itemLink, true)
        if isWorldforged then
          hasWorldforged = hasWorldforged or isWorldforged
          self.ItemScan:QueuePendingItem(itemLink, "loot-opened", {
            isWorldforged = isWorldforged,
            upgradeCandidate = not isWorldforged,
            mapId = lootMapId,
            x = lootX,
            y = lootY,
            continent = lootContinent,
            zone = lootZone,
            zoneName = lootZoneName,
          })
          break
        end
      end
    end
  end

  if self.AutoConfirm and self.AutoConfirm.SetLootContext then
    self.AutoConfirm:SetLootContext(hasWorldforged)
    self.AutoConfirm:TryConfirm()
  else
    self:LootDebug("AutoConfirm context handler missing.")
  end
end)

registerEvent("LOOT_CLOSED", function(self)
  self:LootDebug("LOOT_CLOSED fired.")
  if self.AutoConfirm then
    self.AutoConfirm.lootWindowOpen = false
    self.AutoConfirm.hasWorldforgedLoot = false
    self.AutoConfirm.lootScanUntil = nil
    self.AutoConfirm.lastSeenPopupKey = nil
  end
  if self.AutoConfirm and self.AutoConfirm.SetLootContext then
    self.AutoConfirm:SetLootContext(false)
  end
end)

registerEvent("GET_ITEM_INFO_RECEIVED", function(self, itemId)
  self.ItemScan:RetryPendingItems(itemId)
  if self.ItemScan.RepairStoredItems then
    self.ItemScan:RepairStoredItems(itemId)
  end
  if self.Sync and self.Sync.RefreshItemInfo then
    self.Sync:RefreshItemInfo(itemId)
  end
end)

registerEvent("WORLD_MAP_UPDATE", function(self)
  if self.MapNotes and self.MapNotes.RefreshPinVisibility then
    self.MapNotes:RefreshPinVisibility()
    if self.MapNotes.SchedulePinRefresh then
      self.MapNotes:SchedulePinRefresh()
    end
    if self.MapNotes.RefreshAllMarkers then
      self.MapNotes:RefreshAllMarkers()
    end
  end
end)

registerEvent("CHAT_MSG_ADDON", function(self, prefix, message, channel, sender)
  self.Sync:OnAddonMessage(prefix, message, channel, sender)
end)
