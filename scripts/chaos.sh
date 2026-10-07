#!/usr/bin/env bash
# "Break it on purpose": deny api -> redis in the mesh, prove reads keep working from
# Postgres (fail-open cache), then restore the allow and prove the cache recovers.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${BASE:-http://localhost:8000}"
ID="${1:-1}"

show() { curl -s -i "$BASE/items/$ID" | grep -iE '^HTTP/|^x-cache|^x-instance|"source"' | sed 's/^/    /'; }

echo "== baseline (expect HIT or MISS)"; show

echo "== deny api -> redis"
consul config write "$ROOT/consul/chaos/deny-api-to-redis.hcl" > /dev/null
# Intentions apply to NEW connections. Redis closes idle client connections after 10s
# (--timeout 10 in redis.nomad.hcl), so by now the API's pooled connection is gone and
# its next attempt is refused by redis's sidecar.
printf '   waiting 12s for pooled connections to expire'; for _ in $(seq 12); do printf .; sleep 1; done; echo
echo "== read while cache is denied (expect 200, X-Cache: BYPASS, source: db)"; show
echo "== readiness (expect redis: false, postgres: true)"
curl -s "$BASE/ready" | sed 's/^/    /'; echo

echo "== restore api -> redis"
consul config write "$ROOT/consul/config-entries/20-intentions-redis.hcl" > /dev/null
sleep 2
echo "== read after restore (expect HIT: the entry outlived the outage; a MISS first only if the TTL expired)"; show; show
