-- Delete-my-data and platform checks. Raises if a locked rule fails.
-- Assumes harness.sql and the three migrations have been applied.
-- Does not connect to a hosted Supabase project.

do $$
declare
    ios_user uuid := 'd1111111-1111-4111-8111-111111111111';
    android_user uuid := 'd2222222-2222-4222-8222-222222222222';
    caller uuid := 'd3333333-3333-4333-8333-333333333333';
    other uuid := 'd4444444-4444-4444-8444-444444444444';
    ios_run uuid := 'd5555555-5555-4555-8555-555555555555';
    android_run uuid := 'd6666666-6666-4666-8666-666666666666';
    bad_run uuid := 'd7777777-7777-4777-8777-777777777777';
    caller_run uuid := 'd8888888-8888-4888-8888-888888888888';
    other_run uuid := 'd9999999-9999-4999-8999-999999999999';
    ios_batch uuid := 'daaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1';
    caller_batch uuid := 'daaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2';
    other_batch uuid := 'daaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3';
    ios_event uuid := 'dbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb1';
    android_event uuid := 'dbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2';
    skipped_event uuid := 'dbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb3';
    caller_event uuid := 'dbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb4';
    other_event uuid := 'dbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb5';
    caller_report uuid := 'dccccccc-cccc-4ccc-8ccc-ccccccccccc1';
    other_report uuid := 'dccccccc-cccc-4ccc-8ccc-ccccccccccc2';
    result jsonb;
    today date := date '2099-01-15';
    occurred timestamptz := timestamptz '2099-01-15 18:00:00+00';
    ios_sessions bigint;
    android_sessions bigint;
    all_sessions bigint;
    ios_flaps bigint;
    android_flaps bigint;
    args text;
    definer boolean;
    config text[];
