-- Local stand-ins for the Supabase roles and auth helpers.
-- The hosted project already has these. This file is only for the SQL test.

do $$
begin
    if not exists (select 1 from pg_roles where rolname = 'anon') then
        create role anon nologin;
    end if;
    if not exists (select 1 from pg_roles where rolname = 'authenticated') then
        create role authenticated nologin;
    end if;
end $$;

grant anon to current_user;
grant authenticated to current_user;
grant usage on schema public to anon, authenticated;

create schema if not exists auth;

create table if not exists auth.users (
    id uuid primary key,
    email text
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

create or replace function auth.jwt()
returns jsonb
language sql
stable
as $$
    select coalesce(nullif(current_setting('request.jwt.claim', true), '')::jsonb, '{}'::jsonb);
$$;
