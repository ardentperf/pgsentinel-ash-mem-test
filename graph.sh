#!/usr/bin/env bash
# graph.sh
#
# Generates graphs from existing measurement data files.
# Run this independently of the measurement scripts to iterate on graph formatting.
#
# Usage: bash graph.sh

set -euo pipefail

RESULTS_SHMEM=ash-shmem-results.dat
RESULTS_QSIZE=ash-querysize-results.dat
GRAPH_SHMEM=ash-shmem.png
GRAPH_QSIZE=ash-querysize.png

# Graph 1: ASH memory vs max_entries
echo "==> Generating $GRAPH_SHMEM..."
GP=$(mktemp /tmp/gnuplot_XXXXXX.gp)
cat > "$GP" <<'GPEOF'
set terminal pngcairo size 900,500 font "Sans,10"
set output "ash-shmem.png"
set title "pgsentinel ASH memory usage (MB) vs max_entries\n(pgsentinel_pgssh.enable=off, shared_buffers=128kB)" noenhanced
set xlabel "pgsentinel_ash.max_entries" noenhanced
unset ylabel
set grid
set key top left
set xtics 10000
set yrange [0:]
set format y "%.0f MB"
MB = 1048576.0
plot "ash-shmem-results.dat" using 1:($2/MB) with linespoints pointtype 7 pointsize 1.2 linewidth 2 linecolor rgb "#0072B2" title "pg_shmem_allocations (ASH entries)" noenhanced, \
     "ash-shmem-results.dat" using 1:($3/MB) with linespoints pointtype 5 pointsize 1.2 linewidth 2 linecolor rgb "#009E73" title "cgroup memory.stat shmem (pgnodemx)" noenhanced
GPEOF
gnuplot "$GP"
rm "$GP"

# Graph 2: ASH memory vs track_activity_query_size
echo "==> Generating $GRAPH_QSIZE..."
GP=$(mktemp /tmp/gnuplot_XXXXXX.gp)
cat > "$GP" <<'GPEOF'
set terminal pngcairo size 900,500 font "Sans,10"
set output "ash-querysize.png"
set title "pgsentinel ASH memory usage (MB) vs track_activity_query_size\n(pgsentinel_ash.max_entries=1000, pgsentinel_pgssh.enable=off, shared_buffers=128kB)" noenhanced
set xlabel "track_activity_query_size (bytes)" noenhanced
unset ylabel
set grid
set key top left
set xtics 512
set xtics rotate by -45
set yrange [0:]
set format y "%.0f MB"
MB = 1048576.0
plot "ash-querysize-results.dat" using 1:($2/MB) with linespoints pointtype 7 pointsize 1.2 linewidth 2 linecolor rgb "#0072B2" title "pg_shmem_allocations (ASH entries)" noenhanced, \
     "ash-querysize-results.dat" using 1:($3/MB) with linespoints pointtype 5 pointsize 1.2 linewidth 2 linecolor rgb "#009E73" title "cgroup memory.stat shmem (pgnodemx)" noenhanced
GPEOF
gnuplot "$GP"
rm "$GP"

echo "==> Done."
echo "    $GRAPH_SHMEM"
echo "    $GRAPH_QSIZE"
