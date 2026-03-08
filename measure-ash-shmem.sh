#!/usr/bin/env bash
# measure-ash-shmem.sh
#
# Measures pgsentinel ASH shared memory usage at different max_entries values.
# Reports both pg_shmem_allocations (postgres view) and cgroup memory.stat
# (OS view via pgnodemx). Results written to ash-shmem-results.dat.
#
# Prerequisites:
#   docker
#   Images pulled automatically:
#     ghcr.io/cloudnative-pg/postgresql:18-standard-trixie
#     ghcr.io/ardentperf/pgsentinel:1.3.1-18-trixie
#     ghcr.io/ardentperf/pgnodemx-testing:2.0.1-202603060728-18-trixie
#
# Usage: bash measure-ash-shmem.sh

set -euo pipefail

IMAGE=pgsentinel-ash-test
RESULTS=ash-shmem-results.dat

# Build the test image: CNPG postgres + pgsentinel + pgnodemx extension files
echo "==> Building test image..."
docker build --quiet -t "$IMAGE" - <<'EOF'
FROM ghcr.io/ardentperf/pgsentinel:1.3.1-18-trixie AS pgsentinel
FROM ghcr.io/ardentperf/pgnodemx-testing:2.0.1-202603060728-18-trixie AS pgnodemx
FROM ghcr.io/cloudnative-pg/postgresql:18-standard-trixie
COPY --from=pgsentinel /lib/ /usr/lib/postgresql/18/lib/
COPY --from=pgsentinel /share/extension/ /usr/share/postgresql/18/extension/
COPY --from=pgnodemx /lib/ /usr/lib/postgresql/18/lib/
COPY --from=pgnodemx /share/extension/ /usr/share/postgresql/18/extension/
EOF

# Measure ASH memory for a given max_entries value.
# max_entries is written to postgresql.conf so shared memory is sized correctly
# at postmaster startup (GUC must be set before shmem_request_hook runs).
# Returns: pg_ash_bytes cgroup_shmem_bytes
measure() {
    local entries=$1
    docker run --rm -u 26 "$IMAGE" bash -c "
        initdb -D /var/lib/postgresql/data -A trust -U postgres --no-instructions >/dev/null 2>&1
        echo 'pgsentinel_ash.max_entries = $entries' >> /var/lib/postgresql/data/postgresql.conf
        postgres -D /var/lib/postgresql/data \
            -c shared_preload_libraries='pgsentinel,pgnodemx' \
            -c pgsentinel_pgssh.enable=off \
            -c shared_buffers=128kB \
            -c listen_addresses='' >/dev/null 2>&1 &
        sleep 4
        psql -U postgres -c 'CREATE EXTENSION pgnodemx;' >/dev/null 2>&1
        psql -U postgres -tAc \"
            SELECT
                (SELECT sum(size) FROM pg_shmem_allocations WHERE name LIKE 'Ash%') AS pg_ash_bytes,
                (SELECT val FROM cgroup_setof_kv('memory.stat') WHERE key = 'shmem') AS cgroup_shmem_bytes;
        \" 2>/dev/null
    " 2>/dev/null
}

echo "==> Running measurements (max_entries: 10000 to 100000, step 10000)..."
echo "# max_entries  pg_ash_bytes  cgroup_shmem_bytes" > "$RESULTS"
for entries in 10000 20000 30000 40000 50000 60000 70000 80000 90000 100000; do
    row=$(measure "$entries")
    pg_ash=$(echo "$row" | awk -F'|' '{print $1}' | tr -d ' ')
    cg_shmem=$(echo "$row" | awk -F'|' '{print $2}' | tr -d ' ')
    printf "max_entries=%-5s  pg_ash=%s  cgroup_shmem=%s\n" \
        "$entries" "$pg_ash" "$cg_shmem"
    echo "$entries  $pg_ash  $cg_shmem" >> "$RESULTS"
done

echo "==> Done. Results: $RESULTS"
