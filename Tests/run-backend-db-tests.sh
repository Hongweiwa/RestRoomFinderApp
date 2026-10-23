#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Local disposable PostGIS only. No published ports, production credentials or remote database.
TEST_CONTAINER="restroom-foundation-test-$$"
cleanup() { docker rm -f "$TEST_CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT
# PostGIS upstream image is amd64; Docker Desktop emulates it on Apple Silicon.
docker run --detach --rm --name "$TEST_CONTAINER" --platform linux/amd64 \
    -e POSTGRES_PASSWORD=restroom-local-test-only postgis/postgis:17-3.5 >/dev/null
# Wait for the final TCP server, not the temporary Unix-socket initialization server.
for attempt in {1..30}; do
    if docker exec "$TEST_CONTAINER" pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; then break; fi
    sleep 1
done
# template0 avoids the image's preinstalled public-schema PostGIS.
docker exec "$TEST_CONTAINER" createdb -U postgres -T template0 restroom_test
docker exec -i "$TEST_CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d restroom_test < supabase/tests/local_auth_stub.sql
for migration in supabase/migrations/*.sql; do
    docker exec -i "$TEST_CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d restroom_test < "$migration"
done
docker exec -i "$TEST_CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d restroom_test < supabase/tests/backend_foundation.sql
docker exec -i "$TEST_CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d restroom_test < supabase/tests/auth_profiles.sql
docker exec -i "$TEST_CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d restroom_test < supabase/tests/profile_recovery.sql
docker exec -i "$TEST_CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d restroom_test < supabase/tests/favorites.sql

docker exec -i "$TEST_CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d restroom_test < supabase/tests/reviews.sql

docker exec -i "$TEST_CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d restroom_test < supabase/tests/submissions.sql

docker exec -i "$TEST_CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d restroom_test < supabase/tests/reports.sql
bash Tests/run-report-concurrency-tests.sh "$TEST_CONTAINER"
