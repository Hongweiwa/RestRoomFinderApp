#!/bin/bash
set -euo pipefail
# Disposable container only; called by run-backend-db-tests.sh. No hosted connection.
REPORT_TEST_CONTAINER=${1:?Pass the disposable local test container}
REPORT_TEST_OUTPUT=$(mktemp -d "${TMPDIR:-/tmp}/restroom-report-race.XXXXXX")
trap 'rm -rf "$REPORT_TEST_OUTPUT"' EXIT
report_sql() { docker exec -i "$REPORT_TEST_CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d restroom_test "$@"; }
report_sql <<'SQL'
insert into auth.users(id) values ('17900000-0000-0000-0000-000000000001');
insert into public.restrooms(id,name,latitude,longitude,source,verification_status) values
 ('17910000-0000-0000-0000-000000000001','Local race test',40,-73,'admin','verified');
SQL
for report_race in distinct identical; do
    if [ "$report_race" = distinct ]; then
        REPORT_SECOND_REQUEST=17920000-0000-0000-0000-000000000002
        REPORT_ISSUE=incorrect_location
    else
        REPORT_SECOND_REQUEST=17920000-0000-0000-0000-000000000001
        REPORT_ISSUE=incorrect_accessibility
    fi
    report_sql > "$REPORT_TEST_OUTPUT/first.log" 2>&1 <<SQL &
begin;
set application_name='day17-report-holder';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"17900000-0000-0000-0000-000000000001","is_anonymous":false}',true);
insert into public.reports(restroom_id,report_type,client_request_id) values
 ('17910000-0000-0000-0000-000000000001','$REPORT_ISSUE','17920000-0000-0000-0000-000000000001')
on conflict(user_id,client_request_id) do nothing;
select pg_sleep(3);
commit;
SQL
    REPORT_HOLDER_PID=$!
    # Start connection B only once A is sleeping with its report still uncommitted.
    REPORT_HOLDER_READY=false
    for report_attempt in {1..40}; do
        if [ "$(report_sql -Atc "select count(*) from pg_stat_activity where application_name='day17-report-holder' and wait_event='PgSleep'")" = 1 ]; then
            REPORT_HOLDER_READY=true; break
        fi
        sleep 0.05
    done
    if [ "$REPORT_HOLDER_READY" != true ]; then cat "$REPORT_TEST_OUTPUT/first.log"; exit 1; fi
    REPORT_SECOND_EXIT=0
    report_sql --set=VERBOSITY=verbose > "$REPORT_TEST_OUTPUT/second.log" 2>&1 <<SQL || REPORT_SECOND_EXIT=$?
begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"17900000-0000-0000-0000-000000000001","is_anonymous":false}',true);
insert into public.reports(restroom_id,report_type,client_request_id) values
 ('17910000-0000-0000-0000-000000000001','$REPORT_ISSUE','$REPORT_SECOND_REQUEST')
on conflict(user_id,client_request_id) do nothing;
commit;
SQL
    wait "$REPORT_HOLDER_PID"
    if [ "$report_race" = distinct ]; then
        if [ "$REPORT_SECOND_EXIT" = 0 ] || ! rg -q 'P1701' "$REPORT_TEST_OUTPUT/second.log"; then cat "$REPORT_TEST_OUTPUT/second.log"; exit 1; fi
        printf '%s\n' 'PASS: concurrent different request UUIDs serialize; identical issue rejected after first commit'
    else
        if [ "$REPORT_SECOND_EXIT" != 0 ]; then cat "$REPORT_TEST_OUTPUT/second.log"; exit 1; fi
        printf '%s\n' 'PASS: concurrent same request UUID retries are idempotent'
    fi
    if [ "$(report_sql -Atc "select count(*) from public.reports where user_id='17900000-0000-0000-0000-000000000001'")" != 1 ]; then exit 1; fi
    report_sql -c "delete from public.reports where user_id='17900000-0000-0000-0000-000000000001'" >/dev/null
done
