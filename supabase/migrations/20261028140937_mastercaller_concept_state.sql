-- Explicit concept -> announcement -> publication lifecycle for source-owned games.
alter table predict_private.mastercaller_sources
 add column setup_pending boolean not null default false,
 add column setup_state text,
 add column setup_checked_at timestamptz,
 add column setup_next_check_at timestamptz,
 add column setup_ready_at timestamptz,
 add column setup_error text,
 add column setup_snapshot jsonb,
 add column setup_winner integer not null default 1,
 add column setup_exact integer not null default 3,
 add column setup_actor uuid,
 add column source_layout text not null default 'legacy',
 add column group_first_to integer;
create index mastercaller_setup_due on predict_private.mastercaller_sources(setup_next_check_at) where setup_pending;
create table predict_private.mastercaller_match_map(
 match_id uuid primary key references public.matches(id) on delete cascade,
 tournament_id uuid not null references public.tournaments(id) on delete cascade,
 source_key text not null,group_name text,position integer not null,
 unique(tournament_id,source_key)
);
alter table predict_private.mastercaller_match_map enable row level security;
revoke all on predict_private.mastercaller_match_map from public,anon,authenticated,service_role;
