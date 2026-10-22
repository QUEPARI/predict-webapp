// NODE_PATH=/tmp/predict-dom-test/node_modules node tests/pull-refresh-dom.cjs
// Test dependency: jsdom@27.0.1 (no runtime app dependency).
const {JSDOM}=require('jsdom'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const pause=()=>new Promise(resolve=>setTimeout(resolve,10));
(async()=>{
 const dom=new JSDOM('<main><p id="content">Toernooi</p><input id="input"><div id="nested"><p>Klassement</p></div></main>',{runScripts:'outside-only'}),w=dom.window,d=w.document;
 let mobile=true,mediaChange,scroll=0,calls=0,allowed=true,resolveRefresh;
 const media={get matches(){return mobile},addEventListener(n,fn){mediaChange=fn},removeEventListener(){}};
 w.matchMedia=()=>media;Object.defineProperty(w,'scrollY',{get:()=>scroll});
 w.setTimeout=(fn)=>setTimeout(fn,0);
 w.eval(fs.readFileSync(path.join(__dirname,'../pull-refresh.js'),'utf8').replace('export function','function'));
 const stop=w.installPullRefresh({doc:d,win:w,canRefresh:()=>allowed,onRefresh:()=>{calls++;return new Promise(resolve=>resolveRefresh=resolve)}});
 const content=d.querySelector('#content');
 function touch(type,x,y,target=content,count=1,cancelable=true){const e=new w.Event(type,{bubbles:true,cancelable});Object.defineProperty(e,'touches',{value:type==='touchend'||type==='touchcancel'?[]:Array.from({length:count},()=>({clientX:x,clientY:y}))});target.dispatchEvent(e);return e;}
 function pull({x=10,dy=100,target=content,count=1,cancelable=true}={}){touch('touchstart',10,0,target,count);const move=touch('touchmove',x,dy,target,count,cancelable);touch('touchend',x,dy,target);return move;}
 assert(d.documentElement.classList.contains('pull-refresh-enabled'));
 pull({dy:40});await pause();assert.equal(calls,0,'Short pulls do not refresh');
 const moving=touch('touchstart',10,0);const move=touch('touchmove',10,100);assert(move.defaultPrevented);assert(d.querySelector('.pull-refresh').textContent.includes('Laat los'));touch('touchend',10,100);await pause();assert.equal(calls,1);
 pull();await pause();assert.equal(calls,1,'Only one refresh in flight');resolveRefresh();await pause();assert(d.querySelector('.pull-refresh').hidden);
 scroll=300;pull();await pause();assert.equal(calls,1,'No refresh when scrolled down');scroll=0;
 pull({x:200,dy:40});pull({target:d.querySelector('#input')});pull({count:2});pull({cancelable:false});await pause();assert.equal(calls,1,'Horizontal gestures, fields, multitouch and uncancelable scrolls ignored');
 const nested=d.querySelector('#nested');nested.style.overflowY='auto';Object.defineProperties(nested,{scrollHeight:{value:400},clientHeight:{value:100}});pull({target:nested.querySelector('p')});await pause();assert.equal(calls,1,'Nested scroll containers ignored');
 touch('touchstart',10,0);touch('touchmove',10,120);touch('touchcancel',10,120);touch('touchend',10,120);await pause();assert.equal(calls,1);
 const dialog=d.createElement('dialog');dialog.setAttribute('open','');d.body.append(dialog);pull();await pause();assert.equal(calls,1);dialog.remove();
 allowed=false;pull();await pause();assert.equal(calls,1,'Unsaved edits can cancel refresh');allowed=true;
 mobile=false;mediaChange();pull();await pause();assert.equal(calls,1,'Desktop unchanged');assert(!d.documentElement.classList.contains('pull-refresh-enabled'));
 mobile=true;mediaChange();pull();await pause();assert.equal(calls,2);resolveRefresh();await pause();stop();assert.equal(d.querySelector('.pull-refresh'),null);
 // Exercise the actual app callback: preserve current tournament tab and round.
 d.body.innerHTML='<button data-detail-tab="results" aria-pressed="true"></button><select id="online-round"><option selected value="round-2">Ronde 2</option></select>';
 w.installPullRefresh=options=>w.refreshOptions=options;let renders=0;w.render=()=>renders++;w.confirm=()=>false;
 const source=fs.readFileSync(path.join(__dirname,'../app.js'),'utf8');w.eval(source.slice(source.indexOf('// Refresh database-backed screens')));
 assert(w.refreshOptions.canRefresh());w.refreshOptions.onRefresh();assert.equal(w.initialTournamentTab,'results');assert.equal(w.initialTournamentRound,'round-2');assert.equal(renders,1);
 const form=d.createElement('form');form.dataset.koDirty='true';d.body.append(form);assert.equal(w.refreshOptions.canRefresh(),false);w.confirm=()=>true;assert.equal(w.refreshOptions.canRefresh(),true);
 dom.window.close();console.log('PASS: pull threshold, top-only, no duplicate refresh, horizontal/nested/form/modal/multitouch/cancel guards, desktop unchanged, discard confirmation, current tab and round preserved.');
})().catch(error=>{console.error(error);process.exitCode=1});
