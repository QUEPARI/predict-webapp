create or replace function predict_private.mastercaller_url(p_url text) returns text language plpgsql immutable set search_path='' as $$
declare u text:=trim(p_url);
begin
 u:=regexp_replace(u,'^https://(www\.)?mastercaller\.(com|nl)/','https://mastercaller.com/');
 u:=replace(replace(u,'/toernooien/','/tournaments/'),'/uitslagen','/results');
 u:=regexp_replace(u,'/$','');
 if u is null or u!~'^https://mastercaller\.com/tournaments/([a-z0-9-]+/20[0-9]{2}|players-championships/20[0-9]{2}-pc-[1-9][0-9]?-[a-z0-9]+(-[a-z0-9]+)*)/results$' then raise exception 'Gebruik de Mastercaller-uitslagenlink van één toernooi en jaargang';end if;
 return u;
end $$;
revoke all on function predict_private.mastercaller_url(text) from public,anon,authenticated;

