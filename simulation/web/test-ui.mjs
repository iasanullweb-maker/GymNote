// DOM event smoke tests, not a browser render/accessibility test.
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {loadPanel} from './build.mjs';
export function runUITests(){
 const elements=new Map(),downloads=[];
 class Element{
  constructor(tag){this.tag=tag;this.children=[];this.value='';this.textContent='';this.disabled=false;}
  append(n){this.children.push(n);if(this.tag==='select' && !this.value)this.value=n.value;}
  replaceChildren(){this.children=[];}
  get childElementCount(){return this.children.length;}
  setAttribute(){}
  click(){if(!this.disabled)this.onclick?.();if(this.tag==='a')downloads.push(this.download);}
 }
 for(const id of ['persona','scenario','begin','context','goal','finish','download','packet','tabs','screen-title','screen','error','steps','review','checks','note','evidence'])elements.set(id,new Element(['persona','scenario'].includes(id)?'select':'div'));
 const context=vm.createContext({document:{getElementById:id=>elements.get(id),createElement:tag=>new Element(tag)},Blob:class{constructor(parts){this.parts=parts;}},URL:{createObjectURL:()=> 'blob:test',revokeObjectURL(){}},setTimeout:fn=>fn()});
 const source=readFileSync(new URL('core.mjs',import.meta.url),'utf8').replace(/^export /gm,'')+'\nconst PANEL='+JSON.stringify(loadPanel())+';\n'+readFileSync(new URL('ui.js',import.meta.url),'utf8');
 vm.runInContext(source,context);
 const get=id=>elements.get(id);
 const btn=(id,label)=>{const node=get(id).children.find(n=>n.tag==='button' && n.textContent===label);assert.ok(node,'button '+label);node.click();};
 const field=(value,index=0)=>{const n=get('screen').children.filter(n=>n.tag==='input')[index];assert.ok(n);n.value=value;n.onchange();};
 const read=expr=>JSON.parse(vm.runInContext('JSON.stringify('+expr+')',context));
 get('scenario').value='cancel-record-edit';get('begin').click();btn('screen','푸쉬업 기록 편집');
 const cancel=get('screen').children.find(n=>n.textContent==='취소');field('50');
 assert.equal(get('screen').children.includes(cancel),true,'input change must not remove the button before click');cancel.click();
 assert.equal(read('run.state.records[0].value'),18);get('finish').click();
 assert.equal(get('review').hidden,false);assert.equal(read('output.checks.filter(c=>c.kind==="app-state").every(c=>c.prototypeResult==="pass")'),true);get('download').click();assert.equal(downloads.length,1);
 get('scenario').value='record-previous-workout';get('begin').click();btn('screen','지난 운동 남기기');field('2026-10-11',0);field('어제 푸쉬업',1);field('10,8,6',2);btn('screen','일지 저장');
 assert.equal(get('error').textContent,'');assert.equal(read('run.state.workouts.length'),2);
 get('scenario').value='start-and-record-set';get('begin').click();btn('screen','운동 시작');field('7');btn('screen','이 세트 완료');assert.equal(read('run.state.screen'),'workout-rest');btn('screen','가상 시간 30초 이동');assert.equal(read('run.state.restSeconds'),30);
 get('scenario').value='friend-request-and-private-records';get('begin').click();field('ABCD2345');btn('screen','연결 요청');btn('screen','공개 끄기');btn('screen','새로고침');btn('screen','친구 최고기록 보기');assert.equal(read('run.state.social.published.length'),0);
 get('scenario').value='return-to-selected-plan';get('begin').click();btn('screen','2026-10-14');btn('tabs','기록');btn('tabs','계획');assert.equal(read('run.state.selectedDate'),'2026-10-14');assert.equal(read('run.state.screen'),'plan-date-detail');
 return {flows:5,downloadEvents:downloads.length,browserRenderingPerformed:false};
}
if(typeof process!=='undefined' && process.argv[1]?.endsWith('test-ui.mjs'))console.log(runUITests());
