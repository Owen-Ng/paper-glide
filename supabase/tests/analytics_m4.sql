-- Analytics checks. Raises if a locked rule fails.
-- Assumes harness.sql, the M3 migration, and the M4 migration have been applied.

do $$
declare
    player uuid := '11111111-1111-4111-8111-111111111111';
    other uuid := '22222222-2222-4222-8222-222222222222';
    glide_session uuid := '33333333-3333-4333-8333-333333333333';
    batch_one uuid := '44444444-4444-4444-8444-444444444444';
    batch_two uuid := '55555555-5555-4555-8555-555555555555';
    batch_hijack uuid := '66666666-6666-4666-8666-666666666666';
    report_id uuid := '77777777-7777-4777-8777-777777777777';
    old_report uuid := '88888888-8888-4888-8888-888888888888';
    run_id uuid := '99999999-9999-4999-8999-999999999999';
    dst_session uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
    spring_session uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2';
    result jsonb;
    sessions bigint;
    crashes bigint;
    click_raw bigint;
    click_roll bigint;
    landed date;
    landed_week date;
    forbidden text;
    avg_event numeric;
    avg_session numeric;
    avg_presence numeric;
    avg_rollup numeric;
    week_bytes numeric;
    kept_reports bigint;
    kept_runs bigint;
    kept_profiles bigint;
    kept_rollups bigint;
