#!/usr/bin/env bash
# End-to-end check through the edge -> api -> {redis, postgres} path.
set -euo pipefail

BASE="${BASE:-http://localhost:8000}"
hdr() { grep -iE '^HTTP/|^x-cache|^x-instance|"source"' | sed 's/^/    /'; }

echo "== health";  curl -s -i "$BASE/health" | hdr
echo "== ready";   curl -s "$BASE/ready" | sed 's/^/    /'; echo

echo "== create"
id="$(curl -s -X POST "$BASE/items?name=hello" | jq -r .id)"
echo "    id=$id"

echo "== read #1 (expect X-Cache: MISS, source: db)";    curl -s -i "$BASE/items/$id" | hdr
echo "== read #2 (expect X-Cache: HIT,  source: cache)"; curl -s -i "$BASE/items/$id" | hdr

echo "== update (expect X-Cache: INVALIDATED)"
curl -s -i -X PUT "$BASE/items/$id?name=hello-v2" | hdr
echo "== read #3 (expect MISS with the new name)";       curl -s -i "$BASE/items/$id" | hdr

echo "== 10 reads: watch X-Instance alternate between the two api allocations"
for _ in $(seq 10); do curl -s -i "$BASE/items/$id" | grep -i '^x-instance' | tr -d '\r'; done | sort | uniq -c | sed 's/^/    /'
