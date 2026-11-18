-- Paper Glide analytics, crash diagnostics, player reports, and the owner dashboard.
-- Run this file once in the Supabase SQL editor after the accounts migration.
-- It does not alter profiles, runs, claim_username, submit_run, leaderboard, or my_username.
-- It embeds no keys. The app and the dashboard use the anon key only.
--
-- Raw events, sessions, batches, and crash diagnostics are deleted after 90 days
-- by analytics_cleanup_raw(). Daily rollups and daily presence are kept.
-- Player reports are kept until analytics_delete_report() removes one.
-- Days, weeks, and months are America/Toronto civil dates. Weeks start Monday.
--
-- Storage against the 500 MB free-tier database, for a personal test week of
-- 30 accounts, 4 sessions a day, clicks stored as totals per control (not one
-- row per flap). Measured tuple sizes: event 125 bytes, session 82, presence 43,
-- rollup 54. That week is about 1.0 MB of tuples, about 0.2% of the 500 MB
-- free tier before indexes. Ninety days of raw rows stays on the order of 15–30 MB.

create table if not exists public.analytics_admins (
    email text primary key
);

create table if not exists public.analytics_batches (
    id uuid primary key,
    account_id uuid not null,
    received_at timestamptz not null default now()
);

create table if not exists public.analytics_events (
    id uuid primary key,
    batch_id uuid not null references public.analytics_batches (id) on delete cascade,
    account_id uuid not null,
    event_type text not null,
    occurred_at timestamptz not null,
    session_id uuid,
    page text,
    control text,
    count integer,
    created_at timestamptz not null default now()
);

create index if not exists analytics_events_occurred_idx
    on public.analytics_events (occurred_at);

create table if not exists public.analytics_sessions (
    id uuid primary key,
    account_id uuid not null,
    started_at timestamptz not null,
    toronto_day date not null,
    ended_in_crash boolean not null default false,
    app_version text,
    ios_version text,
    device_model text
);

create index if not exists analytics_sessions_started_idx
    on public.analytics_sessions (started_at);

create table if not exists public.crash_diagnostics (
    id uuid primary key,
    account_id uuid not null,
    session_id uuid,
    occurred_at timestamptz not null,
    toronto_day date not null,
    kind text not null,
    summary text not null,
    details text,
    app_version text,
    ios_version text,
    device_model text,
    created_at timestamptz not null default now()
);

create index if not exists crash_diagnostics_occurred_idx
    on public.crash_diagnostics (occurred_at);

create index if not exists crash_diagnostics_day_idx
    on public.crash_diagnostics (toronto_day, occurred_at desc);

create table if not exists public.player_reports (
    id uuid primary key,
    account_id uuid not null,
    category text not null,
    body text not null default '',
    app_version text,
    ios_version text,
    device_model text,
    created_at timestamptz not null default now(),
    constraint player_reports_body_len check (char_length(body) <= 500)
);

create index if not exists player_reports_created_idx
    on public.player_reports (created_at desc);

create table if not exists public.analytics_daily_accounts (
    day date not null,
    account_id uuid not null,
    primary key (day, account_id)
);

create table if not exists public.analytics_daily_rollups (
    day date not null,
    kind text not null,
    page text not null default '',
    control text not null default '',
    value bigint not null default 0,
    primary key (day, kind, page, control)
);

alter table public.analytics_admins enable row level security;
alter table public.analytics_batches enable row level security;
alter table public.analytics_events enable row level security;
alter table public.analytics_sessions enable row level security;
alter table public.crash_diagnostics enable row level security;
alter table public.player_reports enable row level security;
alter table public.analytics_daily_accounts enable row level security;
alter table public.analytics_daily_rollups enable row level security;

revoke all on table public.analytics_admins from public, anon, authenticated;
revoke all on table public.analytics_batches from public, anon, authenticated;
revoke all on table public.analytics_events from public, anon, authenticated;
revoke all on table public.analytics_sessions from public, anon, authenticated;
revoke all on table public.crash_diagnostics from public, anon, authenticated;
revoke all on table public.player_reports from public, anon, authenticated;
revoke all on table public.analytics_daily_accounts from public, anon, authenticated;
revoke all on table public.analytics_daily_rollups from public, anon, authenticated;

