-- NEON CARBALL — schema additif pour les modes finaux
-- Brouillon de migration : à relire puis exécuter dans Supabase SQL Editor.
-- Ce fichier n'est PAS exécuté automatiquement et ne modifie pas la base distante.
-- Les tables existantes profiles, player_wallets et player_upgrades restent intactes.

create table if not exists public.nc_teams (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 48),
  short_name text check (short_name is null or char_length(short_name) <= 8),
  team_type text not null check (team_type in ('national', 'club', 'custom')),
  country_code text,
  logo_path text,
  primary_color text not null default '#00C8FF',
  secondary_color text not null default '#FF8A00',
  is_public boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint nc_custom_team_owner check (team_type <> 'custom' or owner_id is not null)
);

create table if not exists public.nc_players (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 64),
  player_type text not null check (player_type in ('real', 'fictional')),
  position text not null default 'FWD' check (position in ('GK','DEF','MID','FWD')),
  overall_rating smallint not null default 60 check (overall_rating between 1 and 99),
  nationality text,
  created_at timestamptz not null default now()
);

create table if not exists public.nc_team_rosters (
  team_id uuid not null references public.nc_teams(id) on delete cascade,
  player_id uuid not null references public.nc_players(id) on delete cascade,
  shirt_number smallint check (shirt_number is null or shirt_number between 1 and 99),
  is_captain boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (team_id, player_id)
);

create table if not exists public.nc_tournaments (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 64),
  format text not null check (format in ('knockout', 'groups_knockout', 'league')),
  team_count smallint not null default 4 check (team_count between 2 and 32),
  status text not null default 'draft' check (status in ('draft', 'in_progress', 'completed')),
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.nc_tournament_teams (
  tournament_id uuid not null references public.nc_tournaments(id) on delete cascade,
  team_id uuid not null references public.nc_teams(id) on delete restrict,
  seed smallint,
  group_label text,
  points integer not null default 0,
  played integer not null default 0,
  wins integer not null default 0,
  draws integer not null default 0,
  losses integer not null default 0,
  goals_for integer not null default 0,
  goals_against integer not null default 0,
  primary key (tournament_id, team_id)
);

create table if not exists public.nc_tournament_matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.nc_tournaments(id) on delete cascade,
  round_number smallint not null default 1,
  match_number smallint not null default 1,
  stage text not null default 'league' check (stage in ('group', 'knockout', 'league', 'final')),
  group_label text,
  home_team_id uuid references public.nc_teams(id) on delete restrict,
  away_team_id uuid references public.nc_teams(id) on delete restrict,
  home_score smallint check (home_score is null or home_score >= 0),
  away_score smallint check (away_score is null or away_score >= 0),
  status text not null default 'scheduled' check (status in ('scheduled', 'in_progress', 'completed', 'cancelled')),
  played_at timestamptz,
  created_at timestamptz not null default now(),
  unique (tournament_id, round_number, match_number),
  check (home_team_id is null or away_team_id is null or home_team_id <> away_team_id)
);

create index if not exists nc_teams_owner_idx on public.nc_teams(owner_id);
create index if not exists nc_players_owner_idx on public.nc_players(owner_id);
create index if not exists nc_tournaments_owner_idx on public.nc_tournaments(owner_id);
create index if not exists nc_matches_tournament_idx on public.nc_tournament_matches(tournament_id, round_number, match_number);

alter table public.nc_teams enable row level security;
alter table public.nc_players enable row level security;
alter table public.nc_team_rosters enable row level security;
alter table public.nc_tournaments enable row level security;
alter table public.nc_tournament_teams enable row level security;
alter table public.nc_tournament_matches enable row level security;

-- Les catalogues publics peuvent être lus ; les créations privées restent réservées à leur propriétaire.
create policy "nc teams read public or own" on public.nc_teams
  for select to authenticated using (is_public or owner_id = auth.uid());
create policy "nc teams insert own" on public.nc_teams
  for insert to authenticated with check (owner_id = auth.uid());
create policy "nc teams update own" on public.nc_teams
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "nc teams delete own" on public.nc_teams
  for delete to authenticated using (owner_id = auth.uid());

create policy "nc players read public or own" on public.nc_players
  for select to authenticated using (owner_id is null or owner_id = auth.uid());
create policy "nc players insert own or shared fictional" on public.nc_players
  for insert to authenticated with check (owner_id = auth.uid());
create policy "nc players update own" on public.nc_players
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "nc players delete own" on public.nc_players
  for delete to authenticated using (owner_id = auth.uid());

create policy "nc rosters read accessible teams" on public.nc_team_rosters
  for select to authenticated using (
    exists (select 1 from public.nc_teams t where t.id = team_id and (t.is_public or t.owner_id = auth.uid()))
  );
create policy "nc rosters manage own teams" on public.nc_team_rosters
  for all to authenticated using (
    exists (select 1 from public.nc_teams t where t.id = team_id and t.owner_id = auth.uid())
  ) with check (
    exists (select 1 from public.nc_teams t where t.id = team_id and t.owner_id = auth.uid())
  );

create policy "nc tournaments read own" on public.nc_tournaments
  for select to authenticated using (owner_id = auth.uid());
create policy "nc tournaments insert own" on public.nc_tournaments
  for insert to authenticated with check (owner_id = auth.uid());
create policy "nc tournaments update own" on public.nc_tournaments
  for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "nc tournaments delete own" on public.nc_tournaments
  for delete to authenticated using (owner_id = auth.uid());

create policy "nc tournament teams read own tournament" on public.nc_tournament_teams
  for select to authenticated using (
    exists (select 1 from public.nc_tournaments t where t.id = tournament_id and t.owner_id = auth.uid())
  );
create policy "nc tournament teams manage own tournament" on public.nc_tournament_teams
  for all to authenticated using (
    exists (select 1 from public.nc_tournaments t where t.id = tournament_id and t.owner_id = auth.uid())
  ) with check (
    exists (select 1 from public.nc_tournaments t where t.id = tournament_id and t.owner_id = auth.uid())
  );

create policy "nc tournament matches read own tournament" on public.nc_tournament_matches
  for select to authenticated using (
    exists (select 1 from public.nc_tournaments t where t.id = tournament_id and t.owner_id = auth.uid())
  );
create policy "nc tournament matches manage own tournament" on public.nc_tournament_matches
  for all to authenticated using (
    exists (select 1 from public.nc_tournaments t where t.id = tournament_id and t.owner_id = auth.uid())
  ) with check (
    exists (select 1 from public.nc_tournaments t where t.id = tournament_id and t.owner_id = auth.uid())
  );

-- À compléter avant mise en production :
-- 1) ajouter les données du catalogue officiel uniquement si leur licence le permet ;
-- 2) définir la politique d'accès du stockage des logos ;
-- 3) valider les policies sur un projet de test avant toute exécution en production.
