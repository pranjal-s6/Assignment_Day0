# ADR 0001: Run Nomad and Consul natively in WSL2, not inside Docker

Date: 2026-10-07 · Status: accepted

## Context

Part one of the exercise was a Nomad dev agent inside a Docker container
([`nomad-in-docker/docker-compose.yml`](../../nomad-in-docker/docker-compose.yml)). It
works for "is the scheduler up", but it needed `privileged`, `cgroup: host` and a writable
`/sys/fs/cgroup` to even start the client, and HashiCorp prints a banner that Nomad
clients in Docker are unsupported.

Consul Connect raises the bar: every task group needs `network.mode = "bridge"`, which
means CNI plugins creating network namespaces, iptables rules and a pause container
*on the same host* that runs the task containers, plus an Envoy sidecar per allocation
that Nomad launches through the Docker driver. With the client inside Docker Desktop's
VM, those namespaces, the CNI binaries and the host Docker daemon live in different
PID/mount namespaces.

## Decision

Install Ubuntu 24.04 in WSL2 and run `consul agent -dev` and `nomad agent -dev-connect`
natively there. This is the exact "Linux" path the exercise describes.

**Amended 2026-10-07:** the Docker daemon is Docker Engine installed *inside the distro*
(official `download.docker.com` apt repo, started by systemd), with Docker Desktop's WSL
integration switched off for this distro. The first draft of this ADR used Desktop's
integration instead. That does not work for this job, for the same reason part one did
not:

- Desktop's daemon runs in its own `docker-desktop` distro. Nomad's bridge mode creates
  a pause container, then hands CNI the container's netns path
  (`/var/run/docker/netns/<id>`). That path exists in the daemon's mount namespace, not in
  Ubuntu's, so CNI cannot open it.
- The Postgres `host_volume` is a bind mount of `/opt/nomad/volumes/postgres-data` *in
  Ubuntu*. Desktop would resolve that path inside its own distro.
- With integration on, Desktop puts a stub `docker` on Ubuntu's `$PATH` that forwards to
  the Windows-side daemon. `docker build` from PowerShell and from Ubuntu then land in the
  same image store, which hides the fact that Nomad is talking to a daemon on a different
  host. With Engine in the distro the two are different daemons, and the rule is simply:
  do everything in the Ubuntu shell.

## Consequences

- Bridge networking, CNI, sidecars and the host volume work the documented way; no
  unsupported hacks.
- One more moving part on a Windows machine (a WSL distro with its own Docker Engine),
  scripted by [`scripts/setup-wsl.sh`](../../scripts/setup-wsl.sh).
- systemd must be enabled in `/etc/wsl.conf` (`[boot] systemd=true`) so `dockerd` is a
  normal service. The HashiCorp agents still run via `nohup` from
  [`scripts/dev-up.sh`](../../scripts/dev-up.sh), which also re-applies the bridge sysctls.
- The repo lives in the distro's filesystem (`~/Assignment_Day0`), not under `/mnt/c`:
  faster I/O and no NTFS permission surprises in Docker build contexts.
- The part-one compose file is kept for the record but is not part of the running system.
