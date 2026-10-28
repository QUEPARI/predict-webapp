const assert=require('node:assert/strict');
(async()=>{
 const {parseSourceDraft,fetchSourceDraft}=await import('../supabase/functions/sync-mastercaller/draft-parser.js');
 const url='https://mastercaller.com/tournaments/grand-slam-of-darts/2026/results';
 const results='<html><body><h1>Grand Slam of Darts 2026</h1>Professional Darts Corporation Start Date: 14 Nov 2026 End Date: 22 Nov 2026</body></html>';
 const bracket='<div class="bracket-container"><div class="round-holder" data-col="1"><h2 class="round-title">Final</h2><span class="round-format">Best of 15 Legs</span></div><div class="match-holder" data-col="1" data-row="1"><div class="player1"><div class="name"></div></div><div class="player2"><div class="name"></div></div></div></div>';
 let s=parseSourceDraft(results,bracket,url);assert.equal(s.ready,false);assert.equal(s.format,'groups');assert.equal(s.rounds[0].first_to,null);assert.equal(s.rounds[1].name,'Final');assert.equal(s.roster.length,0);
 const players=['A','B','C','D'],pairs=players.flatMap((a,i)=>players.slice(i+1).map(b=>[a,b]));
 const group=pairs=>'<html><body><section><div><h3>Group AA</h3></div><table><tbody>'+players.map(n=>'<tr><td><a href="/players/'+n+'">'+n+'</a></td></tr>').join('')+'</tbody></table>'+pairs.map(([a,b])=>'<div><div class="relative">Today - 15:00</div><div class="grid grid-cols-1"><div><a href="/players/'+a+'">'+a+'</a></div><div><a href="/players/'+b+'">'+b+'</a></div></div></div>').join('')+'</section></body></html>';
 s=parseSourceDraft(results,bracket,url,group(pairs),new Date('2026-11-14T12:00:00Z'));assert.equal(s.ready,true);assert.equal(s.matches.length,7);assert.equal(s.roster.length,4);assert.equal(s.rounds[0].first_to,null);assert.equal(s.matches[0].start,'2026-11-14T14:00:00.000Z');
 assert.equal(parseSourceDraft(results,bracket,url,group(pairs.slice(1))).ready,false);assert.throws(()=>parseSourceDraft(results,bracket,url,group([...pairs,pairs[0]])),/Dubbele groepswedstrijd/);
 const fetcher=async u=>new Response(u.endsWith('/results')?results:u.endsWith('/bracket')?bracket:'',{status:u.endsWith('/groupstage')?404:200,headers:{'content-type':'text/html'}});assert.equal((await fetchSourceDraft(url,fetcher)).ready,false);
 await assert.rejects(()=>fetchSourceDraft(url,async()=>new Response('',{status:418})),/HTTP 418/);
 assert.throws(()=>parseSourceDraft('<html><body>blocked</body></html>',bracket,url),/herkenbare/);
 s=parseSourceDraft(results,bracket,url.replace('grand-slam-of-darts','european-championship'));assert.equal(s.format,'knockout');assert.equal(s.ready,false);
 console.log('PASS pending draws, group/KO separation, full group pairings, missing format, relative dates, duplicates, HTTP errors.');
})().catch(e=>{console.error(e);process.exitCode=1;});
