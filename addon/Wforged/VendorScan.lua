local addonName, addon = ...

local VendorScan = {}
addon.VendorScan = VendorScan

VendorScan.frameScanInterval = 1.0

local function collectChildFrames(root, output, depth, maxDepth)
  if not root or depth > maxDepth or not root.GetChildren then
    return
  end

  local children = { root:GetChildren() }
  for _, child in ipairs(children) do
    output[#output + 1] = child
    collectChildFrames(child, output, depth + 1, maxDepth)
  end
end

local function collectFrameTexts(frame)
  local texts = {}
  if not frame or not frame.GetRegions then
    return texts
  end

  local regions = { frame:GetRegions() }
  for _, region in ipairs(regions) do
    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
      local text = region:GetText()
      if text and text ~= "" then
        texts[#texts + 1] = text
      end
    end
  end

  return texts
end

local function collectNestedFrameTexts(frame, texts, depth, maxDepth)
  if not frame or depth > maxDepth then
    return
  end

  local ownTexts = collectFrameTexts(frame)
  for _, text in ipairs(ownTexts) do
    texts[#texts + 1] = text
  end

  if frame.GetChildren then
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
      collectNestedFrameTexts(child, texts, depth + 1, maxDepth)
    end
  end
end

local function dumpFrameInternals(frame, prefix)
  if not frame then
    return
  end

  local fields = {
    "id",
    "itemID",
    "itemId",
    "itemLink",
    "ItemLink",
    "link",
    "item",
    "data",
    "index",
    "value",
  }

  for _, key in ipairs(fields) do
    local value = frame[key]
    if value ~= nil then
      addon:LootDebug(string.format("%s field %s=%s", tostring(prefix), tostring(key), tostring(value)))
    end
  end

  local regions = { frame:GetRegions() }
  for index, region in ipairs(regions) do
    if region and region.GetObjectType then
      local objectType = region:GetObjectType()
      if objectType == "FontString" then
        local text = region:GetText()
        if text and text ~= "" then
          addon:LootDebug(string.format("%s region[%d] FontString=%s", tostring(prefix), index, tostring(text)))
        end
      elseif objectType == "Texture" then
        local texture = region.GetTexture and region:GetTexture() or nil
        if texture then
          addon:LootDebug(string.format("%s region[%d] Texture=%s", tostring(prefix), index, tostring(texture)))
        end
      end
    end
  end

  if frame.GetChildren then
    local children = { frame:GetChildren() }
    for index, child in ipairs(children) do
      local childName = child and child.GetName and child:GetName() or "<unnamed>"
      addon:LootDebug(string.format("%s child[%d]=%s", tostring(prefix), index, tostring(childName)))
    end
  end
end

local function frameTextMatches(frame, expectedText)
  if not frame or not expectedText then
    return false
  end

  if frame.GetText then
    local text = frame:GetText()
    if text == expectedText then
      return true
    end
  end

  local regions = { frame:GetRegions() }
  for _, region in ipairs(regions) do
    if region and region.GetObjectType and region:GetObjectType() == "FontString" then
      local text = region:GetText()
      if text == expectedText then
        return true
      end
    end
  end

  return false
end

local function findVisibleUpgradeFrame()
  if not UIParent or not UIParent.GetChildren then
    return nil
  end

  local children = { UIParent:GetChildren() }
  for _, child in ipairs(children) do
    if child and child.IsShown and child:IsShown() then
      if frameTextMatches(child, "Worldforged Upgrades") then
        return child
      end
    end
  end

  return nil
end

local function getNpcIdFromGuid(guid)
  if not guid then
    return nil
  end

  local unitType, _, _, _, _, npcId = strsplit("-", guid)
  if unitType ~= "Creature" and unitType ~= "Vehicle" then
    return nil
  end

  return tonumber(npcId)
end

local function buildItemLinkFromId(itemId, itemName)
  if not itemId then
    return nil
  end

  local directLink = select(2, GetItemInfo(itemId))
  if directLink then
    return directLink
  end

  return string.format("|Hitem:%d:0:0:0:0:0:0:0|h[%s]|h", tonumber(itemId) or 0, tostring(itemName or ("item:" .. tostring(itemId))))
end

local function parseCostFromTexts(texts)
  if type(texts) ~= "table" then
    return nil
  end

  for _, text in ipairs(texts) do
    local cleaned = tostring(text)
    cleaned = cleaned:gsub("|T.-|t", " ")
    cleaned = cleaned:gsub("|c%x%x%x%x%x%x%x%x", " ")
    cleaned = cleaned:gsub("|r", " ")

    local best = nil
    for token in cleaned:gmatch("(%d[%d,]*)") do
      local value = tonumber((token:gsub(",", "")))
      if value and value >= 1000 then
        if not best or value < best then
          best = value
        end
      end
    end

    if best then
      return best
    end
  end

  return nil
end

local function parseSourceItemFromTexts(texts)
  if type(texts) ~= "table" then
    return nil, nil, nil
  end

  for _, text in ipairs(texts) do
    local raw = tostring(text or "")
    local itemId, itemName = raw:match("|Hitem:(%d+)[^|]*|h%[([^%]]+)%]|h")
    if itemId then
      return tonumber(itemId), itemName, raw
    end
  end

  return nil, nil, nil
end

local function getButtonCostTexts(button)
  local buttonName = button and button.GetName and button:GetName() or nil
  local costFrame = buttonName and _G[buttonName .. "Cost"] or nil
  local texts = {}
  if costFrame then
    collectNestedFrameTexts(costFrame, texts, 1, 4)
  end
  return texts
end

local function buildButtonSignature(buttonName, itemId, texts, parsedCost)
  return table.concat({
    tostring(buttonName or ""),
    tostring(itemId or ""),
    table.concat(texts or {}, "|"),
    tostring(parsedCost or ""),
  }, "::")
end

function VendorScan:ScanMerchantItems()
  if not GetMerchantNumItems then
    return
  end

  local npcGuid = UnitGUID("npc")
  local npcId = getNpcIdFromGuid(npcGuid)
  local npcName = UnitName("npc")
  local mapId, x, y = addon:GetPlayerPosition()

  for index = 1, GetMerchantNumItems() do
    local itemLink = GetMerchantItemLink(index)
    if itemLink then
      addon.ItemScan:CaptureItem(itemLink, "merchant")

      local itemName, _, _, itemLevel, _, _, _, _, _, _, _, itemId = GetItemInfo(itemLink)
      local _, _, price = GetMerchantItemInfo(index)
      local itemKey = addon.DB:BuildItemKey(itemId, itemName)

      addon.DB:RecordVendorUpgrade({
        npcId = npcId or 0,
        npcName = npcName,
        mapId = mapId,
        x = x,
        y = y,
        itemKey = itemKey,
        itemLink = itemLink,
        itemName = itemName,
        cost = price,
        currency = "copper",
        fromLevel = itemLevel,
        toLevel = itemLevel,
      })
    end
  end
end

function VendorScan:CountVisibleUpgradeButtons(frame)
  if not frame then
    return 0
  end

  local frames = {}
  collectChildFrames(frame, frames, 1, 4)
  local visible = 0

  for _, child in ipairs(frames) do
    if child and child.GetObjectType and child:GetObjectType() == "Button" then
      local childName = child.GetName and child:GetName() or ""
      if childName:find("RPGItemStoreItem", 1, true) and child.IsShown and child:IsShown() then
        visible = visible + 1
      end
    end
  end

  return visible
end

function VendorScan:ScanUpgradeFrameContents()
  local frame = findVisibleUpgradeFrame()
  if not frame then
    return 0
  end

  local npcGuid = UnitGUID("npc")
  local npcId = getNpcIdFromGuid(npcGuid) or 0
  local npcName = UnitName("npc")
  local mapId, x, y = addon:GetPlayerPosition()

  local frames = {}
  collectChildFrames(frame, frames, 1, 4)
  local candidates = {}
  local signatures = {}
  local captured = 0

  for _, child in ipairs(frames) do
    if child and child.GetObjectType and child:GetObjectType() == "Button" then
      local buttonName = child.GetName and child:GetName() or ""
      if buttonName:find("RPGItemStoreItem", 1, true) then
        local texts = {}
        collectNestedFrameTexts(child, texts, 1, 3)
        local costTexts = getButtonCostTexts(child)

        local itemId = child.itemID or child.itemId or nil
        local itemLink = buildItemLinkFromId(itemId, texts[1])
        local parsedCost = parseCostFromTexts(costTexts)
        local sourceItemId, sourceItemName, sourceRawText = parseSourceItemFromTexts(costTexts)
        local signature = buildButtonSignature(buttonName, itemId, texts, parsedCost)

        signatures[#signatures + 1] = signature
        candidates[#candidates + 1] = {
          frame = child,
          buttonName = buttonName,
          itemId = itemId,
          itemLink = itemLink,
          texts = texts,
          costTexts = costTexts,
          parsedCost = parsedCost,
          sourceItemId = sourceItemId,
          sourceItemName = sourceItemName,
          sourceRawText = sourceRawText,
        }
      end
    end
  end

  table.sort(signatures)
  local frameSignature = table.concat(signatures, "###")
  if self.lastUpgradeFrameSignature == frameSignature then
    return 0
  end
  self.lastUpgradeFrameSignature = frameSignature

  for _, candidate in ipairs(candidates) do
    if #candidate.texts > 0 then
      addon:LootDebug(string.format(
        "Upgrade button scan: name=%s itemId=%s link=%s texts=%s costTexts=%s parsedCost=%s sourceItemId=%s sourceItemName=%s",
        tostring(candidate.buttonName),
        tostring(candidate.itemId or "?"),
        tostring(candidate.itemLink or "?"),
        table.concat(candidate.texts, " | "),
        table.concat(candidate.costTexts or {}, " | "),
        tostring(candidate.parsedCost or "?"),
        tostring(candidate.sourceItemId or "?"),
        tostring(candidate.sourceItemName or "?")
      ))

      if not self.deepUpgradeDebugDone then
        dumpFrameInternals(candidate.frame, candidate.buttonName)
        if candidate.sourceRawText then
          addon:LootDebug(string.format("%s sourceRaw=%s", tostring(candidate.buttonName), tostring(candidate.sourceRawText)))
        end
      end
    end

    if candidate.itemLink and candidate.itemId then
      local itemName, _, _, itemLevel, _, _, _, _, _, itemTexture = GetItemInfo(candidate.itemLink)
      itemName = itemName or candidate.texts[1]
      local itemKey = addon.DB:BuildItemKey(candidate.itemId, itemName)
      local sourceItemKey = nil
      if candidate.sourceItemId then
        sourceItemKey = addon.DB:BuildItemKey(candidate.sourceItemId, candidate.sourceItemName)
      end

      addon.ItemScan:QueuePendingItem(candidate.itemLink, "upgrade-frame", {
        mapId = mapId,
        x = x,
        y = y,
        upgradeLevel = itemLevel,
        isUpgrade = true,
        isWorldforged = true,
        upgradeCandidate = false,
        upgradeCost = candidate.parsedCost,
        upgradeCurrency = candidate.parsedCost and "rune" or "unknown",
        sourceItemId = candidate.sourceItemId,
        sourceItemName = candidate.sourceItemName,
      })

      addon.DB:RecordVendorUpgrade({
        npcId = npcId,
        npcName = npcName,
        mapId = mapId,
        x = x,
        y = y,
        itemKey = itemKey,
        itemId = candidate.itemId,
        itemLink = candidate.itemLink,
        itemName = itemName,
        cost = candidate.parsedCost,
        currency = candidate.parsedCost and "rune" or "unknown",
        sourceItemId = candidate.sourceItemId,
        sourceItemKey = sourceItemKey,
        sourceItemName = candidate.sourceItemName,
        fromLevel = itemLevel,
        toLevel = itemLevel,
        isUpgrade = true,
        itemTexture = itemTexture,
      })
      if candidate.parsedCost then
        local repairedExisting = 0
        for _, existing in pairs(addon.DB.data.itemsByFingerprint or {}) do
          if existing and tonumber(existing.itemId) == tonumber(candidate.itemId) then
            existing.upgradeCost = candidate.parsedCost
            existing.upgradeCurrency = "rune"
            existing.isUpgrade = true
            repairedExisting = repairedExisting + 1
          end
        end
        if repairedExisting > 0 then
          addon:LootDebug(string.format("Upgrade cost repaired from vendor offer: itemId=%s cost=%s variants=%d", tostring(candidate.itemId), tostring(candidate.parsedCost), repairedExisting))
        end
      end
      captured = captured + 1
    end
  end

  if #candidates > 0 then
    self.deepUpgradeDebugDone = true
  end

  if captured > 0 then
    addon:LootDebug("Upgrade frame scan captured items: " .. tostring(captured))
    if addon.DB and addon.DB.Save then addon.DB:Save() end
  end

  return captured
end

function VendorScan:DebugScanUpgradeFrame()
  local frame = findVisibleUpgradeFrame()
  if frame then
    local frameName = frame.GetName and frame:GetName() or "<unnamed>"
    if self.lastUpgradeFrameName ~= frameName or not self.lastUpgradeFrameShown then
      addon:LootDebug("Detected upgrade frame: " .. tostring(frameName))
    end

    local visibleButtons = self:CountVisibleUpgradeButtons(frame)
    if self.lastHookedButtonCount ~= visibleButtons then
      addon:LootDebug("Upgrade frame buttons visible: " .. tostring(visibleButtons))
      self.lastHookedButtonCount = visibleButtons
    end

    self:ScanUpgradeFrameContents()
    self.lastUpgradeFrameName = frameName
    self.lastUpgradeFrameShown = true
  elseif self.lastUpgradeFrameShown then
    addon:LootDebug("Upgrade frame hidden.")
    self.lastUpgradeFrameShown = false
    self.lastUpgradeFrameName = nil
    self.lastUpgradeFrameSignature = nil
    self.lastHookedButtonCount = nil
    self.deepUpgradeDebugDone = false
  end
end
