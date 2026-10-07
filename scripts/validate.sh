#!/usr/bin/env bash
# Static-ish validation with throwaway dev agents (no Docker needed): job specs, Consul
# config entries, Python byte-compilation. Safe to run before Docker integration exists.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

started=""
if ! pgrep -x consul > /dev/null; then consul agent -dev -log-level=error > /dev/null 2>&1 & started="$started consul"; fi
if ! pgrep -x nomad  > /dev/null; then nomad agent -dev -log-level=error  > /dev/null 2>&1 & started="$started nomad";  fi
sleep 6

echo "== python"
python3 -m py_compile api/app/*.py && echo ok

echo "== nomad job validate"
for j in postgres redis api edge; do
  printf '%-10s' "$j"; nomad job validate "jobs/$j.nomad.hcl" 2>&1 | tail -1
done

echo "== consul config entries"
for f in consul/config-entries/*.hcl consul/chaos/*.hcl; do consul config write "$f"; done
consul intention list
printf 'api -> redis: '; consul intention check api redis
printf 'edge -> redis: '; consul intention check edge redis

for p in $started; do pkill -x "$p"; done