begin
    insert into auth.users (id) values (ios_user), (android_user), (caller), (other);
    update public.profiles set username = 'pilot_ios' where id = ios_user;
    update public.profiles set username = 'pilot_droid' where id = android_user;
    update public.profiles set username = 'caller_name' where id = caller;
    update public.profiles set username = 'other_name' where id = other;

    perform set_config('request.jwt.claim.sub', ios_user::text, true);
    set local role authenticated;
    result := public.submit_run(bad_run, 3, 12, now(), 'web');
    reset role;
    if result ->> 'error' is distinct from 'rejected' then
        raise exception 'unknown platform was not rejected: %', result;
    end if;
    if exists (select 1 from public.runs where id = bad_run) then
        raise exception 'rejected platform was stored';
    end if;
    set local role authenticated;
    result := public.submit_run(ios_run, 3, 12, now());
    reset role;
    if result ->> 'result' is distinct from 'stored' then
        raise exception 'default platform submit failed: %', result;
    end if;

    perform set_config('request.jwt.claim.sub', android_user::text, true);
    set local role authenticated;
    result := public.submit_run(android_run, 4, 12, now(), 'android');
    if result ->> 'result' is distinct from 'stored' then
        raise exception 'android submit failed: %', result;
    end if;
    reset role;

    if (select platform from public.runs where id = ios_run) is distinct from 'ios' then
        raise exception 'omitted platform did not default to ios';
    end if;
    if (select platform from public.runs where id = android_run) is distinct from 'android' then
        raise exception 'android run was not stored as android';
    end if;

    begin
        insert into public.runs (id, user_id, score, duration_seconds, played_at, platform)
        values ('deeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', ios_user, 1, 4, now(), 'web');
        raise exception 'runs accepted platform web';
    exception
        when check_violation then
            null;
    end;

    perform set_config('request.jwt.claim.sub', ios_user::text, true);
    set local role authenticated;
    result := public.submit_analytics_batch(ios_batch, jsonb_build_array(
        jsonb_build_object(
            'id', 'dbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb10',
            'kind', 'session_start',
            'occurred_at', occurred,
            'session_id', 'dccccccc-cccc-4ccc-8ccc-cccccccccc10',
            'app_version', '1.0',
            'ios_version', '18.0',
            'device_model', 'iPhone'
        ),
        jsonb_build_object(
            'id', ios_event,
            'kind', 'click',
            'occurred_at', occurred,
            'page', 'playing',
            'control', 'flap',
            'count', 4
        ),
        jsonb_build_object(
            'id', android_event,
            'kind', 'click',
            'occurred_at', occurred,
            'page', 'playing',
            'control', 'flap',
            'count', 7,
            'platform', 'android'
        ),
        jsonb_build_object(
            'id', skipped_event,
            'kind', 'click',
            'occurred_at', occurred,
            'page', 'playing',
            'control', 'flap',
            'count', 9,
            'platform', 'web'
        ),
        jsonb_build_object(
            'id', 'dbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbb11',
            'kind', 'session_start',
            'occurred_at', occurred,
            'session_id', 'dccccccc-cccc-4ccc-8ccc-cccccccccc11',
            'platform', 'android',
            'app_version', '1.0',
            'ios_version', '16',
            'device_model', 'Pixel'
        )
    ));
    reset role;
    if result ->> 'result' is distinct from 'stored' then
        raise exception 'platform batch was not stored: %', result;
    end if;
    if (select platform from public.analytics_events where id = ios_event) is distinct from 'ios' then
        raise exception 'event without platform was not ios';
    end if;
    if (select platform from public.analytics_events where id = android_event) is distinct from 'android' then
        raise exception 'android event was not stored';
    end if;
    if exists (select 1 from public.analytics_events where id = skipped_event) then
        raise exception 'unknown event platform was stored';
    end if;

    select coalesce(sum(value), 0) into ios_flaps
    from public.analytics_daily_rollups
    where day = today and kind = 'clicks' and page = 'playing' and control = 'flap' and platform = 'ios';
    select coalesce(sum(value), 0) into android_flaps
    from public.analytics_daily_rollups
    where day = today and kind = 'clicks' and page = 'playing' and control = 'flap' and platform = 'android';
    if ios_flaps <> 4 or android_flaps <> 7 then
        raise exception 'platform click rollups were ios % android %', ios_flaps, android_flaps;
    end if;

    perform set_config('request.jwt.claim.sub', other::text, true);
    perform set_config('request.jwt.claim', '{"email":"owen@example.com","role":"authenticated"}', true);
    insert into public.analytics_admins (email) values ('owen@example.com')
    on conflict (email) do nothing;
    set local role authenticated;
    result := public.analytics_summary(today, today, 'ios');
    ios_sessions := (result ->> 'sessions')::bigint;
    result := public.analytics_summary(today, today, 'android');
    android_sessions := (result ->> 'sessions')::bigint;
    result := public.analytics_summary(today, today);
    all_sessions := (result ->> 'sessions')::bigint;
    if ios_sessions <> 1 or android_sessions <> 1 or all_sessions <> ios_sessions + android_sessions then
        raise exception 'platform summary sessions ios % android % all %', ios_sessions, android_sessions, all_sessions;
    end if;
    result := public.analytics_clicks(today, today, 'day', 'android');
    if (
        select (control ->> 'count')::bigint
        from jsonb_array_elements(result -> 'pages') page
        cross join lateral jsonb_array_elements(page -> 'controls') control
        where page ->> 'page' = 'playing' and control ->> 'control' = 'flap'
    ) is distinct from 7 then
        raise exception 'android click filter was not 7: %', result;
    end if;
    result := public.analytics_summary(today, today, 'web');
    reset role;
    if result ->> 'error' is distinct from 'invalid' then
        raise exception 'unknown platform filter was accepted: %', result;
    end if;

    insert into public.runs (id, user_id, score, duration_seconds, played_at, platform)
    values (caller_run, caller, 2, 8, now(), 'ios'),
           (other_run, other, 6, 10, now(), 'android');
    insert into public.analytics_batches (id, account_id) values (caller_batch, caller), (other_batch, other);
    insert into public.analytics_events (id, batch_id, account_id, event_type, occurred_at, platform)
    values (caller_event, caller_batch, caller, 'click', now(), 'ios'),
           (other_event, other_batch, other, 'click', now(), 'android');
    insert into public.player_reports (id, account_id, category, body)
    values (caller_report, caller, 'Something else', 'mine'),
           (other_report, other, 'Something else', 'theirs');

    perform set_config('request.jwt.claim.sub', '', true);
    set local role authenticated;
    result := public.delete_my_data();
    reset role;
    if result ->> 'ok' is distinct from 'false' or result ->> 'error' is distinct from 'unauthenticated' then
        raise exception 'unauthenticated delete did not fail: %', result;
    end if;
    if not exists (select 1 from public.profiles where id = caller) then
        raise exception 'unauthenticated delete removed the caller';
    end if;

    begin
        set local role anon;
        perform public.delete_my_data();
        raise exception 'anon executed delete_my_data';
    exception
        when insufficient_privilege then
            reset role;
    end;

    begin
        set local role authenticated;
        delete from public.runs where id = other_run;
        raise exception 'authenticated delete of runs was allowed';
    exception
        when insufficient_privilege then
            reset role;
    end;

    perform set_config('request.jwt.claim.sub', caller::text, true);
    perform set_config('request.jwt.claim', '{"role":"authenticated"}', true);
    set local role authenticated;
    result := public.delete_my_data();
    reset role;
    if result ->> 'result' is distinct from 'deleted' then
        raise exception 'caller delete failed: %', result;
    end if;

    if exists (select 1 from public.profiles where id = caller)
        or exists (select 1 from public.runs where user_id = caller or id = caller_run)
        or exists (select 1 from public.analytics_events where account_id = caller or id = caller_event)
        or exists (select 1 from public.player_reports where account_id = caller or id = caller_report)
        or exists (select 1 from public.analytics_batches where account_id = caller)
        or exists (select 1 from auth.users where id = caller)
    then
        raise exception 'caller rows survived delete_my_data';
    end if;
    if not exists (select 1 from public.profiles where id = other and username = 'other_name')
        or not exists (select 1 from public.runs where id = other_run and user_id = other and platform = 'android')
        or not exists (select 1 from public.analytics_events where id = other_event and account_id = other)
        or not exists (select 1 from public.player_reports where id = other_report and body = 'theirs')
        or not exists (select 1 from auth.users where id = other)
    then
        raise exception 'another user was touched by delete_my_data';
    end if;

    select p.prosecdef, p.proconfig, pg_get_function_identity_arguments(p.oid)
    into definer, config, args
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'delete_my_data';
    if definer is not true or args <> '' or not ('search_path=public' = any(config)) then
        raise exception 'delete_my_data contract changed (definer %, args %, config %)', definer, args, config;
    end if;
    if has_function_privilege('anon', 'public.delete_my_data()', 'execute') then
        raise exception 'anon can execute delete_my_data';
    end if;
    if not has_function_privilege('authenticated', 'public.delete_my_data()', 'execute') then
        raise exception 'authenticated cannot execute delete_my_data';
    end if;
    if (
        select count(*)
        from pg_class c
        join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname in ('profiles', 'runs', 'analytics_events', 'player_reports')
          and c.relrowsecurity
    ) <> 4 then
        raise exception 'RLS is not enabled on the deleted tables';
    end if;
end $$;
