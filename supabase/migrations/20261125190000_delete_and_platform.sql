-- Paper Glide release prep: delete-my-data and the platform column.
-- Run this once after the accounts migration and the analytics migration.
-- It does not embed keys. Do not run it against a hosted project from CI.
--
-- Stable contract for the Android port (do not rename or re-type these):
--   public.delete_my_data() returns jsonb
--     security definer, search_path = public, no arguments
--     deletes only auth.uid(): analytics_events, analytics_sessions,
--     crash_diagnostics, player_reports, analytics_daily_accounts,
--     analytics_batches, runs, profiles, and auth.users
--     {ok:true, result:deleted} or {ok:false, error:unauthenticated}
--   public.runs.platform and public.analytics_events.platform
--     text not null default 'ios' check (platform in ('ios', 'android'))
--   public.submit_run(run_id uuid, score integer, duration_seconds double precision,
--     played_at timestamptz, platform text default 'ios')
--     stores that platform on the run. unknown values are rejected and not stored.
--   submit_analytics_batch events read item->>'platform', default 'ios'.
--     unknown values skip that event. 'ios' and 'android' are stored.
--   Rollups and daily presence also carry platform so the dashboard filter
--     still works after raw events are deleted at 90 days.
--   analytics_summary(start_day, end_day, platform_filter default null)
--   analytics_series(start_day, end_day, group_by, metric, platform_filter default null)
--   analytics_clicks(start_day, end_day, group_by default 'day', platform_filter default null)
--     null platform_filter means all platforms.

alter table public.runs
    add column if not exists platform text not null default 'ios';

alter table public.analytics_events
    add column if not exists platform text not null default 'ios';

alter table public.analytics_daily_rollups
    add column if not exists platform text not null default 'ios';

alter table public.analytics_daily_accounts
    add column if not exists platform text not null default 'ios';

update public.runs set platform = 'ios' where platform is null;
update public.analytics_events set platform = 'ios' where platform is null;
update public.analytics_daily_rollups set platform = 'ios' where platform is null;
update public.analytics_daily_accounts set platform = 'ios' where platform is null;

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'runs_platform_check') then
        alter table public.runs
            add constraint runs_platform_check check (platform in ('ios', 'android'));
    end if;
    if not exists (select 1 from pg_constraint where conname = 'analytics_events_platform_check') then
        alter table public.analytics_events
            add constraint analytics_events_platform_check check (platform in ('ios', 'android'));
    end if;
    if not exists (select 1 from pg_constraint where conname = 'analytics_daily_rollups_platform_check') then
        alter table public.analytics_daily_rollups
            add constraint analytics_daily_rollups_platform_check check (platform in ('ios', 'android'));
    end if;
    if not exists (select 1 from pg_constraint where conname = 'analytics_daily_accounts_platform_check') then
        alter table public.analytics_daily_accounts
            add constraint analytics_daily_accounts_platform_check check (platform in ('ios', 'android'));
    end if;
    if not exists (
        select 1
        from pg_constraint
        where conname = 'analytics_daily_rollups_pkey'
          and pg_get_constraintdef(oid) like '%platform%'
    ) then
        alter table public.analytics_daily_rollups drop constraint analytics_daily_rollups_pkey;
        alter table public.analytics_daily_rollups
            add constraint analytics_daily_rollups_pkey
            primary key (day, kind, page, control, platform);
    end if;
    if not exists (
        select 1
        from pg_constraint
        where conname = 'analytics_daily_accounts_pkey'
          and pg_get_constraintdef(oid) like '%platform%'
    ) then
        alter table public.analytics_daily_accounts drop constraint analytics_daily_accounts_pkey;
        alter table public.analytics_daily_accounts
            add constraint analytics_daily_accounts_pkey
            primary key (day, account_id, platform);
    end if;
end $$;

