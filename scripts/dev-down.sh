#!/usr/bin/env bash
# Stop all jobs, wait for their allocations to be torn down, then stop the Nomad and Consul
# dev agents. Dev-mode state is in-memory, so this is a clean slate -- except the Postgres
# host volume, which persists on purpose.
#
# The wait matters. Killing nomad while allocations are still being torn down leaves pause
# containers and CNI iptables rules behind; on the next `make up` the stale DNAT for port
# 8000 sits ahead of the new one and `localhost:8000` is dead. The cleanup at the end is
# the belt-and-braces for that case and for a crashed agent.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ALLOC_RE='[-_][0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

if pgrep -x nomad > /dev/null; then
  for job in edge api redis postgres; do
    nomad job stop -purge -yes "$job" > /dev/null 2>&1 || true
  done
  printf 'waiting for allocations to stop'
  for _ in $(seq 1 45); do
    [ -z "$(docker ps -q --filter name=nomad_init_ 2>/dev/null)" ] && break
    printf .; sleep 2
  done
  echo
  nomad system gc > /dev/null 2>&1 || true
fi
pkill -x nomad  2>/dev/null || true
pkill -x consul 2>/dev/null || true
sleep 1

# Leftovers from an unclean stop: task + pause containers named <task>-<alloc id>.
left="$(docker ps -a --format '{{.ID}} {{.Names}}' 2>/dev/null | grep -E -- "$ALLOC_RE" | awk '{print $1}')"
if [ -n "$left" ]; then
  echo "removing $(echo "$left" | wc -l) leftover allocation containers"
  echo "$left" | xargs -r docker rm -f > /dev/null 2>&1 || true
fi

# CNI's iptables chains (portmap DNAT, firewall). Nomad recreates them per allocation, so
# with the agent stopped they are only ever stale. The -S output is shell-quoted, hence eval.
for t in nat filter; do
  iptables -t "$t" -S 2>/dev/null | grep -E '^-A (PREROUTING|OUTPUT|POSTROUTING|FORWARD) .*(CNI-|NOMAD-ADMIN)' \
    | sed 's/^-A /-D /' | while read -r rule; do eval "iptables -t $t $rule" 2>/dev/null; done
  chains="$(iptables -t "$t" -S 2>/dev/null | grep -oE '^-N (CNI-[A-Za-z0-9_-]+|NOMAD-ADMIN)' | awk '{print $2}')"
  for c in $chains; do iptables -t "$t" -F "$c" 2>/dev/null; done
  for c in $chains; do iptables -t "$t" -X "$c" 2>/dev/null; done
done

rm -f "$ROOT/.run/"*.pid
echo "stopped"
