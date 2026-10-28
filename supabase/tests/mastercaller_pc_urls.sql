begin; do $test$ declare bad text; begin
if predict_private.mastercaller_url('https://mastercaller.nl/toernooien/players-championships/2026-pc-32-den-bosch/uitslagen')<>'https://mastercaller.com/tournaments/players-championships/2026-pc-32-den-bosch/results' then raise exception 'FAIL PC URL';end if;
if predict_private.mastercaller_url('https://mastercaller.nl/toernooien/european-championship/2026/uitslagen')<>'https://mastercaller.com/tournaments/european-championship/2026/results' then raise exception 'FAIL ordinary URL';end if;
foreach bad in array array['https://mastercaller.com.evil.com/tournaments/players-championships/2026-pc-32-den-bosch/results','https://mastercaller.com/tournaments/other-series/2026-pc-32-den-bosch/results','https://mastercaller.com/tournaments/players-championships/2026-pc-0-den-bosch/results','https://mastercaller.com/tournaments/players-championships/2026-pc-32-den-bosch/results?x=1'] loop
begin perform predict_private.mastercaller_url(bad);raise exception 'FAIL invalid URL accepted';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end loop;end $test$;rollback;
