import test from 'node:test';
import assert from 'node:assert/strict';
import {checkCurrency} from './currency.mjs';
const fixture = () => ({policy:{reverifyWithinDays:3,defaultMaxSourceAgeDays:120},items:[{
  id:'C1',tag:'fact',camp:'lab',claim:'Dated claim',url:'https://example.invalid/source',sourceDate:'2026-10-01',retrieved:'2026-10-03',version:'v1',anchor:'Dated claim',reverified:[{date:'2026-10-03',result:'ok'}]
}]});
test('export-day evidence must match today even when draft research has a three-day window', () => {
  const data=fixture();
  assert.deepEqual(checkCurrency(data,'2026-10-04'),[],'draft currency can use its policy window');
  assert.ok(checkCurrency(data,'2026-10-04',undefined,true).some(error=>/not re-verified for export/.test(error)),'yesterday-only evidence cannot certify today export');
  data.items[0].reverified.push({date:'2026-10-04',result:'ok'});
  assert.deepEqual(checkCurrency(data,'2026-10-04',undefined,true),[]);
});