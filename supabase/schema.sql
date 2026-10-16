-- Predict database foundation: apply in a new Supabase project only after review.
-- Authentication via auth.users. No public insert permissions for tournament configuration.
create extension if not exists pgcrypto;
create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check(length(display_name) between 2 and 60),
 theme text not null default 'system' check(theme in ('system','light','dark')),
 created_at timestamptz not null default now()
);
create table public.system_admins (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 granted_at timestamptz not null default now()
);
create table public.sports (id text primary key, name text not null);
insert into public.sports(id,name) values ('darts','Darts'),('football','Voetbal');
create table public.tournaments (
 id uuid primary key default gen_random_uuid(), sport_id text not null references public.sports(id),
 name text not null, season text not null, status text not null default 'draft'
 check(status in ('draft','published','active','completed','archived')),
 starts_at timestamptz, scoring_locked_at timestamptz,
 created_at timestamptz not null default now()
);
create table public.tournament_entries (
 tournament_id uuid not null references public.tournaments(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 joined_at timestamptz not null default now(), primary key(tournament_id,user_id)
);
create table public.pools (
 id uuid primary key default gen_random_uuid(),
 tournament_id uuid not null references public.tournaments(id) on delete cascade,
 name text not null check(length(name) between 2 and 80),
 owner_id uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 unique(id,tournament_id)
);
create table public.pool_members (
 pool_id uuid not null references public.pools(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 joined_at timestamptz not null default now(), primary key(pool_id,user_id)
);
create table public.invitations (
 id uuid primary key default gen_random_uuid(),
 -- Store only the digest of a strong one-time bearer token.
 token_hash text not null unique, pool_id uuid references public.pools(id) on delete cascade,
 created_by uuid not null references public.profiles(id),
 expires_at timestamptz not null default(now() + interval '7 days'),
 used_by uuid references public.profiles(id), used_at timestamptz,
 revoked_at timestamptz, created_at timestamptz not null default now()
);
create table public.participants (
 id uuid primary key default gen_random_uuid(),
 sport_id text not null references public.sports(id), name text not null,
 kind text not null check(kind in ('player','team'))
);
create table public.stages (
 id uuid primary key default gen_random_uuid(), tournament_id uuid not null references public.tournaments(id) on delete cascade,
 name text not null, sort_order integer not null, format text not null,
 unique(tournament_id,name)
);
create table public.matches (
 id uuid primary key default gen_random_uuid(), tournament_id uuid not null references public.tournaments(id) on delete cascade,
 stage_id uuid not null references public.stages(id),
 home_id uuid references public.participants(id), away_id uuid references public.participants(id),
 scheduled_at timestamptz, deadline_at timestamptz, actual_started_at timestamptz,
 status text not null default 'scheduled' check(status in('scheduled','live','finished','postponed','cancelled','walkover')),
 format text not null check(format in ('sets','legs','goals')),
 first_to integer check(first_to is null or first_to > 0),
 participant_version integer not null default 1,
 next_match_id uuid references public.matches(id), next_slot smallint check(next_slot in(1,2)),
 unique(id,tournament_id), check(home_id is distinct from away_id)
);
create table public.match_results (
 match_id uuid primary key references public.matches(id) on delete cascade,
 home_score integer not null check(home_score>=0), away_score integer not null check(away_score>=0),
 winning_participant_id uuid references public.participants(id),
 played boolean not null default true,
 official boolean not null default false,
 source text not null check(source in ('api','admin')),
 verified_at timestamptz, updated_at timestamptz not null default now()
);
create table public.match_predictions (
 id uuid primary key default gen_random_uuid(), match_id uuid not null references public.matches(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 home_score integer not null check(home_score between 0 and 999),
 away_score integer not null check(away_score between 0 and 999),
 participant_version integer not null,
 invalidated_at timestamptz,
 updated_at timestamptz not null default now(),
 unique(match_id,user_id)
);
create table public.prediction_definitions (
 id uuid primary key default gen_random_uuid(), tournament_id uuid not null references public.tournaments(id) on delete cascade,
 title text not null, answer_type text not null check(answer_type in ('team','player','number','choice')),
 max_answers integer not null default 1 check(max_answers > 0),
 scoring_mode text not null default 'per_correct' check(scoring_mode in ('per_correct','all_or_nothing','custom')),
 points_per_correct integer not null default 0 check(points_per_correct >= 0),
 config jsonb not null default '{}'::jsonb, deadline_at timestamptz not null,
 unique(id,tournament_id)
);
create table public.prediction_options (
 id uuid primary key default gen_random_uuid(), definition_id uuid not null references public.prediction_definitions(id) on delete cascade,
 label text not null, participant_id uuid references public.participants(id),
 unique(definition_id,label),unique(id,definition_id)
);
create table public.extra_predictions (
 id uuid primary key default gen_random_uuid(), definition_id uuid not null references public.prediction_definitions(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(definition_id,user_id)
);
create table public.extra_answers (
 prediction_id uuid not null references public.extra_predictions(id) on delete cascade,
 option_id uuid not null references public.prediction_options(id),
 primary key(prediction_id,option_id)
);
create table public.extra_outcomes (
 definition_id uuid not null references public.prediction_definitions(id) on delete cascade,
 option_id uuid not null references public.prediction_options(id),
 verified_by uuid references public.profiles(id), verified_at timestamptz,
 primary key(definition_id,option_id)
);
create table public.scoring_rules (
 id uuid primary key default gen_random_uuid(), tournament_id uuid not null references public.tournaments(id) on delete cascade,
 stage_id uuid references public.stages(id), mode text not null check(mode in ('replacement','additive')),
 winner_points integer not null default 0, exact_points integer not null default 0,
 version integer not null default 1, locked_at timestamptz,
 unique(tournament_id,stage_id,version)
);
create table public.scoring_results (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
 tournament_id uuid not null references public.tournaments(id) on delete cascade,
 match_prediction_id uuid references public.match_predictions(id) on delete cascade,
 extra_prediction_id uuid references public.extra_predictions(id) on delete cascade,
 points integer not null, rule_version integer not null, computed_at timestamptz not null default now(),
 check ((match_prediction_id is not null) <> (extra_prediction_id is not null))
);
create unique index scoring_one_match on public.scoring_results(match_prediction_id) where match_prediction_id is not null;
create unique index scoring_one_extra on public.scoring_results(extra_prediction_id) where extra_prediction_id is not null;
create table public.external_references (
 id uuid primary key default gen_random_uuid(), source text not null,
 entity_type text not null, external_id text not null, internal_id uuid not null,
 unique(source,entity_type,external_id)
);
create table public.sync_logs (
 id bigserial primary key, source text not null, started_at timestamptz not null default now(),
 ended_at timestamptz, status text not null, details jsonb not null default '{}'::jsonb
);
create table public.result_conflicts (
 id uuid primary key default gen_random_uuid(), match_id uuid not null references public.matches(id) on delete cascade,
 incoming_result jsonb not null, current_result jsonb not null, status text not null default 'open',
 created_at timestamptz not null default now(), resolved_at timestamptz
);
create table public.audit_logs (
 id bigserial primary key, actor_id uuid references public.profiles(id) on delete set null,
 action text not null, entity_type text not null, entity_id uuid,
 old_data jsonb, new_data jsonb, reason text,
 created_at timestamptz not null default now()
);
-- RLS: default-deny. Only narrowly scoped profile and own prediction reads enabled here.
-- Write pathways (invite acceptance, predictions, admin operations) MUST be implemented
-- through vetted server-side transactional functions with deadline and role checks.
do $$ declare tbl text; begin
 foreach tbl in array array['profiles','system_admins','sports','tournaments','tournament_entries','pools','pool_members','invitations','participants','stages','matches','match_results','match_predictions','prediction_definitions','prediction_options','extra_predictions','extra_answers','extra_outcomes','scoring_rules','scoring_results','external_references','sync_logs','result_conflicts','audit_logs'] loop
  execute format('alter table public.%I enable row level security',tbl);
 end loop;
end $$;
create policy profile_self_read on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy own_match_predictions_read on public.match_predictions for select to authenticated using (user_id=(select auth.uid()));
create policy own_extra_predictions_read on public.extra_predictions for select to authenticated using (user_id=(select auth.uid()));
-- NOTE: No insert/update policies are intentionally provided; this schema is a secure foundation,
-- not a deploy-ready application. Public catalog SELECT policies and RPCs remain to be implemented.
