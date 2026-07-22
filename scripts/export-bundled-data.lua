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
  if id and upgrade <= 0 and entry.isWorldforged and hasLocation then
    local current = latest[id]
    if not current or (tonumber(entry.lastSeenAt or 0) or 0) > (tonumber(current.lastSeenAt or 0) or 0) then
      latest[id] = entry
    end
  end
end

local ids = {}
for id in pairs(latest) do ids[#ids + 1] = id end
table.sort(ids)

local function encode(value)
  return tostring(value or "")
    :gsub("%%", "%%25")
    :gsub("|", "%%7C")
    :gsub(";", "%%3B")
    :gsub("\n", "%%0A")
end

local records = {}
for _, id in ipairs(ids) do
  local entry = latest[id]
  local mapId, x, y = tonumber(entry.lastMapId), tonumber(entry.lastX), tonumber(entry.lastY)
  local observedAt = tonumber(entry.lastSeenAt or entry.firstSeenAt or 0) or 0
  records[#records + 1] = table.concat({"WFG6", id, mapId, x, y, observedAt}, "|")
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

local summary = string.format("Bundled snapshot: %d unique located base items.", #ids)
replaceFile(tocPath, "Bundled snapshot: %d+ unique [%a ]+base items%.", summary)
replaceFile(readmePath, "The release currently includes a bundled snapshot.-\n",
  string.format("The release currently includes a bundled snapshot of **%d unique located base items**. Upgrade variants and locationless records are intentionally excluded.\n", #ids))
print(string.format("Exported %d unique base items to %s", #ids, output))
