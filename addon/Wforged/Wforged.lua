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

  if command == "search" or command == "ui" then
    addon.SearchUI:Toggle()
    return
  end

  if command == "debug" then
    addon.debug = not addon.debug
    addon:Print("Debug mode: " .. (addon.debug and "on" or "off"))
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
      self.ItemScan:RepairStoredItems()
    end)
  end
  self.eventFrame:SetScript("OnUpdate", function(frame, elapsed)
    frame.elapsed = (frame.elapsed or 0) + elapsed
    frame.vendorElapsed = (frame.vendorElapsed or 0) + elapsed
    if frame.elapsed >= 0.2 then
      frame.elapsed = 0
      if self.AutoConfirm and self.AutoConfirm.TryConfirm then
        self.AutoConfirm:TryConfirm()
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
  if GetNumLootItems and GetLootSlotLink then
    for slot = 1, GetNumLootItems() do
      local itemLink = GetLootSlotLink(slot)
      if itemLink then
        self:LootDebug("LOOT_OPENED slot item: " .. tostring(itemLink))
        if self.ItemScan:IsWorldforgedItem(itemLink, true) then
          hasWorldforged = true
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
