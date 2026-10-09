// Loopback-only single-document preview, never a filesystem/static directory server.
import http from 'node:http';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import {assertNoLinks} from '../runner/lib/paths.mjs';
export async function servePreview(runId='web-preview-001',port=0){
 if(!/^[a-z0-9][a-z0-9-]{2,79}$/.test(runId) || !Number.isInteger(port) || port<0 || port>65535)throw Error('Invalid preview ID or port');
 const root=fileURLToPath(new URL('../../',import.meta.url)),file=path.join(root,'simulation/runs',runId,'index.html');
 assertNoLinks(root,file,'preview input');
 const html=readFileSync(file);if(html.length>2*1024*1024)throw Error('Preview is too large');
 const server=http.createServer((req,res)=>{
  if(req.headers.host!=='127.0.0.1:'+server.address().port){res.writeHead(403);res.end();return;}
  if(req.method!=='GET' || req.url!=='/'){res.writeHead(404);res.end();return;}
  res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Connection':'close'});res.end(html);
 });
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',resolve);});
 return {server,url:'http://127.0.0.1:'+server.address().port+'/'};
}
if(typeof process!=='undefined' && process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 try{const [, ,id,port]=process.argv;const preview=await servePreview(id,port===undefined?0:Number(port));console.log(preview.url+' — Ctrl+C to stop');}
 catch(e){console.error(e.message);process.exitCode=1;}
}
