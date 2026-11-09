-- Paper Glide accounts and leaderboards.
-- Run this file once in the Supabase SQL Editor (free project). It embeds no keys.
--
-- The dashboard role bypasses RLS, so rows can be deleted in the Table Editor
-- with no app change. Do not put the service-role key in the app.
--
-- Rule numbers match Sources/PaperGlideCore/RunRules.swift and UsernameRules.swift:
--   username: 3–16, ^[a-z][a-z0-9_]{2,15}$, lowercased, unique
--   blocklist (leet-folded, underscores removed, substring):
--     admin, paperglide, support, moderator, apple, official
--     0→o 1→i/l 2→z 3→e 4→a 5→s 6/9→g 7→t 8→b
--   reject when score > duration_seconds/1.5 + 3, duration > 3600, or score > 2500
--   played_at more than 24 hours ahead or older than 30 days is stale (not stored)
--   about 1 accepted-or-rejected attempt per 10 seconds, 500 stored runs per Toronto day
--   daily board: played_at's Toronto civil date is still today
--   weekly board: played_at's Toronto Monday-start week is still this week
--   a run whose day or week has closed is all-time only (late-run rule)
--   all-time has no period window
--
-- Clocks use America/Toronto via timezone(), which follows DST.
-- Resets are 00:00 Toronto daily and Monday 00:00 Toronto weekly.

create table if not exists public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    username text,
    created_at timestamptz not null default now(),
    last_submit_at timestamptz,
    submit_day date,
    submit_count integer not null default 0
);

create unique index if not exists profiles_username_key
    on public.profiles (username);

create table if not exists public.runs (
    id uuid primary key,
    user_id uuid not null references public.profiles (id) on delete cascade,
    score integer not null,
    duration_seconds double precision not null,
    played_at timestamptz not null,
    submitted_at timestamptz not null default now()
);

create index if not exists runs_user_played_idx
    on public.runs (user_id, played_at);

create index if not exists runs_played_idx
    on public.runs (played_at);

alter table public.profiles enable row level security;
alter table public.runs enable row level security;

revoke all on table public.profiles from public, anon, authenticated;
revoke all on table public.runs from public, anon, authenticated;

create or replace function public.leet_letter(letter text, ch text)
returns boolean
language sql
immutable
set search_path = public
as $$
    select case letter
        when 'a' then ch in ('a', '4')
        when 'b' then ch in ('b', '8')
        when 'e' then ch in ('e', '3')
        when 'g' then ch in ('g', '6', '9')
        when 'i' then ch in ('i', '1')
        when 'l' then ch in ('l', '1')
        when 'o' then ch in ('o', '0')
        when 's' then ch in ('s', '5')
        when 't' then ch in ('t', '7')
        when 'z' then ch in ('z', '2')
        else ch = letter
    end;
$$;

create or replace function public.leet_contains(folded text, word text)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
    start_at integer;
    offset_at integer;
    matched boolean;
begin
    if word is null or char_length(word) = 0 or char_length(folded) < char_length(word) then
        return false;
    end if;
    for start_at in 1..(char_length(folded) - char_length(word) + 1) loop
        matched := true;
        for offset_at in 0..(char_length(word) - 1) loop
            if not public.leet_letter(
                substr(word, offset_at + 1, 1),
                substr(folded, start_at + offset_at, 1)
            ) then
                matched := false;
                exit;
            end if;
        end loop;
        if matched then
            return true;
        end if;
    end loop;
    return false;
end;
$$;

