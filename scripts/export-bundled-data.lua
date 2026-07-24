-- Usage: luajit scripts/export-bundled-data.lua path/to/Wforged.lua version
local source = assert(arg[1], "Missing SavedVariables path")
local version = assert(arg[2], "Missing addon version")
local output = "addon/Wforged/BundledData.lua"
local tocPath = "addon/Wforged/Wforged.toc"
local readmePath = "README.md"

dofile(source)
local latest = {}
for _, entry in pairs(WforgedDB.itemsByFingerprint or {}) do
  local id = tonumber(entry.itemId)
  local upgrade = tonumber(entry.upgradeLevel or 0) or 0
  local mapId, x, y = tonumber(entry.lastMapId), tonumber(entry.lastX), tonumber(entry.lastY)
  local hasLocation = mapId and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1
  local hasUpgradeCost = tonumber(entry.upgradeCost or 0) and tonumber(entry.upgradeCost or 0) > 0
  if id and entry.isWorldforged and entry.lastSource ~= "merchant" and (hasLocation or hasUpgradeCost) then
    local variantKey = entry.fingerprint or table.concat({ tostring(id), tostring(entry.lastMapId or ""), tostring(entry.lastX or ""), tostring(entry.lastY or ""), tostring(upgrade), tostring(entry.lastSeenAt or entry.firstSeenAt or 0), tostring(entry.lastSource or "") }, ":")
    local current = latest[variantKey]
    if not current or (tonumber(entry.lastSeenAt or 0) or 0) > (tonumber(current.lastSeenAt or 0) or 0) then
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
  local exportFingerprint = entry.fingerprint or table.concat({ tostring(id), tostring(entry.lastMapId or ""), tostring(entry.lastX or ""), tostring(entry.lastY or ""), tostring(upgrade), tostring(entry.lastSeenAt or entry.firstSeenAt or 0), tostring(entry.lastSource or "") }, ":")
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
replaceFile(tocPath, "Bundled snapshot: %d+ unique [%a ]+items including located base items and upgrades%.", summary)
replaceFile(readmePath, "The release currently includes a bundled snapshot.-\n",
  string.format("The release currently includes a bundled snapshot of **%d unique items including located base items and upgrades**.\n", #variantKeys))
print(string.format("Exported %d unique bundled items to %s", #variantKeys, output))
