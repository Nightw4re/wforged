-- Usage: luajit scripts/export-bundled-data.lua path/to/Wforged.lua version
local source = assert(arg[1], "Missing SavedVariables path")
local version = assert(arg[2], "Missing addon version")
local output = "addon/Wforged/BundledData.lua"
local tocPath = "addon/Wforged/Wforged.toc"
local readmePath = "README.md"

local function findMatchingBrace(text, opening)
  local depth, quote, escaped = 0, nil, false
  for index = opening, #text do
    local char = text:sub(index, index)
    if quote then
      if escaped then
        escaped = false
      elseif char == "\\" then
        escaped = true
      elseif char == quote then
        quote = nil
      end
    elseif char == '"' or char == "'" then
      quote = char
    elseif char == "{" then
      depth = depth + 1
    elseif char == "}" then
      depth = depth - 1
      if depth == 0 then return index end
    end
  end
  return nil
end

local function readFingerprintEntries(path)
  local handle = assert(io.open(path, "r"))
  local text = handle:read("*a")
  handle:close()

  local markerStart = assert(text:find("%[\"itemsByFingerprint\"%]%s*=%s*{"),
    "Missing itemsByFingerprint in SavedVariables")
  local tableStart = assert(text:find("{", markerStart), "Invalid itemsByFingerprint table")
  local tableEnd = assert(findMatchingBrace(text, tableStart), "Unclosed itemsByFingerprint table")
  local entries, cursor = {}, tableStart + 1

  while cursor < tableEnd do
    local keyStart, keyEnd, key = text:find("%[\"([^\"]+)\"%]%s*=%s*{", cursor)
    if not keyStart or keyStart >= tableEnd then break end
    local valueStart = text:find("{", keyEnd - 1, true)
    local valueEnd = assert(findMatchingBrace(text, valueStart), "Unclosed fingerprint entry")
    local chunk = text:sub(valueStart, valueEnd)
    local loader = assert(loadstring("return " .. chunk))
    entries[#entries + 1] = { fingerprint = key, entry = loader() }
    cursor = valueEnd + 1
  end
  return entries
end

local fingerprintEntries = readFingerprintEntries(source)
local latest = {}
local function isUpgradeEntry(entry)
  return entry.isUpgrade == true
    or (tonumber(entry.upgradeLevel or 0) or 0) > 0
    or (tonumber(entry.upgradeCost or 0) or 0) > 0
end

local function recordScore(entry)
  local mapId, x, y = tonumber(entry.lastMapId), tonumber(entry.lastX), tonumber(entry.lastY)
  -- Vendor coordinates on upgrade records are not spawn locations. Prefer a
  -- located base item when several fingerprints share the same item ID.
  local located = not isUpgradeEntry(entry) and mapId and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1
  local cost = tonumber(entry.upgradeCost or 0) or 0
  return (located and 1000000000000 or 0) + (cost > 0 and 1000000000 or 0)
    + (tonumber(entry.lastSeenAt or entry.firstSeenAt or 0) or 0)
end
for _, record in ipairs(fingerprintEntries) do
  local entry = record.entry
  local id = tonumber(entry.itemId)
  local upgrade = tonumber(entry.upgradeLevel or 0) or 0
  local mapId, x, y = tonumber(entry.lastMapId), tonumber(entry.lastX), tonumber(entry.lastY)
  local hasLocation = not isUpgradeEntry(entry) and mapId and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1
  local hasUpgradeCost = tonumber(entry.upgradeCost or 0) and tonumber(entry.upgradeCost or 0) > 0
  if id and entry.isWorldforged and entry.lastSource ~= "merchant" and (hasLocation or hasUpgradeCost) then
    -- Item IDs identify the scaled/upgrade variants in this client. Keep one
    -- best snapshot per ID instead of exporting repeated fingerprints.
    local variantKey = tostring(id)
    local current = latest[variantKey]
    if not current or recordScore(entry) > recordScore(current) then
      latest[variantKey] = entry
    end
  end
end

local variantKeys = {}
for key in pairs(latest) do variantKeys[#variantKeys + 1] = key end
table.sort(variantKeys)

local function encode(value)
  local result = tostring(value or "")
  result = result:gsub("%%", "%%25")
  result = result:gsub("|", "%%7C")
  result = result:gsub(";", "%%3B")
  result = result:gsub("\n", "%%0A")
  return result
end

local records = {}
for _, variantKey in ipairs(variantKeys) do
  local entry = latest[variantKey]
  local id = tonumber(entry.itemId)
  local upgrade = tonumber(entry.upgradeLevel or 0) or 0
  local exportFingerprint = variantKey
  local mapId, x, y = tonumber(entry.lastMapId), tonumber(entry.lastX), tonumber(entry.lastY)
  local observedAt = tonumber(entry.lastSeenAt or entry.firstSeenAt or 0) or 0
  if mapId and x and y then
    records[#records + 1] = table.concat({"WFG6", id, mapId, x, y, observedAt, encode(entry.realm or "Unknown"), encode(entry.lastZoneName or ""), entry.upgradeCost or "", encode(entry.upgradeCurrency or ""), upgrade, encode(exportFingerprint)}, "|")
  else
    records[#records + 1] = table.concat({"WFG6", id, "", observedAt, encode(entry.realm or "Unknown"), "", "", entry.upgradeCost or "", encode(entry.upgradeCurrency or ""), upgrade, encode(exportFingerprint)}, "|")
  end
end

local file = assert(io.open(output, "w"))
file:write("-- Generated bundled snapshot. Do not edit manually.\n")
file:write("WforgedBundledDataVersion = ", string.format("%q", version), "\n")
file:write("WforgedBundledData = ", string.format("%q", "WFGDB6;" .. table.concat(records, ";")), "\n")
file:close()

local function replaceFile(path, pattern, replacement)
  local input = io.open(path, "r")
  if not input then return end
  local content = input:read("*a")
  input:close()
  local updated, count = content:gsub(pattern, replacement)
  if count > 0 then
    local target = assert(io.open(path, "w"))
    target:write(updated)
    target:close()
  end
end

local summary = string.format("Bundled snapshot: %d unique items including located base items and upgrades.", #variantKeys)
replaceFile(tocPath, "Bundled snapshot: %d+ unique items including located base items and upgrades%.", summary)
replaceFile(readmePath, "The release currently includes a bundled snapshot.-\n",
  string.format("The release currently includes a bundled snapshot of **%d unique items including located base items and upgrades**.\n", #variantKeys))
print(string.format("Exported %d unique bundled items to %s", #variantKeys, output))
