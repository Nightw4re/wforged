const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const db = fs.readFileSync(path.join(__dirname, '..', 'addon', 'Wforged', 'DB.lua'), 'utf8');
const scan = fs.readFileSync(path.join(__dirname, '..', 'addon', 'Wforged', 'ItemScan.lua'), 'utf8');
const core = fs.readFileSync(path.join(__dirname, '..', 'addon', 'Wforged', 'Wforged.lua'), 'utf8');
const ui = fs.readFileSync(path.join(__dirname, '..', 'addon', 'Wforged', 'SearchUI.lua'), 'utf8');

test('upgrade locations use an explicit source reference', () => {
  assert.match(db, /sourceInfo\.sourceItemKey/);
  assert.match(db, /sourceInfo\.sourceItemId/);
  assert.match(db, /GetResolvedSourceLocation\(itemKey\)/);
});

test('same-name and ilvl fallback is not used for upgrade locations', () => {
  assert.doesNotMatch(db, /nearest lower-level base variant/);
  assert.doesNotMatch(db, /candidateLevel < currentLevel/);
});

test('vendor coordinates are rejected as item locations', () => {
  assert.match(db, /function DB:IsVendorLocation/);
  assert.match(db, /not self:IsVendorLocation\(point\.mapId, point\.x, point\.y\)/);
  assert.match(db, /source == "merchant"/);
  assert.match(db, /not isLocationlessSource\(payload\.sourceType\)/);
  assert.match(scan, /record\.sourceType ~= "upgrade-frame"/);
});

test('bundled database snapshots can replace stale shared locations', () => {
  assert.match(sync, /sourceType = fields\.importSource or "import"/);
  assert.match(sync, /local bundledSource = payload\.sourceType == "bundled"/);
  assert.match(sync, /bundledSource or \(not existing\)/);
  assert.match(core, /Import\(WforgedBundledData, \{ source = "bundled" \}\)/);
});

test('show-all keeps the selected item marker visible', () => {
  assert.doesNotMatch(mapCore, /local selectedPin = self\.pin and self\.pin:IsShown\(\) and self\.pin\.result/);
  assert.doesNotMatch(mapCore, /Do not draw the smaller "show all" marker/);
  assert.match(mapCore, /visible\[key\] = true/);
});

test('show-all excludes upgrade markers', () => {
  assert.match(mapCore, /local isUpgradeResult = result\.isUpgrade == true/);
  assert.match(mapCore, /if not isUpgradeResult and result\.lastX and result\.lastY/);
});

test('open-map zone repair is cached per map', () => {
  assert.match(scan, /openMapRepairCompletedKey == mapPreviewKey/);
  assert.match(scan, /openMapRepairCompletedKey = mapPreviewKey/);
});

test('guild imports remain searchable while item metadata loads', () => {
  assert.match(sync, /self:Import\(message, \{ source = "guild" \}\)/);
  assert.match(db, /local sharedSource = entry\.lastSource == "import"/);
  assert.match(db, /\(hasBindOnPickup\(entry\) or sharedSource\)/);
});

test('database consolidates duplicate fingerprints by item id once', () => {
  assert.match(db, /itemIdConsolidationV1/);
  assert.match(db, /ConsolidateItemIdRecords/);
  assert.match(db, /removed %d duplicate records/);
  assert.match(db, /self\.data\.itemsByFingerprint\[duplicate\.fingerprint\] = nil/);
});

test('upgrade repair waits 30 seconds after login', () => {
  assert.match(core, /C_Timer\.After\(30, function\(\)/);
});

test('runtime addon version is not left on the old hardcoded version', () => {
  assert.doesNotMatch(core, /addon\.version\s*=\s*"1\.0\.1"/);
});

test('previous-item search makes exact phrase syntax visible', () => {
  assert.match(ui, /quotedSourceName = sourceName and \('\"' \.\. tostring\(sourceName\)/);
  assert.match(ui, /SetText\(quotedSourceName\)/);
});

test('preferred fingerprint can select a located imported variant', () => {
  assert.match(db, /validated spawn location/);
  assert.match(db, /self:GetBestLocationForFingerprint\(fingerprint\)/);
});

test('search restores a missing zone name from an exact stored location', () => {
  assert.match(db, /function DB:GetStoredLocationName/);
  assert.match(db, /storedLocationKey\(itemId, location\)/);
  assert.match(db, /sourceEntry and sourceEntry\.itemId/);
  assert.match(db, /location\.zoneName = storedName\.zoneName/);
});

test('upgrade location repair is queued and processed incrementally', () => {
  assert.match(db, /upgradeLocationRepairQueue/);
  assert.match(db, /function DB:ProcessUpgradeLocationRepair\(limit\)/);
  assert.match(core, /ProcessUpgradeLocationRepair\(1\)/);
  assert.match(core, /frame\.repairElapsed >= 1\.5/);
  assert.doesNotMatch(core, /C_Timer\.After\(5, function\(\)/);
});

test('upgrade repair cache is invalidated when item data changes', () => {
  assert.match(db, /self\.resolvedSourceLocationCache = \{\}/);
  assert.match(db, /local cached = self\.resolvedSourceLocationCache\[itemKey\]/);
  assert.match(db, /self\.resolvedSourceLocationCache = \{\}/);
  assert.match(db, /function DB:RecordVendorUpgrade/);
});

test('UI uses stored upgrade metadata for price and previous-item actions', () => {
  assert.match(db, /isUpgrade = entryIsUpgrade/);
  assert.match(db, /upgradeCost = entry\.upgradeCost or/);
  assert.match(ui, /result\.isUpgrade == true/);
  assert.match(ui, /SearchUI:SearchForSource\(result\)/);
});

test('shift-click inserts a colorized chat item link', () => {
  assert.match(ui, /ChatEdit_InsertLink\(buildChatItemLink\(clickedRow\.result\)\)/);
});

test('WFG6 parser preserves empty fields between location metadata', () => {
  const sync = fs.readFileSync(path.join(__dirname, '..', 'addon', 'Wforged', 'Sync.lua'), 'utf8');
  assert.match(sync, /string\.find\(text, "\\|", start, true\)/);
  assert.doesNotMatch(sync, /gmatch\(tostring\(record or ""\), "\[\^\|\]\+"\)/);
});

test('startup clears malformed imported fingerprints from location display', () => {
  assert.match(db, /function DB:CleanupMalformedImportedLocations/);
  assert.match(db, /entry\.lastZoneName = nil/);
  assert.match(db, /malformedImportedLocationsV1/);
});

test('unknown zone keeps map coordinates usable in the search UI', () => {
  assert.doesNotMatch(ui, /result\.zoneRepairPending or not result\.lastZoneName/);
  assert.match(ui, /return "unknown zone"/);
});
