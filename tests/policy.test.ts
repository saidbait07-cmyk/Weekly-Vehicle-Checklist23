import {test} from 'node:test';
import assert from 'node:assert/strict';
import {companyDate,validateResponses,transitions} from '../src/server/policy';
test('Muscat date rolls over before UTC midnight',()=>{assert.equal(companyDate(new Date('2026-11-03T21:00:00Z')),'2026-11-04')});
const items=[{id:'brakes',isRequired:true,allowedResponses:['PASS','FAIL','NA']},{id:'horn',isRequired:true,allowedResponses:['PASS','FAIL','NA']}];
test('missing, duplicate, foreign, and invalid answers are rejected',()=>{for(const r of [[{checklistItemId:'brakes',response:'PASS'}],[{checklistItemId:'brakes',response:'PASS'},{checklistItemId:'brakes',response:'FAIL'}],[{checklistItemId:'brakes',response:'PASS'},{checklistItemId:'unknown',response:'PASS'}],[{checklistItemId:'brakes',response:'PASS'},{checklistItemId:'horn',response:'UNSAFE'}]])assert.throws(()=>validateResponses(items,r));});
test('complete answers including NA are accepted',()=>assert.doesNotThrow(()=>validateResponses(items,[{checklistItemId:'brakes',response:'PASS'},{checklistItemId:'horn',response:'NA'}])));
test('faults cannot skip review and closure is terminal',()=>{assert.deepEqual(transitions.VERIFIED_AND_CLOSED,[]);assert(!transitions.REPORTED.includes('VERIFIED_AND_CLOSED'));assert(transitions.RESOLVED.includes('VERIFIED_AND_CLOSED'))});
