#!/usr/bin/env python3
# max-connections-table.py
#
# Calculates the maximum max_connections that keeps the pgsentinel ASH buffer
# at or under 10% of total RAM while retaining 2 minutes of data at 1 sample/sec
# with all connections active.
#
# Prints two tables:
#   1. By RAM size (default track_activity_query_size=1024)
#   2. By track_activity_query_size at 4GB RAM
#
# Formula: bytes/entry      = 896 + 2 * track_activity_query_size
#          max_connections  = floor(RAM * RAM_FRACTION / (bytes_per_entry * RETENTION_SEC))

RETENTION_SEC        = 120   # 2 minutes at 1 sample/sec
RAM_FRACTION         = 0.10  # ASH buffer target: at most 10% of total RAM
DEFAULT_QUERY_SIZE   = 1024  # default track_activity_query_size
FIXED_OVERHEAD_BYTES = 896   # sizeof(ashEntry) + 12 * NAMEDATALEN

def bytes_per_entry(query_size):
    return FIXED_OVERHEAD_BYTES + 2 * query_size

def max_connections(ram_bytes, bpe):
    limit_bytes = ram_bytes * RAM_FRACTION
    max_entries = int(limit_bytes / bpe)
    return int(max_entries / RETENTION_SEC), max_entries

print(f"Assumptions:")
print(f"  retention:        {RETENTION_SEC}s (2 min @ 1 sample/sec, all connections active)")
print(f"  ASH buffer limit: {RAM_FRACTION*100:.0f}% of total RAM")
print()

# Table 1: by RAM, default track_activity_query_size
bpe = bytes_per_entry(DEFAULT_QUERY_SIZE)
print(f"Table 1: by RAM (track_activity_query_size={DEFAULT_QUERY_SIZE}, bytes/entry={bpe:,})")
print()
print(f"{'RAM':>6}  {'10% limit':>10}  {'max_entries':>12}  {'max_connections':>16}")
print("-" * 50)
for ram_gb in [1, 2, 4, 8, 16]:
    ram_bytes = ram_gb * 1024**3
    max_conn, max_entries = max_connections(ram_bytes, bpe)
    limit_mb = ram_bytes * RAM_FRACTION / 1024**2
    print(f"{ram_gb:>4}G  {limit_mb:>8.0f}MB  {max_entries:>12,}  {max_conn:>16,}")

print()

# Table 2: by track_activity_query_size, fixed 4GB RAM
ram_gb = 4
ram_bytes = ram_gb * 1024**3
print(f"Table 2: by track_activity_query_size ({ram_gb}GB RAM)")
print()
print(f"{'query_size':>12}  {'bytes/entry':>12}  {'max_entries':>12}  {'max_connections':>16}")
print("-" * 58)
for qsize in range(512, 5121, 512):
    bpe = bytes_per_entry(qsize)
    max_conn, max_entries = max_connections(ram_bytes, bpe)
    print(f"{qsize:>11}B  {bpe:>12,}  {max_entries:>12,}  {max_conn:>16,}")