create or replace function public.analytics_add_rollup(
    bucket date,
    rollup_kind text,
    rollup_page text,
    rollup_control text,
    amount bigint,
    rollup_platform text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if rollup_platform not in ('ios', 'android') then
        return;
    end if;
    insert into public.analytics_daily_rollups as rollup (day, kind, page, control, platform, value)
    values (
        bucket,
        rollup_kind,
        coalesce(rollup_page, ''),
        coalesce(rollup_control, ''),
        rollup_platform,
        amount
    )
    on conflict (day, kind, page, control, platform)
    do update set value = rollup.value + excluded.value;
end;
$$;

create or replace function public.analytics_mark_active(bucket date, account uuid, account_platform text)
returns void
language sql
security definer
set search_path = public
as $$
    insert into public.analytics_daily_accounts (day, account_id, platform)
    values (bucket, account, account_platform)
    on conflict (day, account_id, platform) do nothing;
$$;

create or replace function public.analytics_apply_event(uid uuid, batch uuid, item jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    event_kind text;
    event_platform text;
    occurred timestamptz;
    bucket date;
    event_id uuid;
    sid uuid;
    event_page text;
    event_control text;
    cnt integer;
    category text;
    body text;
    app_version text;
    ios_version text;
    device_model text;
    crash_kind text;
    crash_summary text;
    crash_details text;
    inserted uuid;
    flipped uuid;
begin
    begin
        event_kind := item ->> 'kind';
        occurred := (item ->> 'occurred_at')::timestamptz;
        event_id := (item ->> 'id')::uuid;
        if nullif(item ->> 'session_id', '') is null then
            sid := null;
        else
            sid := (item ->> 'session_id')::uuid;
        end if;
    exception when others then
        return;
    end;
    if occurred is null or event_id is null or event_kind is null then
        return;
    end if;
    event_platform := lower(coalesce(nullif(btrim(coalesce(item ->> 'platform', '')), ''), 'ios'));
    if event_platform not in ('ios', 'android') then
        return;
    end if;
    bucket := (timezone('America/Toronto', occurred))::date;
    app_version := left(coalesce(item ->> 'app_version', ''), 40);
    ios_version := left(coalesce(item ->> 'ios_version', ''), 40);
    device_model := left(coalesce(item ->> 'device_model', ''), 80);

    if event_kind = 'session_start' then
        if sid is null then
            return;
        end if;
        insert into public.analytics_sessions (
            id, account_id, started_at, toronto_day, app_version, ios_version, device_model
        )
        values (sid, uid, occurred, bucket, app_version, ios_version, device_model)
        on conflict (id) do nothing
        returning id into inserted;
        if inserted is not null then
            perform public.analytics_add_rollup(bucket, 'sessions', '', '', 1, event_platform);
        end if;
        perform public.analytics_mark_active(bucket, uid, event_platform);
        insert into public.analytics_events (
            id, batch_id, account_id, event_type, occurred_at, session_id, platform
        )
        values (event_id, batch, uid, 'session_start', occurred, sid, event_platform)
        on conflict (id) do nothing;
        return;
    end if;

    if event_kind = 'click' then
        event_page := item ->> 'page';
        event_control := item ->> 'control';
        begin
            cnt := coalesce((item ->> 'count')::integer, 1);
        exception when others then
            return;
        end;
        if cnt < 1 or cnt > 1000000 then
            return;
        end if;
        if not (
            (event_page = 'start' and event_control in ('play', 'leaderboard', 'report', 'other'))
            or (event_page = 'playing' and event_control = 'flap')
            or (event_page = 'leaderboard' and event_control in ('Today', 'This week', 'All time', 'back', 'other', 'scroll'))
        ) then
            return;
        end if;
        perform public.analytics_add_rollup(bucket, 'clicks', event_page, event_control, cnt, event_platform);
        perform public.analytics_mark_active(bucket, uid, event_platform);
        insert into public.analytics_events (
            id, batch_id, account_id, event_type, occurred_at, session_id, page, control, count, platform
        )
        values (event_id, batch, uid, 'click', occurred, sid, event_page, event_control, cnt, event_platform)
        on conflict (id) do nothing;
        return;
    end if;

    if event_kind = 'crash' then
        if sid is null then
            return;
        end if;
        crash_kind := item ->> 'crash_kind';
        if crash_kind not in ('unclean_exit', 'metrickit') then
            return;
        end if;
        crash_summary := left(coalesce(nullif(item ->> 'crash_summary', ''), crash_kind), 300);
        crash_details := left(coalesce(item ->> 'crash_details', ''), 4000);
        insert into public.analytics_sessions (
            id, account_id, started_at, toronto_day, app_version, ios_version, device_model
        )
        values (sid, uid, occurred, bucket, app_version, ios_version, device_model)
        on conflict (id) do nothing
        returning id into inserted;
        if inserted is not null then
            perform public.analytics_add_rollup(bucket, 'sessions', '', '', 1, event_platform);
        end if;
        select toronto_day into bucket
        from public.analytics_sessions
        where id = sid and account_id = uid;
        if bucket is null then
            return;
        end if;
        update public.analytics_sessions
        set ended_in_crash = true
        where id = sid and account_id = uid and ended_in_crash = false
        returning id into flipped;
        if flipped is not null then
            perform public.analytics_add_rollup(bucket, 'crashes', '', '', 1, event_platform);
        end if;
        insert into public.crash_diagnostics (
            id, account_id, session_id, occurred_at, toronto_day, kind, summary, details,
            app_version, ios_version, device_model
        )
        values (
            sid, uid, sid, occurred, bucket, crash_kind, crash_summary, crash_details,
            app_version, ios_version, device_model
        )
        on conflict (id) do update
        set summary = excluded.summary,
            details = excluded.details,
            kind = excluded.kind
        where public.crash_diagnostics.account_id = uid
          and (public.crash_diagnostics.kind <> 'metrickit' or excluded.kind = 'metrickit');
        perform public.analytics_mark_active(bucket, uid, event_platform);
        insert into public.analytics_events (
            id, batch_id, account_id, event_type, occurred_at, session_id, platform
        )
        values (event_id, batch, uid, 'crash', occurred, sid, event_platform)
        on conflict (id) do nothing;
        return;
    end if;

    if event_kind = 'report' then
        category := item ->> 'category';
        if category not in (
            'The game crashed or froze',
            'Something looks wrong',
            'Leaderboard or my name',
            'I have an idea',
            'Something else'
        ) then
            return;
        end if;
        body := left(coalesce(item ->> 'text', ''), 500);
        insert into public.player_reports (
            id, account_id, category, body, app_version, ios_version, device_model, created_at
        )
        values (event_id, uid, category, body, app_version, ios_version, device_model, occurred)
        on conflict (id) do nothing;
        perform public.analytics_mark_active(bucket, uid, event_platform);
        return;
    end if;
end;
$$;


drop function if exists public.analytics_add_rollup(date, text, text, text, bigint);
drop function if exists public.analytics_mark_active(date, uuid);

drop function if exists public.analytics_summary(date, date);
drop function if exists public.analytics_series(date, date, text, text);
drop function if exists public.analytics_clicks(date, date, text);
drop function if exists public.submit_run(uuid, integer, double precision, timestamptz);

create or replace function public.analytics_summary(start_day date, end_day date, platform_filter text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    today date := (timezone('America/Toronto', now()))::date;
    week_start date := date_trunc('week', today::timestamp)::date;
    month_start date := date_trunc('month', today::timestamp)::date;
    dau bigint := 0;
    wau bigint := 0;
    mau bigint := 0;
    sessions bigint := 0;
    crashes bigint := 0;
    crash_free integer;
begin
    if not public.analytics_is_admin() then
        return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
    if start_day is null or end_day is null then
        return jsonb_build_object('ok', false, 'error', 'invalid');
    end if;
    if platform_filter is not null and platform_filter not in ('ios', 'android') then
        return jsonb_build_object('ok', false, 'error', 'invalid');
    end if;
    select count(distinct account_id) into dau
    from public.analytics_daily_accounts
    where day = today
      and (platform_filter is null or platform = platform_filter);
    select count(distinct account_id) into wau
    from public.analytics_daily_accounts
    where day >= week_start and day <= today
      and (platform_filter is null or platform = platform_filter);
    select count(distinct account_id) into mau
    from public.analytics_daily_accounts
    where day >= month_start and day <= today
      and (platform_filter is null or platform = platform_filter);
    if end_day >= start_day then
        select coalesce(sum(value), 0) into sessions
        from public.analytics_daily_rollups
        where kind = 'sessions' and day between start_day and end_day
          and (platform_filter is null or platform = platform_filter);
        select coalesce(sum(value), 0) into crashes
        from public.analytics_daily_rollups
        where kind = 'crashes' and day between start_day and end_day
          and (platform_filter is null or platform = platform_filter);
    end if;
    if sessions = 0 then
        crash_free := null;
    else
        crash_free := round((100.0 * greatest(sessions - crashes, 0)) / sessions);
    end if;
    return jsonb_build_object(
        'ok', true,
        'dau', dau,
        'wau', wau,
        'mau', mau,
        'crashes', crashes,
        'sessions', sessions,
        'crash_free', crash_free
    );
end;
$$;

create or replace function public.analytics_series(start_day date, end_day date, group_by text, metric text, platform_filter text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    today date := (timezone('America/Toronto', now()))::date;
    payload jsonb;
begin
    if not public.analytics_is_admin() then
        return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
    if start_day is null or end_day is null or group_by not in ('day', 'week', 'month') or metric not in ('active', 'crashes') then
        return jsonb_build_object('ok', false, 'error', 'invalid');
    end if;
    if platform_filter is not null and platform_filter not in ('ios', 'android') then
        return jsonb_build_object('ok', false, 'error', 'invalid');
    end if;
    if end_day < start_day then
        return jsonb_build_object('ok', true, 'buckets', '[]'::jsonb);
    end if;

    with buckets as (
        select bucket_start::date as bucket_start,
            case group_by
                when 'day' then (bucket_start + interval '1 day')::date
                when 'week' then (bucket_start + interval '7 day')::date
                else (bucket_start + interval '1 month')::date
            end as bucket_end
        from generate_series(
            case group_by
                when 'day' then start_day::timestamp
                when 'week' then date_trunc('week', start_day::timestamp)
                else date_trunc('month', start_day::timestamp)
            end,
            case group_by
                when 'day' then end_day::timestamp
                when 'week' then date_trunc('week', end_day::timestamp)
                else date_trunc('month', end_day::timestamp)
            end,
            case group_by
                when 'day' then interval '1 day'
                when 'week' then interval '7 day'
                else interval '1 month'
            end
        ) as bucket_start
    ),
    counted as (
        select
            b.bucket_start,
            case
                when metric = 'active' then (
                    select count(distinct a.account_id)
                    from public.analytics_daily_accounts a
                    where a.day >= b.bucket_start
                      and a.day < b.bucket_end
                      and a.day between start_day and end_day
                      and (platform_filter is null or a.platform = platform_filter)
                )
                else (
                    select coalesce(sum(r.value), 0)
                    from public.analytics_daily_rollups r
                    where r.kind = 'crashes'
                      and r.day >= b.bucket_start
                      and r.day < b.bucket_end
                      and r.day between start_day and end_day
                      and (platform_filter is null or r.platform = platform_filter)
                )
            end as amount,
            case
                when metric = 'crashes' then (
                    select coalesce(sum(r.value), 0)
                    from public.analytics_daily_rollups r
                    where r.kind = 'sessions'
                      and r.day >= b.bucket_start
                      and r.day < b.bucket_end
                      and r.day between start_day and end_day
                      and (platform_filter is null or r.platform = platform_filter)
                )
                else null
            end as session_amount,
            (today >= b.bucket_start and today < b.bucket_end) as so_far
        from buckets b
    )
    select coalesce(jsonb_agg(
        jsonb_build_object(
            'start', bucket_start,
            'count', amount,
            'sessions', session_amount,
            'crash_free', case
                when metric <> 'crashes' then null
                when coalesce(session_amount, 0) = 0 then null
                else round((100.0 * greatest(session_amount - amount, 0)) / session_amount)
            end,
            'so_far', so_far
        )
        order by bucket_start
    ), '[]'::jsonb)
    into payload
    from counted;

    return jsonb_build_object('ok', true, 'buckets', payload);
end;
$$;

create or replace function public.analytics_clicks(start_day date, end_day date, group_by text default 'day', platform_filter text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    grouping text := coalesce(nullif(group_by, ''), 'day');
    payload jsonb;
begin
    if not public.analytics_is_admin() then
        return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
    if start_day is null or end_day is null or grouping not in ('day', 'week', 'month') then
        return jsonb_build_object('ok', false, 'error', 'invalid');
    end if;
    if platform_filter is not null and platform_filter not in ('ios', 'android') then
        return jsonb_build_object('ok', false, 'error', 'invalid');
    end if;

    with controls as (
        select *
        from (values
            ('start', 'play', 1),
            ('start', 'leaderboard', 2),
            ('start', 'report', 3),
            ('start', 'other', 4),
            ('playing', 'flap', 1),
            ('leaderboard', 'Today', 1),
            ('leaderboard', 'This week', 2),
            ('leaderboard', 'All time', 3),
            ('leaderboard', 'back', 4),
            ('leaderboard', 'other', 5),
            ('leaderboard', 'scroll', 6)
        ) as listed(page, control, ord)
    ),
    sums as (
        select page, control, sum(value)::bigint as amount
        from public.analytics_daily_rollups
        where kind = 'clicks'
          and end_day >= start_day
          and day between start_day and end_day
          and (platform_filter is null or platform = platform_filter)
        group by page, control
    ),
    page_totals as (
        select page, sum(amount)::bigint as total
        from sums
        group by page
    ),
    buckets as (
        select bucket_start::date as bucket_start,
            case grouping
                when 'day' then (bucket_start + interval '1 day')::date
                when 'week' then (bucket_start + interval '7 day')::date
                else (bucket_start + interval '1 month')::date
            end as bucket_end
        from generate_series(
            case grouping
                when 'day' then start_day::timestamp
                when 'week' then date_trunc('week', start_day::timestamp)
                else date_trunc('month', start_day::timestamp)
            end,
            case grouping
                when 'day' then end_day::timestamp
                when 'week' then date_trunc('week', end_day::timestamp)
                else date_trunc('month', end_day::timestamp)
            end,
            case grouping
                when 'day' then interval '1 day'
                when 'week' then interval '7 day'
                else interval '1 month'
            end
        ) as bucket_start
        where end_day >= start_day
    ),
    today as (
        select (timezone('America/Toronto', now()))::date as today
    ),
    bucket_counts as (
        select
            b.bucket_start,
            pages.page,
            coalesce(sum(r.value), 0)::bigint as amount,
            (b.bucket_start <= t.today and t.today < b.bucket_end) as so_far
        from buckets b
        cross join (select distinct page from controls) pages
        cross join today t
        left join public.analytics_daily_rollups r
            on r.kind = 'clicks'
            and r.page = pages.page
            and r.day >= b.bucket_start
            and r.day < b.bucket_end
            and r.day between start_day and end_day
            and (platform_filter is null or r.platform = platform_filter)
        group by b.bucket_start, b.bucket_end, pages.page, t.today
    ),
    pages as (
        select
            c.page,
            coalesce(max(t.total), 0)::bigint as total,
            jsonb_agg(
                jsonb_build_object(
                    'control', c.control,
                    'count', coalesce(s.amount, 0),
                    'share', case
                        when coalesce(t.total, 0) = 0 then 0
                        else round((100.0 * coalesce(s.amount, 0)) / t.total)
                    end
                )
                order by coalesce(s.amount, 0) desc, c.ord
            ) as controls,
            (
                select coalesce(jsonb_agg(
                    jsonb_build_object(
                        'start', bc.bucket_start,
                        'count', bc.amount,
                        'so_far', bc.so_far
                    )
                    order by bc.bucket_start
                ), '[]'::jsonb)
                from bucket_counts bc
                where bc.page = c.page
            ) as buckets
        from controls c
        left join sums s on s.page = c.page and s.control = c.control
        left join page_totals t on t.page = c.page
        group by c.page
    )
    select coalesce(jsonb_agg(
        jsonb_build_object('page', page, 'total', total, 'controls', controls, 'buckets', buckets)
        order by case page when 'start' then 1 when 'playing' then 2 else 3 end
    ), '[]'::jsonb)
    into payload
    from pages;

    return jsonb_build_object('ok', true, 'pages', payload);
end;
$$;

create or replace function public.submit_run(
    run_id uuid,
    score integer,
    duration_seconds double precision,
    played_at timestamptz,
    platform text default 'ios'
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
    chosen_platform text;
begin
    if uid is null then
        return jsonb_build_object('ok', false, 'error', 'unauthenticated');
    end if;
    if run_id is null or score is null or duration_seconds is null or played_at is null then
        return jsonb_build_object('ok', false, 'error', 'rejected');
    end if;
    chosen_platform := lower(coalesce(nullif(btrim(coalesce(platform, '')), ''), 'ios'));
    if chosen_platform not in ('ios', 'android') then
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
        return jsonb_build_object('ok', false, 'error', 'stale');
    end if;

    if duration_seconds <> duration_seconds
        or duration_seconds < 0
        or duration_seconds > 3600
        or score < 0
        or score > 2500
        or score::double precision > (duration_seconds / 1.5) + 3
    then
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

    insert into public.runs (id, user_id, score, duration_seconds, played_at, platform)
    values (run_id, uid, score, duration_seconds, played_at, chosen_platform);

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


create or replace function public.delete_my_data()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
begin
    if uid is null then
        return jsonb_build_object('ok', false, 'error', 'unauthenticated');
    end if;

    delete from public.analytics_events where account_id = uid;
    delete from public.analytics_sessions where account_id = uid;
    delete from public.crash_diagnostics where account_id = uid;
    delete from public.player_reports where account_id = uid;
    delete from public.analytics_daily_accounts where account_id = uid;
    delete from public.analytics_batches where account_id = uid;
    delete from public.runs where user_id = uid;
    delete from public.profiles where id = uid;
    delete from auth.users where id = uid;

    return jsonb_build_object('ok', true, 'result', 'deleted');
end;
$$;

revoke all on function public.analytics_add_rollup(date, text, text, text, bigint, text) from public, anon, authenticated;
revoke all on function public.analytics_mark_active(date, uuid, text) from public, anon, authenticated;
revoke all on function public.analytics_apply_event(uuid, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.submit_run(uuid, integer, double precision, timestamptz, text) from public, anon, authenticated;
revoke all on function public.analytics_summary(date, date, text) from public, anon, authenticated;
revoke all on function public.analytics_series(date, date, text, text, text) from public, anon, authenticated;
revoke all on function public.analytics_clicks(date, date, text, text) from public, anon, authenticated;
revoke all on function public.delete_my_data() from public, anon, authenticated;

grant execute on function public.submit_run(uuid, integer, double precision, timestamptz, text) to authenticated;
grant execute on function public.analytics_summary(date, date, text) to authenticated;
grant execute on function public.analytics_series(date, date, text, text, text) to authenticated;
grant execute on function public.analytics_clicks(date, date, text, text) to authenticated;
grant execute on function public.delete_my_data() to authenticated;

notify pgrst, 'reload schema';
