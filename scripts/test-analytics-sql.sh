#!/bin/sh
# Applies the migrations to a throwaway database and runs the analytics,
# platform, and delete-my-data checks. Does not touch a hosted Supabase project.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
db=${PAPER_GLIDE_TEST_DB:-paper_glide_m8_test}
psql=${PSQL:-psql}

if ! command -v "$psql" >/dev/null 2>&1; then
    echo "psql is not installed." >&2
    exit 1
fi

run_psql() {
    if "$psql" -d postgres -c 'select 1' >/dev/null 2>&1; then
        "$psql" "$@"
    else
        sudo -u postgres "$psql" "$@"
    fi
}

run_psql -d postgres -v ON_ERROR_STOP=1 -c "drop database if exists ${db};"
run_psql -d postgres -v ON_ERROR_STOP=1 -c "create database ${db};"
run_psql -d "$db" -v ON_ERROR_STOP=1 -f "$root/supabase/tests/harness.sql"
run_psql -d "$db" -v ON_ERROR_STOP=1 -f "$root/supabase/migrations/20261109190000_accounts_leaderboards.sql"
run_psql -d "$db" -v ON_ERROR_STOP=1 -f "$root/supabase/migrations/20261110160000_analytics.sql"
run_psql -d "$db" -v ON_ERROR_STOP=1 -f "$root/supabase/migrations/20261125190000_delete_and_platform.sql"
run_psql -d "$db" -v ON_ERROR_STOP=1 -f "$root/supabase/tests/analytics_m4.sql"
run_psql -d "$db" -v ON_ERROR_STOP=1 -f "$root/supabase/tests/delete_and_platform.sql"
echo "analytics SQL tests passed"
