import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRun,act,finish,replay,fixture,userPacket} from './core.mjs';
import {loadPanel} from './build.mjs';
export function runTests(){
 const panel=loadPanel();let passed=0;
 const test=(name,fn)=>{try{fn();passed++;}catch(e){throw Error(name+': '+e.message,{cause:e});}};
 const scenario=id=>panel.scenarios.find(s=>s.id===id),persona=panel.personas[0];
 for(const s of panel.scenarios)test('script '+s.id,()=>{const r=replay(persona,s);assert.equal(r.events.length>0,true);assert.equal(r.checks.some(c=>c.prototypeResult==='fail'),false);assert.equal(r.checks.every(c=>c.nativeResult==='not-evaluated'),true);assert.equal(r.modelRequests,0);});
 test('no-op cancel fails',()=>{const r=finish(createRun(persona,scenario('cancel-record-edit')));assert.equal(r.checks.find(c=>c.id==='edit-was-attempted').prototypeResult,'fail');assert.equal(r.checks.find(c=>c.id==='cancel-preserves-record').prototypeResult,'fail');});
 test('wrong reps rejected by evaluator',()=>{const r=createRun(persona,scenario('start-and-record-set'));act(r,{type:'start'});act(r,{type:'reps',value:8});act(r,{type:'complete-set'});assert.equal(finish(r).checks.find(c=>c.id==='first-set-saved').prototypeResult,'fail');});
 test('failed action atomic',()=>{const r=createRun(persona,scenario('start-and-record-set')),before=JSON.stringify(r);assert.throws(()=>act(r,{type:'complete-set'}));assert.equal(JSON.stringify(r),before);});
 test('sessions isolated',()=>{const a=createRun(persona,scenario('start-and-record-set')),b=createRun(persona,scenario('start-and-record-set'));act(a,{type:'start'});assert.equal(b.state.activeWorkout,null);assert.equal(fixture().activeWorkout,null);});
 test('negative and empty counts rejected',()=>{const r=createRun(persona,scenario('start-and-record-set'));act(r,{type:'start'});for(const value of [-1,1.2,'',1000,'abc'])assert.throws(()=>act(r,{type:'reps',value}));});
 test('invalid previous date atomic',()=>{const r=createRun(persona,scenario('record-previous-workout'));act(r,{type:'new-journal'});act(r,{type:'draft',field:'date',value:'2026-10-32'});act(r,{type:'draft',field:'title',value:'x'});act(r,{type:'draft',field:'reps',value:'10'});assert.throws(()=>act(r,{type:'save'}));assert.equal(r.state.workouts.length,1);});
 test('no duplicate friend request',()=>{const r=createRun(persona,scenario('friend-request-and-private-records'));act(r,{type:'friend-code',value:'ABCD2345'});act(r,{type:'request'});assert.throws(()=>act(r,{type:'request'}));assert.equal(r.state.social.requests.length,1);});
 test('private refresh preserves backup',()=>{const r=createRun(persona,scenario('friend-request-and-private-records'));act(r,{type:'sharing',enabled:false});act(r,{type:'refresh'});assert.deepEqual(r.state.social.published,[]);assert.deepEqual(r.state.social.backup,r.before.social.backup);});
 test('finished run immutable',()=>{const r=createRun(persona,scenario('cancel-record-edit'));finish(r);assert.throws(()=>act(r,{type:'edit-record'}));});
 test('step limit',()=>{const r=createRun(persona,{...scenario('cancel-record-edit'),maxSteps:1});act(r,{type:'refresh'});assert.throws(()=>act(r,{type:'refresh'}));});
 test('user packet has no evaluator data',()=>{const r=createRun(persona,scenario('friend-request-and-private-records'));const p=userPacket(r);assert.deepEqual(Object.keys(p),['persona','userGoal','currentScreen']);assert.equal(JSON.stringify(p).includes('checks'),false);assert.equal(JSON.stringify(p).includes('backup'),false);assert.equal(JSON.stringify(p).includes('SCRIPTS'),false);});
 test('manual and observations unevaluated',()=>{const r=replay(persona,scenario('friend-request-and-private-records'));assert.equal(r.checks.filter(c=>c.kind!=='app-state').every(c=>c.prototypeResult==='not-evaluated'),true);});
 test('no network and persistent storage dependencies',()=>{for(const file of ['core.mjs','ui.js']){const source=readFileSync(new URL(file,import.meta.url),'utf8');assert.equal(/\b(fetch|XMLHttpRequest|WebSocket|localStorage|sessionStorage)\b/.test(source),false);}});
 return {passed,modelRequests:0,nativeEvaluationPerformed:false};
}
if(typeof process!=='undefined' && process.argv[1]?.endsWith('tests.mjs'))console.log(runTests());
