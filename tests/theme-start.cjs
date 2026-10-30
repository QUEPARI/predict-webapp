// Execute the shipped head bootstrap and account/theme handlers without any hosted calls.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const root=path.resolve(__dirname,'..'),html=fs.readFileSync(path.join(root,'index.html'),'utf8'),app=fs.readFileSync(path.join(root,'app.js'),'utf8'),css=fs.readFileSync(path.join(root,'styles.css'),'utf8');
const bootstrap=html.match(/<script>([\s\S]*?)<\/script>/)[1];
assert(html.indexOf('<script>')<html.indexOf('rel="stylesheet"'),'Theme runs before render-blocking stylesheet');
assert(css.includes(':root.dark,body.dark{color-scheme:dark;'),'Startup and loaded app share the same palette');
const handlers=app.slice(app.indexOf("const STORE='predict-ui-v2'"),app.indexOf('const tournaments='));
const account=app.slice(app.indexOf('let currentProfile = null;'),app.indexOf('function persistProfile('));
const classes=()=>{const values=new Set();return {toggle(k,on){if(on)values.add(k);else values.delete(k);},contains:k=>values.has(k)};};
function environment(raw,system,blocked=false){
 const store=new Map(raw===undefined?[]:[['predict-ui-v2',raw]]),media={matches:system,addEventListener(_,fn){this.changed=fn;}},meta={content:'#101010'},document={documentElement:{classList:classes(),style:{}},body:{classList:classes()},querySelector:selector=>selector.includes('theme-color')?meta:null};
 const context=vm.createContext({document,localStorage:{getItem(k){if(blocked)throw Error('Storage denied');return store.get(k)??null;},setItem(k,v){if(blocked)throw Error('Storage denied');store.set(k,v);},removeItem(k){if(blocked)throw Error('Storage denied');store.delete(k);}},window:{matchMedia:()=>media,dispatchEvent(){}},CustomEvent:class{constructor(type,args){this.type=type;this.detail=args.detail;}},applyBrandAccent(){}});
 return {context,document,media,meta,store};
}
let count=0;
for(const raw of [undefined,'null','{bad',JSON.stringify({theme:'invalid'}),...['light','dark','system'].map(theme=>JSON.stringify({theme}))])for(const system of [false,true])for(const blocked of [false,true]){
 const e=environment(raw,system,blocked);let saved;try{saved=JSON.parse(raw||'{}')?.theme;}catch{}
 const theme=!blocked&&['light','dark','system'].includes(saved)?saved:'system',dark=theme==='dark'||theme==='system'&&system;
 vm.runInContext(bootstrap,e.context);assert.equal(e.document.documentElement.classList.contains('dark'),dark);assert.equal(e.document.documentElement.style.colorScheme,dark?'dark':'light');assert.equal(e.meta.content,dark?'#101010':'#f3f5f9');
 vm.runInContext(handlers+account,e.context);
 for(const accountTheme of ['light','dark','system']){
  vm.runInContext(`applyAccountProfile({username:'qa',theme:'${accountTheme}'})`,e.context);const expected=accountTheme==='dark'||accountTheme==='system'&&e.media.matches;
  assert.equal(e.document.documentElement.classList.contains('dark'),expected);assert.equal(e.document.body.classList.contains('dark'),expected);assert.equal(e.meta.content,expected?'#101010':'#f3f5f9');
  if(!blocked){assert.equal(JSON.parse(e.store.get('predict-ui-v2')).theme,accountTheme);const next=environment(e.store.get('predict-ui-v2'),e.media.matches);vm.runInContext(bootstrap,next.context);assert.equal(next.document.documentElement.classList.contains('dark'),expected,'Next launch uses updated account choice');}
 }
 e.media.matches=!e.media.matches;e.media.changed();assert.equal(e.document.documentElement.classList.contains('dark'),e.media.matches,'System changes propagate');assert.equal(e.document.body.classList.contains('dark'),e.media.matches);count++;
}
console.log(`PASS ${count} startup cases: persisted light/dark/system, missing/corrupt/null/blocked storage, account reconciliation, next launch and system changes.`);
