#!/usr/bin/env bash
# Seed the Consul KV keys that the job templates render from (see jobs/*.nomad.hcl).
# Tasks that template a missing key block at startup, so run this before `make deploy`.
set -euo pipefail

consul kv put app/db/user      "${DB_USER:-app}"
consul kv put app/db/password  "${DB_PASSWORD:-app}"
consul kv put app/db/name      "${DB_NAME:-app}"
consul kv put app/cache/ttl    "${CACHE_TTL:-60}"

echo
consul kv get -recurse app/