begin
    insert into auth.users (id, email) values (player, null);
    insert into auth.users (id, email) values (other, 'other@example.com');
    insert into public.runs (id, user_id, score, duration_seconds, played_at)
    values (run_id, player, 3, 12, timestamptz '2026-07-15 16:00:00+00');

    perform set_config('request.jwt.claim.sub', player::text, true);
    perform set_config('request.jwt.claim', '{"role":"authenticated"}', true);
    set local role authenticated;

    result := public.submit_analytics_batch(batch_one, jsonb_build_array(
        jsonb_build_object(
            'id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1',
            'kind', 'session_start',
            'occurred_at', '2026-07-16T03:30:00Z',
            'session_id', glide_session,
            'app_version', '1.0 (1)',
            'ios_version', '18.0',
            'device_model', 'iPhone16,1'
        ),
        jsonb_build_object(
            'id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
            'kind', 'click',
            'occurred_at', '2026-07-16T03:30:00Z',
            'session_id', glide_session,
            'page', 'start',
            'control', 'play',
            'count', 2
        ),
        jsonb_build_object(
            'id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3',
            'kind', 'click',
            'occurred_at', '2026-07-16T03:31:00Z',
            'session_id', glide_session,
            'page', 'playing',
            'control', 'flap',
            'count', 10
        ),
        jsonb_build_object(
            'id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4',
            'kind', 'click',
            'occurred_at', '2026-07-16T03:32:00Z',
            'session_id', glide_session,
            'page', 'leaderboard',
            'control', 'Today',
            'count', 1
        ),
        jsonb_build_object(
            'id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5',
            'kind', 'click',
            'occurred_at', '2026-07-16T03:33:00Z',
            'session_id', glide_session,
            'page', 'leaderboard',
            'control', 'scroll',
            'count', 1
        ),
        jsonb_build_object(
            'id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb6',
            'kind', 'click',
            'occurred_at', '2026-07-16T03:34:00Z',
            'session_id', glide_session,
            'page', 'start',
            'control', 'not-a-control',
            'count', 9
        ),
        jsonb_build_object(
            'id', report_id,
            'kind', 'report',
            'occurred_at', '2026-07-16T03:35:00Z',
            'session_id', glide_session,
            'category', 'Something looks wrong',
            'text', 'the sky flickered',
            'app_version', '1.0 (1)',
            'ios_version', '18.0',
            'device_model', 'iPhone16,1'
        )
    ));
    if result ->> 'result' is distinct from 'stored' then
        raise exception 'batch was not stored: %', result;
    end if;

    result := public.submit_analytics_batch(batch_one, '[]'::jsonb);
    if result ->> 'result' is distinct from 'duplicate' then
        raise exception 'retried batch was not a duplicate: %', result;
    end if;

    result := public.submit_analytics_batch(batch_two, jsonb_build_array(
        jsonb_build_object(
            'id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb7',
            'kind', 'crash',
            'occurred_at', '2026-07-16T03:40:00Z',
            'session_id', glide_session,
            'crash_kind', 'unclean_exit',
            'crash_summary', 'unclean exit',
            'app_version', '1.0 (1)',
            'ios_version', '18.0',
            'device_model', 'iPhone16,1'
        ),
        jsonb_build_object(
            'id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb8',
            'kind', 'crash',
            'occurred_at', '2026-07-16T03:41:00Z',
            'session_id', glide_session,
            'crash_kind', 'metrickit',
            'crash_summary', 'signal 11 exception 1/0',
            'crash_details', 'call stack',
            'app_version', '1.0 (1)',
            'ios_version', '18.0',
            'device_model', 'iPhone16,1'
        )
    ));
    if result ->> 'result' is distinct from 'stored' then
        raise exception 'crash batch was not stored: %', result;
    end if;

    reset role;
    perform set_config('request.jwt.claim.sub', other::text, true);
    set local role authenticated;
    perform public.submit_analytics_batch(batch_hijack, jsonb_build_array(
        jsonb_build_object(
            'id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb9',
            'kind', 'crash',
            'occurred_at', '2026-07-16T03:42:00Z',
            'session_id', glide_session,
            'crash_kind', 'metrickit',
            'crash_summary', 'hijack',
            'app_version', '1.0',
            'ios_version', '18.0',
            'device_model', 'iPhone'
        )
    ));
    reset role;

    if exists (
        select 1 from public.analytics_events where account_id <> player
    ) then
        raise exception 'an account wrote an event for someone else';
    end if;
    if exists (
        select 1 from public.analytics_sessions
        where id = glide_session and account_id <> player
    ) then
        raise exception 'session owner changed';
    end if;
    if exists (
        select 1 from public.crash_diagnostics
        where id = glide_session and (account_id <> player or summary = 'hijack')
    ) then
        raise exception 'crash diagnostic was overwritten';
    end if;
    if exists (
        select 1 from public.analytics_events where event_type = 'report' or event_type = 'click' and page = 'not-a-control'
    ) then
        raise exception 'report body or unknown click landed in raw events';
    end if;
    if exists (
        select 1 from public.analytics_events where id::text || coalesce(page, '') || coalesce(control, '') like '%flickered%'
    ) then
        raise exception 'report text landed in an event';
    end if;

    select toronto_day into landed from public.analytics_sessions where id = glide_session;
    if landed is distinct from date '2026-07-15' then
        raise exception '23:30 Toronto session landed on %', landed;
    end if;
    landed_week := date_trunc('week', landed::timestamp)::date;
    if landed_week is distinct from date '2026-07-13' then
        raise exception '23:30 Toronto week was %', landed_week;
    end if;

    select count(*) into sessions from public.analytics_sessions where id = glide_session and ended_in_crash;
    if sessions <> 1 then
        raise exception 'session crash flag was %', sessions;
    end if;
    select value into crashes
    from public.analytics_daily_rollups
    where day = date '2026-07-15' and kind = 'crashes';
    if crashes is distinct from 1 then
        raise exception 'crash rollup counted %', crashes;
    end if;
    select value into sessions
    from public.analytics_daily_rollups
    where day = date '2026-07-15' and kind = 'sessions';
    if sessions is distinct from 1 then
        raise exception 'session rollup counted %', sessions;
    end if;

    select coalesce(sum(count), 0) into click_raw
    from public.analytics_events where event_type = 'click';
    select coalesce(sum(value), 0) into click_roll
    from public.analytics_daily_rollups where kind = 'clicks';
    if click_raw is distinct from click_roll or click_raw is distinct from 14 then
        raise exception 'click rollup % did not match raw %', click_roll, click_raw;
    end if;

    if (select body from public.player_reports where id = report_id) is distinct from 'the sky flickered' then
        raise exception 'player report was not stored once';
    end if;
    if (select count(*) from public.player_reports where id = report_id) <> 1 then
        raise exception 'player report was duplicated';
    end if;

    -- DST boundaries: repeated hour stays on Nov 1, spring gap stays on Mar 8.
    perform set_config('request.jwt.claim.sub', player::text, true);
    set local role authenticated;
    perform public.submit_analytics_batch('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaa10', jsonb_build_array(
        jsonb_build_object(
            'id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb10',
            'kind', 'session_start',
            'occurred_at', '2026-11-01T06:30:00Z',
            'session_id', dst_session,
            'app_version', '1.0',
            'ios_version', '18.0',
            'device_model', 'iPhone'
        ),
        jsonb_build_object(
            'id', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb11',
            'kind', 'session_start',
            'occurred_at', '2026-03-08T07:30:00Z',
            'session_id', spring_session,
            'app_version', '1.0',
            'ios_version', '18.0',
            'device_model', 'iPhone'
        )
    ));
    reset role;
    if (select toronto_day from public.analytics_sessions where id = dst_session) is distinct from date '2026-11-01' then
        raise exception 'fall-back session left November 1';
    end if;
    if date_trunc('week', (select toronto_day from public.analytics_sessions where id = dst_session)::timestamp)::date
        is distinct from date '2026-10-26' then
        raise exception 'fall-back week was not the Monday of Oct 26';
    end if;
    if (select toronto_day from public.analytics_sessions where id = spring_session) is distinct from date '2026-03-08' then
        raise exception 'spring-forward session left March 8';
    end if;
    if date_trunc('week', (select toronto_day from public.analytics_sessions where id = spring_session)::timestamp)::date
        is distinct from date '2026-03-02' then
        raise exception 'spring-forward week was not March 2';
    end if;

    insert into public.analytics_admins (email) values ('owen@example.com');

    perform set_config('request.jwt.claim.sub', other::text, true);
    perform set_config('request.jwt.claim', '{"email":"stranger@example.com","role":"authenticated"}', true);
    set local role authenticated;
    result := public.analytics_summary(date '2026-07-01', date '2026-07-31');
    reset role;
    forbidden := result::text;
    if result ->> 'error' is distinct from 'forbidden' or forbidden like '%"dau"%' or forbidden like '%"crashes"%' then
        raise exception 'non-allowlisted login saw data: %', result;
    end if;

    perform set_config('request.jwt.claim.sub', player::text, true);
    perform set_config('request.jwt.claim', '{"role":"authenticated"}', true);
    set local role authenticated;
    result := public.analytics_summary(date '2026-07-15', date '2026-07-15');
    reset role;
    if result ->> 'error' is distinct from 'forbidden' then
        raise exception 'anonymous game account was treated as an admin: %', result;
    end if;

    perform set_config('request.jwt.claim.sub', other::text, true);
    perform set_config('request.jwt.claim', '{"email":"Owen@Example.com","role":"authenticated"}', true);
    set local role authenticated;
    result := public.analytics_summary(date '2020-01-01', date '2020-01-07');
    if result ->> 'ok' is distinct from 'true'
        or (result ->> 'sessions')::bigint <> 0
        or (result ->> 'crashes')::bigint <> 0
        or result -> 'crash_free' is distinct from 'null'::jsonb
    then
        raise exception 'empty range was not zeros and a null crash-free: %', result;
    end if;
    result := public.analytics_series(date '2020-01-01', date '2020-01-07', 'day', 'active');
    if result ->> 'ok' is distinct from 'true' or jsonb_array_length(result -> 'buckets') <> 7 then
        raise exception 'empty series failed: %', result;
    end if;
    if exists (
        select 1 from jsonb_array_elements(result -> 'buckets') bucket
        where (bucket ->> 'count')::bigint <> 0
    ) then
        raise exception 'empty series had a count';
    end if;
    result := public.analytics_clicks(date '2020-01-01', date '2020-01-07');
    if result ->> 'ok' is distinct from 'true' then
        raise exception 'empty clicks failed: %', result;
    end if;
    result := public.analytics_reports(date '2020-01-01', date '2020-01-07', 'all', null, null);
    if (result -> 'counts' ->> 'all')::bigint <> 0 then
        raise exception 'empty reports were not zero: %', result;
    end if;

    result := public.analytics_series(date '2026-07-15', date '2026-07-15', 'day', 'active');
    if (result -> 'buckets' -> 0 ->> 'start') is distinct from '2026-07-15'
        or (result -> 'buckets' -> 0 ->> 'count')::bigint <> 1
    then
        raise exception 'July 15 bucket missed the 23:30 session: %', result;
    end if;
    result := public.analytics_series(date '2026-07-13', date '2026-07-19', 'week', 'active');
    if (result -> 'buckets' -> 0 ->> 'start') is distinct from '2026-07-13' then
        raise exception 'week bucket did not start Monday: %', result;
    end if;
    result := public.analytics_series(date '2026-07-01', date '2026-07-31', 'month', 'crashes');
    if (result -> 'buckets' -> 0 ->> 'start') is distinct from '2026-07-01'
        or (result -> 'buckets' -> 0 ->> 'count')::bigint <> 1
    then
        raise exception 'month crash bucket was wrong: %', result;
    end if;

    result := public.analytics_summary(date '2026-07-15', date '2026-07-15');
    if (result ->> 'sessions')::bigint <> 1 or (result ->> 'crashes')::bigint <> 1 or (result ->> 'crash_free')::int <> 0 then
        raise exception 'summary did not match the raw session: %', result;
    end if;
    reset role;
    perform set_config('request.jwt.claim.sub', player::text, true);
    perform set_config('request.jwt.claim', '{"role":"authenticated"}', true);
    set local role authenticated;
    result := public.analytics_delete_report(old_report, 'player');
    reset role;
    if result ->> 'error' is distinct from 'forbidden' then
        raise exception 'a player deleted a report: %', result;
    end if;

    perform set_config('request.jwt.claim.sub', other::text, true);
    perform set_config('request.jwt.claim', '{"email":"owen@example.com","role":"authenticated"}', true);
    set local role authenticated;
    result := public.analytics_delete_report(report_id, 'player');
    reset role;
    if result ->> 'result' is distinct from 'deleted' then
        raise exception 'owner delete failed: %', result;
    end if;
    if exists (select 1 from public.player_reports where id = report_id) then
        raise exception 'deleted report came back';
    end if;

    insert into public.player_reports (
        id, account_id, category, body, created_at
    )
    values (
        old_report, player, 'I have an idea', 'keep me', now() - interval '200 days'
    );
    update public.analytics_events
    set occurred_at = now() - interval '91 days'
    where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2';
    update public.crash_diagnostics
    set occurred_at = now() - interval '91 days'
    where id = glide_session;
    update public.analytics_sessions
    set started_at = now() - interval '91 days'
    where id = spring_session;

    perform public.analytics_cleanup_raw();

    if exists (
        select 1 from public.analytics_events where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'
    ) then
        raise exception 'cleanup left a raw event older than 90 days';
    end if;
    if exists (select 1 from public.crash_diagnostics where id = glide_session) then
        raise exception 'cleanup left a crash diagnostic older than 90 days';
    end if;
    if exists (select 1 from public.analytics_sessions where id = spring_session) then
        raise exception 'cleanup left an old session';
    end if;
    if not exists (select 1 from public.player_reports where id = old_report) then
        raise exception 'cleanup deleted a player report';
    end if;
    select count(*) into kept_rollups from public.analytics_daily_rollups where kind = 'clicks';
    if kept_rollups = 0 then
        raise exception 'cleanup deleted click rollups';
    end if;
    select count(*) into kept_runs from public.runs;
    select count(*) into kept_profiles from public.profiles;
    select count(*) into kept_reports from public.player_reports where id = old_report;
    if kept_runs <> 1 or kept_profiles < 1 or kept_reports <> 1 then
        raise exception 'cleanup touched M3 rows or reports (runs %, profiles %, reports %)', kept_runs, kept_profiles, kept_reports;
    end if;
    if not exists (
        select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname = 'claim_username'
    ) then
        raise exception 'claim_username is missing';
    end if;

    perform set_config('request.jwt.claim.sub', player::text, true);
    set local role authenticated;
    result := public.claim_username('pilot');
    reset role;
    if result ->> 'username' is distinct from 'pilot' then
        raise exception 'M3 claim_username broke: %', result;
    end if;

    begin
        set local role authenticated;
        insert into public.analytics_events (
            id, batch_id, account_id, event_type, occurred_at
        )
        values (
            'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
            batch_one,
            player,
            'click',
            now()
        );
        raise exception 'authenticated insert into analytics_events was allowed';
    exception
        when insufficient_privilege then
            reset role;
    end;

    select avg(pg_column_size(e.*)) into avg_event from public.analytics_events e;
    select avg(pg_column_size(s.*)) into avg_session from public.analytics_sessions s;
    select avg(pg_column_size(a.*)) into avg_presence from public.analytics_daily_accounts a;
    select avg(pg_column_size(r.*)) into avg_rollup from public.analytics_daily_rollups r;
    -- 30 accounts, 4 sessions a day, 9 stored events each (session + up to 8 click buckets).
    week_bytes := (30 * 7 * 4 * 9) * coalesce(avg_event, 0)
        + (30 * 7 * 4) * coalesce(avg_session, 0)
        + (30 * 7) * coalesce(avg_presence, 0)
        + (40 * 7) * coalesce(avg_rollup, 0);
    raise notice 'STORAGE avg_event=% avg_session=% avg_presence=% avg_rollup=% test_week_bytes=% free_tier_bytes=% week_percent=%',
        round(avg_event, 1),
        round(avg_session, 1),
        round(avg_presence, 1),
        round(avg_rollup, 1),
        round(week_bytes),
        500 * 1024 * 1024,
        round((week_bytes / (500 * 1024 * 1024)) * 100, 4);
end $$;
