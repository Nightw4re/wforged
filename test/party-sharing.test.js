const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const sync = fs.readFileSync(path.join(__dirname, '..', 'addon', 'Wforged', 'Sync.lua'), 'utf8');
const ui = fs.readFileSync(path.join(__dirname, '..', 'addon', 'Wforged', 'SearchUI.lua'), 'utf8');

test('party database sharing requires a selected target', () => {
  assert.match(ui, /UnitName and UnitName\("target"\)/);
  assert.match(ui, /Target a party member before sharing the database/);
});

test('party transfer uses an explicit request and approval handshake', () => {
  assert.match(sync, /WFGSHARE_REQ\|/);
  assert.match(sync, /WFGSHARE_ACK\|/);
  assert.match(sync, /pendingShareRequests/);
  assert.match(sync, /shortName\(sender\).*pending\.target/);
});

test('party chunks are targeted, checksummed and throttled', () => {
  assert.match(sync, /WFGSHARE1\|%s\|%s\|%s\|%d\|%d\|%s\|%s/);
  assert.match(sync, /shareChecksum\(chunk\) == checksum/);
  assert.match(sync, /C_Timer\.After\(self\.shareChunkDelay/);
  assert.match(sync, /targetName and shortName\(targetName\) ~= shortName\(playerName\)/);
});

test('completed party transfer accepts only WFGDB8 data', () => {
  assert.match(sync, /data:sub\(1, 7\) == "WFGDB8;"/);
});

test('party receiver binds all chunks to one sender and expires transfers', () => {
  assert.match(sync, /share\.sender ~= shortName\(senderName\)/);
  assert.match(sync, /share\.expiresAt and time\(\) > share\.expiresAt/);
});

test('a local party-share request test command is available', () => {
  const core = fs.readFileSync(path.join(__dirname, '..', 'addon', 'Wforged', 'Wforged.lua'), 'utf8');
  assert.match(core, /test-party-request/);
  assert.match(core, /No data was sent or changed/);
});

test('loot scanning does not queue ordinary non-Worldforged items', () => {
  const core = fs.readFileSync(path.join(__dirname, '..', 'addon', 'Wforged', 'Wforged.lua'), 'utf8');
  assert.match(core, /if isWorldforged then/);
  assert.match(core, /frame\.pendingElapsed >= 1/);
});

test('upgrade pending records preserve cost after the vendor closes', () => {
  const scan = fs.readFileSync(path.join(__dirname, '..', 'addon', 'Wforged', 'ItemScan.lua'), 'utf8');
  const db = fs.readFileSync(path.join(__dirname, '..', 'addon', 'Wforged', 'DB.lua'), 'utf8');
  assert.match(scan, /upgradeCost = context and context\.upgradeCost/);
  assert.match(scan, /upgradeCurrency = context and context\.upgradeCurrency/);
  assert.match(db, /entry\.upgradeCost = payload\.upgradeCost or entry\.upgradeCost/);
});

test('vendor scan repairs existing variants from visible offers', () => {
  const vendor = fs.readFileSync(path.join(__dirname, '..', 'addon', 'Wforged', 'VendorScan.lua'), 'utf8');
  assert.match(vendor, /Upgrade cost repaired from vendor offer/);
  assert.match(vendor, /tonumber\(existing\.itemId\) == tonumber\(candidate\.itemId\)/);
});
