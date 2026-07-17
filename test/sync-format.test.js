const test = require('node:test');
const assert = require('node:assert/strict');

const realExport = 'WFGDB6;WFG6|450559|40|0.7154|0.7379|1784222003;WFG6|450557|40|0.5317|0.7906|1784195081;WFG6|450748|40|0.6078|0.5827|1784194402;WFG6|1388996||1784192678;WFG6|1388679||1784192678;WFG6|450934||1784192669;WFG6|521267||1784192669;WFG6|450556|40|0.428|0.885|1784221802;WFG6|1388570||1784192678;WFG6|450555|40|0.3356|0.8647|1784221687;WFG6|1388779||1784192678;WFG6|450551||1784192669;WFG6|515681||1784192669;WFG6|1388546||1784192678;WFG6|515687|40|0.3573|0.904|1784221326;WFG6|450564|40|0.4137|0.6647|1784197106;WFG6|515430||1784192669;WFG6|450562|40|0.4007|0.68|1784194762;WFG6|451117||1784192669;WFG6|450593|35|0.1914|0.5561|1784222456;WFG6|450563|15|0.409|0.8196|1784200008;WFG6|515684|40|0.7007|0.7482|1784222170;WFG6|450528||1784192669;WFG6|450594|35|0.1747|0.5636|1784222299;WFG6|1388997||1784192678;WFG6|450673||1784192669;WFG6|1389367||1784192678;WFG6|450909||1784192669;WFG6|1388771||1784192678;WFG6|515429||1784192669';

function parseImport(text) {
  if (text.slice(0, 6) !== 'WFGDB6') throw new Error('Expected WFGDB6');
  return text.slice(7).split(';').filter(Boolean).map((record) => record.split('|')).filter((fields) => {
    return fields[0] === 'WFG6' && /^\d+$/.test(fields[1] || '');
  });
}

function decodeRecord(fields) {
  const located = fields.length >= 6 && fields[2] !== '' && fields[3] !== '' && fields[4] !== '';
  return {
    itemId: Number(fields[1]),
    mapId: located ? Number(fields[2]) : null,
    x: located ? Number(fields[3]) : null,
    y: located ? Number(fields[4]) : null,
    observedAt: Number(located ? fields[5] : fields[3]),
  };
}

function shouldShowAllMarker(result, currentMapId, viewingTargetZone) {
  return result.x !== null && result.y !== null
    && (currentMapId === result.mapId || viewingTargetZone === result.zoneName);
}

test('parses a located item', () => {
  assert.deepEqual(parseImport('WFGDB6;WFG6|450559|40|0.7154|0.7379|1784222003'), [
    ['WFG6', '450559', '40', '0.7154', '0.7379', '1784222003'],
  ]);
});

test('keeps the empty location field', () => {
  const record = parseImport('WFGDB6;WFG6|1388996||1784192678')[0];
  assert.equal(record[2], '');
  assert.equal(record[3], '1784192678');
});

test('filters malformed and old-version records', () => {
  const records = parseImport('WFGDB6;bad;WFG5|450557|40|0.3|0.4|2;WFG6|450557||3');
  assert.deepEqual(records.map((record) => record[1]), ['450557']);
});

test('rejects an unsupported header', () => {
  assert.throws(() => parseImport('WFGDB5;WFG5|450559'), /WFGDB6/);
});

test('keeps decimal coordinates as text until validation', () => {
  const record = parseImport('WFGDB6;WFG6|450559|40|0.0001|1.0000|1784222003')[0];
  assert.equal(Number(record[3]), 0.0001);
  assert.equal(Number(record[4]), 1);
});

test('does not accept non-numeric item IDs', () => {
  assert.equal(parseImport('WFGDB6;WFG6|abc|40|0.1|0.2|1').length, 0);
});

test('does not accept records with missing IDs', () => {
  assert.equal(parseImport('WFGDB6;WFG6||40|0.1|0.2|1').length, 0);
});

test('preserves record order before application sorting', () => {
  const records = parseImport('WFGDB6;WFG6|2|40|0.1|0.2|1;WFG6|1||2');
  assert.deepEqual(records.map((record) => record[1]), ['2', '1']);
});

test('accepts a large batch without dropping records', () => {
  const records = Array.from({ length: 1800 }, (_, index) => `WFG6|${index + 1}||${index + 100}`).join(';');
  assert.equal(parseImport(`WFGDB6;${records}`).length, 1800);
});

test('accepts the real exported database fixture', () => {
  const records = parseImport(realExport);
  assert.equal(records.length, 30);
  assert.equal(records.filter((record) => record.length === 6).length, 12);
  assert.equal(records.filter((record) => record.length === 4).length, 18);
  assert.equal(records[0][1], '450559');
  assert.equal(records[0][2], '40');
  assert.equal(records[0][3], '0.7154');
  assert.equal(records[0][4], '0.7379');
});

test('real fixture keeps locationless timestamps in the fourth field', () => {
  const record = parseImport(realExport).find((item) => item[1] === '1388996');
  assert.deepEqual(record, ['WFG6', '1388996', '', '1784192678']);
});

test('real fixture never treats a timestamp as a map ID', () => {
  for (const fields of parseImport(realExport)) {
    const decoded = decodeRecord(fields);
    if (decoded.mapId !== null) {
      assert.ok(decoded.mapId < 1000, `unexpected map ID for item ${decoded.itemId}`);
    }
    assert.ok(decoded.observedAt > 1000000000, `invalid timestamp for item ${decoded.itemId}`);
  }
});

test('real fixture preserves every located coordinate', () => {
  const expected = {
    450559: [40, 0.7154, 0.7379],
    450557: [40, 0.5317, 0.7906],
    450563: [15, 0.409, 0.8196],
    450593: [35, 0.1914, 0.5561],
    515687: [40, 0.3573, 0.904],
  };
  for (const fields of parseImport(realExport)) {
    const itemId = Number(fields[1]);
    if (!expected[itemId]) continue;
    assert.deepEqual([decodeRecord(fields).mapId, decodeRecord(fields).x, decodeRecord(fields).y], expected[itemId]);
  }
});

test('real fixture keeps locationless items without coordinates', () => {
  const locationlessIds = [1388996, 1388679, 450934, 521267, 515430, 450673, 515429];
  for (const fields of parseImport(realExport)) {
    if (!locationlessIds.includes(Number(fields[1]))) continue;
    const decoded = decodeRecord(fields);
    assert.equal(decoded.mapId, null);
    assert.equal(decoded.x, null);
    assert.equal(decoded.y, null);
  }
});

test('show all keeps markers when map ID and zone name are both known', () => {
  const record = decodeRecord(parseImport(realExport).find((item) => item[1] === '450748'));
  assert.equal(shouldShowAllMarker({ x: record.x, y: record.y, mapId: record.mapId, zoneName: 'Westfall' }, 40, null), true);
});

test('show all hides markers from another map', () => {
  const record = decodeRecord(parseImport(realExport).find((item) => item[1] === '450748'));
  assert.equal(shouldShowAllMarker({ x: record.x, y: record.y, mapId: record.mapId, zoneName: 'Westfall' }, 35, 'Duskwood'), false);
});
