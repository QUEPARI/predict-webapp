const assert=require('node:assert/strict');
(async()=>{
 const {sourceUrl,parseResults,parseBracket,fetchTournament}=await import('../supabase/functions/sync-mastercaller/parser.js');
 const pc='https://mastercaller.com/tournaments/players-championships/2026-pc-32-den-bosch/results';
 assert.equal(sourceUrl('https://mastercaller.nl/toernooien/players-championships/2026-pc-32-den-bosch/uitslagen'),pc);
 assert.equal(sourceUrl(pc+'/'),pc);
 for(const bad of [pc.replace('pc-32','pc-0'),pc.replace('players-championships','other-series'),pc.replace('2026-pc','pc'),pc+'/extra',pc+'?x=1',pc.replace('mastercaller.com','mastercaller.com.evil.com'),pc.replace('https:','http:')])assert.throws(()=>sourceUrl(bad));
 const html='<html><body><h1>Players Championship 32</h1>Professional Darts Corporation<div><div><h3>Final</h3></div><div><div class="relative">Wed 28 Oct - 18:00</div><div class="grid grid-cols-1"><div><a href="/players/a">A</a><div class="bg-green-500">8</div></div><div><div class="bg-red-500">4</div><a href="/players/b">B</a></div></div></div></div></body></html>';
 assert.equal(parseResults(html,pc).records[0].date,'2026-10-28');
 assert.equal(parseResults(html,'https://mastercaller.com/tournaments/european-championship/2026/results').records[0].date,'2026-10-28');
 const blank='<div class="bracket-container"><div class="round-holder" data-col="1"><h2 class="round-title">Final</h2><span class="round-format">Best of 15 Legs</span></div><div class="match-holder" data-col="1" data-row="1"><div class="player1"><div class="name"></div></div><div class="player2"><div class="name"></div></div></div></div>';
 assert.throws(()=>parseBracket(blank,{fixtures:[],records:[]}),/loting.*nog niet ingevuld/);
 console.log('PASS Players Championship URL validation, date year and ordinary URL regression');
 if(process.argv.includes('--live')){try{const data=await fetchTournament(pc);assert.equal(data.roster.length,128);assert.equal(data.bracket.length,127);assert.equal(data.rounds.length,7);console.log(JSON.stringify({importable:true,players:data.roster.length,matches:data.bracket.length,start:data.start_date}));}catch(error){if(!/loting.*nog niet ingevuld/.test(error.message))throw error;console.log('LIVE: URL accepted; Mastercaller bracket has no drawn participants yet: '+error.message);}}
})().catch(e=>{console.error(e);process.exitCode=1;});