-- null when the name is acceptable. Otherwise too_short, must_start_with_letter,
-- invalid, or unavailable. Uniqueness is checked by the caller.
create or replace function public.username_problem(raw_name text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
    trimmed text;
    folded text;
    words text[] := array['admin', 'paperglide', 'support', 'moderator', 'apple', 'official'];
    word text;
begin
    trimmed := lower(btrim(coalesce(raw_name, ''), E' \t\n\r'));
    if char_length(trimmed) < 3 then
        return 'too_short';
    end if;
    if substr(trimmed, 1, 1) !~ '[a-z]' then
        return 'must_start_with_letter';
    end if;
    if trimmed !~ '^[a-z][a-z0-9_]{2,15}$' then
        return 'invalid';
    end if;
    folded := replace(trimmed, '_', '');
    foreach word in array words loop
        if public.leet_contains(folded, word) then
            return 'unavailable';
        end if;
    end loop;
    return null;
end;
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.profiles (id)
    values (new.id)
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

create or replace function public.my_username()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
    current_name text;
begin
    if uid is null then
        return jsonb_build_object('ok', false, 'error', 'unauthenticated');
    end if;
    select username into current_name from public.profiles where id = uid;
    return jsonb_build_object('ok', true, 'username', current_name);
end;
$$;

create or replace function public.claim_username(raw_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
    trimmed text := lower(btrim(coalesce(raw_name, ''), E' \t\n\r'));
    existing text;
    problem text;
begin
    if uid is null then
        return jsonb_build_object('ok', false, 'error', 'unauthenticated');
    end if;
    insert into public.profiles (id) values (uid) on conflict (id) do nothing;
    select username into existing from public.profiles where id = uid;
    if existing is not null then
        return jsonb_build_object('ok', true, 'result', 'already_named', 'username', existing);
    end if;
    problem := public.username_problem(trimmed);
    if problem is not null then
        return jsonb_build_object('ok', false, 'error', problem);
    end if;
    begin
        update public.profiles
        set username = trimmed
        where id = uid and username is null;
    exception
        when unique_violation then
            return jsonb_build_object('ok', false, 'error', 'taken');
    end;
    select username into existing from public.profiles where id = uid;
    if existing is null then
        return jsonb_build_object('ok', false, 'error', 'taken');
    end if;
    return jsonb_build_object('ok', true, 'result', 'saved', 'username', existing);
end;
$$;

create or replace function public.submit_run(
    run_id uuid,
    score integer,
    duration_seconds double precision,
    played_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
    owner uuid;
    current_name text;
    previous_at timestamptz;
    stored_day date;
    stored_count integer;
    today date;
    next_count integer;
begin
    if uid is null then
        return jsonb_build_object('ok', false, 'error', 'unauthenticated');
    end if;
    if run_id is null or score is null or duration_seconds is null or played_at is null then
        return jsonb_build_object('ok', false, 'error', 'rejected');
    end if;
    insert into public.profiles (id) values (uid) on conflict (id) do nothing;
    select username, last_submit_at, submit_day, submit_count
    into current_name, previous_at, stored_day, stored_count
    from public.profiles
    where id = uid
    for update;

    if current_name is null then
        return jsonb_build_object('ok', false, 'error', 'needs_name');
    end if;

    select user_id into owner from public.runs where id = run_id;
    if owner = uid then
        return jsonb_build_object('ok', true, 'result', 'duplicate');
    end if;
    if owner is not null then
        return jsonb_build_object('ok', false, 'error', 'rejected');
    end if;

    if previous_at is not null and previous_at > now() - interval '10 seconds' then
        return jsonb_build_object('ok', false, 'error', 'rate_limited');
    end if;

    if played_at > now() + interval '24 hours' or played_at < now() - interval '30 days' then
        update public.profiles set last_submit_at = now() where id = uid;
        return jsonb_build_object('ok', false, 'error', 'stale');
    end if;

    if duration_seconds <> duration_seconds
        or duration_seconds < 0
        or duration_seconds > 3600
        or score < 0
        or score > 2500
        or score::double precision > (duration_seconds / 1.5) + 3
    then
        update public.profiles set last_submit_at = now() where id = uid;
        return jsonb_build_object('ok', false, 'error', 'rejected');
    end if;

    today := (timezone('America/Toronto', now()))::date;
    if stored_day is distinct from today then
        next_count := 0;
    else
        next_count := coalesce(stored_count, 0);
    end if;
    if next_count >= 500 then
        return jsonb_build_object('ok', false, 'error', 'rate_limited');
    end if;

    insert into public.runs (id, user_id, score, duration_seconds, played_at)
    values (run_id, uid, score, duration_seconds, played_at);

    update public.profiles
    set last_submit_at = now(),
        submit_day = today,
        submit_count = next_count + 1
    where id = uid;

    return jsonb_build_object('ok', true, 'result', 'stored');
exception
    when unique_violation then
        return jsonb_build_object('ok', true, 'result', 'duplicate');
end;
$$;

create or replace function public.leaderboard(period text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
    payload jsonb;
begin
    if uid is null then
        return jsonb_build_object('ok', false, 'error', 'unauthenticated');
    end if;
    if period not in ('daily', 'weekly', 'all_time') then
        return jsonb_build_object('ok', false, 'error', 'invalid');
    end if;

    with local_now as (
        select timezone('America/Toronto', now()) as ts
    ),
    bounds as (
        select
            ts::date as today,
            date_trunc('week', ts)::date as week_start
        from local_now
    ),
    eligible as (
        select r.user_id, r.score, r.played_at
        from public.runs r
        cross join bounds b
        where period = 'all_time'
            or (
                period = 'daily'
                and (timezone('America/Toronto', r.played_at))::date = b.today
            )
            or (
                period = 'weekly'
                and (timezone('America/Toronto', r.played_at))::date >= b.week_start
                and (timezone('America/Toronto', r.played_at))::date < b.week_start + 7
            )
    ),
    bests as (
        select distinct on (e.user_id)
            e.user_id,
            e.score,
            e.played_at
        from eligible e
        join public.profiles p on p.id = e.user_id
        where p.username is not null
        order by e.user_id, e.score desc, e.played_at asc
    ),
    ranked as (
        select
            b.user_id,
            p.username,
            b.score,
            b.played_at,
            (1 + (
                select count(*)
                from bests higher
                where higher.score > b.score
            ))::integer as rank
        from bests b
        join public.profiles p on p.id = b.user_id
    )
    select jsonb_build_object(
        'ok', true,
        'fetched_at', extract(epoch from now()),
        'entries', coalesce((
            select jsonb_agg(
                jsonb_build_object(
                    'rank', top.rank,
                    'username', top.username,
                    'score', top.score
                )
                order by top.rank, top.played_at, top.username
            )
            from (
                select *
                from ranked
                order by rank, played_at, username
                limit 50
            ) top
        ), '[]'::jsonb),
        'you', (
            select jsonb_build_object(
                'rank', ranked.rank,
                'username', ranked.username,
                'score', ranked.score
            )
            from ranked
            where ranked.user_id = uid
        )
    )
    into payload;

    return payload;
end;
$$;

revoke all on function public.leet_letter(text, text) from public, anon, authenticated;
revoke all on function public.leet_contains(text, text) from public, anon, authenticated;
revoke all on function public.username_problem(text) from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.my_username() from public, anon, authenticated;
revoke all on function public.claim_username(text) from public, anon, authenticated;
revoke all on function public.submit_run(uuid, integer, double precision, timestamptz) from public, anon, authenticated;
revoke all on function public.leaderboard(text) from public, anon, authenticated;

grant execute on function public.my_username() to authenticated;
grant execute on function public.claim_username(text) to authenticated;
grant execute on function public.submit_run(uuid, integer, double precision, timestamptz) to authenticated;
grant execute on function public.leaderboard(text) to authenticated;

notify pgrst, 'reload schema';
