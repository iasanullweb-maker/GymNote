// Offline behavioural prototype. This is not the Swift app or its storage.
export const SCREENS = ['workout-ready','workout-active','workout-rest','plan-month','plan-date-detail','records-overview','journal-calendar','journal-entry','friends-home','friends-ranking'];
const copy = x => JSON.parse(JSON.stringify(x));
const same = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const count = x => { const n=Number(x); if (String(x).trim()==='' || !Number.isInteger(n) || n<0 || n>999) throw Error('0~999의 정수를 입력하세요.'); return n; };
export function fixture(screen='workout-ready') {
  if (!SCREENS.includes(screen)) throw Error('Unknown screen');
  return {clock:'2026-10-12T09:00:00+09:00',screen,selectedDate:'2026-10-12',restSeconds:60,
    scheduledPlans:{'2026-10-12':{title:'상체 운동',sets:3,reps:10},'2026-10-14':{title:'수요일 상체',sets:3,reps:10}},
    activeWorkout:null,workouts:[{id:'existing-journal',date:'2026-10-08',title:'아침 상체 운동',actualReps:[10,12],completedSets:2}],
    records:[{id:'manual-pushup',name:'푸쉬업',value:18,date:'2026-10-08'}],logs:[],
    social:{ownCode:'SELF1234',targetCode:'ABCD2345',share_records:true,requests:[],published:[{id:'published-pushup',value:18}],backup:[{id:'manual-pushup',value:18}]},
    draft:null,inputReps:10,friendCode:'',message:''};
}
export function createRun(persona,scenario,controller='human') {
  if (!['human','scripted'].includes(controller)) throw Error('Unknown controller');
  const state=fixture(scenario.startCaptureId);
  return {persona:copy(persona),scenario:copy(scenario),controller,before:copy(state),state,events:[],finished:false};
}
function reduce(state,a) {
  const s=copy(state); s.message='';
  switch(a.type) {
    case 'navigate':
      if (!SCREENS.includes(a.screen)) throw Error('Unknown screen');
      // A draft is deliberately discarded when leaving its screen.
      if (s.draft && a.screen!==s.screen) s.draft=null;
      s.screen=a.screen; break;
    case 'select-date':
      if (s.screen!=='plan-month' || !s.scheduledPlans[a.date]) throw Error('계획이 있는 날짜를 선택하세요.');
      s.selectedDate=a.date;s.screen='plan-date-detail';break;
    case 'start':
      if(s.screen!=='workout-ready' || s.activeWorkout) throw Error('시작할 운동이 없습니다.');
      s.activeWorkout={date:'2026-10-12',completedSets:0,actualReps:[]};s.screen='workout-active';break;
    case 'reps':
      if(s.screen!=='workout-active') throw Error('운동 화면에서 입력하세요.');s.inputReps=count(a.value);break;
    case 'complete-set':
      if(s.screen!=='workout-active' || !s.activeWorkout || s.activeWorkout.completedSets>=3) throw Error('완료할 세트가 없습니다.');
      s.activeWorkout.actualReps.push(s.inputReps);s.activeWorkout.completedSets++;s.screen='workout-rest';s.restSeconds=60;break;
    case 'tick':
      if(s.screen!=='workout-rest') throw Error('휴식 중에만 시간을 이동할 수 있습니다.');
      s.restSeconds=Math.max(0,s.restSeconds-count(a.seconds));if(!s.restSeconds)s.screen='workout-active';break;
    case 'new-journal':
      if(!['records-overview','journal-calendar'].includes(s.screen)) throw Error('기록 또는 일지에서 시작하세요.');
      s.draft={kind:'journal',date:'2026-10-11',title:'',reps:'',exercise:'푸쉬업'};s.screen='journal-entry';break;
    case 'edit-record':
      if(s.screen!=='records-overview' || s.draft) throw Error('기록 화면에서 시작하세요.');
      s.draft={kind:'record',id:'manual-pushup',value:s.records[0].value};break;
    case 'draft':
      if(!s.draft) throw Error('편집을 먼저 시작하세요.');
      if(s.draft.kind==='record') {if(a.field!=='value')throw Error('Unknown field');s.draft.value=count(a.value);}
      else {if(!['date','title','reps'].includes(a.field))throw Error('Unknown field');if(typeof a.value!=='string' || a.value.length>120)throw Error('입력이 너무 깁니다.');s.draft[a.field]=a.value;}
      break;
    case 'cancel':
      if(!s.draft)throw Error('취소할 편집이 없습니다.');s.draft=null;s.screen='records-overview';s.message='변경을 버렸습니다.';break;
    case 'save':
      if(!s.draft)throw Error('저장할 편집이 없습니다.');
      if(s.draft.kind==='record')s.records[0].value=s.draft.value;
      else {
        const d=s.draft;if(!/^2026-10-(0[1-9]|1[0-2])$/.test(d.date) || !d.title.trim())throw Error('기준 날짜 이전의 날짜와 제목을 입력하세요.');
        const values=d.reps.split(',').map(v=>count(v));if(values.length<1 || values.length>10)throw Error('세트는 1~10개입니다.');
        s.workouts.push({id:'web-journal-'+s.workouts.length,date:d.date,title:d.title.trim(),exercise:d.exercise,actualReps:values,completedSets:values.length});
      }
      s.draft=null;s.screen='records-overview';s.message='가상 저장소에 저장했습니다.';break;
    case 'friend-code':
      if(s.screen!=='friends-home' || typeof a.value!=='string' || a.value.length>8)throw Error('친구 코드 8자를 입력하세요.');s.friendCode=a.value.toUpperCase();break;
    case 'request':
      if(s.screen!=='friends-home' || s.friendCode!==s.social.targetCode)throw Error('합성 친구 코드가 아닙니다.');
      if(s.social.requests.length)throw Error('이미 요청 대기 중입니다.');s.social.requests.push({code:s.friendCode,accepted:false});s.message='상대 수락 대기';break;
    case 'sharing':
      if(s.screen!=='friends-home' || typeof a.enabled!=='boolean')throw Error('공개 설정을 확인하세요.');
      s.social.share_records=a.enabled;s.social.published=a.enabled?copy(s.social.backup):[];break;
    case 'refresh':s.message='합성 저장소를 새로 읽었습니다.';break;
    default:throw Error('Unknown action');
  }
  return s;
}
export function act(run,action) {
  if(run.finished)throw Error('종료된 세션입니다.');
  // Continuous typing is one logical input action, not a step per keystroke.
  const prior=run.events.at(-1);
  const mergeInput=['reps','draft','friend-code'].includes(action.type) && prior?.action.type===action.type && prior.action.field===action.field && prior.screen===run.state.screen;
  if(!mergeInput && run.events.length>=run.scenario.maxSteps)throw Error('시나리오 단계 한도에 도달했습니다.');
  const before=copy(run.state),after=reduce(before,action);
  if(mergeInput){prior.action=copy(action);prior.after=copy(after);}
  else run.events.push({step:run.events.length+1,screen:before.screen,action:copy(action),before,after:copy(after)});
  run.state=after;
  return run;
}
export function userPacket(run) {
  // No checks, evaluator preconditions, future screens, or scripts.
  return {persona:copy(run.persona),userGoal:run.scenario.userGoal,currentScreen:{id:run.state.screen,state:visible(run.state)}};
}
export function visible(s) {
  switch(s.screen) {
    case 'workout-ready':return {plan:s.scheduledPlans['2026-10-12']};
    case 'workout-active':return {plan:s.scheduledPlans['2026-10-12'],progress:s.activeWorkout,inputReps:s.inputReps};
    case 'workout-rest':return {progress:s.activeWorkout,restSeconds:s.restSeconds};
    case 'plan-month':return {dates:Object.keys(s.scheduledPlans),selectedDate:s.selectedDate};
    case 'plan-date-detail':return {selectedDate:s.selectedDate,plan:s.scheduledPlans[s.selectedDate]};
    case 'records-overview':return {records:s.records,draft:s.draft,message:s.message};
    case 'journal-calendar':return {workouts:s.workouts};
    case 'journal-entry':return {draft:s.draft};
    case 'friends-home':return {code:s.friendCode,requests:s.social.requests,sharing:s.social.share_records,message:s.message};
    case 'friends-ranking':return {published:s.social.published};
  }
}
function predicates(run) {
  const b=run.before,s=run.state,e=run.events;
  return {
    'first-set-saved':s.activeWorkout?.completedSets===1 && same(s.activeWorkout.actualReps,[7]) && same(s.workouts,b.workouts),
    'plan-preserved':same(s.scheduledPlans,b.scheduledPlans),
    'selected-date-retained':s.screen==='plan-date-detail' && s.selectedDate==='2026-10-14' && e.some(x=>x.after.screen==='records-overview') && e.some(x=>x.after.screen==='plan-date-detail'),
    'navigation-does-not-edit':same(s.scheduledPlans,b.scheduledPlans) && same(s.records,b.records),
    'previous-workout-saved':s.workouts.length===b.workouts.length+1 && s.workouts.at(-1).date==='2026-10-11' && s.workouts.at(-1).title==='어제 푸쉬업' && s.workouts.at(-1).completedSets===3 && same(s.workouts.at(-1).actualReps,[10,8,6]) && s.activeWorkout===null,
    'previous-data-preserved':same(s.workouts.slice(0,b.workouts.length),b.workouts) && same(s.activeWorkout,b.activeWorkout) && same(s.scheduledPlans,b.scheduledPlans) && same(s.records,b.records) && same(s.logs,b.logs),
    'edit-was-attempted':e.some(x=>x.action.type==='edit-record') && e.some(x=>x.after.draft?.kind==='record' && x.after.draft.value===50),
    'cancel-preserves-record':s.draft===null && e.some(x=>x.action.type==='cancel') && same(s.records,b.records),
    'friend-request-pending':s.social.requests.length===1 && s.social.requests[0].code==='ABCD2345' && !s.social.requests[0].accepted,
    'sharing-disabled-and-cleared':!s.social.share_records && !s.social.published.length && same(s.social.backup,b.social.backup) && e.some(x=>x.action.type==='refresh')
  };
}
export function report(run) {
  const answers=predicates(run);
  return {webFormat:1,environment:'web-prototype',synthetic:true,controller:run.controller,personaId:run.persona.id,scenarioId:run.scenario.id,
    modelRequests:0,nativeEvaluationPerformed:false,finished:run.finished,before:copy(run.before),after:copy(run.state),events:copy(run.events),
    checks:run.scenario.checks.map(c=>({id:c.id,kind:c.kind,prototypeResult:run.finished && c.kind==='app-state' && Object.hasOwn(answers,c.id)?(answers[c.id]?'pass':'fail'):'not-evaluated',nativeResult:'not-evaluated',evidence:run.finished && c.kind==='app-state'?['before','after','events']:[]})),
    planner:{basis:'상태 비교에 따른 기계적 검사이며 사람의 관찰은 별도로 필요함',questions:['조작 중 어디에서 망설였는가?','표시와 저장 결과가 일치하는가?','개선안을 같은 시나리오로 재검증할 수 있는가?']}};
}
export function finish(run) {run.finished=true;return report(run);}
export const SCRIPTS = {
  'start-and-record-set':[{type:'start'},{type:'reps',value:7},{type:'complete-set'}],
  'return-to-selected-plan':[{type:'select-date',date:'2026-10-14'},{type:'navigate',screen:'records-overview'},{type:'navigate',screen:'plan-date-detail'}],
  'record-previous-workout':[{type:'new-journal'},{type:'draft',field:'title',value:'어제 푸쉬업'},{type:'draft',field:'date',value:'2026-10-11'},{type:'draft',field:'reps',value:'10,8,6'},{type:'save'}],
  'cancel-record-edit':[{type:'edit-record'},{type:'draft',field:'value',value:50},{type:'cancel'}],
  'friend-request-and-private-records':[{type:'friend-code',value:'ABCD2345'},{type:'request'},{type:'sharing',enabled:false},{type:'refresh'},{type:'navigate',screen:'friends-ranking'}]
};
export function replay(persona,scenario) {
  if(!SCRIPTS[scenario.id])throw Error('시나리오 재생기가 없습니다.');
  const run=createRun(persona,scenario,'scripted');for(const a of SCRIPTS[scenario.id])act(run,a);return finish(run);
}
