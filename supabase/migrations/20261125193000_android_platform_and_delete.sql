-- Android platform tag and in-app deletion.
-- Do not run this against the hosted project from CI. Owen applies it in the SQL editor.
-- iOS keeps working: submit_run.platform defaults to 'ios', and analytics events
-- without a platform are stored as ios.
-- The anon key is the only key the apps use. This file embeds no keys.

alter table public.runs add column if not exists platform text not null default 'ios';

alter table public.runs drop constraint if exists runs_platform_check;
alter table public.runs
    add constraint runs_platform_check check (platform in ('ios', 'android'));

alter table public.analytics_sessions add column if not exists platform text not null default 'ios';
alter table public.crash_diagnostics add column if not exists platform text not null default 'ios';
alter table public.player_reports add column if not exists platform text not null default 'ios';

drop function if exists public.submit_run(uuid, integer, double precision, timestamptz);

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
    stored_platform text;
begin
    if uid is null then
        return jsonb_build_object('ok', false, 'error', 'unauthenticated');
    end if;
    stored_platform := lower(coalesce(nullif(btrim(platform), ''), 'ios'));
    if stored_platform not in ('ios', 'android') then
        return jsonb_build_object('ok', false, 'error', 'rejected');
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
    values (run_id, uid, score, duration_seconds, played_at, stored_platform);

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

-- Same event application as 20261110160000, plus platform on the session,
-- the crash row, and the report row. Unknown or missing platform is ios.
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
    event_platform text;
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
    event_platform := lower(left(coalesce(nullif(item ->> 'platform', ''), 'ios'), 16));
    if event_platform not in ('ios', 'android') then
        event_platform := 'ios';
    end if;

    if event_kind = 'session_start' then
        if sid is null then
            return;
        end if;
        insert into public.analytics_sessions (
            id, account_id, started_at, toronto_day, app_version, ios_version, device_model, platform
        )
        values (sid, uid, occurred, bucket, app_version, ios_version, device_model, event_platform)
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
            id, account_id, started_at, toronto_day, app_version, ios_version, device_model, platform
        )
        values (sid, uid, occurred, bucket, app_version, ios_version, device_model, event_platform)
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
            app_version, ios_version, device_model, platform
        )
        values (
            sid, uid, sid, occurred, bucket, crash_kind, crash_summary, crash_details,
            app_version, ios_version, device_model, event_platform
        )
        on conflict (id) do update
        set summary = excluded.summary,
            details = excluded.details,
            kind = excluded.kind,
            platform = excluded.platform
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
            id, account_id, category, body, app_version, ios_version, device_model, created_at, platform
        )
        values (event_id, uid, category, body, app_version, ios_version, device_model, occurred, event_platform)
        on conflict (id) do nothing;
        perform public.analytics_mark_active(bucket, uid);
        return;
    end if;
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
    delete from public.player_reports where account_id = uid;
    delete from public.crash_diagnostics where account_id = uid;
    delete from public.analytics_events where account_id = uid;
    delete from public.analytics_sessions where account_id = uid;
    delete from public.analytics_batches where account_id = uid;
    delete from public.analytics_daily_accounts where account_id = uid;
    delete from public.profiles where id = uid;
    begin
        delete from auth.users where id = uid;
    exception when others then
        null;
    end;
    return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.analytics_platform_totals(start_day date, end_day date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
    if not public.analytics_is_admin() then
        return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
    return jsonb_build_object(
        'ok', true,
        'rows', coalesce((
            select jsonb_agg(jsonb_build_object('platform', platform, 'sessions', sessions) order by platform)
            from (
                select platform, count(*) as sessions
                from public.analytics_sessions
                where toronto_day between start_day and end_day
                group by platform
            ) counted
        ), '[]'::jsonb)
    );
end;
$$;

revoke all on function public.submit_run(uuid, integer, double precision, timestamptz, text) from public, anon;
revoke all on function public.delete_my_data() from public, anon;
revoke all on function public.analytics_platform_totals(date, date) from public, anon;
grant execute on function public.submit_run(uuid, integer, double precision, timestamptz, text) to authenticated;
grant execute on function public.delete_my_data() to authenticated;
grant execute on function public.analytics_platform_totals(date, date) to authenticated;