create or replace function public.analytics_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from public.analytics_admins
        where email = lower(coalesce(auth.jwt() ->> 'email', ''))
          and email <> ''
    );
$$;

drop function if exists public.analytics_add_rollup(date, text, text, text, bigint);

create or replace function public.analytics_add_rollup(
    bucket date,
    rollup_kind text,
    rollup_page text,
    rollup_control text,
    amount bigint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    insert into public.analytics_daily_rollups as rollup (day, kind, page, control, value)
    values (bucket, rollup_kind, coalesce(rollup_page, ''), coalesce(rollup_control, ''), amount)
    on conflict (day, kind, page, control)
    do update set value = rollup.value + excluded.value;
end;
$$;

create or replace function public.analytics_mark_active(bucket date, account uuid)
returns void
language sql
security definer
set search_path = public
as $$
    insert into public.analytics_daily_accounts (day, account_id)
    values (bucket, account)
    on conflict (day, account_id) do nothing;
$$;

create or replace function public.analytics_apply_event(uid uuid, batch uuid, item jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    event_kind text;
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
            perform public.analytics_add_rollup(bucket, 'sessions', '', '', 1);
        end if;
        perform public.analytics_mark_active(bucket, uid);
        insert into public.analytics_events (
            id, batch_id, account_id, event_type, occurred_at, session_id
        )
        values (event_id, batch, uid, 'session_start', occurred, sid)
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
        perform public.analytics_add_rollup(bucket, 'clicks', event_page, event_control, cnt);
        perform public.analytics_mark_active(bucket, uid);
        insert into public.analytics_events (
            id, batch_id, account_id, event_type, occurred_at, session_id, page, control, count
        )
        values (event_id, batch, uid, 'click', occurred, sid, event_page, event_control, cnt)
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
            perform public.analytics_add_rollup(bucket, 'sessions', '', '', 1);
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
            perform public.analytics_add_rollup(bucket, 'crashes', '', '', 1);
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
        perform public.analytics_mark_active(bucket, uid);
        insert into public.analytics_events (
            id, batch_id, account_id, event_type, occurred_at, session_id
        )
        values (event_id, batch, uid, 'crash', occurred, sid)
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
        perform public.analytics_mark_active(bucket, uid);
        return;
    end if;
end;
$$;

create or replace function public.submit_analytics_batch(batch_id uuid, events jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    uid uuid := auth.uid();
    item jsonb;
begin
    if uid is null then
        return jsonb_build_object('ok', false, 'error', 'unauthenticated');
    end if;
    if batch_id is null or events is null or jsonb_typeof(events) <> 'array' then
        return jsonb_build_object('ok', false, 'error', 'rejected');
    end if;
    if jsonb_array_length(events) > 50 then
        return jsonb_build_object('ok', false, 'error', 'rejected');
    end if;
    begin
        insert into public.analytics_batches (id, account_id)
        values (batch_id, uid);
    exception when unique_violation then
        return jsonb_build_object('ok', true, 'result', 'duplicate');
    end;
    for item in select value from jsonb_array_elements(events)
    loop
        perform public.analytics_apply_event(uid, batch_id, item);
    end loop;
    return jsonb_build_object('ok', true, 'result', 'stored');
end;
$$;

create or replace function public.analytics_who()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if auth.uid() is null then
        return jsonb_build_object('ok', false, 'error', 'unauthenticated');
    end if;
    return jsonb_build_object('ok', true, 'admin', public.analytics_is_admin());
end;
$$;

create or replace function public.analytics_summary(start_day date, end_day date)
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
    select count(*) into dau
    from public.analytics_daily_accounts
    where day = today;
    select count(distinct account_id) into wau
    from public.analytics_daily_accounts
    where day >= week_start and day <= today;
    select count(distinct account_id) into mau
    from public.analytics_daily_accounts
    where day >= month_start and day <= today;
    if end_day >= start_day then
        select coalesce(sum(value), 0) into sessions
        from public.analytics_daily_rollups
        where kind = 'sessions' and day between start_day and end_day;
        select coalesce(sum(value), 0) into crashes
        from public.analytics_daily_rollups
        where kind = 'crashes' and day between start_day and end_day;
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

create or replace function public.analytics_series(start_day date, end_day date, group_by text, metric text)
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
                )
                else (
                    select coalesce(sum(r.value), 0)
                    from public.analytics_daily_rollups r
                    where r.kind = 'crashes'
                      and r.day >= b.bucket_start
                      and r.day < b.bucket_end
                      and r.day between start_day and end_day
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

drop function if exists public.analytics_clicks(date, date);

create or replace function public.analytics_clicks(start_day date, end_day date, group_by text default 'day')
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

create or replace function public.analytics_reports(
    start_day date,
    end_day date,
    report_filter text,
    before_at timestamptz,
    before_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    today date := (timezone('America/Toronto', now()))::date;
    filter_kind text := coalesce(report_filter, 'all');
    all_count bigint := 0;
    crash_count bigint := 0;
    player_count bigint := 0;
    payload jsonb;
    has_more boolean := false;
begin
    if not public.analytics_is_admin() then
        return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
    if start_day is null or end_day is null or filter_kind not in ('all', 'crash', 'player') then
        return jsonb_build_object('ok', false, 'error', 'invalid');
    end if;

    if end_day >= start_day then
        select count(*) into player_count
        from public.player_reports
        where (timezone('America/Toronto', created_at))::date between start_day and end_day;
        select count(*) into crash_count
        from public.crash_diagnostics
        where toronto_day between start_day and end_day;
    end if;
    all_count := player_count + crash_count;

    with combined as (
        select
            r.id,
            r.created_at as happened_at,
            'player'::text as report_kind,
            r.category,
            null::text as summary,
            r.body as full_text,
            null::text as details,
            r.app_version,
            r.ios_version,
            r.device_model,
            r.account_id,
            p.username
        from public.player_reports r
        left join public.profiles p on p.id = r.account_id
        where end_day >= start_day
          and (timezone('America/Toronto', r.created_at))::date between start_day and end_day
          and filter_kind in ('all', 'player')
        union all
        select
            c.id,
            c.occurred_at,
            'crash',
            null,
            c.summary,
            null,
            c.details,
            c.app_version,
            c.ios_version,
            c.device_model,
            c.account_id,
            p.username
        from public.crash_diagnostics c
        left join public.profiles p on p.id = c.account_id
        where end_day >= start_day
          and c.toronto_day between start_day and end_day
          and filter_kind in ('all', 'crash')
    ),
    windowed as (
        select *
        from combined
        where before_at is null
           or happened_at < before_at
           or (happened_at = before_at and (before_id is null or id < before_id))
        order by happened_at desc, id desc
        limit 51
    ),
    page as (
        select * from windowed order by happened_at desc, id desc limit 50
    )
    select coalesce(jsonb_agg(
        jsonb_build_object(
            'id', id,
            'happened_at', happened_at,
            'kind', report_kind,
            'category', category,
            'summary', summary,
            'text', full_text,
            'details', details,
            'app_version', app_version,
            'ios_version', ios_version,
            'device_model', device_model,
            'account_id', account_id,
            'username', username
        )
        order by happened_at desc, id desc
    ), '[]'::jsonb)
    into payload
    from page;

    select count(*) > 50 into has_more from (
        select 1 from (
            select r.created_at as happened_at, r.id
            from public.player_reports r
            where end_day >= start_day
              and (timezone('America/Toronto', r.created_at))::date between start_day and end_day
              and filter_kind in ('all', 'player')
            union all
            select c.occurred_at, c.id
            from public.crash_diagnostics c
            where end_day >= start_day
              and c.toronto_day between start_day and end_day
              and filter_kind in ('all', 'crash')
        ) listed
        where before_at is null
           or happened_at < before_at
           or (happened_at = before_at and (before_id is null or id < before_id))
        limit 51
    ) extra;

    return jsonb_build_object(
        'ok', true,
        'counts', jsonb_build_object('all', all_count, 'crash', crash_count, 'player', player_count),
        'reports', payload,
        'has_more', coalesce(has_more, false),
        'retention_note', start_day <= (today - 90)
    );
end;
$$;

create or replace function public.analytics_delete_report(report_id uuid, report_kind text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    removed uuid;
begin
    if not public.analytics_is_admin() then
        return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
    if report_id is null or report_kind not in ('player', 'crash') then
        return jsonb_build_object('ok', false, 'error', 'invalid');
    end if;
    if report_kind = 'player' then
        delete from public.player_reports where id = report_id returning id into removed;
    else
        delete from public.crash_diagnostics where id = report_id returning id into removed;
    end if;
    if removed is null then
        return jsonb_build_object('ok', true, 'result', 'missing');
    end if;
    return jsonb_build_object('ok', true, 'result', 'deleted');
end;
$$;

-- Deletes raw events, batches, sessions, and crash diagnostics older than 90 days.
-- Does not delete rollups, presence, player reports, profiles, or runs.
create or replace function public.analytics_cleanup_raw()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    cutoff timestamptz := now() - interval '90 days';
begin
    delete from public.analytics_events where occurred_at < cutoff;
    delete from public.crash_diagnostics where occurred_at < cutoff;
    delete from public.analytics_sessions where started_at < cutoff;
    delete from public.analytics_batches b
    where b.received_at < cutoff
      and not exists (
          select 1 from public.analytics_events e where e.batch_id = b.id
      );
end;
$$;

revoke all on function public.analytics_is_admin() from public, anon, authenticated;
revoke all on function public.analytics_add_rollup(date, text, text, text, bigint) from public, anon, authenticated;
revoke all on function public.analytics_mark_active(date, uuid) from public, anon, authenticated;
revoke all on function public.analytics_apply_event(uuid, uuid, jsonb) from public, anon, authenticated;
revoke all on function public.submit_analytics_batch(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.analytics_who() from public, anon, authenticated;
revoke all on function public.analytics_summary(date, date) from public, anon, authenticated;
revoke all on function public.analytics_series(date, date, text, text) from public, anon, authenticated;
revoke all on function public.analytics_clicks(date, date, text) from public, anon, authenticated;
revoke all on function public.analytics_reports(date, date, text, timestamptz, uuid) from public, anon, authenticated;
revoke all on function public.analytics_delete_report(uuid, text) from public, anon, authenticated;
revoke all on function public.analytics_cleanup_raw() from public, anon, authenticated;

grant execute on function public.submit_analytics_batch(uuid, jsonb) to authenticated;
grant execute on function public.analytics_who() to authenticated;
grant execute on function public.analytics_summary(date, date) to authenticated;
grant execute on function public.analytics_series(date, date, text, text) to authenticated;
grant execute on function public.analytics_clicks(date, date, text) to authenticated;
grant execute on function public.analytics_reports(date, date, text, timestamptz, uuid) to authenticated;
grant execute on function public.analytics_delete_report(uuid, text) to authenticated;

do $$
begin
    begin
        perform 1 from pg_extension where extname = 'pg_cron';
        if not found then
            create extension pg_cron;
        end if;
    exception when others then
        raise notice 'pg_cron is not available (%). Enable the extension, then run: select cron.schedule(''analytics-raw-cleanup'', ''30 8 * * *'', ''select public.analytics_cleanup_raw()'');', sqlerrm;
        return;
    end;
    if exists (select 1 from cron.job where jobname = 'analytics-raw-cleanup') then
        perform cron.unschedule('analytics-raw-cleanup');
    end if;
    perform cron.schedule(
        'analytics-raw-cleanup',
        '30 8 * * *',
        'select public.analytics_cleanup_raw()'
    );
exception when others then
    raise notice 'could not schedule analytics cleanup (%). Enable pg_cron, then run: select cron.schedule(''analytics-raw-cleanup'', ''30 8 * * *'', ''select public.analytics_cleanup_raw()'');', sqlerrm;
end $$;

notify pgrst, 'reload schema';
