// DOM values and external dataset text are inserted through textContent.
const $=id=>document.getElementById(id);
let run,output;
function text(parent,tag,value){const n=document.createElement(tag);n.textContent=value;parent.append(n);return n;}
function button(parent,label,action){const n=text(parent,'button',label);n.type='button';n.disabled=run.finished;n.onclick=()=>dispatch(action);return n;}
function input(parent,label,value,handler,type='text'){const id='field-'+parent.childElementCount;const l=text(parent,'label',label);l.htmlFor=id;const n=document.createElement('input');n.id=id;n.type=type;n.value=value;n.disabled=run.finished;n.onchange=()=>{try{handler(n.value);$('error').textContent='';}catch(e){$('error').textContent=e.message;}};parent.append(n);return n;}
function updateField(action){act(run,action);$('packet').textContent=JSON.stringify(userPacket(run),null,2);$('steps').textContent='조작 '+run.events.length+' / '+run.scenario.maxSteps;}
function dispatch(action){try{act(run,action);render();$('error').textContent='';}catch(e){$('error').textContent=e.message;}}
const titles={'workout-ready':'오늘 운동','workout-active':'진행 중 운동','workout-rest':'세트 사이 휴식','plan-month':'10월 운동 계획','plan-date-detail':'선택 날짜 계획','records-overview':'내 기록','journal-calendar':'운동 일지','journal-entry':'지난 운동 입력','friends-home':'친구','friends-ranking':'친구 최고기록'};
function render(){
 const s=run.state,c=$('screen');c.replaceChildren();$('screen-title').textContent=titles[s.screen];$('tabs').replaceChildren();
 for(const [label,target] of [['운동',s.activeWorkout?(s.restSeconds>0&&s.screen==='workout-rest'?'workout-rest':'workout-active'):'workout-ready'],['계획',s.selectedDate==='2026-10-14'?'plan-date-detail':'plan-month'],['기록','records-overview'],['일지','journal-calendar'],['친구','friends-home']]){const b=button($('tabs'),label,{type:'navigate',screen:target});b.setAttribute('aria-current',String(s.screen===target));}
 switch(s.screen){
  case 'workout-ready':text(c,'article','2026-10-12 · 상체 운동 / 푸쉬업 3세트 × 10회');button(c,'운동 시작',{type:'start'});break;
  case 'workout-active':text(c,'article','푸쉬업 · 완료 '+(s.activeWorkout?.completedSets??0)+' / 3세트');if(s.activeWorkout){input(c,'실제 횟수',s.inputReps,v=>updateField({type:'reps',value:v}),'number');button(c,'이 세트 완료',{type:'complete-set'});}else text(c,'p','진행 중 운동이 없습니다.');break;
  case 'workout-rest':text(c,'article','완료 '+s.activeWorkout?.completedSets+'세트 · 휴식 '+s.restSeconds+'초');button(c,'가상 시간 30초 이동',{type:'tick',seconds:30});button(c,'휴식 건너뛰기',{type:'tick',seconds:s.restSeconds});break;
  case 'plan-month':text(c,'p','합성 계획이 있는 날짜');for(const date of Object.keys(s.scheduledPlans))button(c,date,{type:'select-date',date});break;
  case 'plan-date-detail':text(c,'article',s.selectedDate+' · '+s.scheduledPlans[s.selectedDate].title+' / 푸쉬업 3세트 × 10회');button(c,'월간 일정',{type:'navigate',screen:'plan-month'});break;
  case 'records-overview':for(const r of s.records)text(c,'article',r.name+' · '+r.value+'회 ('+r.date+')');if(s.draft?.kind==='record'){input(c,'편집 중 횟수',s.draft.value,v=>updateField({type:'draft',field:'value',value:v}),'number');button(c,'저장',{type:'save'});button(c,'취소',{type:'cancel'});}else{button(c,'푸쉬업 기록 편집',{type:'edit-record'});button(c,'지난 운동 남기기',{type:'new-journal'});}break;
  case 'journal-calendar':for(const w of s.workouts)text(c,'article',w.date+' · '+w.title+' / '+w.actualReps.join(', ')+'회');button(c,'지난 운동 남기기',{type:'new-journal'});break;
  case 'journal-entry':if(s.draft?.kind==='journal'){input(c,'날짜',s.draft.date,v=>updateField({type:'draft',field:'date',value:v}),'date');input(c,'제목',s.draft.title,v=>updateField({type:'draft',field:'title',value:v}));text(c,'p','종목: 푸쉬업');input(c,'세트별 실제 횟수 (쉼표로 구분)',s.draft.reps,v=>updateField({type:'draft',field:'reps',value:v}));button(c,'일지 저장',{type:'save'});button(c,'취소',{type:'cancel'});}else{ text(c,'p','입력 중인 일지가 없습니다.');button(c,'일지 목록',{type:'navigate',screen:'journal-calendar'});}break;
  case 'friends-home':input(c,'친구 코드',s.friendCode,v=>updateField({type:'friend-code',value:v}));button(c,'연결 요청',{type:'request'});for(const r of s.social.requests)text(c,'article',r.code+' · 수락 대기');text(c,'p','최고기록 공개: '+(s.social.share_records?'켜짐':'꺼짐'));button(c,s.social.share_records?'공개 끄기':'공개 켜기',{type:'sharing',enabled:!s.social.share_records});button(c,'새로고침',{type:'refresh'});button(c,'친구 최고기록 보기',{type:'navigate',screen:'friends-ranking'});break;
  case 'friends-ranking':text(c,'article',s.social.published.length?s.social.published.map(r=>'합성 공개 기록 '+r.value+'회').join('\n'):'공개 기록 없음');button(c,'친구 설정으로',{type:'navigate',screen:'friends-home'});break;
 }
 if(s.message)text(c,'p',s.message);$('steps').textContent='조작 '+run.events.length+' / '+run.scenario.maxSteps+' · 기준 시각 '+s.clock;
 $('packet').textContent=JSON.stringify(userPacket(run),null,2);$('finish').disabled=run.finished;
}
function start(){run=createRun(PANEL.personas.find(p=>p.id===$('persona').value),PANEL.scenarios.find(s=>s.id===$('scenario').value));output=null;$('review').hidden=true;$('download').disabled=true;$('note').value='';$('error').textContent='';$('context').replaceChildren();text($('context'),'p',run.persona.context);text($('context'),'small',run.persona.goals.join(' · '));$('goal').textContent=run.scenario.userGoal;render();}
for(const [id,items] of [['persona',PANEL.personas],['scenario',PANEL.scenarios]])for(const item of items){const o=document.createElement('option');o.value=item.id;o.textContent=item.name??item.title;$(id).append(o);}
$('begin').onclick=start;
$('finish').onclick=()=>{output=finish(run);render();$('review').hidden=false;$('download').disabled=false;$('checks').replaceChildren();for(const c of output.checks)text($('checks'),'div',c.id+' · 웹 '+c.prototypeResult+' / iOS '+c.nativeResult).className='check';$('evidence').textContent=JSON.stringify({events:output.events,before:output.before,after:output.after},null,2);};
$('download').onclick=()=>{if(!output)return;const result={...output,plannerNote:$('note').value,inputs:PANEL.hashes,code:PANEL.code};const url=URL.createObjectURL(new Blob([JSON.stringify(result,null,2)],{type:'application/json'}));const a=document.createElement('a');a.href=url;a.download='gymnote-web-'+run.scenario.id+'.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);};
start();
