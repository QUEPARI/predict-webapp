-- RLS already limits reads to the caller. Mutations belong to vetted RPCs only.
revoke all on public.tournament_entries from public,anon,authenticated;
grant select on public.tournament_entries to authenticated;
alter table public.tournament_entries enable row level security;
