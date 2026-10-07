#!/usr/bin/env bash
# One-time host setup for the WSL2 Ubuntu box: Docker Engine (inside the distro, not Docker
# Desktop), HashiCorp apt repo, Nomad, Consul, CNI plugins (needed for Nomad bridge
# networking) and the bridge-netfilter sysctls.
# Versions verified against releases.hashicorp.com / GitHub / docs.docker.com on 2026-10-07.
set -euo pipefail

NOMAD_VERSION="${NOMAD_VERSION:-2.0.7}"
CONSUL_VERSION="${CONSUL_VERSION:-2.0.4}"
CNI_VERSION="${CNI_VERSION:-v1.9.1}"

[ "$(id -u)" -eq 0 ] || { echo "run as root: sudo $0" >&2; exit 1; }

# systemd is what starts dockerd here (no Docker Desktop). Enable it once, then restart the
# distro from PowerShell with `wsl --shutdown` and run this script again.
if [ "$(ps -p 1 -o comm=)" != "systemd" ]; then
  mkdir -p /etc
  grep -q '^\[boot\]' /etc/wsl.conf 2>/dev/null || printf '[boot]\nsystemd=true\n' >> /etc/wsl.conf
  grep -q '^systemd=true' /etc/wsl.conf || sed -i 's/^\[boot\]/[boot]\nsystemd=true/' /etc/wsl.conf
  echo "systemd enabled in /etc/wsl.conf. From PowerShell: wsl --shutdown  then re-run: make setup" >&2
  exit 2
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get install -y -q curl gnupg lsb-release unzip jq make iptables ca-certificates

# --- Docker Engine, the official docs.docker.com/engine/install/ubuntu way -------------------
# Nomad's docker driver must talk to a daemon on *this* host: CNI configures the pause
# container's network namespace by path, and the Postgres host_volume is a bind mount of a
# directory in this distro. Docker Desktop's daemon lives in the separate docker-desktop
# distro, so neither path exists there. See ADR 0001.
for p in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  dpkg -s "$p" > /dev/null 2>&1 && apt-get remove -y -q "$p" || true
done
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
CODENAME="$(lsb_release -cs)"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

# HashiCorp apt repo
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | gpg --dearmor --yes -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  > /etc/apt/sources.list.d/hashicorp.list

apt-get update -q
apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
apt-get install -y -q "nomad=${NOMAD_VERSION}-1" "consul=${CONSUL_VERSION}-1"

systemctl enable --now docker
docker info > /dev/null   # fails loudly if the daemon did not come up

# CNI reference plugins (bridge, firewall, portmap, ...). Nomad looks in /opt/cni/bin by default.
arch="$(dpkg --print-architecture)"
tmp="$(mktemp -d)"
curl -fsSL -o "$tmp/cni.tgz" \
  "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${arch}-${CNI_VERSION}.tgz"
mkdir -p /opt/cni/bin
tar -C /opt/cni/bin -xzf "$tmp/cni.tgz"
rm -rf "$tmp"

# Bridge traffic must traverse iptables so the CNI firewall/portmap plugins work.
# scripts/dev-up.sh re-applies these on every start too.
modprobe br_netfilter 2>/dev/null || true
cat > /etc/sysctl.d/99-nomad-bridge.conf <<'SYSCTL'
net.bridge.bridge-nf-call-arptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
SYSCTL
sysctl --system > /dev/null

# Backing directory for the Postgres host_volume (see nomad/client.hcl).
mkdir -p /opt/nomad/volumes/postgres-data

echo
echo "docker $(docker version --format '{{.Server.Version}}' ) (daemon: $(docker info --format '{{.Name}}'))"
echo "nomad  $(nomad version | head -1)"
echo "consul $(consul version | head -1)"
echo "cni    $(ls /opt/cni/bin | tr '\n' ' ')"
