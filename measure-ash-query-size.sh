#!/usr/bin/env bash
# measure-ash-query-size.sh
#
# Measures pgsentinel ASH shared memory usage at different track_activity_query_size
# values (pgsentinel_ash.max_entries fixed at 1000).
# Results written to ash-querysize-results.dat.
#
# Prerequisites:
#   docker
#   Images pulled automatically:
#     ghcr.io/cloudnative-pg/postgresql:18-standard-trixie
#     ghcr.io/ardentperf/pgsentinel:1.3.1-18-trixie
#     ghcr.io/ardentperf/pgnodemx-testing:2.0.1-202603060728-18-trixie
#
# Usage: bash measure-ash-query-size.sh

set -euo pipefail

IMAGE=pgsentinel-ash-test
RESULTS=ash-querysize-results.dat
MAX_ENTRIES=1000

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

# Measure ASH memory for a given track_activity_query_size.
# Returns: pg_ash_bytes cgroup_shmem_bytes
measure() {
    local qsize=$1
    docker run --rm -u 26 "$IMAGE" bash -c "
        initdb -D /var/lib/postgresql/data -A trust -U postgres --no-instructions >/dev/null 2>&1
        echo 'pgsentinel_ash.max_entries = $MAX_ENTRIES' >> /var/lib/postgresql/data/postgresql.conf
        postgres -D /var/lib/postgresql/data \
            -c shared_preload_libraries='pgsentinel,pgnodemx' \
            -c pgsentinel_pgssh.enable=off \
            -c track_activity_query_size=$qsize \
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

echo "==> Running measurements (track_activity_query_size: 512 to 5120, step 512)..."
echo "# query_size_bytes  pg_ash_bytes  cgroup_shmem_bytes  bytes_per_entry" > "$RESULTS"
for qsize in 512 1024 1536 2048 2560 3072 3584 4096 4608 5120; do
    row=$(measure "$qsize")
    pg_ash=$(echo "$row" | awk -F'|' '{print $1}' | tr -d ' ')
    cg_shmem=$(echo "$row" | awk -F'|' '{print $2}' | tr -d ' ')
    bpe=$(( pg_ash / MAX_ENTRIES ))
    printf "query_size=%-5s  pg_ash=%s  cgroup_shmem=%s  bytes/entry=%s\n" \
        "$qsize" "$pg_ash" "$cg_shmem" "$bpe"
    echo "$qsize  $pg_ash  $cg_shmem  $bpe" >> "$RESULTS"
done

echo "==> Done. Results: $RESULTS"
