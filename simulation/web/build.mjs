import {readFileSync,writeFileSync,mkdirSync,readdirSync} from 'node:fs';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {validatePanel,validateSession} from '../contracts/validate.mjs';
import {buildDryRunSession} from '../runner/lib/session.mjs';
import {readCodeCommit} from '../runner/lib/git.mjs';
import {assertNoLinks,isInside} from '../runner/lib/paths.mjs';
import {replay} from './core.mjs';
const ROOT=fileURLToPath(new URL('../../',import.meta.url));
const hash=s=>createHash('sha256').update(s).digest('hex');
export function loadPanel(root=ROOT){
 const hashes={};
 function read(rel){const absolute=path.resolve(root,rel);if(!isInside(root,absolute))throw Error('Input escape');assertNoLinks(root,absolute,'web input');const raw=readFileSync(absolute,'utf8');hashes[rel]=hash(raw);return JSON.parse(raw);}
 function list(dir){assertNoLinks(root,path.join(root,dir),'web input');return readdirSync(path.join(root,dir)).filter(n=>n.endsWith('.json')).sort().map(n=>read(dir+'/'+n));}
 const personas=list('simulation/personas'),scenarios=list('simulation/scenarios'),manifest=read('simulation/capture/manifest.json');
 validatePanel({personas,scenarios,manifest});
 const code=readCodeCommit(root);
 code.sourceHashes=Object.fromEntries(['core.mjs','ui.js','preview.html','build.mjs'].map(file=>[file,hash(readFileSync(new URL(file,import.meta.url)))]));
 try {code.dirty=code.dirty || Boolean(execFileSync('git',['-C',root,'status','--porcelain','--','simulation/web'],{encoding:'utf8',windowsHide:true}).trim());}catch {code.dirty=null;}
 return {personas,scenarios,hashes,code};
}
// One self-contained file: works via file:// on Windows, no server or CDN.
export function buildPreview(root=ROOT,runId='web-preview'){
 if(!/^[a-z0-9][a-z0-9-]{2,79}$/.test(runId))throw Error('Invalid run ID');
 const panel=loadPanel(root),dir=path.join(root,'simulation/runs',runId);
 assertNoLinks(root,dir,'web output');mkdirSync(path.dirname(dir),{recursive:true});mkdirSync(dir);
 const local=file=>readFileSync(new URL(file,import.meta.url),'utf8');
 const core=local('core.mjs').replace(/^export /gm,'');
 const json=JSON.stringify(panel).replace(/</g,'\\u003c').replace(/\u2028/g,'\\u2028').replace(/\u2029/g,'\\u2029');
 const html=local('preview.html').replace('/* CORE */',()=>core).replace('/* PANEL */',()=>'const PANEL='+json+';').replace('/* UI */',()=>local('ui.js'));
 writeFileSync(path.join(dir,'index.html'),html,{flag:'wx'});
 return {file:path.join(dir,'index.html'),personas:panel.personas.length,scenarios:panel.scenarios.length,modelRequests:0};
}
export function runWebBatch(root=ROOT,runId='web-batch'){
 if(!/^[a-z0-9][a-z0-9-]{2,79}$/.test(runId))throw Error('Invalid run ID');
 const panel=loadPanel(root),results=[],native=[];
 for(const persona of panel.personas)for(const scenario of panel.scenarios)for(let iteration=1;iteration<=3;iteration++){
  const result=replay(persona,scenario);result.iteration=iteration;results.push(result);
  const baseline=buildDryRunSession({runId,persona,scenario,iteration,appCommit:panel.code.commit,promptVersion:'v1'});
  validateSession(baseline,scenario);native.push(baseline);
 }
 const failed=results.flatMap(s=>s.checks.filter(c=>c.prototypeResult==='fail'));
 const dir=path.join(root,'simulation/runs',runId);assertNoLinks(root,dir,'web output');mkdirSync(path.dirname(dir),{recursive:true});mkdirSync(dir);
 const report={webFormat:1,environment:'web-prototype',controller:'scripted',synthetic:true,code:panel.code,inputs:panel.hashes,modelRequests:0,nativeEvaluationPerformed:false,
  sessions:results.length,failedChecks:failed.length,note:'동일 스크립트 반복은 안정성 검사이며 사용자 행동 다양성·실제 사용성 지표가 아니다.',results};
 writeFileSync(path.join(dir,'web-results.json'),JSON.stringify(report,null,2),{flag:'wx'});
 writeFileSync(path.join(dir,'native-not-run.json'),JSON.stringify(native,null,2),{flag:'wx'});
 writeFileSync(path.join(dir,'summary.md'),'# 웹 프로토타입 재생 검사\n\n합성 스크립트 '+results.length+'세션, 웹 상태 검사 실패 '+failed.length+'개. 모델 요청 0. 실제 iOS 검사는 모두 not-evaluated.\n\n반복은 행동 다양성이나 사용성 성공률을 의미하지 않는다. 근거는 web-results.json의 before/after/events이며 사람의 이해도·친구 관찰자 검사는 미평가다.\n',{flag:'wx'});
 return {dir,sessions:results.length,failedChecks:failed.length,modelRequests:0};
}
if(typeof process!=='undefined' && process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{
  const [mode='preview',id]=process.argv.slice(2);if(!['preview','batch'].includes(mode))throw Error('Usage: node simulation/web/build.mjs preview|batch [new-run-id]');
  console.log(JSON.stringify(mode==='preview'?buildPreview(ROOT,id):runWebBatch(ROOT,id),null,2));
 }catch(e){console.error(e.message);process.exitCode=1;}
}
