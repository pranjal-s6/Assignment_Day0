#!/usr/bin/env bash
# Start Consul and Nomad dev agents in the background. Logs and PIDs land in .run/.
# Idempotent: re-running only starts what is not already running.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN="$ROOT/.run"
mkdir -p "$RUN"

[ "$(id -u)" -eq 0 ] || { echo "run as root: nomad -dev-connect creates network namespaces" >&2; exit 1; }

# No systemd in WSL2 -> sysctls from setup-wsl.sh do not survive a restart of the distro.
modprobe br_netfilter 2>/dev/null || true
sysctl -q net.bridge.bridge-nf-call-iptables=1 net.bridge.bridge-nf-call-ip6tables=1 net.bridge.bridge-nf-call-arptables=1

docker info > /dev/null 2>&1 \
  || { echo "docker is not reachable. Docker Engine must run inside this distro: 'systemctl start docker' (or 'make setup'). Docker Desktop's WSL integration must stay OFF for this distro." >&2; exit 1; }

if ! pgrep -x consul > /dev/null; then
  nohup consul agent -dev -ui -log-level=info > "$RUN/consul.log" 2>&1 &
  echo $! > "$RUN/consul.pid"
fi
printf 'waiting for consul'
until curl -fs localhost:8500/v1/status/leader 2>/dev/null | grep -q ':'; do printf .; sleep 1; done
echo

if ! pgrep -x nomad > /dev/null; then
  # -dev-connect = dev mode + bridge networking + Consul service mesh. client.hcl adds the host volume.
  nohup nomad agent -dev-connect -config="$ROOT/nomad/client.hcl" -log-level=info > "$RUN/nomad.log" 2>&1 &
  echo $! > "$RUN/nomad.pid"
fi
printf 'waiting for nomad'
until nomad node status 2>/dev/null | grep -q ' ready'; do printf .; sleep 1; done
echo

echo "Consul UI  http://localhost:8500"
echo "Nomad UI   http://localhost:4646"
