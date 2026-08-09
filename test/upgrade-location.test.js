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
  assert.match(core, /C_Timer\.After\(5, function\(\)/);
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
