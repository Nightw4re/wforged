const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const addonDir = path.join(__dirname, '..', 'addon', 'Wforged');
const bundled = fs.readFileSync(path.join(addonDir, 'BundledData.lua'), 'utf8');
const toc = fs.readFileSync(path.join(addonDir, 'Wforged.toc'), 'utf8');

test('bundled database has a valid WFGDB6 snapshot', () => {
  const match = bundled.match(/WforgedBundledData\s*=\s*"([^"]+)"/);
  assert.ok(match, 'BundledData.lua must define WforgedBundledData');
  assert.match(match[1], /^WFGDB6;WFG6\|/);
  const records = match[1].split(';').slice(1);
  assert.ok(records.length > 0);
  for (const record of records) {
    const fields = record.split('|');
    assert.equal(fields[0], 'WFG6');
    assert.match(fields[1], /^\d+$/);
    assert.ok(fields.length === 7 || fields.length === 10 || fields.length === 11 || fields.length === 12, 'bundled records must use the base or upgrade format');
    if (fields[2] && fields[3]) {
      assert.match(fields[2], /^\d+$/);
      assert.match(fields[3], /^0?\.\d+$/);
      assert.match(fields[4], /^0?\.\d+$/);
      assert.match(fields[5], /^\d+$/);
      assert.ok(fields[6], 'bundled records must include a source realm');
    } else {
      assert.match(fields[3], /^\d+$/);
      assert.ok(fields[4], 'locationless upgrades must include a source realm');
      assert.match(fields[7], /^\d+$/);
    }
  }
});

test('bundled database is loaded by the addon and documented in the TOC', () => {
  assert.match(toc, /^BundledData\.lua$/m);
  assert.match(fs.readFileSync(path.join(addonDir, 'Wforged.lua'), 'utf8'), /self\.Sync:Import\(WforgedBundledData\)/);
  assert.match(toc, /Bundled snapshot: \d+ unique items including located base items and upgrades\./);
});
